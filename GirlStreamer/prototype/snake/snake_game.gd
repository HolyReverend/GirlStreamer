class_name SnakeGame
extends Node

signal score_changed(score: int)
signal attempt_finished(reason: StringName, score: int)

enum AttemptState { STOPPED, PLAYING, WAITING_FOR_RETRY }

const MOVE_DIRECTIONS: Dictionary[StringName, Vector2i] = {
	&"snake_up": Vector2i.UP,
	&"snake_down": Vector2i.DOWN,
	&"snake_left": Vector2i.LEFT,
	&"snake_right": Vector2i.RIGHT,
}
const TICK_EPSILON_SECONDS := 1.0e-9

@export_range(8, 64) var columns: int = 24
@export_range(8, 64) var rows: int = 18
@export_range(0.05, 1.0, 0.01, "suffix:s") var tick_interval_seconds: float = 0.20
@export var use_fixed_seed: bool = false
@export var food_seed: int = 12345

var _state := SnakeState.new()
var _active_grid_size: Vector2i
var _active_tick_seconds: float
var _attempt_state: AttemptState = AttemptState.STOPPED
var _accumulator_seconds := 0.0
var _action_authorizer: Callable

@onready var _board: SnakeBoard = $Board


func start() -> void:
	stop()
	if not _action_authorizer.is_valid():
		push_error("SnakeGame requires an action authorizer.")
		return
	if columns < 8 or columns > 64 or rows < 8 or rows > 64:
		push_error("SnakeGame requires grid dimensions between 8 and 64.")
		return
	if not is_finite(tick_interval_seconds) or tick_interval_seconds < 0.05 or tick_interval_seconds > 1.0:
		push_error("SnakeGame requires a finite tick interval between 0.05 and 1.00 seconds.")
		return

	_active_grid_size = Vector2i(columns, rows)
	_active_tick_seconds = tick_interval_seconds
	var random_source := RandomNumberGenerator.new()
	if use_fixed_seed:
		random_source.seed = food_seed
	else:
		random_source.randomize()
	_state.reset(_active_grid_size, random_source)
	_attempt_state = AttemptState.PLAYING
	_publish_snapshot()
	score_changed.emit(_state.get_score())


func stop() -> void:
	_attempt_state = AttemptState.STOPPED
	_accumulator_seconds = 0.0


func restart_attempt() -> bool:
	if not is_waiting_for_retry():
		return false
	start()
	return is_playing()


func is_playing() -> bool:
	return _attempt_state == AttemptState.PLAYING


func is_waiting_for_retry() -> bool:
	return _attempt_state == AttemptState.WAITING_FOR_RETRY


func set_board_rect(rect: Rect2) -> void:
	_board.set_board_rect(rect)


func set_action_authorizer(authorizer: Callable) -> void:
	_action_authorizer = authorizer


func _is_action_authorized() -> bool:
	if not _action_authorizer.is_valid():
		push_error("SnakeGame lost its action authorizer.")
		stop()
		return false
	# Expiry can stop this controller synchronously inside the callback.
	return _action_authorizer.call() and is_playing()


func _physics_process(delta: float) -> void:
	if not is_playing() or not _is_action_authorized():
		return
	_accumulator_seconds += delta
	var moved := false
	# Allow for rounding when a whole number of physics frames equals a tick.
	while is_playing() and _accumulator_seconds + TICK_EPSILON_SECONDS >= _active_tick_seconds:
		if not _is_action_authorized():
			break
		_accumulator_seconds = maxf(0.0, _accumulator_seconds - _active_tick_seconds)
		var previous_score := _state.get_score()
		if _state.step():
			moved = true
		var score := _state.get_score()
		if _state.is_finished():
			var reason := _state.get_finish_reason()
			_attempt_state = AttemptState.WAITING_FOR_RETRY
			_accumulator_seconds = 0.0
			_publish_snapshot()
			if score != previous_score:
				score_changed.emit(score)
			attempt_finished.emit(reason, score)
			return
		if score != previous_score:
			score_changed.emit(score)
	if moved:
		_publish_snapshot()


func _publish_snapshot() -> void:
	_board.set_snapshot(
		_active_grid_size, _state.get_body_cells(), _state.has_food(), _state.get_food_cell()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not is_playing() or not event.is_pressed() or event.is_echo():
		return
	for action: StringName in MOVE_DIRECTIONS:
		if event.is_action_pressed(action):
			if not _is_action_authorized():
				return
			_state.request_turn(MOVE_DIRECTIONS[action])
			get_viewport().set_input_as_handled()
			return
