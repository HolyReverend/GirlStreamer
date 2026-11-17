extends SceneTree

const Director = preload("res://prototype/stream/stream_director.gd")

const SESSION = preload("res://prototype/prototype_session.tscn")
const SessionScript = preload("res://prototype/prototype_session.gd")
const TimedChecks = preload("res://tests/iteration01/test_timed_session.gd")
const StreamChoice = preload("res://prototype/stream/stream_choice.gd")
const SessionState = SessionScript.SessionState
const HUD_PATH := "PrototypeHUD/MarginContainer/VBoxContainer/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_default_deadline, _ready_requires_enter, _pause_excludes_wall_time, _pause_clears_pending_turn,
		_pause_preserves_question_schedule, _pause_preserves_retry,
		_actions_at_cutoff, _closing_and_restart, _bad_configuration,
	]
	for check in checks:
		var passed: bool = await check.call()
		for child in root.get_children():
			child.free()
		if not passed:
			printerr("ITER02_STAGE01_LIFETIME_FAIL ", check.get_method())
			quit(1)
			return
	print("ITER02_STAGE01_LIFETIME_PASS groups=", checks.size())
	quit()


func _make_session(gap_seconds: float = 1.0) -> TimedChecks.ClockSession:
	var scene := SESSION.instantiate()
	scene.set_script(TimedChecks.ClockSession)
	var session := scene as TimedChecks.ClockSession
	session.session_duration_seconds = 10
	session.messages_enabled = true
	var director := session.get_node("StreamDirector") as Director
	director.first_delay_seconds = 1.0
	director.gap_seconds = gap_seconds
	session.question_window_seconds = 2.0
	var game := _game(session)
	game.columns = 8
	game.rows = 8
	game.use_fixed_seed = true
	root.add_child(session)
	session.set_process(false)
	game.set_physics_process(false)
	return session


func _wait_for_layout(session: TimedChecks.ClockSession) -> bool:
	for frame in range(12):
		if session.is_layout_ready():
			return true
		await process_frame
	return false


func _running_session(gap_seconds: float = 1.0) -> TimedChecks.ClockSession:
	var session := _make_session(gap_seconds)
	if await _wait_for_layout(session) and session.start_session():
		return session
	return null


func _game(session: TimedChecks.ClockSession) -> SnakeGame:
	return session.get_node("SnakeGame") as SnakeGame


func _choice(session: TimedChecks.ClockSession) -> StreamChoice:
	return session.get_node("StreamChoice") as StreamChoice


func _board_rect(session: TimedChecks.ClockSession) -> Rect2:
	var board := session.get_node(HUD_PATH + "MainArea/LeftColumn/BoardArea") as Control
	return board.get_global_rect()


func _layout_fits(session: TimedChecks.ClockSession) -> bool:
	var board := _board_rect(session)
	var choice := (session.get_node(HUD_PATH + "MainArea/LeftColumn/ChoiceArea") as Control).get_global_rect()
	var side_path := HUD_PATH + "MainArea/SideColumn/"
	var webcam := (session.get_node(side_path + "WebcamSlot") as Control).get_global_rect()
	var chat := (session.get_node(side_path + "ChatSlot") as Control).get_global_rect()
	var viewport := root.get_visible_rect()
	return (
		board.size.x >= 480.0 and board.size.y >= 360.0 and choice.size.y >= 180.0
		and webcam.size.x >= 280.0 and webcam.size.y >= 160.0 and chat.has_area()
		and viewport.encloses(board) and viewport.encloses(choice)
		and viewport.encloses(webcam) and viewport.encloses(chat)
		and board.end.x <= webcam.position.x and webcam.end.y <= chat.position.y
		and board.end.y <= choice.position.y and choice.end.x <= chat.position.x
	)


func _key(keycode: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)


func _default_deadline() -> bool:
	var scene := SESSION.instantiate()
	scene.set_script(TimedChecks.ClockSession)
	var session := scene as TimedChecks.ClockSession
	root.add_child(session)
	session.set_process(false)
	_game(session).set_physics_process(false)
	if not await _wait_for_layout(session) or not session.start_session():
		return false
	var timer := session.get_node(HUD_PATH + "Header/Stats/TimeLabel") as Label
	if timer.text != "Время: 03:00":
		return false
	var started := session.now
	for due in range(10000, 180000, 10000):
		session.now = started + due - 1
		session._process(0.0)
		if session._donations._next_due_msec != due:
			return false
		session.now = started + due
		session._process(0.0)
		if session._donations._next_due_msec != due + 10000:
			return false
	var paid := session._donations.get_count()
	session.now = started + 179999
	session._process(0.0)
	if session._session_state != SessionState.RUNNING:
		return false
	session.now += 1
	session._process(0.0)
	return (
		session._session_state == SessionState.CLOSING
		and session._results.duration_seconds == 180.0
		and session._results.audience.step_count == 180
		and session._results.donation_count == paid
	)


func _ready_requires_enter() -> bool:
	var session := _make_session()
	var game := _game(session)
	_key(KEY_ENTER)
	if not await _wait_for_layout(session):
		return false
	for size in [Vector2i(1024, 768), Vector2i(1280, 900), Vector2i(1024, 768)]:
		root.size = size
		await process_frame
		await process_frame
		if (
			game.is_playing() or _choice(session).is_open()
			or session._attempts_started != 0 or session.get_stream_time_msec() != 0
			or not _layout_fits(session)
		):
			return false
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	if game.is_playing():
		return false
	_key(KEY_ENTER)
	_key(KEY_ENTER)
	return game.is_playing() and session._attempts_started == 1


func _pause_excludes_wall_time() -> bool:
	var session := await _running_session()
	if session == null:
		return false
	var model := _game(session).get("_state") as SnakeState
	var body := model.get_body_cells()
	session.now = 3000
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, true, true)
	_key(KEY_ESCAPE, false)
	session.now = 63000
	if (
		session._session_state != SessionState.PAUSED or session.get_stream_time_msec() != 2000
		or session.start_session() or session.is_stream_active() or paused
	):
		return false
	_key(KEY_ESCAPE)
	session.now = 64000
	if session.get_stream_time_msec() != 3000 or session.get_remaining_seconds() != 7.0:
		return false
	if not session.pause_session():
		return false
	session.now = 74000
	if not session.resume_session():
		return false
	session.now = 75000
	return (
		session.get_stream_time_msec() == 4000 and session.get_remaining_seconds() == 6.0
		and session._attempts_started == 1 and model.get_body_cells() == body
	)


func _pause_clears_pending_turn() -> bool:
	var session := await _running_session()
	if session == null:
		return false
	var game := _game(session)
	var model := game.get("_state") as SnakeState
	var body := model.get_body_cells()
	var food := model.get_food_cell()
	game._physics_process(0.1)
	_key(KEY_UP)
	if not model.get("_has_pending_turn") or not session.pause_session():
		return false
	session.now = 61000
	_key(KEY_DOWN)
	_key(KEY_ENTER)
	game._physics_process(10.0)
	session._process(0.0)
	if (
		model.get_body_cells() != body or model.get_food_cell() != food or model.get_score() != 0
		or model.get_direction() != Vector2i.RIGHT or session._attempts_started != 1
		or session._session_state != SessionState.PAUSED
	):
		return false
	if not session.resume_session():
		return false
	game._physics_process(0.1)
	if model.get_body_cells()[0] != body[0] + Vector2i.RIGHT:
		return false
	_key(KEY_DOWN)
	game._physics_process(0.2)
	return model.get_body_cells()[0] == body[0] + Vector2i.RIGHT + Vector2i.DOWN


func _pause_preserves_question_schedule() -> bool:
	var session := await _running_session(2.0)
	if session == null:
		return false
	var choice := _choice(session)
	await process_frame
	await process_frame
	var board := _board_rect(session)
	session.now = 1500
	session.pause_session()
	session.now = 11500
	session._process(0.0)
	if session._questions_shown != 0:
		return false
	session.resume_session()
	session.now = 11999
	session._process(0.0)
	if session._questions_shown != 0:
		return false
	session.now = 12000
	session._process(0.0)
	await process_frame
	if not choice.is_open() or choice.get_remaining_seconds(1000) != 2.0 or _board_rect(session) != board:
		return false
	session.now = 12500
	session.pause_session()
	session.now = 72500
	session._process(0.0)
	for key: Key in [KEY_1, KEY_2, KEY_3]:
		_key(key)
	await process_frame
	if (
		session._questions_shown != 1 or not session._choice_resolutions.is_empty()
		or not choice.is_open() or choice.get_remaining_seconds(1500) != 1.5
		or _board_rect(session) != board
	):
		return false
	session.resume_session()
	session.now = 73000
	_key(KEY_1)
	if choice.get_last_resolution().elapsed_msec != 1000 or session._answer_times_seconds != [1.0]:
		return false
	await process_frame
	if _feedback_is_empty(session) or _board_rect(session) != board:
		return false
	session.pause_session()
	session.now = 82000
	session._process(0.0)
	if _feedback_is_empty(session):
		return false
	session.resume_session()
	session.now = 82999
	session._process(0.0)
	if _feedback_is_empty(session) or session._questions_shown != 1:
		return false
	session.now = 83000
	session._process(0.0)
	session._process(0.0)
	return _feedback_is_empty(session) and session._questions_shown == 2


func _pause_preserves_retry() -> bool:
	var session := await _running_session()
	if session == null:
		return false
	var game := _game(session)
	var choice := _choice(session)
	session.now = 2000
	session._process(0.0)
	game._physics_process(2.0)
	if not game.is_waiting_for_retry() or not choice.is_open() or not session.pause_session():
		return false
	_key(KEY_SPACE)
	if session._attempts_started != 1 or not game.is_waiting_for_retry():
		return false
	session.now = 62000
	if not session.resume_session() or not game.is_waiting_for_retry():
		return false
	_key(KEY_SPACE)
	return (
		game.is_playing() and session._attempts_started == 2 and session.get_stream_time_msec() == 1000
		and choice.is_open() and choice.get_remaining_seconds(1000) == 2.0
	)


func _actions_at_cutoff() -> bool:
	for key: Key in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_UP, KEY_1]:
		var session := await _running_session()
		if session == null:
			return false
		var game := _game(session)
		var model := game.get("_state") as SnakeState
		session.now = 2000
		session._process(0.0)
		if key == KEY_SPACE:
			game._physics_process(2.0)
		var body := model.get_body_cells()
		var food := model.get_food_cell()
		session.now = 11000
		_key(key)
		if (
			session._session_state != SessionState.CLOSING or game.is_playing()
			or game.is_waiting_for_retry() or session._attempts_started != 1
			or model.get_body_cells() != body or model.get_food_cell() != food
			or model.get("_has_pending_turn") or session._questions_cancelled != 1
			or session._questions_answered != 0
		):
			printerr("Cutoff action failed: ", key)
			return false
		session.free()
	return true


func _closing_and_restart() -> bool:
	var session := await _running_session()
	if session == null:
		return false
	var choice := _choice(session)
	session.now = 2000
	session._process(0.0)
	session.now = 11000
	_key(KEY_ENTER)
	if (
		session._session_state != SessionState.CLOSING or session.start_session()
		or session.get_stream_time_msec() != 10000 or session.get_remaining_seconds() != 0.0
		or session._choice_resolutions.size() != 1 or session._choice_resolutions[0].outcome != &"cancelled"
		or session._questions_cancelled != 1 or choice.is_open()
	):
		return false
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	session.now = 12999
	session._process(0.0)
	if session._session_state != SessionState.CLOSING:
		return false
	session.now = 13000
	session._process(0.0)
	if session._session_state != SessionState.FINISHED or session._choice_resolutions.size() != 1:
		return false
	_key(KEY_ENTER)
	_key(KEY_ENTER, true, true)
	if (
		session._session_state != SessionState.RUNNING or session.get_stream_time_msec() != 0
		or session._attempts_started != 1 or session._questions_shown != 0
		or session._questions_cancelled != 0 or not session._answer_times_seconds.is_empty()
	):
		return false
	session.now = 23000
	_key(KEY_ENTER)
	if session._session_state != SessionState.CLOSING:
		return false
	_key(KEY_ENTER)
	return session._session_state == SessionState.FINISHED and session._attempts_started == 1


func _bad_configuration() -> bool:
	var session := _make_session()
	if not await _wait_for_layout(session):
		return false
	session.session_duration_seconds = 0
	if session.start_session() or session._session_state != SessionState.READY:
		return false
	session.session_duration_seconds = 10
	session.question_window_seconds = 0.0
	if session.start_session() or session._session_state != SessionState.READY:
		return false
	session.question_window_seconds = 2.0
	var game := _game(session)
	game.columns = 7
	if (
		session.start_session() or session._session_state != SessionState.READY
		or game.is_playing() or _choice(session).is_open()
		or session.get_stream_time_msec() != 0 or session._attempts_started != 0
	):
		return false
	game.columns = 8
	if not session.start_session():
		return false
	session.now += 10000
	session._process(0.0)
	_key(KEY_ENTER)
	if session._session_state != SessionState.FINISHED:
		return false
	var results := session._results
	session.session_duration_seconds = 0
	if session.start_session() or session._session_state != SessionState.FINISHED:
		return false
	if session._results != results or session.get_stream_time_msec() != 10000:
		return false
	session.session_duration_seconds = 10
	return (
		session.start_session() and game.is_playing()
		and session.get_stream_time_msec() == 0 and session._attempts_started == 1
	)


func _feedback_is_empty(session: TimedChecks.ClockSession) -> bool:
	var label := session.get_node(HUD_PATH + "MainArea/LeftColumn/ChoiceArea/MessageContent/FeedbackLabel") as Label
	return label.text.is_empty()