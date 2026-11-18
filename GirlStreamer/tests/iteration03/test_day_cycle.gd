extends SceneTree

const Days = preload("res://prototype/day/day_cycle.tscn")
const Cycle = preload("res://prototype/day/day_cycle.gd")
const Day = preload("res://prototype/day/day_state.gd")
const Scene = preload("res://prototype/prototype_session.tscn")
const Session = preload("res://prototype/prototype_session.gd")
const Timed = preload("res://tests/iteration01/test_timed_session.gd")
const Donations = preload("res://tests/iteration02/test_stream_donations.gd")
const Integration = preload("res://tests/iteration02/test_stream_integration.gd")


class ControlledSession extends Timed.ClockSession:
	func _ready() -> void:
		super._ready()
		set_process(false)
		_snake_game.set_physics_process(false)


var _fixture: PackedScene


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_fixture = _pack_controlled_stream()
	var checks: Array[Callable] = [
		_stream_then_skip, _skip_then_stream, _untouched_skip, _mouse_handoff, _missing_frozen_results,
	]
	for check in checks:
		var passed: bool = await check.call()
		for child in root.get_children():
			child.free()
		if not passed:
			printerr("STAGE05_DAY_CYCLE_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE05_DAY_CYCLE_PASS groups=", checks.size())
	quit()


func _stream_then_skip() -> bool:
	var cycle := _mount()
	_prepare_to_zero(cycle)
	var stream := await _start(cycle)
	if stream == null or stream.get_audience_snapshot().total != 33 or cycle._day.get_snapshot().ap != 0:
		return false
	_key(KEY_M, true)
	_key(KEY_M, false)
	for payment: Array in [[1000, 2], [2000, 5], [3000, 5]]:
		_tick(stream, payment[0], payment[1])
	if stream._donations.get_total() != 12 or cycle._day.get_snapshot().coins != 0:
		return false
	_tick(stream, 8000)
	if (
		not stream._stream_choice.is_open()
		or stream._stream_choice._active.template_id != &"prepared_snake_record"
	):
		return false
	_tick(stream, 12000)
	var frozen := stream.build_results_snapshot()
	if (
		frozen == null or frozen.donation_count != 3 or frozen.donation_total != 12
		or frozen.questions_cancelled != 1 or cycle._day.get_snapshot().coins != 0
		or _results(cycle).visible
	):
		return false
	# Even the active session's frozen payload is premature during goodbye.
	stream.managed_completed.emit(frozen)
	_tick(stream, 13999)
	if _results(cycle).visible or cycle._day.get_snapshot().phase != Day.Phase.STREAMING:
		return false
	_tick(stream, 14000)
	if not _settlement_is(cycle, 1, Day.DayOutcome.STREAMED, 0, 12, 6, 3, 3, 1):
		return false
	stream.managed_completed.emit(frozen)
	if not _settlement_is(cycle, 1, Day.DayOutcome.STREAMED, 0, 12, 6, 3, 3, 1):
		return false
	if stream.can_process() or stream.build_results_snapshot() != frozen:
		return false
	_key(KEY_ENTER, true)
	_results(cycle).continue_requested.emit()
	await process_frame
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	if not _morning_is(cycle, 2, 12, 6, 4, 1):
		return false
	if is_instance_valid(stream) or _room(cycle).get_node("%PublishPost") != root.gui_get_focus_owner():
		return false
	if not (_room(cycle).get_node("%Feedback") as Label).text.is_empty():
		return false

	_room(cycle).skip_requested.emit()
	if not _settlement_is(cycle, 2, Day.DayOutcome.SKIPPED, 12, 0, 6, 4, 6, 4):
		return false
	_results(cycle).get_node("%ContinueButton").pressed.emit()
	_results(cycle).continue_requested.emit()
	await process_frame
	if not _morning_is(cycle, 3, 12, 9, 7, 1):
		return false
	var third := await _start(cycle)
	return (
		third != null and third.muted and third._stream_audio._muted
		and third._hud._mute_label.text.contains("выкл")
		and third.get_audience_snapshot().counts == Vector3i(10, 10, 10)
		and third._donations.get_total() == 0 and third._questions_shown == 0
		and third._attempts_started == 1
	)


func _skip_then_stream() -> bool:
	var cycle := _mount()
	_prepare_to_zero(cycle)
	_room(cycle).skip_requested.emit()
	if not _settlement_is(cycle, 1, Day.DayOutcome.SKIPPED, 0, 0, 6, 3, 6, 3):
		return false
	_results(cycle).continue_requested.emit()
	await process_frame
	if not _morning_is(cycle, 2, 0, 9, 6, 1):
		return false
	var stream := await _start(cycle)
	if stream == null or stream.get_audience_snapshot().total != 30 or stream._donations.get_count() != 0:
		return false
	var stale := Session.StreamResults.new()
	stale.donation_total = 99
	var old_source := Scene.instantiate() as Session
	old_source._session_state = Session.SessionState.FINISHED
	old_source._results = stale
	stream._session_state = Session.SessionState.FINISHED
	stream._results = stale
	cycle._on_stream_completed(stale, 1, stream)
	cycle._on_stream_completed(stale, 2, old_source)
	old_source.free()
	if cycle._day.get_snapshot().coins != 0 or _results(cycle).visible:
		return false
	stream._session_state = Session.SessionState.RUNNING
	stream._results = null
	_tick(stream, 1000, 5)
	_tick(stream, 8000)
	if (
		not stream._stream_choice.is_open()
		or stream._stream_choice._active.template_id == &"prepared_snake_record"
	):
		return false
	_tick(stream, 12000)
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, true, true)
	await process_frame
	if not _settlement_is(cycle, 2, Day.DayOutcome.STREAMED, 0, 5, 9, 6, 6, 4):
		return false
	_key(KEY_ENTER, false)
	return _results(cycle).visible and cycle._day.get_snapshot().day_number == 2


func _untouched_skip() -> bool:
	var cycle := _mount()
	var button := _room(cycle).get_node("%SkipStream") as Button
	button.grab_focus()
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	if not _results(cycle).visible:
		return false
	_room(cycle).skip_requested.emit()
	if not _settlement_is(cycle, 1, Day.DayOutcome.SKIPPED, 0, 0, 8, 8, 8, 8):
		return false
	if cycle._day.get_snapshot().ap != 6 or not (_results(cycle).get_node("%ContinueButton") as Button).has_focus():
		return false
	await process_frame
	if not _results(cycle).visible:
		return false
	_key(KEY_ENTER, true)
	await process_frame
	_key(KEY_ENTER, true, true)
	_key(KEY_ENTER, false)
	return _morning_is(cycle, 2, 0, 10, 10, 0)


func _mouse_handoff() -> bool:
	var cycle := _mount()
	await process_frame
	await process_frame
	var skip := _room(cycle).get_node("%SkipStream") as Button
	_click(skip)
	await process_frame
	await process_frame
	var next := _results(cycle).get_node("%ContinueButton") as Button
	if not _results(cycle).visible:
		return false
	_click(next, true)
	await process_frame
	if not _results(cycle).visible or cycle._day.get_snapshot().day_number != 1:
		return false
	_click(next)
	await process_frame
	await process_frame
	if not _morning_is(cycle, 2, 0, 10, 10, 0):
		return false
	_click(skip, true)
	await process_frame
	return _morning_is(cycle, 2, 0, 10, 10, 0)


func _missing_frozen_results() -> bool:
	var cycle := _mount()
	var stream := await _start(cycle)
	if stream == null:
		return false
	_tick(stream, 1000, 5)
	_tick(stream, 12000)
	stream._results = null
	_tick(stream, 14000)
	var day := cycle._day.get_snapshot()
	return (
		stream.is_finished() and stream._donations.get_total() == 5
		and day.phase == Day.Phase.STREAMING and day.coins == 0
		and [day.vigor, day.concentration] == [8, 8]
		and not _results(cycle).visible and cycle._day.get_day_result() == null
	)


func _pack_controlled_stream() -> PackedScene:
	var session := Scene.instantiate()
	session.scene_file_path = ""
	session.set_script(ControlledSession)
	session.session_duration_seconds = 12
	session.get_node("StreamAudio").set_script(Integration.AudioSpy)
	var donations := session.get_node("DonationController")
	donations.set_script(Donations.ScriptedController)
	donations.interval_seconds = 1
	session.get_node("StreamDirector").first_delay_seconds = 8.0
	var fixture := PackedScene.new()
	var result := fixture.pack(session)
	session.free()
	return fixture if result == OK else null


func _mount() -> Cycle:
	var cycle := Days.instantiate() as Cycle
	cycle.stream_scene = _fixture
	root.add_child(cycle)
	return cycle


func _prepare_to_zero(cycle: Cycle) -> void:
	for activity in [&"train_snake", &"train_snake", &"publish_post", &"prepare_topic"]:
		_room(cycle).activity_requested.emit(activity)


func _start(cycle: Cycle) -> ControlledSession:
	_room(cycle).stream_requested.emit()
	for frame in range(16):
		if is_instance_valid(cycle._active_session):
			return cycle._active_session as ControlledSession
		await process_frame
	return null


func _tick(stream: ControlledSession, active_msec: int, payment: int = 0) -> void:
	var donations := stream._donations as Donations.ScriptedController
	donations.draws.assign([0.99] if payment == 0 else [
		0.0, 0.0, 0.0 if payment == 2 else 0.5, 0.3,
	])
	stream.now = 1000 + active_msec
	stream._process(0.0)


func _settlement_is(
	cycle: Cycle, day_number: int, outcome: Day.DayOutcome, balance: int, income: int,
	vigor_before: int, concentration_before: int, vigor_after: int, concentration_after: int
) -> bool:
	var result := cycle._day.get_day_result()
	var state := cycle._day.get_snapshot()
	return (
		result != null and result.day_number == day_number and result.outcome == outcome
		and result.balance_before == balance and result.income == income and result.balance_after == balance + income
		and [result.vigor_before, result.concentration_before] == [vigor_before, concentration_before]
		and [result.vigor_after, result.concentration_after] == [vigor_after, concentration_after]
		and state.phase == Day.Phase.RESULTS and state.coins == balance + income
		and _results(cycle).visible and not _room(cycle).visible
		and cycle._stream_host.get_child_count() == int(outcome == Day.DayOutcome.STREAMED)
	)


func _morning_is(cycle: Cycle, day_number: int, coins: int, vigor: int, concentration: int, mastery: int) -> bool:
	var day := cycle._day.get_snapshot()
	return (
		day.phase == Day.Phase.PREPARING and day.day_number == day_number and day.coins == coins
		and day.ap == 6 and day.vigor == vigor and day.concentration == concentration
		and day.mastery_level == mastery and not day.post_published and not day.topic_prepared
		and _room(cycle).visible and not _results(cycle).visible
		and cycle._stream_host.get_child_count() == 0
	)


func _room(cycle: Cycle) -> Cycle.Preparation:
	return cycle._preparation


func _results(cycle: Cycle) -> Cycle.ResultsView:
	return cycle._results


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	root.push_input(event)


func _click(button: Button, double_click: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		event.double_click = double_click and pressed
		root.push_input(event, true)
