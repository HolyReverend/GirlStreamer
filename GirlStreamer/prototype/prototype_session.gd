extends Node

const MIN_WINDOW_SIZE := Vector2i(1024, 768)

var _started := false

@onready var _snake_game: SnakeGame = $SnakeGame
@onready var _hud: PrototypeHUD = $PrototypeHUD


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE
	_hud.board_rect_changed.connect(_on_board_rect_changed)
	_apply_initial_layout.call_deferred()


func _apply_initial_layout() -> void:
	_on_board_rect_changed(_hud.get_board_rect())


func _on_board_rect_changed(rect: Rect2) -> void:
	_snake_game.set_board_rect(rect)
	if not _started and rect.has_area():
		_started = true
		_snake_game.start()
