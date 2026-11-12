extends SceneTree

const SNAKE_GAME = preload("res://prototype/snake/snake_game.tscn")
const GRID := Vector2i(24, 18)
const SMALL_GRID := Vector2i(8, 8)
const NO_FOOD := Vector2i(-1, -1)
const SEED := 12345


class Fixture extends SnakeState:
	func place_food(cell: Vector2i) -> void:
		_has_food = true
		_food_cell = cell

	func respawn_food() -> void:
		_spawn_food()

	func arrange_last_free_cell(grid_size: Vector2i, random_source: RandomNumberGenerator) -> void:
		reset(grid_size, random_source)
		_body.clear()
		# The head-to-tail path leaves only (0, 0) free.
		for x in range(1, grid_size.x):
			_body.append(Vector2i(x, 0))
		for y in range(1, grid_size.y):
			for column in range(grid_size.x):
				var x := grid_size.x - 1 - column if y % 2 == 1 else column
				_body.append(Vector2i(x, y))
		_direction = Vector2i.LEFT
		_score = _body.size() - INITIAL_LENGTH
		_spawn_food()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_initial_state_and_seeded_spawning,
		_collect_and_move,
		_complete_board,
		_reset_after_collection,
		_finish_controller_once,
	]
	for check in checks:
		if not check.call():
			printerr("STAGE02_FOOD_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE02_FOOD_PASS checks=", checks.size())
	quit()


func _seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _has_valid_food(state: SnakeState, grid: Vector2i) -> bool:
	var cell := state.get_food_cell()
	return (
		state.has_food() and Rect2i(Vector2i.ZERO, grid).has_point(cell)
		and not state.get_body_cells().has(cell)
	)


func _initial_state_and_seeded_spawning() -> bool:
	var first := Fixture.new()
	var second := Fixture.new()
	var first_rng := _seeded_rng()
	var second_rng := _seeded_rng()
	var initial_rng_state := first_rng.state
	first.reset(GRID, first_rng)
	second.reset(GRID, second_rng)
	if (
		first.get_body_cells().size() != 3 or second.get_body_cells().size() != 3
		or first.get_score() != 0 or second.get_score() != 0
		or first.is_complete() or second.is_complete()
	):
		return false
	for spawn_index in range(4):
		if (
			not _has_valid_food(first, GRID) or not _has_valid_food(second, GRID)
			or first.get_food_cell() != second.get_food_cell()
		):
			return false
		if spawn_index < 3:
			first.respawn_food()
			second.respawn_food()
	return first_rng.state != initial_rng_state and second_rng.state != initial_rng_state


func _collect_and_move() -> bool:
	var state := Fixture.new()
	state.reset(GRID, _seeded_rng())
	state.place_food(Vector2i(13, 9))
	if (
		not state.step() or state.get_score() != 1 or not _has_valid_food(state, GRID)
		or state.get_body_cells() != [Vector2i(13, 9), Vector2i(12, 9), Vector2i(11, 9), Vector2i(10, 9)]
		or state.get_body_cells().size() != 3 + state.get_score()
	):
		return false
	var off_path := Vector2i(0, 0)
	state.place_food(off_path)
	return (
		state.step() and state.get_score() == 1 and state.has_food()
		and state.get_food_cell() == off_path
		and state.get_body_cells() == [Vector2i(14, 9), Vector2i(13, 9), Vector2i(12, 9), Vector2i(11, 9)]
		and state.get_body_cells().size() == 3 + state.get_score()
	)


func _complete_board() -> bool:
	var state := Fixture.new()
	state.arrange_last_free_cell(SMALL_GRID, _seeded_rng())
	if not state.has_food() or state.get_food_cell() != Vector2i.ZERO or not state.step():
		return false
	var full_body := state.get_body_cells()
	return (
		full_body.size() == 64 and full_body[0] == Vector2i.ZERO and state.get_score() == 61
		and state.is_complete() and not state.has_food() and state.get_food_cell() == NO_FOOD
		and not state.request_turn(Vector2i.DOWN) and not state.step()
		and state.get_body_cells() == full_body and state.get_score() == 61
	)


func _reset_after_collection() -> bool:
	var collected := Fixture.new()
	collected.reset(GRID, _seeded_rng())
	collected.place_food(Vector2i(13, 9))
	if not collected.step() or not collected.request_turn(Vector2i.UP):
		return false
	var completed := Fixture.new()
	completed.arrange_last_free_cell(SMALL_GRID, _seeded_rng())
	if not completed.step() or not completed.is_complete():
		return false
	for state: Fixture in [collected, completed]:
		state.reset(GRID, _seeded_rng())
		if (
			state.get_body_cells() != [Vector2i(12, 9), Vector2i(11, 9), Vector2i(10, 9)]
			or state.get_score() != 0 or state.is_complete() or not _has_valid_food(state, GRID)
			or state.get_direction() != Vector2i.RIGHT or not state.step()
			or state.get_body_cells()[0] != Vector2i(13, 9)
		):
			return false
	return true


func _finish_controller_once() -> bool:
	var game := SNAKE_GAME.instantiate() as SnakeGame
	game.columns = SMALL_GRID.x
	game.rows = SMALL_GRID.y
	game.use_fixed_seed = true
	# Adding the scene to the ready root initializes its onready fields synchronously.
	root.add_child(game)
	game.set_physics_process(false)
	game.set_action_authorizer(_allow_action)
	game.start()

	var state := Fixture.new()
	state.arrange_last_free_cell(SMALL_GRID, _seeded_rng())
	game.set("_state", state)
	var board := game.get_node("Board")
	var events: Array[Array] = []
	game.score_changed.connect(func(score: int) -> void:
		events.append([&"score", score, game.is_waiting_for_retry(), board.get("_food_present")])
	)
	game.attempt_finished.connect(func(reason: StringName, score: int) -> void:
		events.append([reason, score])
	)

	game._physics_process(1.0)
	var full_body := state.get_body_cells()
	var expected_events := [[&"score", 61, true, false], [&"board_full", 61]]
	var valid_completion: bool = (
		events == expected_events and full_body.size() == 64 and game.is_waiting_for_retry() and not game.is_playing()
		and game.get("_accumulator_seconds") == 0.0
		and board.get("_body") == full_body and not board.get("_food_present")
		and board.get("_food_cell") == NO_FOOD
	)
	game._physics_process(1.0)
	var unchanged := events == expected_events and state.get_body_cells() == full_body
	game.free()
	return valid_completion and unchanged


func _allow_action() -> bool:
	return true
