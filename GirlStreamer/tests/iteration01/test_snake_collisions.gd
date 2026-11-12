extends SceneTree

const SNAKE_GAME = preload("res://prototype/snake/snake_game.tscn")
const SESSION = preload("res://prototype/prototype_session.tscn")
const FoodChecks = preload("res://tests/iteration01/test_snake_food.gd")
const GRID := Vector2i(8, 8)


class Fixture extends SnakeState:
	func arrange(body: Array[Vector2i], direction: Vector2i, food: Vector2i) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		reset(Vector2i(8, 8), rng)
		_body = body.duplicate()
		_direction = direction
		_food_cell = food
		_score = body.size() - INITIAL_LENGTH

	func get_rng_state() -> int:
		return _random_source.state


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_wall_collision, _retained_body_collision, _vacating_tail, _controller_finishes_once,
		_parent_retries,
	]
	for check in checks:
		if not await check.call():
			printerr("STAGE03_COLLISIONS_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE03_COLLISIONS_PASS groups=", checks.size())
	quit()


func _wall_fixture() -> Fixture:
	var state := Fixture.new()
	state.arrange([Vector2i(7, 3), Vector2i(6, 3), Vector2i(5, 3)], Vector2i.RIGHT, Vector2i.ZERO)
	return state


func _retained_fixture() -> Fixture:
	var state := Fixture.new()
	state.arrange(
		[Vector2i(2, 2), Vector2i(2, 3), Vector2i(1, 3), Vector2i(1, 2), Vector2i(1, 1)],
		Vector2i.UP, Vector2i(6, 6)
	)
	return state


func _board_state(state: Fixture) -> Array:
	return [
		state.get_body_cells(), state.has_food(), state.get_food_cell(),
		state.get_score(), state.get_rng_state(),
	]


func _wall_collision() -> bool:
	var state := _wall_fixture()
	var before := _board_state(state)
	return (
		not state.step() and state.is_finished() and not state.is_complete()
		and state.get_finish_reason() == &"wall_collision" and _board_state(state) == before
		and not state.request_turn(Vector2i.UP) and not state.step() and _board_state(state) == before
		and state.get_direction() == Vector2i.RIGHT and state.get_finish_reason() == &"wall_collision"
	)


func _retained_body_collision() -> bool:
	var state := _retained_fixture()
	var before := _board_state(state)
	return (
		state.request_turn(Vector2i.LEFT) and not state.step()
		and state.is_finished() and not state.is_complete()
		and state.get_finish_reason() == &"self_collision" and _board_state(state) == before
	)


func _vacating_tail() -> bool:
	var state := Fixture.new()
	state.arrange(
		[Vector2i(2, 2), Vector2i(2, 3), Vector2i(1, 3), Vector2i(1, 2)],
		Vector2i.UP, Vector2i(6, 6)
	)
	return (
		state.request_turn(Vector2i.LEFT) and state.step()
		and state.get_body_cells() == [Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3), Vector2i(1, 3)]
		and state.get_score() == 1 and state.has_food() and state.get_food_cell() == Vector2i(6, 6)
		and not state.is_finished() and state.get_finish_reason() == &""
	)


func _controller_finishes_once() -> bool:
	var game := SNAKE_GAME.instantiate() as SnakeGame
	_configure(game)
	root.add_child(game)
	game.set_physics_process(false)
	game.start()
	var state := _wall_fixture()
	game.set("_state", state)
	var before := _board_state(state)
	var events := _record_events(game)
	game._physics_process(1.0)
	var terminal_ok: bool = (
		game.is_waiting_for_retry() and not game.is_playing()
		and game.get("_accumulator_seconds") == 0.0 and not paused
		and game.get_node("Board").get("_body") == state.get_body_cells()
	)
	game._physics_process(1.0)
	root.push_input(_key(KEY_UP))
	var frozen_ok: bool = (
		events == [[&"wall_collision", 0]] and _board_state(state) == before
		and not state.get("_has_pending_turn")
	)
	game.free()
	return terminal_ok and frozen_ok


func _parent_retries() -> bool:
	var session := SESSION.instantiate()
	var game := session.get_node("SnakeGame") as SnakeGame
	_configure(game)
	root.add_child(session)
	for frame in range(12):
		if game.is_playing():
			break
		await process_frame
	var passed := game.is_playing() and _exercise_retry_cycles(session, game)
	session.free()
	return passed


func _exercise_retry_cycles(session: Node, game: SnakeGame) -> bool:
	game.set_physics_process(false)
	var state := _retained_fixture()
	game.set("_state", state)
	var expected_food := (FoodChecks.Fixture.new())
	var seeded_rng := RandomNumberGenerator.new()
	seeded_rng.seed = game.food_seed
	expected_food.reset(GRID, seeded_rng)
	var first_food := expected_food.get_food_cell()
	var session_id := session.get_instance_id()
	var snake_id := game.get_instance_id()
	var score := session.get_node("PrototypeHUD/MarginContainer/VBoxContainer/ScoreLabel") as Label
	var status := session.get_node("PrototypeHUD/MarginContainer/VBoxContainer/StatusLabel") as Label
	game.score_changed.emit(2)
	var events := _record_events(game)
	root.push_input(_key(KEY_LEFT))
	game._physics_process(1.0)
	if (
		not game.is_waiting_for_retry() or score.text != "Score: 2"
		or status.text != "Self collision — press Space to retry."
	):
		return false
	root.push_input(_key(KEY_SPACE, true, true))
	root.push_input(_key(KEY_SPACE, false))
	root.push_input(_key(KEY_RIGHT))
	if (
		not game.is_waiting_for_retry() or state.get("_has_pending_turn")
		or events != [[&"self_collision", 2]]
	):
		return false
	root.push_input(_key(KEY_SPACE))
	if (
		not _fresh_attempt(game, state, first_food, score, status)
		or session.get_instance_id() != session_id
		or session.get_node("SnakeGame").get_instance_id() != snake_id
	):
		return false
	game._physics_process(0.19)
	if state.get_body_cells()[0] != Vector2i(4, 4):
		return false
	game._physics_process(0.01)
	if state.get_body_cells()[0] != Vector2i(5, 4):
		return false
	root.push_input(_key(KEY_SPACE))
	if state.get_body_cells()[0] != Vector2i(5, 4) or not game.is_playing():
		return false

	var full := FoodChecks.Fixture.new()
	full.arrange_last_free_cell(GRID, RandomNumberGenerator.new())
	game.set("_state", full)
	game._physics_process(1.0)
	if (
		not game.is_waiting_for_retry() or score.text != "Score: 61"
		or status.text != "Board complete — press Space to play again."
	):
		return false
	root.push_input(_key(KEY_SPACE))
	if not _fresh_attempt(game, full, first_food, score, status):
		return false
	game.stop()
	root.push_input(_key(KEY_SPACE))
	return (
		not game.is_playing() and not game.is_waiting_for_retry()
		and events == [[&"self_collision", 2], [&"score", 0], [&"score", 61], [&"board_full", 61], [&"score", 0]]
	)


func _fresh_attempt(game: SnakeGame, state: SnakeState, food: Vector2i, score: Label, status: Label) -> bool:
	return (
		game.is_playing() and not game.is_waiting_for_retry()
		and game.get("_accumulator_seconds") == 0.0
		and state.get_body_cells() == [Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4)]
		and state.get_direction() == Vector2i.RIGHT and not state.get("_has_pending_turn")
		and state.get_score() == 0 and not state.is_finished() and state.get_finish_reason() == &""
		and state.has_food() and state.get_food_cell() == food
		and Rect2i(Vector2i.ZERO, GRID).has_point(food) and not state.get_body_cells().has(food)
		and score.text == "Score: 0" and status.text.is_empty() and not status.visible
	)


func _configure(game: SnakeGame) -> void:
	game.columns = GRID.x
	game.rows = GRID.y
	game.use_fixed_seed = true


func _record_events(game: SnakeGame) -> Array[Array]:
	var events: Array[Array] = []
	game.score_changed.connect(func(score: int) -> void:
		events.append([&"score", score])
	)
	game.attempt_finished.connect(func(reason: StringName, score: int) -> void:
		events.append([reason, score])
	)
	return events


func _key(keycode: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event
