extends SceneTree

const Director = preload("res://prototype/stream/stream_director.gd")

const SESSION = preload("res://prototype/prototype_session.tscn")
const TimedChecks = preload("res://tests/iteration01/test_timed_session.gd")
const FoodChecks = preload("res://tests/iteration01/test_snake_food.gd")
const SessionScript = preload("res://prototype/prototype_session.gd")
const Event = preload("res://prototype/stream/stream_event.gd")
const Feed = preload("res://prototype/stream/chat_feed.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const Webcam = preload("res://prototype/ui/hero_webcam.gd")
const HUD_PATH := "PrototypeHUD/MarginContainer/VBoxContainer/"
const GRID := Vector2i(8, 8)


class EventSession extends TimedChecks.ClockSession:
	var events: Array[Event] = []

	func _route_stream_event(event: Event) -> void:
		events.append(event)
		super._route_stream_event(event)


class FoodFixture extends FoodChecks.Fixture:
	func arrange_collection(grid: Vector2i, score: int) -> void:
		reset(grid, RandomNumberGenerator.new())
		_score = score
		place_food(Vector2i(5, 4))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_feed_cadence_and_history, _webcam_states, _score_and_retry,
		_full_board, _cutoff_full_board, _pause_and_answers, _answer_at_cutoff,
		_reaction_after_retry, _reaction_expiration, _snake_seed_independence, _full_feed_layout,
		_pending_reaction_pause_and_cutoff,
		_audience_source_routing, _audience_choice_effects, _audience_sampled_timing,
		_audience_boundary_partition,
	]
	for check in checks:
		var passed: bool = await check.call()
		for child in root.get_children():
			child.free()
		if not passed:
			printerr("ITER02_STAGE02_FEEDBACK_FAIL ", check.get_method())
			quit(1)
			return
	print("ITER02_STAGE02_FEEDBACK_PASS groups=", checks.size())
	quit()


func _session(duration: int = 10) -> EventSession:
	var node := SESSION.instantiate()
	node.set_script(EventSession)
	var session := node as EventSession
	session.session_duration_seconds = duration
	var director := session.get_node("StreamDirector") as Director
	director.first_delay_seconds = 1.0
	director.gap_seconds = 1.0
	session.question_window_seconds = 2.0
	var game := session.get_node("SnakeGame") as SnakeGame
	game.columns = GRID.x
	game.rows = GRID.y
	game.use_fixed_seed = true
	root.add_child(session)
	session.set_process(false)
	game.set_physics_process(false)
	for frame in range(12):
		if session.is_layout_ready():
			return session if session.start_session() else null
		await process_frame
	return null


func _feed(session: EventSession) -> Feed:
	return session.get_node("ChatFeed") as Feed


func _game(session: EventSession) -> SnakeGame:
	return session.get_node("SnakeGame") as SnakeGame


func _webcam(session: EventSession) -> Webcam:
	return (session.get_node("PrototypeHUD") as PrototypeHUD).get_webcam()


func _contexts(feed: Feed) -> Array[StringName]:
	var contexts: Array[StringName] = []
	for line in feed.get_lines():
		contexts.append(line.context)
	return contexts


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)


func _collect(session: EventSession, previous_score: int, now: int) -> void:
	var model := FoodFixture.new()
	model.arrange_collection(GRID, previous_score)
	session._last_attempt_score = previous_score
	_game(session).set("_state", model)
	session.now = now
	_game(session)._physics_process(0.2)


func _feed_cadence_and_history() -> bool:
	if not Content.validate().is_empty():
		return false
	var feed := Feed.new()
	var control := Feed.new()
	root.add_child(feed)
	root.add_child(control)
	for owner in [feed, control]:
		owner.reset(17)
		owner.start(0)
		owner.start(0)
		owner.tick(3999, true)
		if _contexts(owner) != [&"start"]:
			return false
	feed.append_context(&"unknown", 3999)
	feed.append_context(&"donation", 3999)
	for owner in [feed, control]:
		owner.tick(4000, true)
		owner.tick(16000, false)
		owner.tick(16000, false)
		owner.append_context(&"food", 18000)
		owner.tick(21999, true)
		if _contexts(owner) != [&"start", &"ambient_playing", &"ambient_waiting", &"food"]:
			return false
		owner.tick(22000, true)
	var original := feed.get_lines()
	var expected := control.get_lines()
	for index in range(expected.size()):
		if original[index].template_id != expected[index].template_id or original[index].nick != expected[index].nick:
			return false
	original[0].text = "changed"
	if feed.get_lines()[0].text != expected[0].text:
		return false
	feed.lines_changed.connect(func(lines: Array[Content.ChatLine]) -> void:
		lines[-1].text = "changed signal payload"
	)
	for index in range(75):
		feed.append_context(&"food", 23000 + index)
	var retained := feed.get_lines()
	if retained.size() != 60 or retained[0].time_msec != 23015 or retained[-1].text == "changed signal payload":
		return false
	for index in range(1, retained.size()):
		if retained[index].template_id == retained[index - 1].template_id:
			return false
	feed.stop()
	feed.tick(100000, true)
	feed.append_context(&"loss", 100000)
	return feed.get_lines()[-1].time_msec == 23074


func _webcam_states() -> bool:
	var session := await _session()
	if session == null:
		return false
	var webcam := _webcam(session)
	var label := webcam.get_node("StateLabel") as Label
	var caption := webcam.get_node("CaptionLabel") as Label
	var labels: Array[String] = [label.text]
	for emotion: StringName in [&"happy", &"shy", &"sad"]:
		webcam.show_automatic(emotion, 10)
		if webcam.get_emotion() != emotion or caption.text.is_empty():
			return false
		labels.append(label.text)
	webcam.set_playing(false)
	webcam.show_automatic(&"happy", 100)
	webcam.tick(2009)
	if webcam.get_emotion() != &"sad":
		return false
	webcam.tick(2010)
	labels.append(label.text)
	for value in labels:
		if value.is_empty() or labels.count(value) != 1:
			return false
	return webcam.get_emotion() == &"neutral" and caption.text.is_empty()


func _score_and_retry() -> bool:
	var session := await _session()
	if session == null:
		return false
	var feed := _feed(session)
	if _contexts(feed) != [&"start"] or not session.events.is_empty():
		return false
	_collect(session, 0, 1100)
	_collect(session, 1, 1200)
	_collect(session, 4, 1300)
	if (
		_contexts(feed) != [&"start", &"food", &"achievement"]
		or session._total_food != 3 or session.events.size() != 3
		or session.events[0].time_msec != 100 or session.events[1].kind != Event.Kind.FOOD
		or session.events[2].kind != Event.Kind.MILESTONE
	):
		printerr("Score routing: ", _contexts(feed), " total=", session._total_food, " events=", session.events.size())
		return false
	# Keep random respawns from changing the intended wall-collision fixture.
	_game(session)._state.set("_food_cell", Vector2i.ZERO)
	_game(session)._physics_process(2.0)
	if session.events[-1].kind != Event.Kind.COLLISION or session.events[-1].reason != &"wall_collision":
		return false
	var before_retry := _contexts(feed)
	var audience_before_retry := session.get_audience_snapshot()
	_key(KEY_SPACE)
	if _contexts(feed) != before_retry:
		printerr("Retry altered chat: ", _contexts(feed), " expected=", before_retry)
		return false
	var audience_after_retry := session.get_audience_snapshot()
	if (
		audience_after_retry.counts != audience_before_retry.counts
		or audience_after_retry.carries != audience_before_retry.carries
		or audience_after_retry.precise_impressions != audience_before_retry.precise_impressions
	):
		return false
	_collect(session, 4, 4500)
	if _contexts(feed)[-1] != &"food" or session.events[-1].kind != Event.Kind.FOOD:
		printerr("Repeated milestone: ", _contexts(feed), " kind=", session.events[-1].kind)
		return false
	var before_records := _contexts(feed)
	_collect(session, 5, 4600)
	_collect(session, 6, 4700)
	if (
		session.events[-2].kind != Event.Kind.RECORD or session.events[-1].kind != Event.Kind.RECORD
		or session._high_score != 7 or _contexts(feed) != before_records
		or session._director._latest_event_id != session.events[-1].id
	):
		return false
	for index in range(session.events.size()):
		if session.events[index].id != index + 1:
			return false
	session.now = 11000
	session._process(0.0)
	_key(KEY_ENTER)
	_key(KEY_ENTER)
	if _contexts(feed) != [&"start"] or _webcam(session).get_emotion() != &"focused":
		printerr("Restart: ", _contexts(feed), " emotion=", _webcam(session).get_emotion())
		return false
	_collect(session, 4, 11100)
	return session.events[-1].id == 1 and session.events[-1].kind == Event.Kind.MILESTONE


func _arm_full_board(session: EventSession) -> void:
	var model := FoodChecks.Fixture.new()
	model.arrange_last_free_cell(GRID, RandomNumberGenerator.new())
	_game(session).set("_state", model)
	session._last_attempt_score = model.get_score()
	session._total_food = model.get_score()


func _full_board() -> bool:
	var session := await _session()
	if session == null:
		return false
	_arm_full_board(session)
	session.now = 2000
	_game(session)._physics_process(0.2)
	return (
		session._total_food == 61 and session._boards_completed == 1
		and session.events.size() == 1 and session.events[0].kind == Event.Kind.BOARD_COMPLETED
		and session.events[0].score == 61 and session.events[0].reason == &"board_full"
		and _contexts(_feed(session)) == [&"start", &"achievement"]
		and _webcam(session).get_emotion() == &"happy"
	)


func _cutoff_full_board() -> bool:
	var session := await _session()
	if session == null:
		return false
	_arm_full_board(session)
	session.samples.assign([10999, 10999, 11000])
	_game(session)._physics_process(0.2)
	if (
		not session.is_stream_active() or session._total_food != 61 or session._boards_completed != 1
		or session.events.size() != 1 or session.events[0].time_msec != 9999
		or session.events[0].kind != Event.Kind.BOARD_COMPLETED
		or session._director._latest_event_id != session.events[0].id
		or session._director._pending_reaction == null
		or session._director._pending_reaction.id != session.events[0].id
		or session._stream_choice.is_open()
		or _contexts(_feed(session)) != [&"start"]
		or _webcam(session).get_emotion() != &"focused"
	):
		return false
	session._process(0.0)
	session._on_attempt_finished(&"wall_collision", 61)
	return (
		session._session_state == SessionScript.SessionState.CLOSING
		and session._results.total_food == 61 and session._results.boards_completed == 1
		and session._results.audience.impressions.is_equal_approx(Vector3(59.9, 52.9, 52.9))
		and session._results.highlights.size() == 1 and session._results.highlights[0].source_id == 1
		and session.events.size() == 1 and _contexts(_feed(session)) == [&"start"]
	)


func _pause_and_answers() -> bool:
	var session := await _session()
	if session == null:
		return false
	_collect(session, 0, 1500)
	session.now = 2000
	session._process(0.0)
	session.pause_session()
	session.now = 62000
	_key(KEY_1)
	session._process(0.0)
	if _webcam(session).get_emotion() != &"happy" or _contexts(_feed(session)) != [&"start", &"food"]:
		return false
	session.resume_session()
	# The pre-pause happy deadline is still 2500 active milliseconds.
	session.now = 63499
	session._process(0.0)
	if _webcam(session).get_emotion() != &"happy":
		return false
	session.now = 63500
	session._process(0.0)
	if _webcam(session).get_emotion() != &"focused":
		return false
	_key(KEY_1)
	if (
		session._questions_answered != 1
		or _webcam(session).get_emotion() != session._choice_resolutions[0].option.emotion
		or _contexts(_feed(session)) != [&"start", &"food", &"answer"]
	):
		return false
	session.now = 64500
	session._process(0.0)
	session.now = 66500
	session._process(0.0)
	if session._questions_expired != 1 or _webcam(session).get_emotion() != &"focused":
		return false
	session.now = 69000
	session._process(0.0)
	session.now = 71000
	session._process(0.0)
	return session._questions_cancelled == 1 and _contexts(_feed(session)).count(&"answer") == 1


func _answer_at_cutoff() -> bool:
	var session := await _session()
	if session == null:
		return false
	session.now = 10500
	session._process(0.0)
	session.samples.assign([10999, 11000])
	_key(KEY_1)
	if (
		not session.is_stream_active() or session._questions_answered != 1
		or _contexts(_feed(session)).has(&"answer")
		or _webcam(session).get_emotion() != &"focused"
	):
		return false
	session._process(0.0)
	return (
		session._results.questions_answered == 1 and session._results.questions_cancelled == 0
		and session._results.audience.step_count == 10 and session._audience_causes.size() == 1
		and session._audience_causes[0].time_msec == 9999
		and session._audience_causes[0].delta.is_equal_approx(session._choice_resolutions[0].option.effects)
	)


func _open_loss_reaction(session: EventSession) -> bool:
	var model := _game(session).get("_state") as SnakeState
	model.set("_score", 5)
	model.set("_food_cell", Vector2i.ZERO)
	session.now = 2000
	_game(session)._physics_process(2.0)
	session._process(0.0)
	return (
		_game(session).is_waiting_for_retry() and session._stream_choice.is_open()
		and session.events.size() == 1 and session.events[-1].kind == Event.Kind.COLLISION
		and session._choice_counts.get(&"reaction") == Vector4i(1, 0, 0, 0)
	)


func _reaction_after_retry() -> bool:
	var session := await _session()
	if session == null or not _open_loss_reaction(session):
		return false
	var loss := session.events[-1]
	_key(KEY_SPACE)
	_collect(session, 5, 2500)
	if session.events[-1].kind != Event.Kind.RECORD or session.events[-1].attempt_id != 2:
		return false
	_key(KEY_2)
	if session._choice_resolutions.size() != 1:
		return false
	var reaction := session._choice_resolutions[0]
	if (
		reaction.kind != &"reaction" or reaction.outcome != &"answered"
		or reaction.source_event_id != loss.id or reaction.source_attempt_id != 1
		or reaction.source_event_kind != &"collision" or reaction.option_index != 1
		or _contexts(_feed(session)).count(&"answer") != 1
		or _webcam(session).get_emotion() != reaction.option.emotion
	):
		return false
	session.now = 11000
	session._process(0.0)
	return session._results.reaction_counts == Vector4i(1, 1, 0, 0) and session._results.questions_shown == 0


func _reaction_expiration() -> bool:
	var session := await _session()
	if session == null or not _open_loss_reaction(session):
		return false
	var before := _contexts(_feed(session))
	session.now = 5000
	session._process(0.0)
	if session._choice_resolutions.size() != 1:
		return false
	var reaction := session._choice_resolutions[0]
	return (
		not session._stream_choice.is_open() and reaction.outcome == &"expired"
		and reaction.option_index == -1 and reaction.option == null
		and session._choice_counts.get(&"reaction") == Vector4i(1, 0, 1, 0)
		and session._questions_expired == 0 and _webcam(session).get_emotion() == &"neutral"
		and _contexts(_feed(session)).count(&"answer") == before.count(&"answer")
	)


func _pending_reaction_pause_and_cutoff() -> bool:
	var session := await _session()
	if session == null:
		return false
	var director := session.get_node("StreamDirector") as Director
	var model := _game(session).get("_state") as SnakeState
	model.set("_score", 5)
	model.set("_food_cell", Vector2i.ZERO)
	session.now = 10000
	_game(session)._physics_process(2.0)
	if director._pending_reaction == null or not session.pause_session():
		return false
	session.now = 70000
	session._process(0.0)
	if director._pending_reaction == null or director._next_reaction_msec != 69000:
		return false
	session.resume_session()
	session._process(0.0)
	if not session._stream_choice.is_open():
		return false
	session.now = 71000
	_key(KEY_3)
	if (
		session._results == null or session._results.reaction_counts != Vector4i(1, 0, 0, 1)
		or session._results.choice_totals != Vector4i(1, 0, 0, 1)
		or session._results.donation_question_counts != Vector4i.ZERO
		or session._choice_resolutions.size() != 1 or session._choice_resolutions[0].option != null
	):
		return false
	_key(KEY_ENTER)
	_key(KEY_ENTER)
	return director._next_reaction_msec == 0 and session._high_score == 0 and session._choice_resolutions.is_empty()


func _snake_seed_independence() -> bool:
	var enabled := await _session()
	var disabled := await _session()
	if enabled == null or disabled == null:
		return false
	_feed(disabled).stop()
	var enabled_game := _game(enabled)
	var disabled_game := _game(disabled)
	var first := enabled_game.get("_state") as SnakeState
	var second := disabled_game.get("_state") as SnakeState
	# Both attempts have independent, identically seeded model RNGs.
	var first_rng := first.get("_random_source") as RandomNumberGenerator
	var second_rng := second.get("_random_source") as RandomNumberGenerator
	if first_rng == null or second_rng == null or first_rng.state != second_rng.state:
		return false
	for x in range(5, 8):
		if first.get_food_cell() != second.get_food_cell():
			return false
		for model in [first, second]:
			model.set("_food_cell", Vector2i(x, 4))
		enabled_game._physics_process(0.2)
		disabled_game._physics_process(0.2)
	return (
		first.get_food_cell() == second.get_food_cell() and first.get_score() == 3
		and first_rng.state == second_rng.state and _contexts(_feed(enabled)).has(&"food")
		and _contexts(_feed(disabled)) == [&"start"]
	)


func _audience_source_routing() -> bool:
	var session := await _session(120)
	if session == null:
		return false
	session.now = 11000
	var milestone := Event.new(1, Event.Kind.MILESTONE, 10000, 5, &"", 1)
	session._route_stream_event(milestone)
	session._route_stream_event(milestone)
	if session.get_audience_snapshot().impressions != Vector3(58, 52, 52):
		return false
	if session.get_audience_snapshot().step_count != 10:
		return false
	session.now = 70999
	session._route_stream_event(Event.new(2, Event.Kind.RECORD, 69999, 6, &"", 1))
	session.now = 71000
	session._route_stream_event(Event.new(3, Event.Kind.RECORD, 70000, 7, &"", 1))
	if session._audience_causes.size() != 2 or session._next_record_reward_msec != 130000:
		return false
	for event_id in range(4, 29):
		session._route_stream_event(Event.new(event_id, Event.Kind.COLLISION, 70000, 0, &"wall_collision", 1))
	if session._audience_causes.size() != 20:
		return false
	var snapshot := session.get_audience_snapshot()
	if not session.pause_session():
		return false
	session.now += 60000
	session._process(0.0)
	if session.get_audience_snapshot().carries != snapshot.carries:
		return false
	session.resume_session()
	session.now += 50000
	session._process(0.0)
	session.now += 5000
	session._process(0.0)
	if session._results.audience.step_count != 120 or session.get_audience_snapshot().step_count != 120:
		return false
	_key(KEY_ENTER)
	var results := session.get_node(HUD_PATH + "ResultsPanel/ResultsScroll/ResultsLabel") as Label
	if not results.text.contains("Зрители: в начале 30") or not results.text.contains("Поклонники образа"):
		return false
	_key(KEY_ENTER)
	return session.get_audience_snapshot().counts == Vector3i(10, 10, 10) and session._audience_causes.is_empty()


func _audience_boundary_partition() -> bool:
	var frequent := await _session(5)
	var sparse := await _session(5)
	var short := await _session(1)
	if frequent == null or sparse == null or short == null:
		return false
	for session: EventSession in [frequent, sparse]:
		session.now = 2000
		session._route_stream_event(Event.new(1, Event.Kind.MILESTONE, 1000, 5, &"", 1))
		var state := session.get_audience_snapshot()
		if not is_equal_approx(state.carries[0], 0.05) or state.impressions.x != 58.0:
			return false
	for sample in [2250, 3000, 4000, 5999]:
		frequent.now = sample
		frequent._process(0.0)
	for session: EventSession in [frequent, sparse, short]:
		session.now = 6000
		session._process(0.0)
	var first := frequent._results.audience
	var second := sparse._results.audience
	return (
		first.step_count == 5 and second.step_count == 5 and short._results.audience.step_count == 1
		and first.counts == second.counts and first.carries == second.carries
		and first.precise_impressions == second.precise_impressions
	)


func _audience_choice_effects() -> bool:
	var session := await _session()
	if session == null:
		return false
	var option := Content.get_reactions()[2].options[0]
	var result := Content.ChoiceResolution.new()
	result.kind = &"reaction"
	result.source_event_kind = &"collision"
	result.outcome = &"answered"
	result.option = option
	for id in range(1, 4):
		result.choice_id = id
		session._apply_choice_audience_effect(result)
		session._apply_choice_audience_effect(result)
	var state := session.get_audience_snapshot()
	if state.impressions != Vector3(56, 51.5, 50) or state.style_uses.get(&"competitive") != 3:
		return false
	result.choice_id = 4
	result.kind = &"donation_question"
	result.option = Content.get_questions()[0].options[0]
	result.source_group_index = 2
	var expected := state.impressions + result.option.effects * 1.5
	session._apply_choice_audience_effect(result)
	session._apply_choice_audience_effect(result)
	result.choice_id = 5
	result.outcome = &"expired"
	result.option = null
	session._apply_choice_audience_effect(result)
	result.choice_id = 6
	result.outcome = &"cancelled"
	session._apply_choice_audience_effect(result)
	return session.get_audience_snapshot().impressions.is_equal_approx(expected - Vector3(0, 0, 2))


func _audience_sampled_timing() -> bool:
	var viewers := [30]
	var provider := func() -> int: return viewers[0]
	var feed := Feed.new()
	root.add_child(feed)
	feed.set_viewer_count_provider(provider)
	feed.reset(7)
	feed.start(0)
	viewers[0] = 60
	feed.tick(3999, true)
	if feed.get_lines().size() != 1:
		return false
	feed.tick(4000, true)
	feed.tick(6000, true)
	if feed.get_lines().size() != 3:
		return false
	viewers[0] = 0
	feed.tick(8000, true)
	feed.tick(13999, true)
	if feed.get_lines().size() != 4:
		return false
	feed.tick(14000, true)
	if feed.get_lines().size() != 5:
		return false
	var director := Director.new()
	root.add_child(director)
	var windows: Array[int] = []
	director.configure(func(definition: Content.ChoiceDefinition, _now: int) -> bool:
		windows.append(definition.window_msec)
		definition.id = windows.size()
		return true
	)
	director.set_viewer_count_provider(provider)
	director.first_delay_seconds = 1.0
	director.gap_seconds = 1.0
	director.start(true)
	for count in [30, 80, 130, 600]:
		viewers[0] = count
		var now := (windows.size() + 1) * 1000
		director.tick(now, true)
		var result := Content.ChoiceResolution.new()
		result.choice_id = windows.size()
		result.outcome = &"answered"
		result.resolved_at_msec = now
		director.on_choice_resolved(result)
	return windows == [6000, 5500, 5000, 5000]


func _full_feed_layout() -> bool:
	var session := await _session()
	if session == null:
		return false
	root.size = Vector2i(1024, 768)
	await process_frame
	await process_frame
	var board := session.get_node(HUD_PATH + "MainArea/BoardArea") as Control
	var chat := session.get_node(HUD_PATH + "MainArea/SideColumn/ChatSlot") as Control
	var choice := session.get_node(HUD_PATH + "ChoiceArea") as Control
	var hud := session.get_node("PrototypeHUD") as PrototypeHUD
	var history := chat.get_node("ChatContent/ChatHistory") as RichTextLabel
	var before := board.get_global_rect()
	for index in range(75):
		_feed(session).append_context(&"food", index)
	await process_frame
	await process_frame
	var retained := _feed(session).get_lines()
	var newest := retained[-1]
	var scrollbar := history.get_v_scroll_bar()
	var layout_ok := (
		retained.size() == 60 and board.get_global_rect() == before
		and history.text.split("\n").size() == 60 and history.text.ends_with("%s: %s" % [newest.nick, newest.text])
		and scrollbar.max_value > scrollbar.page
		and is_equal_approx(scrollbar.value, scrollbar.max_value - scrollbar.page)
		and root.min_size == Vector2i(1024, 768) and before.size.x >= 480 and before.size.y >= 360
		and before.end.x <= chat.get_global_rect().position.x
		and chat.get_global_rect().end.y <= choice.get_global_rect().position.y
	)
	if not layout_ok:
		return false
	var long_line := Content.ChatLine.new(&"wrap", "Лис", "Длинная строка для проверки переноса. ".repeat(3), &"food", 100)
	var wrapped_lines: Array[Content.ChatLine] = [long_line]
	hud.set_chat_lines(wrapped_lines)
	await process_frame
	await process_frame
	if history.get_line_count() <= 1 or board.get_global_rect() != before:
		return false
	_webcam(session).show_automatic(&"happy", 0)
	root.size = Vector2i(1280, 900)
	await process_frame
	await process_frame
	return (
		board.get_global_rect().size.x >= before.size.x
		and _webcam(session).get_emotion() == &"happy"
		and history.text.ends_with(long_line.text)
	)
