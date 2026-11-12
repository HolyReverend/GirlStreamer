extends Node

const MIN_WINDOW_SIZE := Vector2i(1024, 768)

var _started := false

@onready var _snake_game: SnakeGame = $SnakeGame
@onready var _hud: PrototypeHUD = $PrototypeHUD


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE
	_hud.board_rect_changed.connect(_on_board_rect_changed)
	_snake_game.score_changed.connect(_on_score_changed)
	_snake_game.attempt_finished.connect(_on_attempt_finished)
	_apply_initial_layout.call_deferred()


func _apply_initial_layout() -> void:
	_on_board_rect_changed(_hud.get_board_rect())


func _on_board_rect_changed(rect: Rect2) -> void:
	_snake_game.set_board_rect(rect)
	if not _started and rect.has_area():
		_started = true
		_hud.set_status("")
		_snake_game.start()


func _on_score_changed(score: int) -> void:
	_hud.set_score(score)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"attempt_retry"):
		return
	if not _snake_game.is_waiting_for_retry():
		return
	get_viewport().set_input_as_handled()
	_try_retry_attempt()


func _try_retry_attempt() -> bool:
	if not _snake_game.is_waiting_for_retry():
		return false
	if not _snake_game.restart_attempt():
		_hud.set_status("Cannot start — invalid Snake settings; correct them and run again.")
		return false
	_hud.set_status("")
	return true


func _on_attempt_finished(reason: StringName, _score: int) -> void:
	match reason:
		&"wall_collision":
			_hud.set_status("Wall collision — press Space to retry.")
		&"self_collision":
			_hud.set_status("Self collision — press Space to retry.")
		&"board_full":
			_hud.set_status("Board complete — press Space to play again.")
