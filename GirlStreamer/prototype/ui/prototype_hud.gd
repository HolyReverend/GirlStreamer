class_name PrototypeHUD
extends Control

signal board_rect_changed(rect: Rect2)

@onready var _board_area: Control = $MarginContainer/VBoxContainer/BoardArea
@onready var _score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	_board_area.resized.connect(_report_board_rect, CONNECT_DEFERRED)


func get_board_rect() -> Rect2:
	return _board_area.get_global_rect()


func set_score(score: int) -> void:
	_score_label.text = "Score: %d" % score


func set_status(message: String) -> void:
	_status_label.text = message
	_status_label.visible = not message.is_empty()


func _report_board_rect() -> void:
	board_rect_changed.emit(get_board_rect())
