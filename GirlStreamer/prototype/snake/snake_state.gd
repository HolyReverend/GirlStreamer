class_name SnakeState
extends RefCounted

const INITIAL_LENGTH := 3
const NO_FOOD := Vector2i(-1, -1)

var _body: Array[Vector2i] = []
var _grid_size: Vector2i
var _direction: Vector2i
var _pending_direction: Vector2i
var _has_pending_turn := false
var _random_source: RandomNumberGenerator
var _has_food := false
var _food_cell := NO_FOOD
var _score := 0
var _finish_reason: StringName = &""


func reset(grid_size: Vector2i, random_source: RandomNumberGenerator) -> void:
	_grid_size = grid_size
	_random_source = random_source
	_direction = Vector2i.RIGHT
	_pending_direction = Vector2i.ZERO
	_has_pending_turn = false
	_score = 0
	_finish_reason = &""
	_body.clear()
	var center := Vector2i(Vector2(grid_size) * 0.5)
	for segment in range(INITIAL_LENGTH):
		_body.append(center - Vector2i(segment, 0))
	_spawn_food()


func request_turn(candidate: Vector2i) -> bool:
	if is_finished() or candidate.abs().x + candidate.abs().y != 1:
		return false
	if _has_pending_turn or candidate == _direction or candidate == -_direction:
		return false
	_pending_direction = candidate
	_has_pending_turn = true
	return true


func step() -> bool:
	if is_finished():
		return false
	if _has_pending_turn:
		_direction = _pending_direction
		_has_pending_turn = false
	var next_head := _body[0] + _direction
	var collected := _has_food and next_head == _food_cell
	if not Rect2i(Vector2i.ZERO, _grid_size).has_point(next_head):
		_finish_reason = &"wall_collision"
		return false
	# A normal step vacates the tail; growth retains every segment.
	var retained_count := _body.size() if collected else _body.size() - 1
	for index in range(retained_count):
		if _body[index] == next_head:
			_finish_reason = &"self_collision"
			return false
	_body.push_front(next_head)
	if collected:
		_score += 1
		_has_food = false
		_spawn_food()
	else:
		_body.pop_back()
	return true


func get_body_cells() -> Array[Vector2i]:
	return _body.duplicate()


func get_direction() -> Vector2i:
	return _direction


func get_score() -> int:
	return _score


func has_food() -> bool:
	return _has_food


func get_food_cell() -> Vector2i:
	return _food_cell


func is_complete() -> bool:
	return _finish_reason == &"board_full"


func is_finished() -> bool:
	return not _finish_reason.is_empty()


func get_finish_reason() -> StringName:
	return _finish_reason


func _spawn_food() -> void:
	var occupied: Dictionary[Vector2i, bool] = {}
	for cell in _body:
		occupied[cell] = true

	var free_cells: Array[Vector2i] = []
	for row in range(_grid_size.y):
		for column in range(_grid_size.x):
			var cell := Vector2i(column, row)
			if not occupied.has(cell):
				free_cells.append(cell)

	_has_food = not free_cells.is_empty()
	if not _has_food:
		_food_cell = NO_FOOD
		_finish_reason = &"board_full"
		return
	_food_cell = free_cells[_random_source.randi_range(0, free_cells.size() - 1)]
