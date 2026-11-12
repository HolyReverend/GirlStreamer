class_name SnakeState
extends RefCounted

const INITIAL_LENGTH := 3

var _body: Array[Vector2i] = []
var _grid_size: Vector2i
var _direction: Vector2i
var _pending_direction: Vector2i
var _has_pending_turn := false


func reset(grid_size: Vector2i) -> void:
	_grid_size = grid_size
	_direction = Vector2i.RIGHT
	_has_pending_turn = false
	_body.clear()
	var center := Vector2i(Vector2(grid_size) * 0.5)
	for segment in range(INITIAL_LENGTH):
		_body.append(center - Vector2i(segment, 0))


func request_turn(candidate: Vector2i) -> bool:
	if candidate.abs().x + candidate.abs().y != 1:
		return false
	if _has_pending_turn or candidate == _direction or candidate == -_direction:
		return false
	_pending_direction = candidate
	_has_pending_turn = true
	return true


func step() -> bool:
	if _has_pending_turn:
		_direction = _pending_direction
		_has_pending_turn = false
	var next_head := _body[0] + _direction
	# Stage 1 keeps the body at the edge until the player turns away.
	if not Rect2i(Vector2i.ZERO, _grid_size).has_point(next_head):
		return false
	_body.push_front(next_head)
	_body.pop_back()
	return true


func get_body_cells() -> Array[Vector2i]:
	return _body.duplicate()


func get_direction() -> Vector2i:
	return _direction
