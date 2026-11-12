class_name SnakeGame
extends Node

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

var _state := SnakeState.new()
var _active_grid_size: Vector2i
var _active_tick_seconds: float
var _running := false
var _accumulator_seconds := 0.0

@onready var _board: SnakeBoard = $Board


func start() -> void:
	stop()
	if columns < 8 or columns > 64 or rows < 8 or rows > 64:
		push_error("SnakeGame requires grid dimensions between 8 and 64.")
		return
	if not is_finite(tick_interval_seconds) or tick_interval_seconds < 0.05 or tick_interval_seconds > 1.0:
		push_error("SnakeGame requires a finite tick interval between 0.05 and 1.00 seconds.")
		return

	_active_grid_size = Vector2i(columns, rows)
	_active_tick_seconds = tick_interval_seconds
	_state.reset(_active_grid_size)
	_board.set_snapshot(_active_grid_size, _state.get_body_cells())
	_running = true


func stop() -> void:
	_running = false
	_accumulator_seconds = 0.0


func set_board_rect(rect: Rect2) -> void:
	_board.set_board_rect(rect)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	_accumulator_seconds += delta
	var moved := false
	# Allow for rounding when a whole number of physics frames equals a tick.
	while _accumulator_seconds + TICK_EPSILON_SECONDS >= _active_tick_seconds:
		_accumulator_seconds = maxf(0.0, _accumulator_seconds - _active_tick_seconds)
		if _state.step():
			moved = true
	if moved:
		_board.set_snapshot(_active_grid_size, _state.get_body_cells())


func _unhandled_input(event: InputEvent) -> void:
	if not _running or not event.is_pressed() or event.is_echo():
		return
	for action: StringName in MOVE_DIRECTIONS:
		if event.is_action_pressed(action):
			_state.request_turn(MOVE_DIRECTIONS[action])
			get_viewport().set_input_as_handled()
			return
