extends SceneTree

const SESSION = preload("res://prototype/prototype_session.tscn")
const TimedChecks = preload("res://tests/iteration01/test_timed_session.gd")
const Messages = preload("res://prototype/messages/quick_messages.gd")
const HUD_PATH := "PrototypeHUD/MarginContainer/VBoxContainer/"
const MESSAGE_PATH := HUD_PATH + "PlayArea/MessageArea/MarginContainer/MessageContent/"


class Events:
	var opens: Array[Array] = []
	var resolutions: Array[Array] = []

	func observe(messages: Messages) -> void:
		messages.question_opened.connect(_on_opened)
		messages.question_resolved.connect(_on_resolved)

	func _on_opened(id: int, prompt: String, options: Array[String]) -> void:
		opens.append([id, prompt, options.duplicate()])

	func _on_resolved(id: int, index: int, elapsed: float, outcome: StringName) -> void:
		resolutions.append([id, index, elapsed, outcome])


var _now := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_scheduling, _answer_and_expiration, _retry_independence,
		_session_expiry, _metrics_and_baseline,
	]
	for check in checks:
		if not await check.call():
			printerr("STAGE05_MESSAGES_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE05_MESSAGES_PASS groups=", checks.size())
	quit()


func _sample() -> int:
	return _now


func _controller(events: Events) -> Messages:
	var messages := Messages.new()
	root.add_child(messages)
	messages.set_time_sampler(_sample)
	events.observe(messages)
	messages.reset_for_session(true, 45.0, 45.0, 5.0)
	return messages


func _session(duration: int) -> TimedChecks.ClockSession:
	var scene := SESSION.instantiate()
	scene.set_script(TimedChecks.ClockSession)
	var session := scene as TimedChecks.ClockSession
	session.session_duration_seconds = duration
	session.messages_enabled = true
	session.first_question_delay_seconds = 1.0
	session.question_gap_seconds = 1.0
	session.question_window_seconds = 2.0
	var game := _game(session)
	game.columns = 8
	game.rows = 8
	game.use_fixed_seed = true
	root.add_child(session)
	session.set_process(false)
	game.set_physics_process(false)
	for frame in range(12):
		if game.is_playing():
			return session
		await process_frame
	session.free()
	printerr("Question fixture session did not start after twelve layout frames")
	return null


func _game(session: TimedChecks.ClockSession) -> SnakeGame:
	return session.get_node("SnakeGame") as SnakeGame


func _messages(session: TimedChecks.ClockSession) -> Messages:
	return session.get_node("QuickMessages") as Messages


func _results(session: TimedChecks.ClockSession) -> Label:
	return session.get_node(HUD_PATH + "ResultsPanel/ResultsLabel") as Label


func _message_text(session: TimedChecks.ClockSession, field: String) -> String:
	var label := session.get_node(MESSAGE_PATH + field + "Slot/" + field + "Label") as Label
	return label.text


func _tick(session: TimedChecks.ClockSession, elapsed_msec: int) -> void:
	session.now = session._start_msec + elapsed_msec
	session._process(0.0)


func _press(key: Key, echo: bool = false, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.echo = echo
	event.pressed = pressed
	root.push_input(event)


func _scheduling() -> bool:
	var events := Events.new()
	var messages := _controller(events)
	messages.tick(44999, true)
	var early_ok := not messages.is_open() and events.opens.is_empty()
	messages.tick(45000, true)
	messages.tick(49000, true)
	var defaults_ok := (
		events.opens == [[1, "Какой цвет выберешь?", ["Красный", "Зелёный", "Синий"]]]
		and messages.is_open() and messages.get_remaining_seconds(45000) == 5.0
	)
	messages.reset_for_session(true, 45.0, 45.0, 5.0)
	events.opens.clear()
	messages.tick(65000, false)
	var waiting_ok := not messages.is_open() and events.opens.is_empty()
	messages.tick(67000, true)
	waiting_ok = waiting_ok and messages.get_remaining_seconds(67000) == 5.0
	_now = 68000
	_press(KEY_2)
	messages.tick(112999, true)
	var gap_ok := events.opens.size() == 1 and events.resolutions == [[1, 1, 1.0, &"answered"]]
	messages.tick(140000, true)
	messages.tick(140001, true)
	gap_ok = gap_ok and events.opens.size() == 2 and events.opens[1][0] == 2
	gap_ok = gap_ok and events.opens[1][1] == "Какой напиток выберешь?"
	messages.reset_for_session(false, 45.0, 45.0, 5.0)
	messages.tick(500000, true)
	var disabled_ok := not messages.is_open() and events.opens.size() == 2
	messages.free()
	return early_ok and defaults_ok and waiting_ok and gap_ok and disabled_ok


func _answer_and_expiration() -> bool:
	for index in range(3):
		var events := Events.new()
		var messages := _controller(events)
		var key := (KEY_1 + index) as Key
		_now = 44999
		_press(key)
		var idle_ok := events.opens.is_empty() and events.resolutions.is_empty()
		messages.tick(45000, true)
		_now = 46250
		_press(key, true)
		_press(key, false, false)
		_press(KEY_F)
		var ignored_ok := events.resolutions.is_empty() and messages.is_open()
		_press(key)
		var selected: String = events.opens[0][2][index]
		var feedback_ok := messages.get_feedback_text() == "Выбрано: " + selected
		messages.tick(47249, true)
		feedback_ok = feedback_ok and not messages.get_feedback_text().is_empty()
		messages.tick(47250, true)
		feedback_ok = feedback_ok and messages.get_feedback_text().is_empty()
		_press(key)
		_press(key, true)
		messages.tick(50000, true)
		var answer_ok := not messages.is_open() and events.resolutions == [[1, index, 1.25, &"answered"]]
		messages.free()
		if not (idle_ok and ignored_ok and feedback_ok and answer_ok):
			return false
	for use_input in [true, false]:
		var events := Events.new()
		var messages := _controller(events)
		messages.tick(59002, true)
		_now = 64002
		if use_input:
			_press(KEY_1)
		else:
			messages.tick(_now, true)
		messages.tick(64003, true)
		_press(KEY_2)
		messages.tick(109001, true)
		var valid := (
			not messages.is_open() and events.opens.size() == 1
			and events.resolutions == [[1, -1, 5.0, &"expired"]]
		)
		messages.free()
		if not valid:
			return false
	return true


func _retry_independence() -> bool:
	for mode: StringName in [&"answer_while_waiting", &"answer_after_retry", &"expire_while_waiting"]:
		var session := await _session(15)
		if session == null:
			return false
		var valid := _check_retry_mode(session, mode)
		session.free()
		if not valid:
			printerr("Retry mode failed: ", mode)
			return false
	return true


func _check_retry_mode(session: TimedChecks.ClockSession, mode: StringName) -> bool:
	var messages := _messages(session)
	var game := _game(session)
	var model := game.get("_state") as SnakeState
	var events := Events.new()
	events.observe(messages)
	var body_before := model.get_body_cells()
	var speed: float = game.get("_active_tick_seconds")
	game._physics_process(0.1)
	var accumulator: float = game.get("_accumulator_seconds")
	_tick(session, 1000)
	var open_ok: bool = (
		messages.is_open() and messages.get("_current_id") == 1
		and model.get_body_cells() == body_before and game.get("_active_tick_seconds") == speed
		and game.get("_accumulator_seconds") == accumulator
	)
	game._physics_process(0.1)
	var movement_ok := model.get_body_cells()[0] == body_before[0] + Vector2i.RIGHT
	game._physics_process(2.0)
	if not (open_ok and movement_ok and game.is_waiting_for_retry() and messages.is_open()):
		return false
	match mode:
		&"answer_while_waiting":
			session.now = session._start_msec + 1750
			_press(KEY_1)
			return game.is_waiting_for_retry() and events.resolutions == [[1, 0, 0.75, &"answered"]]
		&"answer_after_retry":
			_tick(session, 1500)
			var deadline: int = messages.get("_answer_deadline_msec")
			_press(KEY_SPACE)
			var retry_ok: bool = (
				game.is_playing() and messages.is_open() and messages.get("_current_id") == 1
				and deadline == 3000 and messages.get("_answer_deadline_msec") == deadline
			)
			_press(KEY_3)
			return retry_ok and events.resolutions == [[1, 2, 0.5, &"answered"]]
		&"expire_while_waiting":
			_tick(session, 3000)
			_tick(session, 5000)
			var waiting_ok := (
				game.is_waiting_for_retry() and not messages.is_open()
				and events.resolutions == [[1, -1, 2.0, &"expired"]] and events.opens.size() == 1
			)
			_press(KEY_SPACE)
			_tick(session, 5000)
			return waiting_ok and messages.is_open() and events.opens.size() == 2 and events.opens[1][0] == 2
	return false


func _session_expiry() -> bool:
	for at_msec in [3000, 9000]:
		var session := await _session(3)
		if session == null:
			return false
		var valid := _check_session_expiry(session, at_msec)
		session.free()
		if not valid:
			return false
	return true


func _check_session_expiry(session: TimedChecks.ClockSession, at_msec: int) -> bool:
	var messages := _messages(session)
	var id := messages.get_instance_id()
	var events := Events.new()
	events.observe(messages)
	_tick(session, 1000)
	var shown_ok := _message_text(session, "Prompt") == "Какой цвет выберешь?"
	session.now = session._start_msec + at_msec
	_press(KEY_2)
	var summary := _results(session).text
	var cancel_ok: bool = (
		shown_ok and events.resolutions == [[1, -1, 2.0, &"cancelled"]]
		and not messages.is_open() and not messages.get("_enabled")
		and messages.get_feedback_text().is_empty() and _metrics(session) == [1, 0, 0, 1]
		and session._active_question_id == 0 and _results(session).is_visible_in_tree()
		and summary.contains("Cancelled: 1") and _message_text(session, "Prompt").is_empty()
		and _message_text(session, "Feedback").is_empty()
	)
	session._process(0.0)
	_press(KEY_2)
	var frozen_ok := events.resolutions.size() == 1 and _results(session).text == summary
	_press(KEY_ENTER)
	_tick(session, 999)
	var reset_ok := (
		_messages(session).get_instance_id() == id and not messages.is_open()
		and messages.get_feedback_text().is_empty() and _metrics(session) == [0, 0, 0, 0]
		and session._answer_times_seconds.is_empty() and not _results(session).is_visible_in_tree()
	)
	_tick(session, 1000)
	reset_ok = reset_ok and events.opens.size() == 2 and events.opens[1][0] == 1
	return cancel_ok and frozen_ok and reset_ok


func _metrics_and_baseline() -> bool:
	var session := await _session(7)
	if session == null:
		return false
	_tick(session, 1000)
	session.now = session._start_msec + 2250
	_press(KEY_1)
	_tick(session, 3250)
	_tick(session, 5250)
	_tick(session, 6250)
	_tick(session, 7000)
	var summary := _results(session).text
	var counts_ok := (
		_metrics(session) == [3, 1, 1, 1] and session._answer_times_seconds == [1.25]
		and session._active_question_id == 0 and summary.contains("50%")
		and summary.contains("Mean response time: 1.25 s")
		and summary.contains("Shown: 3") and summary.contains("Answered: 1")
		and summary.contains("Expired: 1") and summary.contains("Cancelled: 1")
	)
	session.messages_enabled = false
	_press(KEY_ENTER)
	_tick(session, 1000)
	_tick(session, 6500)
	var playable := _game(session).is_playing() and not _messages(session).is_open()
	_tick(session, 7000)
	summary = _results(session).text
	var disabled_ok := (
		_metrics(session) == [0, 0, 0, 0] and session._answer_times_seconds.is_empty()
		and summary.contains("Messages: off") and summary.count("N/A") == 2
	)
	session.free()
	return counts_ok and playable and disabled_ok


func _metrics(session: TimedChecks.ClockSession) -> Array[int]:
	return [
		session._questions_shown, session._questions_answered,
		session._questions_expired, session._questions_cancelled,
	]
