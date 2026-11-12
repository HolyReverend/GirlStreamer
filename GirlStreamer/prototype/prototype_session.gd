extends Node

enum SessionState { READY, RUNNING, FINISHED }

const MIN_WINDOW_SIZE := Vector2i(1024, 768)
const INVALID_SNAKE_SETTINGS := "Cannot start — invalid Snake settings; correct them and run again."
const MessageController = preload("res://prototype/messages/quick_messages.gd")

@export_range(1, 600, 1, "suffix:s") var session_duration_seconds: int = 360
@export var messages_enabled: bool = true
@export_range(1.0, 120.0, 0.1, "suffix:s") var first_question_delay_seconds: float = 45.0
@export_range(1.0, 120.0, 0.1, "suffix:s") var question_gap_seconds: float = 45.0
@export_range(1.0, 15.0, 0.1, "suffix:s") var question_window_seconds: float = 5.0

var _session_state: SessionState = SessionState.READY
var _initial_layout_handled := false
var _duration_seconds := 0
var _start_msec := 0
var _deadline_msec := 0
var _total_food := 0
var _attempts_started := 0
var _collisions := 0
var _boards_completed := 0
var _last_attempt_score := 0
var _session_messages_enabled := false
var _active_question_id := 0
var _questions_shown := 0
var _questions_answered := 0
var _questions_expired := 0
var _questions_cancelled := 0
var _answer_times_seconds: Array[float] = []

@onready var _snake_game: SnakeGame = $SnakeGame
@onready var _hud: PrototypeHUD = $PrototypeHUD
@onready var _quick_messages: MessageController = $QuickMessages


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE
	_hud.board_rect_changed.connect(_on_board_rect_changed)
	_snake_game.score_changed.connect(_on_score_changed)
	_snake_game.attempt_finished.connect(_on_attempt_finished)
	_snake_game.set_action_authorizer(_authorize_snake_action)
	_quick_messages.set_time_sampler(_sample_running_time_msec)
	_quick_messages.question_opened.connect(_on_question_opened)
	_quick_messages.question_resolved.connect(_on_question_resolved)
	_apply_initial_layout.call_deferred()


func _apply_initial_layout() -> void:
	_on_board_rect_changed(_hud.get_board_rect())


func _on_board_rect_changed(rect: Rect2) -> void:
	_snake_game.set_board_rect(rect)
	if not _initial_layout_handled and rect.has_area():
		_initial_layout_handled = true
		start_session()


func start_session() -> bool:
	if _session_state == SessionState.RUNNING:
		return false
	if session_duration_seconds < 1 or session_duration_seconds > 600:
		push_error("PrototypeSession requires a duration between 1 and 600 seconds.")
		_hud.set_status("Cannot start — session duration must be 1–600 seconds.")
		return false
	if not _has_valid_message_settings() or not _quick_messages.has_valid_content():
		push_error("PrototypeSession requires valid quick-message timing and content.")
		_hud.set_status("Cannot start — invalid question settings or content.")
		return false

	_snake_game.stop()
	_total_food = 0
	_attempts_started = 0
	_collisions = 0
	_boards_completed = 0
	_last_attempt_score = 0
	_hud.hide_session_results()
	_hud.set_status("")
	_hud.set_total_food(0)
	_duration_seconds = session_duration_seconds
	_start_msec = _now_msec()
	_deadline_msec = _start_msec + _duration_seconds * 1000
	_session_state = SessionState.RUNNING
	_snake_game.start()
	if not _snake_game.is_playing():
		_session_state = SessionState.READY
		_duration_seconds = 0
		_start_msec = 0
		_deadline_msec = 0
		_hud.set_score(0)
		_hud.set_remaining_time(0.0)
		_hud.set_status(INVALID_SNAKE_SETTINGS)
		_hud.set_messages_enabled(false)
		_hud.clear_question()
		_hud.set_message_feedback("")
		return false
	_attempts_started = 1
	_reset_messages()
	_hud.set_remaining_time(float(_duration_seconds))
	return true


func _has_valid_message_settings() -> bool:
	return (
		is_finite(first_question_delay_seconds) and first_question_delay_seconds >= 1.0
		and first_question_delay_seconds <= 120.0
		and is_finite(question_gap_seconds) and question_gap_seconds >= 1.0
		and question_gap_seconds <= 120.0
		and is_finite(question_window_seconds) and question_window_seconds >= 1.0
		and question_window_seconds <= 15.0
	)


func _reset_messages() -> void:
	_session_messages_enabled = messages_enabled
	_active_question_id = 0
	_questions_shown = 0
	_questions_answered = 0
	_questions_expired = 0
	_questions_cancelled = 0
	_answer_times_seconds.clear()
	_quick_messages.reset_for_session(
		_session_messages_enabled, first_question_delay_seconds, question_gap_seconds,
		question_window_seconds
	)
	_hud.set_messages_enabled(_session_messages_enabled)
	_hud.clear_question()
	_hud.set_message_feedback("")


func get_elapsed_seconds() -> float:
	match _session_state:
		SessionState.RUNNING:
			return clampi(_now_msec() - _start_msec, 0, _duration_seconds * 1000) / 1000.0
		SessionState.FINISHED:
			return float(_duration_seconds)
	return 0.0


func get_remaining_seconds() -> float:
	if _session_state != SessionState.RUNNING:
		return 0.0
	return _duration_seconds - get_elapsed_seconds()


func _now_msec() -> int:
	return Time.get_ticks_msec()


func _sample_running_time_msec() -> int:
	if _session_state != SessionState.RUNNING:
		return -1
	var now := _now_msec()
	if now >= _deadline_msec:
		_finish_session()
		return -1
	return maxi(0, now - _start_msec)


func _authorize_snake_action() -> bool:
	return _sample_running_time_msec() >= 0


func _process(_delta: float) -> void:
	var elapsed := _sample_running_time_msec()
	if elapsed < 0:
		return
	_hud.set_remaining_time(_duration_seconds - elapsed / 1000.0)
	_quick_messages.tick(elapsed, _snake_game.is_playing())
	if _quick_messages.is_open():
		_hud.set_question_time(_quick_messages.get_remaining_seconds(elapsed))
	_hud.set_message_feedback(_quick_messages.get_feedback_text())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	match _session_state:
		SessionState.RUNNING:
			if event.is_action_pressed(&"attempt_retry"):
				_try_retry_attempt()
			elif event.is_action_pressed(&"session_restart"):
				# Expiry discovered here must leave the results visible for a fresh Enter.
				_authorize_snake_action()
		SessionState.FINISHED:
			if event.is_action_pressed(&"session_restart"):
				get_viewport().set_input_as_handled()
				start_session()


func _try_retry_attempt() -> bool:
	if not _authorize_snake_action() or not _snake_game.is_waiting_for_retry():
		return false
	get_viewport().set_input_as_handled()
	var previous_score := _last_attempt_score
	_last_attempt_score = 0
	if not _snake_game.restart_attempt():
		_last_attempt_score = previous_score
		_hud.set_status(INVALID_SNAKE_SETTINGS)
		return false
	_attempts_started += 1
	_hud.set_status("")
	return true


func _finish_session() -> void:
	if _session_state != SessionState.RUNNING:
		return
	_session_state = SessionState.FINISHED
	_snake_game.stop()
	# Cancellation emits synchronously and must be counted before the summary.
	_quick_messages.stop_for_session_end(_duration_seconds * 1000)
	_hud.clear_question(false)
	_hud.set_message_feedback("")
	_hud.set_remaining_time(0.0)
	_hud.set_status("Session finished")
	_hud.set_message_results(
		_session_messages_enabled, _questions_shown, _questions_answered, _questions_expired,
		_questions_cancelled, _answer_times_seconds
	)
	_hud.show_session_results(
		float(_duration_seconds), _total_food, _attempts_started, _collisions, _boards_completed
	)


func _on_score_changed(score: int) -> void:
	if _session_state != SessionState.RUNNING:
		return
	if score < _last_attempt_score:
		push_error("Attempt score decreased outside the session reset path.")
		return
	_total_food += score - _last_attempt_score
	_last_attempt_score = score
	_hud.set_total_food(_total_food)
	_hud.set_score(score)


func _on_attempt_finished(reason: StringName, _score: int) -> void:
	if _session_state != SessionState.RUNNING:
		return
	match reason:
		&"wall_collision":
			_collisions += 1
			_hud.set_status("Wall collision — press Space to retry.")
		&"self_collision":
			_collisions += 1
			_hud.set_status("Self collision — press Space to retry.")
		&"board_full":
			_boards_completed += 1
			_hud.set_status("Board complete — press Space to play again.")


func _on_question_opened(id: int, prompt: String, options: Array[String]) -> void:
	if _session_state != SessionState.RUNNING or _active_question_id != 0:
		return
	_active_question_id = id
	_questions_shown += 1
	_hud.show_question(prompt, options)


func _on_question_resolved(id: int, _answer_index: int, elapsed_seconds: float, outcome: StringName) -> void:
	if _session_state != SessionState.RUNNING:
		if _session_state != SessionState.FINISHED or outcome != &"cancelled":
			return
	if _active_question_id == 0 or id != _active_question_id:
		return
	_active_question_id = 0
	match outcome:
		&"answered":
			_questions_answered += 1
			_answer_times_seconds.append(elapsed_seconds)
		&"expired":
			_questions_expired += 1
		&"cancelled":
			_questions_cancelled += 1
	_hud.clear_question()
	_hud.set_message_feedback(_quick_messages.get_feedback_text())
