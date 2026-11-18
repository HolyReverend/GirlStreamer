extends SceneTree

const DAYS = preload("res://prototype/day/day_cycle.tscn")
const SESSION = preload("res://prototype/prototype_session.tscn")
const Session = preload("res://prototype/prototype_session.gd")
const DayModel = preload("res://prototype/day/day_state.gd")
const Forecast = preload("res://prototype/day/stream_forecast.gd")
const FoodChecks = preload("res://tests/iteration01/test_snake_food.gd")

const GRID := Vector2i(8, 8)


class Fixture extends FoodChecks.Fixture:
	func arrange(body: Array[Vector2i], direction: Vector2i, food: Vector2i) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		reset(Vector2i(8, 8), rng)
		_body = body.duplicate()
		_direction = direction
		_score = body.size() - INITIAL_LENGTH
		place_food(food)

	func values() -> Array:
		return [
			_body.duplicate(), _direction, _has_pending_turn, _pending_direction,
			_has_food, _food_cell, _score, _finish_reason, _random_source.state,
		]


class ClockSession extends Session:
	var clock_msec := 1000

	func _now_msec() -> int:
		return clock_msec


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_tier_boundaries, _projected_paths, _seeded_equivalence, _room_to_runtime,
		_warning_lifecycle, _question_deadline,
	]
	for check in checks:
		var passed: bool = await check.call()
		for child in root.get_children():
			child.free()
		if not passed:
			printerr("STAGE03_STREAM_CONDITION_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE03_STREAM_CONDITION_PASS groups=", checks.size())
	quit()


func _room_to_runtime() -> bool:
	for rested: bool in [false, true]:
		var cycle := DAYS.instantiate()
		root.add_child(cycle)
		var room := cycle.get_node("PreparationScreen")
		room.emit_signal("activity_requested", &"train_snake")
		room.emit_signal("activity_requested", &"train_snake")
		if rested:
			room.emit_signal("activity_requested", &"watch_anime")
		var forecast := (room.get_node("%Forecast") as Label).text
		if not forecast.contains("2 клетки") or not forecast.contains("обычное" if rested else "−10%"):
			return false
		room.emit_signal("stream_requested")
		var host := cycle.get_node("StreamHost")
		for frame in range(16):
			if not room.visible:
				break
			await process_frame
		if room.visible or host.get_child_count() != 1:
			return false
		var session := host.get_child(0) as Session
		session.set_process(false)
		session._snake_game.set_physics_process(false)
		session._stream_audio.set_muted(true)
		if session._get_viewer_count() != 30 or session._snake_game._warning_range != 2:
			return false
		session._director.tick(20000, true)
		var choice := session._stream_choice
		if not choice.is_open() or choice._active.window_msec != (6000 if rested else 5400):
			return false
		cycle.free()
	return true


func _tier_boundaries() -> bool:
	var conditions := [0, 2, 3, 5, 6, 10]
	var cells := [0, 0, 1, 1, 2, 2]
	var scales := [0.8, 0.8, 0.9, 0.9, 1.0, 1.0]
	for index in conditions.size():
		var value: int = conditions[index]
		if (
			Forecast.warning_cells(0, value) != 0
			or Forecast.warning_cells(1, value) != cells[index]
			or not is_equal_approx(Forecast.question_window_scale(value), scales[index])
		):
			return false
	return true


func _projected_paths() -> bool:
	var state := _near_wall()
	var before := state.values()
	if state.predict_danger(0) != null or state.predict_danger(1) != null:
		return false
	var hint := state.predict_danger(2)
	if (
		hint == null or hint.kind != &"wall_collision" or hint.distance != 2
		or hint.last_legal_head != Vector2i(7, 3) or hint.attempted_cell != Vector2i(8, 3)
		or state.values() != before
	):
		return false
	if (
		state.request_turn(Vector2i.LEFT) or not state.request_turn(Vector2i.UP)
		or state.request_turn(Vector2i.DOWN) or state.predict_danger(2) != null
	):
		return false

	var loop_body: Array[Vector2i] = [
		Vector2i(2, 2), Vector2i(2, 3), Vector2i(1, 3), Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 1),
	]
	state.arrange(loop_body, Vector2i.UP, Vector2i(6, 6))
	state.request_turn(Vector2i.LEFT)
	# The second target is retained before step one, then becomes a vacating tail.
	if state.predict_danger(2) != null:
		return false
	state.place_food(Vector2i(1, 2))
	hint = state.predict_danger(2)
	if (
		hint == null or hint.kind != &"self_collision" or hint.distance != 2
		or hint.last_legal_head != Vector2i(1, 2) or hint.attempted_cell != Vector2i(0, 2)
		or not state.step() or state.step() or state.get_finish_reason() != &"self_collision"
		or state.predict_danger(2) != null
	):
		return false

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	state.arrange_last_free_cell(GRID, rng)
	return (
		state.predict_danger(2) == null and state.step() and state.is_complete()
		and state.predict_danger(2) == null
	)


func _seeded_equivalence() -> bool:
	var with_warning := Fixture.new()
	var baseline := Fixture.new()
	for state: Fixture in [with_warning, baseline]:
		state.arrange(
			[Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4)], Vector2i.RIGHT, Vector2i(4, 5)
		)
		if not state.request_turn(Vector2i.DOWN):
			return false
	for move in range(4):
		var before := with_warning.values()
		for sample in range(3):
			with_warning.predict_danger(2)
		if with_warning.values() != before or with_warning.step() != baseline.step():
			return false
		if with_warning.values() != baseline.values():
			return false
	return (
		with_warning.get_score() >= 1 and with_warning.get_finish_reason() == &"wall_collision"
		and with_warning.predict_danger(2) == null
	)


func _warning_lifecycle() -> bool:
	# High concentration stays normal here regardless of vigor or mastery.
	for preset: Array in [[0, 10, 0], [1, 2, 0], [1, 5, 1], [1, 6, 2]]:
		var session := _mount_session()
		if not await _wait_for_layout(session):
			return false
		var launch := DayModel.LaunchSnapshot.new()
		launch.mastery_level = preset[0]
		launch.vigor = preset[1]
		launch.concentration = 10
		if not session.start_session(launch):
			return false
		launch.vigor = 0
		launch.mastery_level = 0
		var game := session._snake_game
		game._state = _near_wall()
		game._publish_snapshot()
		var board := game.get_node("Board") as SnakeBoard
		var expected: int = preset[2]
		if _distance(board) != (2 if expected == 2 else 0):
			return false
		if expected == 2:
			_press(&"snake_up")
			if _distance(board) != 0 or not session.pause_session() or _distance(board) != 2:
				return false
			if not session.resume_session():
				return false
		game._physics_process(game.tick_interval_seconds)
		if _distance(board) != (1 if expected > 0 else 0):
			return false
		game._physics_process(game.tick_interval_seconds)
		if (
			_distance(board) != 0 or not game.is_waiting_for_retry()
			or game._state.get_finish_reason() != &"wall_collision" or game._state.get_score() != 0
			or not session._try_retry_attempt() or game._warning_range != expected
		):
			return false
		game._state = _near_wall()
		game._publish_snapshot()
		if _distance(board) != (2 if expected == 2 else 0):
			return false
		session.clock_msec += session.session_duration_seconds * 1000
		session._process(0.0)
		if _distance(board) != 0 or session._session_state != Session.SessionState.CLOSING:
			return false
		session.free()
	return true


func _question_deadline() -> bool:
	var session := _mount_session()
	if not await _wait_for_layout(session):
		return false
	var launch := DayModel.LaunchSnapshot.new()
	launch.mastery_level = 1
	launch.vigor = 10
	launch.concentration = 2
	if not session.start_session(launch):
		return false
	launch.concentration = 10
	var choice := session._stream_choice
	session._director.tick(20000, true)
	if not choice.is_open() or choice._active.window_msec != 5000:
		return false

	session.clock_msec = 22500
	if not session.pause_session():
		return false
	session.clock_msec += 8000
	if not is_equal_approx(choice.get_remaining_seconds(session.get_stream_time_msec()), 3.5):
		return false
	if not session.resume_session():
		return false

	var game := session._snake_game
	game._state = _near_wall()
	game._physics_process(game.tick_interval_seconds * 2)
	if not session._try_retry_attempt() or choice._deadline_msec != 25000:
		return false

	# Total active time reaches the adjusted deadline despite the wall-clock pause.
	session.clock_msec = 34000
	var answer := InputEventAction.new()
	answer.action = &"message_answer_1"
	answer.pressed = true
	root.push_input(answer)
	var resolved := choice.get_last_resolution()
	if resolved == null or resolved.outcome != &"expired" or resolved.elapsed_msec != 5000:
		return false
	session._finish_session(session.clock_msec)
	_press(&"session_restart")
	_press(&"session_restart")
	if session._session_state != Session.SessionState.FINISHED:
		return false
	session.free()

	var standalone := _mount_session()
	if not await _wait_for_layout(standalone) or not standalone.start_session():
		return false
	standalone._finish_session(standalone.clock_msec)
	_press(&"session_restart")
	if standalone._session_state != Session.SessionState.FINISHED:
		return false
	_press(&"session_restart")
	if not standalone.is_stream_active():
		return false
	standalone._director.tick(20000, true)
	var standalone_choice := standalone._stream_choice
	return (
		standalone._snake_game._warning_range == 0
		and standalone_choice.is_open() and standalone_choice._active.window_msec == 6000
	)


func _mount_session() -> ClockSession:
	var node := SESSION.instantiate()
	node.set_script(ClockSession)
	var session := node as ClockSession
	root.add_child(session)
	session.set_process(false)
	session._stream_audio.set_muted(true)
	var game := session._snake_game
	game.columns = GRID.x
	game.rows = GRID.y
	game.use_fixed_seed = true
	game.set_physics_process(false)
	return session


func _wait_for_layout(session: Session) -> bool:
	for frame in range(12):
		if session.is_layout_ready():
			return true
		await process_frame
	return false


func _near_wall() -> Fixture:
	var state := Fixture.new()
	state.arrange(
		[Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)], Vector2i.RIGHT, Vector2i.ZERO
	)
	return state


func _distance(board: SnakeBoard) -> int:
	return 0 if board._danger_hint == null else board._danger_hint.distance


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
