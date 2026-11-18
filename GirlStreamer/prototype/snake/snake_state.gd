class_name SnakeState
extends RefCounted

const INITIAL_LENGTH := 3
const NO_FOOD := Vector2i(-1, -1)
const MAX_WARNING_RANGE := 2


class DangerHint extends RefCounted:
	var kind: StringName
	var distance: int
	var last_legal_head: Vector2i
	var attempted_cell: Vector2i

	func _init(
		collision_kind: StringName, steps: int, legal_head: Vector2i, target: Vector2i
	) -> void:
		kind = collision_kind
		distance = steps
		last_legal_head = legal_head
		attempted_cell = target


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
	clear_pending_turn()
	_score = 0
	_finish_reason = &""
	_body.clear()
	var center := Vector2i(Vector2(grid_size) * 0.5)
	for segment in range(INITIAL_LENGTH):
		_body.append(center - Vector2i(segment, 0))
	_spawn_food()


func clear_pending_turn() -> void:
	_has_pending_turn = false
	_pending_direction = Vector2i.ZERO


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
	_finish_reason = _collision_kind(_body, next_head, collected)
	if is_finished():
		return false
	_body.push_front(next_head)
	if collected:
		_score += 1
		_has_food = false
		_spawn_food()
	else:
		_body.pop_back()
	return true


func predict_danger(max_steps: int) -> DangerHint:
	var steps := clampi(max_steps, 0, MAX_WARNING_RANGE)
	if steps == 0 or is_finished() or _body.is_empty():
		return null

	var projected_body: Array[Vector2i] = _body.duplicate()
	var direction := _pending_direction if _has_pending_turn else _direction
	var food_available := _has_food
	for distance in range(1, steps + 1):
		var head := projected_body[0]
		var target := head + direction
		var collected := food_available and target == _food_cell
		var kind := _collision_kind(projected_body, target, collected)
		if not kind.is_empty():
			return DangerHint.new(kind, distance, head, target)

		projected_body.push_front(target)
		if collected:
			if projected_body.size() == _grid_size.x * _grid_size.y:
				return null
			# New food must be on a free cell, so it cannot affect the next collision.
			food_available = false
		else:
			projected_body.pop_back()
	return null


func _collision_kind(body: Array[Vector2i], target: Vector2i, collected: bool) -> StringName:
	if not Rect2i(Vector2i.ZERO, _grid_size).has_point(target):
		return &"wall_collision"
	# A normal step vacates the tail; growth retains every segment.
	var retained_count := body.size() if collected else body.size() - 1
	for index in range(retained_count):
		if body[index] == target:
			return &"self_collision"
	return &""


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
