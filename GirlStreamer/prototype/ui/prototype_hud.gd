class_name PrototypeHUD
extends Control

signal board_rect_changed(rect: Rect2)

@onready var _board_area: Control = $MarginContainer/VBoxContainer/BoardArea


func _ready() -> void:
	_board_area.resized.connect(_report_board_rect, CONNECT_DEFERRED)


func get_board_rect() -> Rect2:
	return _board_area.get_global_rect()


func _report_board_rect() -> void:
	board_rect_changed.emit(get_board_rect())
