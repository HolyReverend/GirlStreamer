extends SceneTree

const Director = preload("res://prototype/stream/stream_director.gd")

const SessionScene = preload("res://prototype/prototype_session.tscn")
const TimedChecks = preload("res://tests/iteration01/test_timed_session.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const Choice = preload("res://prototype/stream/stream_choice.gd")
const Event = preload("res://prototype/stream/stream_event.gd")

var _now := 0
var _samples := 0
var _opens: Array[Content.ChoiceDefinition] = []
var _outcomes: Array[Content.ChoiceResolution] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_catalog, _malformed_catalog, _snapshot_and_keys, _exact_boundary, _reentrant_cancel,
		_default_schedule, _context_freshness, _context_catalog, _exhausted_general_pool,
		_finish_metrics_and_restart, _disabled_questions, _reply_priority, _caption_fit,
		_pause_at_deadline, _resolution_while_waiting,
	]
	for check in checks:
		_opens.clear()
		_outcomes.clear()
		var passed: bool = await check.call()
		for child in root.get_children():
			child.free()
		if not passed:
			printerr("ITER02_STAGE03_CHOICES_FAIL ", check.get_method())
			quit(1)
			return
	print("ITER02_STAGE03_CHOICES_PASS groups=", checks.size())
	quit()


func _catalog() -> bool:
	var templates := Content.get_questions()
	var ids := {}
	var option_ids := {}
	var replies := {}
	var contexts := {&"general": 0, &"achievement": 0, &"loss": 0}
	for question in templates:
		if question.id in ids or question.context not in contexts or question.options.size() != 3:
			return false
		ids[question.id] = true
		contexts[question.context] += 1
		var labels := {}
		var effects := {}
		for option in question.options:
			if (
				option.id in option_ids or option.reply in replies or option.label in labels
				or option.effects in effects or option.chat_responses.size() != 2
				or option.chat_responses[0] == option.chat_responses[1]
			):
				return false
			option_ids[option.id] = true
			replies[option.reply] = true
			labels[option.label] = true
			effects[option.effects] = true
	return contexts == {&"general": 6, &"achievement": 3, &"loss": 3}


func _definition(id: int) -> Content.ChoiceDefinition:
	var question := Content.get_questions()[0]
	return Content.ChoiceDefinition.new(
		id, question.id, &"question", question.prompt, "Viewer", question.options, 6000, 0, -1
	)


func _observe(choice: Choice) -> void:
	choice.opened.connect(func(definition: Content.ChoiceDefinition): _opens.append(definition))
	choice.resolved.connect(func(_id: int, _index: int, _outcome: StringName):
		_outcomes.append(choice.get_last_resolution())
	)


func _controller() -> Choice:
	var choice := Choice.new()
	root.add_child(choice)
	_observe(choice)
	_samples = 0
	choice.set_time_sampler(func() -> int:
		_samples += 1
		return _now
	)
	return choice


func _snapshot_and_keys() -> bool:
	var choice := _controller()
	var keys: Array[Key] = [KEY_1, KEY_2, KEY_3]
	for index in range(3):
		var definition := _definition(index + 1)
		var prompt := definition.prompt
		var reply := definition.options[index].reply
		var response := definition.options[index].chat_responses[0]
		var effects := definition.options[index].effects
		if not choice.try_open(definition, 1000) or choice.try_open(_definition(99), 1001):
			return false
		definition.prompt = "changed"
		definition.window_msec = 1
		definition.options[index].reply = "changed"
		definition.options[index].chat_responses[0] = "changed"
		_opens[-1].options[index].effects = Vector3.ZERO
		if _opens[-1].prompt != prompt or choice.get_remaining_seconds(1000) != 6.0:
			return false
		_now = 6999
		_key(keys[index], false)
		_key(keys[index], true, true)
		_key(KEY_KP_1)
		if not choice.is_open() or _samples != index:
			return false
		_key(keys[index])
		_key(keys[index])
		if choice.is_open() or _samples != index + 1 or _outcomes.size() != index + 1:
			return false
		var result := _outcomes[-1]
		if (
			result.choice_id != index + 1 or result.option_index != index
			or result.outcome != &"answered" or result.elapsed_msec != 5999
			or result.option.reply != reply or result.option.effects != effects
			or result.option.chat_responses[0] != response
		):
			return false
		result.option.chat_responses.clear()
		if choice.get_last_resolution().option.chat_responses.size() != 2:
			return false
	return _opens.size() == 3


func _exact_boundary() -> bool:
	var choice := _controller()
	if not choice.try_open(_definition(1), 1000):
		return false
	choice.tick(6999)
	if not choice.is_open():
		return false
	_now = 7000
	_key(KEY_1)
	if not choice.try_open(_definition(2), 7000):
		return false
	choice.tick(13000)
	choice.cancel(13000)
	if _outcomes.size() != 2:
		return false
	for result in _outcomes:
		if result.outcome != &"expired" or result.option != null or result.option_index != -1:
			return false
	return true


func _reentrant_cancel() -> bool:
	var choice := _controller()
	choice.set_time_sampler(func() -> int:
		_samples += 1
		choice.cancel(7000)
		return -1
	)
	if not choice.try_open(_definition(1), 1000):
		return false
	_key(KEY_2)
	return (
		_samples == 1 and not choice.is_open() and _outcomes.size() == 1
		and _outcomes[0].outcome == &"cancelled" and _outcomes[0].option == null
	)


func _session(duration: int = 360, delay: float = 30.0, gap: float = 25.0,
		enabled: bool = true) -> TimedChecks.ClockSession:
	var node := SessionScene.instantiate()
	node.set_script(TimedChecks.ClockSession)
	var session := node as TimedChecks.ClockSession
	session.session_duration_seconds = duration
	session.messages_enabled = enabled
	var director := session.get_node("StreamDirector") as Director
	director.first_delay_seconds = delay
	director.gap_seconds = gap
	var game := _game(session)
	game.columns = 8
	game.rows = 8
	game.use_fixed_seed = true
	root.add_child(session)
	session.set_process(false)
	game.set_physics_process(false)
	if not session.has_node("StreamChoice"):
		printerr("Startup session must include StreamChoice")
		return null
	_observe(session.get_node("StreamChoice") as Choice)
	for frame in range(12):
		if session.is_layout_ready() and session.start_session():
			session._donations.stop()
			return session
		await process_frame
	return null


func _game(session: TimedChecks.ClockSession) -> SnakeGame:
	return session.get_node("SnakeGame") as SnakeGame


func _tick(session: TimedChecks.ClockSession, elapsed_msec: int) -> void:
	session.now = session.fixture_started_at + elapsed_msec
	session._process(0.0)


func _key(key: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)


func _default_schedule() -> bool:
	var session := await _session()
	if session == null:
		return false
	_tick(session, 29999)
	if not _opens.is_empty():
		return false
	_tick(session, 30000)
	# Neutral organic growth has brought the audience to 33 at the first opening.
	if _opens.size() != 1 or _opens[0].window_msec != 5970:
		return false
	_tick(session, 32000)
	_key(KEY_UP)
	var game := _game(session)
	var state := game.get("_state") as SnakeState
	game._physics_process(0.2)
	if not session._stream_choice.is_open() or state.get_direction() != Vector2i.UP:
		return false
	_key(KEY_2)
	if (
		state.get_direction() != Vector2i.UP or _outcomes.size() != 1
		or _outcomes[0].elapsed_msec != 2000
	):
		return false
	game._physics_process(2.0)
	_tick(session, 200000)
	if not game.is_waiting_for_retry() or _opens.size() != 1:
		return false
	_key(KEY_SPACE)
	_tick(session, 200001)
	return _opens.size() == 2 and _opens[1].id == 2 and _opens[0].template_id != _opens[1].template_id


func _pause_at_deadline() -> bool:
	var session := await _session(30, 1.0, 1.0)
	if session == null:
		return false
	_tick(session, 1000)
	session.now = 8000
	if not session.pause_session() or _outcomes.size() != 1 or _outcomes[0].outcome != &"expired":
		return false
	if session._stream_choice.is_open() or _opens.size() != 1:
		return false
	session.now = 68000
	return session.get_stream_time_msec() == 7000 and _outcomes.size() == 1


func _resolution_while_waiting() -> bool:
	for should_answer in [true, false]:
		var session := await _session(30, 1.0, 1.0)
		if session == null:
			return false
		_tick(session, 1000)
		_game(session)._physics_process(2.0)
		if not _game(session).is_waiting_for_retry() or not session._stream_choice.is_open():
			return false
		if should_answer:
			_tick(session, 1500)
			_key(KEY_1)
			if _outcomes.size() != 1 or _outcomes[0].outcome != &"answered":
				return false
		else:
			_tick(session, 7000)
			if _outcomes.size() != 1 or _outcomes[0].outcome != &"expired":
				return false
		session.free()
		_opens.clear()
		_outcomes.clear()
	return true


func _context_freshness() -> bool:
	for age in [15000, 15001]:
		var session := await _session(120, 20.0)
		if session == null:
			return false
		_tick(session, 20000 - age)
		_game(session)._physics_process(2.0)
		_tick(session, 19999)
		if not _opens.is_empty() or not _game(session).is_waiting_for_retry():
			return false
		_key(KEY_SPACE)
		_tick(session, 20000)
		if _opens.size() != 1:
			return false
		var expected: StringName = &"q10" if age == 15000 else &"q01"
		if _opens[0].template_id != expected or (_opens[0].source_event_id > 0) != (age == 15000):
			return false
		session.free()
		_opens.clear()
	return true


func _exhausted_general_pool() -> bool:
	var session := await _session(30, 1.0, 1.0)
	if session == null:
		return false
	for index in range(1, 7):
		_tick(session, index * 1000)
		if _opens.size() != index or _opens[-1].template_id != StringName("q%02d" % index):
			return false
		_key(KEY_1)
	_tick(session, 7000)
	if _opens.size() != 6:
		return false
	_game(session)._physics_process(2.0)
	_key(KEY_SPACE)
	_tick(session, 8000)
	return _opens.size() == 7 and _opens[-1].template_id == &"q10"


func _finish_metrics_and_restart() -> bool:
	var session := await _session(16, 1.0, 1.0)
	if session == null:
		return false
	_tick(session, 1000)
	_tick(session, 1500)
	_key(KEY_3)
	_tick(session, 2500)
	_tick(session, 8500)
	_tick(session, 10000)
	# The stream and choice deadlines both fall at 16000.
	_tick(session, 15999)
	session.now += 1
	_key(KEY_1)
	_key(KEY_1)
	if (
		_outcomes.size() != 3 or _outcomes[2].outcome != &"cancelled"
		or session._questions_shown != 3 or session._questions_answered != 1
		or session._questions_expired != 1 or session._questions_cancelled != 1
		or session._answer_times_seconds != [0.5] or session._results.questions_cancelled != 1
	):
		return false
	_key(KEY_ENTER)
	var summary := (session.get_node(
		"PrototypeHUD/MarginContainer/VBoxContainer/ResultsPanel/ResultsScroll/ResultsLabel"
	) as Label).text
	if not summary.contains("50%"):
		return false
	_key(KEY_ENTER)
	session.fixture_started_at = session.now
	_tick(session, 1000)
	return (
		session._choice_resolutions.is_empty() and _opens.size() == 4
		and _opens[-1].id == 1 and _opens[-1].template_id == _opens[0].template_id
	)


func _disabled_questions() -> bool:
	var session := await _session(10, 1.0, 1.0, false)
	if session == null:
		return false
	_tick(session, 4000)
	_key(KEY_1)
	var feed := session.get_node("ChatFeed")
	return (
		_game(session).is_playing() and feed.get_lines().size() >= 2
		and _opens.is_empty() and session._choice_resolutions.is_empty()
	)


func _reply_priority() -> bool:
	var session := await _session(20, 1.0, 1.0)
	if session == null:
		return false
	var webcam := session.get_node(
		"PrototypeHUD/MarginContainer/VBoxContainer/MainArea/SideColumn/WebcamSlot/HeroWebcam"
	)
	var caption := webcam.get_node("CaptionLabel") as Label
	var feed := session.get_node("ChatFeed")
	_tick(session, 1000)
	_key(KEY_1)
	var first := _outcomes[0].option
	var lines: Array[Content.ChatLine] = feed.get_lines()
	if (
		lines.size() != 2 or lines[-1].context != &"answer"
		or lines[-1].text not in first.chat_responses or webcam.get_emotion() != first.emotion
		or caption.text != first.reply
	):
		return false
	webcam.show_automatic(&"sad", 1500)
	_tick(session, 2500)
	_key(KEY_2)
	var second := _outcomes[1].option
	_tick(session, 3500)
	webcam.show_automatic(&"sad", 3500)
	_tick(session, 5499)
	if webcam.get_emotion() != second.emotion or caption.text != second.reply:
		return false
	_tick(session, 5500)
	if webcam.get_emotion() != &"focused":
		return false
	webcam.show_reply("Reply", &"shy", 6000)
	webcam.show_automatic(&"sad", 8500)
	webcam.tick(9000)
	if webcam.get_emotion() != &"sad":
		return false
	webcam.tick(10500)
	return webcam.get_emotion() == &"focused"


func _context_catalog() -> bool:
	var session := await _session(40, 1.0, 1.0)
	if session == null:
		return false
	var game := _game(session)
	# The retry drops the pending loss reaction while preserving its cooldown.
	(game.get("_state") as SnakeState).set("_score", 5)
	game._physics_process(2.0)
	_key(KEY_SPACE)
	_tick(session, 1000)
	if _opens.size() != 1 or _opens[0].template_id != &"q10":
		return false
	_key(KEY_1)
	for index in range(2, 4):
		_tick(session, index * 1000 - 1)
		game._physics_process(2.0)
		_key(KEY_SPACE)
		_tick(session, index * 1000)
		if _opens.size() != index or _opens[-1].template_id != StringName("q%d" % (9 + index)):
			return false
		_key(KEY_1)
	for index in range(4, 7):
		_tick(session, index * 1000 - 1)
		session._route_stream_event(Event.new(100 + index, Event.Kind.MILESTONE, index * 1000 - 1, 5, &"", session._attempts_started))
		_tick(session, index * 1000)
		if (
			_opens.size() != index or _opens[-1].template_id != StringName("q%02d" % (index + 3))
			or _opens[-1].source_event_id != 100 + index
		):
			return false
		_key(KEY_1)
	return true


func _caption_fit() -> bool:
	var session := await _session()
	if session == null:
		return false
	root.size = Vector2i(1024, 768)
	await process_frame
	await process_frame
	var caption := session.get_node(
		"PrototypeHUD/MarginContainer/VBoxContainer/MainArea/SideColumn/WebcamSlot/HeroWebcam/CaptionLabel"
	) as Label
	var font := caption.get_theme_font("font")
	var font_size := caption.get_theme_font_size("font_size")
	if font_size != 14 or caption.size.x <= 0.0:
		return false
	var fits := true
	var catalog := Content.get_questions()
	catalog.append_array(Content.get_reactions())
	catalog.append_array(Content.get_donation_questions())
	for question in catalog:
		for option in question.options:
			var lines := font.get_multiline_string_size(
				option.reply, HORIZONTAL_ALIGNMENT_LEFT, caption.size.x, font_size
			)
			if lines.y > minf(caption.size.y, 2.0 * font.get_height(font_size)):
				printerr("Reply exceeds the caption bounds: ", option.id, " size=", lines, " caption=", caption.size, " line=", font.get_height(font_size))
				fits = false
	return fits


func _malformed_catalog() -> bool:
	var catalog := Content.get_questions()
	if not Content.validate_questions(catalog).is_empty():
		return false
	catalog[1].id = catalog[0].id
	if Content.validate_questions(catalog).is_empty():
		return false
	catalog = Content.get_questions()
	catalog[0].options.pop_back()
	if Content.validate_questions(catalog).is_empty():
		return false
	catalog = Content.get_questions()
	catalog[0].options[0].effects.x = INF
	if Content.validate_questions(catalog).is_empty():
		return false
	catalog = Content.get_questions()
	catalog[0].options[0].emotion = &"unsupported"
	if Content.validate_questions(catalog).is_empty():
		return false
	catalog = Content.get_questions()
	catalog[0].options[0].style_id = &"competitive"
	return not Content.validate_questions(catalog).is_empty()
