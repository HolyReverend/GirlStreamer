extends SceneTree

const SESSION = preload("res://prototype/prototype_session.tscn")
const SessionScript = preload("res://prototype/prototype_session.gd")
const FoodChecks = preload("res://tests/iteration01/test_snake_food.gd")
const GRID := Vector2i(8, 8)
const HUD_PATH := "PrototypeHUD/MarginContainer/VBoxContainer/"


class ClockSession extends SessionScript:
	var now := 1000
	var fixture_started_at := 1000
	var samples: Array[int] = []

	func _now_msec() -> int:
		if not samples.is_empty():
			now = samples.pop_front()
		return now


class ModelFixture extends FoodChecks.Fixture:
	func arrange_scored_wall() -> void:
		reset(Vector2i(8, 8), RandomNumberGenerator.new())
		_body.assign([
			Vector2i(7, 3), Vector2i(6, 3), Vector2i(5, 3),
			Vector2i(4, 3), Vector2i(3, 3), Vector2i(2, 3),
		])
		_score = 3
		place_food(Vector2i.ZERO)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_retry_preserves_session, _expiry_precedes_actions, _accounting,
		_new_session_resets_once, _presentation_and_input_boundary,
	]
	for check in checks:
		if not await check.call():
			printerr("STAGE04_SESSION_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE04_SESSION_PASS groups=", checks.size())
	quit()


func _session() -> ClockSession:
	var scene := SESSION.instantiate()
	scene.set_script(ClockSession)
	var session := scene as ClockSession
	session.session_duration_seconds = 2
	session.messages_enabled = false
	var game := _game(session)
	game.columns = GRID.x
	game.rows = GRID.y
	game.use_fixed_seed = true
	root.add_child(session)
	session.set_process(false)
	game.set_physics_process(false)
	for frame in range(12):
		if session.is_layout_ready() and session.start_session():
			return session
		await process_frame
	session.free()
	printerr("Timed session did not start after twelve layout frames")
	return null


func _game(session: ClockSession) -> SnakeGame:
	return session.get_node("SnakeGame") as SnakeGame


func _model(game: SnakeGame) -> SnakeState:
	return game.get("_state") as SnakeState


func _label(session: ClockSession, path: String) -> Label:
	return session.get_node(HUD_PATH + path) as Label


func _results(session: ClockSession) -> Label:
	return _label(session, "ResultsPanel/ResultsScroll/ResultsLabel")


func _totals(session: ClockSession) -> Array[int]:
	return [session._total_food, session._attempts_started, session._collisions, session._boards_completed]


func _press(keycode: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)


func _collide_with_three_food(game: SnakeGame) -> void:
	var state := ModelFixture.new()
	state.arrange_scored_wall()
	game.set("_state", state)
	game.score_changed.emit(3)
	game._physics_process(0.2)


func _arm_next_collection(game: SnakeGame) -> FoodChecks.Fixture:
	var fixture := ModelFixture.new()
	fixture.reset(GRID, RandomNumberGenerator.new())
	fixture.place_food(Vector2i(5, 4))
	game.set("_state", fixture)
	return fixture


func _retry_preserves_session() -> bool:
	var session := await _session()
	if session == null:
		return false
	var game := _game(session)
	var session_id := session.get_instance_id()
	var game_id := game.get_instance_id()
	session.now = 1500
	_collide_with_three_food(game)
	var collision_ok := game.is_waiting_for_retry() and _totals(session) == [3, 1, 1, 0]
	session.now = 2000
	session._process(0.0)
	var waiting_ok := (
		game.is_waiting_for_retry() and session.get_elapsed_seconds() == 1.0
		and _label(session, "Header/Stats/TimeLabel").text == "Время: 00:01"
	)
	_press(KEY_SPACE)
	var retry_ok := (
		game.is_playing() and session.get_stream_time_msec() == 1000 and session.get_remaining_seconds() == 1.0
		and _totals(session) == [3, 2, 1, 0] and _model(game).get_score() == 0
		and session.get_instance_id() == session_id and _game(session).get_instance_id() == game_id
	)
	session.free()
	return collision_ok and waiting_ok and retry_ok


func _expiry_precedes_actions() -> bool:
	for action: StringName in [&"movement", &"retry", &"stall", &"direction", &"before", &"catchup"]:
		var session := await _session()
		if session == null:
			return false
		var valid := _check_expiry_action(session, action)
		session.free()
		if not valid:
			printerr("Expiry action failed: ", action)
			return false
	return true


func _check_expiry_action(session: ClockSession, action: StringName) -> bool:
	var game := _game(session)
	var model: SnakeState = _arm_next_collection(game)
	if action == &"retry":
		session.now = 1500
		_collide_with_three_food(game)
		model = _model(game)
	var body_before := model.get_body_cells()
	var food_before := model.get_food_cell()
	var totals_before := _totals(session)
	session.now = 3000
	match action:
		&"retry":
			_press(KEY_SPACE)
		&"direction":
			_press(KEY_UP)
		&"stall":
			session.now = 12000
			game._physics_process(5.0)
		&"before":
			session.now = 2999
			game._physics_process(0.2)
			return game.is_playing() and model.get_score() == 1 and _totals(session) == [1, 1, 0, 0]
		&"catchup":
			session.samples.assign([2999, 2999, 3000])
			game._physics_process(0.6)
			return (
				_closing(session) and model.get_score() == 1 and _totals(session) == [1, 1, 0, 0]
				and model.get_body_cells().size() == 4 and model.get_body_cells()[0] == Vector2i(5, 4)
				and game.get_node("Board").get("_body") == model.get_body_cells()
				and not _results(session).is_visible_in_tree()
			)
		_:
			game._physics_process(0.2)
	var frozen: bool = (
		_closing(session) and model.get_body_cells() == body_before and model.get_food_cell() == food_before
		and _totals(session) == totals_before and not model.get("_has_pending_turn")
		and not _results(session).is_visible_in_tree()
	)
	var result := _results(session).text
	session._process(0.0)
	game._physics_process(2.0)
	_press(KEY_SPACE)
	return frozen and _results(session).text == result and _totals(session) == totals_before


func _accounting() -> bool:
	var session := await _session()
	if session == null:
		return false
	var game := _game(session)
	session.now = 1500
	_collide_with_three_food(game)
	session.now = 2000
	_press(KEY_SPACE)
	var state := _arm_next_collection(game)
	game._physics_process(0.2)
	state.place_food(Vector2i(6, 4))
	game._physics_process(0.2)
	session.now = 3000
	session._process(0.0)
	var accounting_ok := (
		_closing(session) and _totals(session) == [5, 2, 1, 0]
		and _label(session, "Header/Stats/ScoreLabel").text == "Счёт: 2"
		and _label(session, "Header/Stats/SessionFoodLabel").text == "Еда за эфир: 5"
	)
	session.free()
	return accounting_ok and await _full_board_accounting()


func _full_board_accounting() -> bool:
	var session := await _session()
	if session == null:
		return false
	var game := _game(session)
	var near_full := FoodChecks.Fixture.new()
	near_full.arrange_last_free_cell(GRID, RandomNumberGenerator.new())
	game.set("_state", near_full)
	game.score_changed.emit(60)
	game._physics_process(0.2)
	var board_ok := game.is_waiting_for_retry() and _totals(session) == [61, 1, 0, 1]
	session.now = 3000
	session._process(0.0)
	var accounting_ok := board_ok and _closing(session) and _totals(session) == [61, 1, 0, 1]
	session.free()
	return accounting_ok


func _new_session_resets_once() -> bool:
	var session := await _session()
	if session == null:
		return false
	var game := _game(session)
	var session_id := session.get_instance_id()
	var game_id := game.get_instance_id()
	var scores: Array[int] = []
	game.score_changed.connect(func(score: int) -> void: scores.append(score))
	_collide_with_three_food(game)
	var reset_ok := true
	for cycle in range(2):
		session.now = session.fixture_started_at + 2000
		session._process(0.0)
		_press(KEY_SPACE)
		_press(KEY_ENTER, true, true)
		_press(KEY_ENTER, false)
		if not _closing(session):
			reset_ok = false
			break
		_press(KEY_ENTER)
		session.now += 500
		session.fixture_started_at = session.now
		_press(KEY_ENTER)
		session.now += 250
		_press(KEY_ENTER)
		if not (
			session.get_stream_time_msec() == 250 and session.get_remaining_seconds() == 1.75
			and _totals(session) == [0, 1, 0, 0] and game.is_playing()
			and game.get("_accumulator_seconds") == 0.0 and not _results(session).is_visible_in_tree()
			and _model(game).get_body_cells() == [Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4)]
			and _model(game).has_food() and not _model(game).is_finished() and _model(game).get_score() == 0
			and session.get_instance_id() == session_id and _game(session).get_instance_id() == game_id
		):
			reset_ok = false
			break
	session.free()
	return reset_ok and scores == [3, 0, 0]


func _presentation_and_input_boundary() -> bool:
	var session := await _session()
	if session == null:
		return false
	_collide_with_three_food(_game(session))
	session.now = 2999
	session._process(0.0)
	var rounding_ok := _label(session, "Header/Stats/TimeLabel").text == "Время: 00:01"
	session.now = 3000
	_press(KEY_ENTER)
	var closing_ok := _closing(session)
	_press(KEY_ENTER)
	var text := _results(session).text
	var result_ok := (
		closing_ok and session.get_elapsed_seconds() == 2.0
		and session.get_remaining_seconds() == 0.0 and _totals(session) == [3, 1, 1, 0]
		and _label(session, "Header/Stats/TimeLabel").text == "Время: 00:00"
		and session._session_state == SessionScript.SessionState.FINISHED
		and _results(session).is_visible_in_tree() and text.contains("Длительность: 00:02")
		and text.contains("Собрано еды: 3") and text.contains("Начато попыток: 1")
		and text.contains("Столкновения: 1") and text.contains("Заполнено полей: 0")
		and _label(session, "ResultsInstructions").text == "Enter — новый стрим"
	)
	session.now = 4500
	session._process(0.0)
	var frozen_ok := _results(session).text == text
	session.free()
	return rounding_ok and result_ok and frozen_ok


func _closing(session: ClockSession) -> bool:
	var game := _game(session)
	return (
		session._session_state == SessionScript.SessionState.CLOSING
		and not game.is_playing() and not game.is_waiting_for_retry()
		and game.get("_accumulator_seconds") == 0.0 and not _results(session).is_visible_in_tree()
	)
