extends SceneTree



class Fixture extends SnakeState:
	func reset_for_movement() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		reset(Vector2i(24, 18), rng)
		# Keep food outside every movement route exercised by this runner.
		_food_cell = Vector2i(0, 0)


func _initialize() -> void:
	var checks: Array[Callable] = [
		_reset_and_step, _reject_reverse, _buffer_one_turn, _ignore_non_turns,
	]
	for check in checks:
		if not check.call():
			printerr("STAGE01_MOVEMENT_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE01_MOVEMENT_PASS checks=", checks.size())
	quit()


func _reset_and_step() -> bool:
	var state := Fixture.new()
	state.reset_for_movement()
	if state.get_body_cells() != [Vector2i(12, 9), Vector2i(11, 9), Vector2i(10, 9)]:
		return false
	var snapshot := state.get_body_cells()
	snapshot.clear()
	return (
		state.get_direction() == Vector2i.RIGHT and state.step()
		and state.get_body_cells() == [Vector2i(13, 9), Vector2i(12, 9), Vector2i(11, 9)]
	)


func _reject_reverse() -> bool:
	var state := Fixture.new()
	state.reset_for_movement()
	return (
		not state.request_turn(Vector2i.LEFT) and state.step()
		and state.get_body_cells()[0] == Vector2i(13, 9)
		and not state.request_turn(Vector2i.LEFT) and state.request_turn(Vector2i.UP)
	)


func _buffer_one_turn() -> bool:
	var state := Fixture.new()
	state.reset_for_movement()
	return (
		state.request_turn(Vector2i.UP) and not state.request_turn(Vector2i.LEFT)
		and state.get_direction() == Vector2i.RIGHT and state.step()
		and state.get_body_cells()[0] == Vector2i(12, 8)
		and state.get_direction() == Vector2i.UP and state.request_turn(Vector2i.LEFT)
		and state.step() and state.get_body_cells()[0] == Vector2i(11, 8)
	)


func _ignore_non_turns() -> bool:
	var state := Fixture.new()
	state.reset_for_movement()
	if (
		state.request_turn(Vector2i.RIGHT) or state.request_turn(Vector2i.ZERO)
		or state.request_turn(Vector2i(1, 1)) or state.request_turn(Vector2i(0, -2))
		or not state.request_turn(Vector2i.UP)
	):
		return false
	state.reset_for_movement()
	return state.step() and state.get_body_cells()[0] == Vector2i(13, 9)
