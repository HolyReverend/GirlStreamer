extends SceneTree

const Model = preload("res://prototype/snake/snake_state.gd")
const GRID := Vector2i(24, 18)


func _initialize() -> void:
	var checks: Array[Callable] = [
		_reset_and_step, _reject_reverse, _buffer_one_turn, _ignore_non_turns, _guard_boundary,
	]
	for check in checks:
		if not check.call():
			printerr("STAGE01_MOVEMENT_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE01_MOVEMENT_PASS checks=", checks.size())
	quit()


func _reset_and_step() -> bool:
	var state := Model.new()
	state.reset(GRID)
	if state.get_body_cells() != [Vector2i(12, 9), Vector2i(11, 9), Vector2i(10, 9)]:
		return false
	var snapshot := state.get_body_cells()
	snapshot.clear()
	return (
		state.get_direction() == Vector2i.RIGHT and state.step()
		and state.get_body_cells() == [Vector2i(13, 9), Vector2i(12, 9), Vector2i(11, 9)]
	)


func _reject_reverse() -> bool:
	var state := Model.new()
	state.reset(GRID)
	return (
		not state.request_turn(Vector2i.LEFT) and state.step()
		and state.get_body_cells()[0] == Vector2i(13, 9)
		and not state.request_turn(Vector2i.LEFT) and state.request_turn(Vector2i.UP)
	)


func _buffer_one_turn() -> bool:
	var state := Model.new()
	state.reset(GRID)
	return (
		state.request_turn(Vector2i.UP) and not state.request_turn(Vector2i.LEFT)
		and state.get_direction() == Vector2i.RIGHT and state.step()
		and state.get_body_cells()[0] == Vector2i(12, 8)
		and state.get_direction() == Vector2i.UP and state.request_turn(Vector2i.LEFT)
		and state.step() and state.get_body_cells()[0] == Vector2i(11, 8)
	)


func _ignore_non_turns() -> bool:
	var state := Model.new()
	state.reset(GRID)
	if (
		state.request_turn(Vector2i.RIGHT) or state.request_turn(Vector2i.ZERO)
		or state.request_turn(Vector2i(1, 1)) or state.request_turn(Vector2i(0, -2))
		or not state.request_turn(Vector2i.UP)
	):
		return false
	state.reset(GRID)
	return state.step() and state.get_body_cells()[0] == Vector2i(13, 9)


func _guard_boundary() -> bool:
	var state := Model.new()
	state.reset(GRID)
	for step_index in range(11):
		if not state.step():
			return false
	var edge := state.get_body_cells()
	return (
		edge[0] == Vector2i(23, 9) and not state.step() and state.get_body_cells() == edge
		and state.request_turn(Vector2i.UP) and state.step()
		and state.get_body_cells()[0] == Vector2i(23, 8)
	)
