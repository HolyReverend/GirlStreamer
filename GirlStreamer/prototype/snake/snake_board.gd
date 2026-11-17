class_name SnakeBoard
extends Node2D

const BACKGROUND := Color("#101a21")
const GRID := Color("#293941")
const BODY := Color("#47bb86")
const HEAD := Color("#c2f58c")
const FOOD := Color("#ffad66")

var _board_rect: Rect2
var _grid_size: Vector2i
var _body: Array[Vector2i] = []
var _food_present := false
var _food_cell: Vector2i


func set_board_rect(rect: Rect2) -> void:
	_board_rect = Rect2(to_local(rect.position), rect.size)
	queue_redraw()


func set_snapshot(
	grid_size: Vector2i, body_cells: Array[Vector2i], food_present: bool, food_cell: Vector2i
) -> void:
	_grid_size = grid_size
	_body = body_cells.duplicate()
	_food_present = food_present
	_food_cell = food_cell
	queue_redraw()


func _draw() -> void:
	if not _board_rect.has_area() or _grid_size.x <= 0 or _grid_size.y <= 0:
		return
	var cell_size := minf(_board_rect.size.x / _grid_size.x, _board_rect.size.y / _grid_size.y)
	var size := Vector2(_grid_size) * cell_size
	# Keep the visible bottom edge aligned with chat even when width limits the scale.
	var origin := _board_rect.position + Vector2(
		(_board_rect.size.x - size.x) * 0.5, _board_rect.size.y - size.y
	)
	draw_rect(Rect2(origin, size), BACKGROUND)
	for column in range(1, _grid_size.x):
		var top := origin + Vector2(column * cell_size, 0)
		draw_line(top, top + Vector2(0, size.y), GRID, 1.0)
	for row in range(1, _grid_size.y):
		var left := origin + Vector2(0, row * cell_size)
		draw_line(left, left + Vector2(size.x, 0), GRID, 1.0)

	var segment_size := Vector2.ONE * cell_size
	if _food_present:
		var food_center := origin + (Vector2(_food_cell) + Vector2(0.5, 0.5)) * cell_size
		draw_circle(food_center, cell_size * 0.28, FOOD, true, -1.0, true)
	# Draw the head last so it stays visible when segments overlap.
	for index in range(_body.size() - 1, -1, -1):
		var segment := Rect2(origin + Vector2(_body[index]) * cell_size, segment_size)
		draw_rect(segment.grow(-cell_size * 0.08), HEAD if index == 0 else BODY)
