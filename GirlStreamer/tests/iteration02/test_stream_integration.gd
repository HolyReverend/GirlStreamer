extends SceneTree

const Summary = preload("res://prototype/stream/stream_results.gd")
const ResultContent = preload("res://prototype/stream/stream_content.gd")
const RESULT_LABEL_PATH := "PrototypeHUD/MarginContainer/VBoxContainer/ResultsPanel/ResultsScroll/ResultsLabel"

const Timed = preload("res://tests/iteration01/test_timed_session.gd")
const Donations = preload("res://tests/iteration02/test_stream_donations.gd")
const Audio = preload("res://prototype/stream/stream_audio.gd")
const SessionScene = preload("res://prototype/prototype_session.tscn")


class AudioSpy extends Audio:
	var requests: Array[StringName] = []
	var active_cue: StringName

	func play_question() -> void:
		_request(&"question")

	func play_donation() -> void:
		_request(&"donation")

	func play_finish() -> void:
		_request(&"finish")

	func stop_all() -> void:
		requests.append(&"stop")
		active_cue = &""
		super.stop_all()

	func _request(cue: StringName) -> void:
		requests.append(cue)
		if not _muted:
			active_cue = cue


func _initialize() -> void:
	_run.call_deferred()


func _result_arithmetic_and_copies() -> bool:
	var session := await _session()
	if session == null:
		return false
	session._questions_shown = 3
	session._questions_answered = 2
	session._questions_expired = 1
	session._answer_times_seconds.assign([1.0, 3.0])
	session._choice_counts[&"donation_question"] = Vector4i(3, 1, 2, 0)
	session._choice_counts[&"reaction"] = Vector4i(1, 1, 0, 0)
	var source_id := 0
	for sample: Array in [
		[&"question", 1000], [&"question", 3000], [&"donation_question", 5000], [&"reaction", 200],
	]:
		source_id += 1
		var record := ResultContent.ChoiceResolution.new()
		record.choice_id = source_id
		record.kind = sample[0]
		record.elapsed_msec = sample[1]
		record.outcome = &"answered"
		if record.kind == &"reaction":
			record.source_event_kind = &"collision"
			record.option = ResultContent.get_reactions()[2].options[1]
		session._choice_resolutions.append(record)
	session._apply_audience_effect(&"milestone", 1000, "Первый рубеж", Vector3(8, 2, 2), &"", 1)
	session._apply_audience_effect(&"record", 2000, "Равный эффект", Vector3(8, 2, 2), &"", 2)
	session._apply_audience_effect(&"question", 3000, "Ответ зрителю", Vector3(1, 4, 1), &"", 1)
	session._apply_audience_effect(&"reaction", 4000, "Без изменения", Vector3.ZERO, &"humor", 4)
	session.now = 13000
	session._process(0.0)
	var result := session._results
	if result == null:
		session.free()
		return false
	var passed := (
		result.choice_totals == Vector4i(7, 4, 3, 0)
		and result.question_latency_seconds == 4.0 and result.donation_question_latency_seconds == 5.0
		and result.reaction_latency_seconds == 0.2 and result.highlights.size() == 2
		and result.highlights[0].source_id == 1 and result.highlights[0].category == &"achievement"
		and result.highlights[1].category == &"question"
		and result.selected_reactions.size() == 1 and result.selected_reactions[0].style == &"humor"
		and result.selected_reactions[0].source_kind == &"collision"
	)
	session._audience_causes[0].explanation = "Changed live source"
	session._choice_resolutions[-1].option.style_id = &"flirt"
	session._answer_times_seconds.clear()
	session._audience.reset()
	session._complete_closing()
	var text := (session.get_node(RESULT_LABEL_PATH) as Label).text
	passed = passed and (
		text.contains("Доля ответов: 50%") and text.contains("Среднее время ответа: 3.00 с")
		and text.contains("Первый рубеж") and not text.contains("Changed live source")
		and text.contains("С юмором — Попытка закончилась")
		and result.answer_times_seconds == [1.0, 3.0] and result.audience.step_count == 12
	)
	var hud := session.get_node("PrototypeHUD") as PrototypeHUD
	var minimal := Summary.new()
	minimal.questions_shown = 1
	minimal.questions_cancelled = 1
	hud.show_stream_results(minimal)
	text = (session.get_node(RESULT_LABEL_PATH) as Label).text
	passed = passed and text.contains("Доля ответов: нет данных") and text.contains("Получено монет: 0")
	minimal.questions_cancelled = 0
	minimal.questions_expired = 1
	hud.show_stream_results(minimal)
	text = (session.get_node(RESULT_LABEL_PATH) as Label).text
	passed = passed and text.contains("Доля ответов: 0%") and text.contains("Среднее время ответа: нет данных")
	session.free()
	return passed


func _run() -> void:
	var checks: Array[Callable] = [_crowded_finish, _pause_and_mute, _wave_assets, _result_arithmetic_and_copies]
	for check in checks:
		if not await check.call():
			printerr("ITER02_STAGE07_INTEGRATION_FAIL ", check.get_method())
			quit(1)
			return
	print("ITER02_STAGE07_INTEGRATION_PASS groups=", checks.size())
	quit()


func _session() -> Timed.ClockSession:
	var node := SessionScene.instantiate()
	node.set_script(Timed.ClockSession)
	var session := node as Timed.ClockSession
	session.session_duration_seconds = 12
	session.question_window_seconds = 6.0
	session.get_node("StreamAudio").set_script(AudioSpy)
	var controller := session.get_node("DonationController")
	controller.set_script(Donations.ScriptedController)
	controller.interval_seconds = 1
	var director := session.get_node("StreamDirector")
	director.first_delay_seconds = 8.0
	director.gap_seconds = 1.0
	root.add_child(session)
	session.set_process(false)
	session.get_node("SnakeGame").set_physics_process(false)
	for frame in range(12):
		if session.is_layout_ready() and session.start_session():
			return session
		await process_frame
	session.free()
	return null


func _tick(session: Timed.ClockSession, elapsed: int, payment: int = 0) -> void:
	var controller := session.get_node("DonationController") as Donations.ScriptedController
	controller.draws.clear()
	controller.draws.append_array([0.99] if payment == 0 else [0.0, 0.0, 0.50, 0.0 if payment == 2 else 0.30])
	session.now = 1000 + elapsed
	session._process(0)


func _key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	if code != KEY_M:
		event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)


func _crowded_finish() -> bool:
	var session := await _session()
	if session == null:
		return false
	var passed := _verify_crowded_finish(session)
	session.free()
	return passed


func _verify_crowded_finish(session: Timed.ClockSession) -> bool:
	var audio := session._stream_audio as AudioSpy
	var controller := session.get_node("DonationController") as Donations.ScriptedController
	for second in range(1, 11):
		_tick(session, second * 1000, 1)
		if second == 9:
			session.now = 10500
			_key(KEY_1)
	_tick(session, 10500)
	_tick(session, 11000, 2)
	var latest := controller.get_last_donation()
	session._on_donation_received(latest.id, latest.group_index, latest.amount, latest.nick, latest.message, true)
	if not (
		session._stream_choice.is_open() and session._webcam._reply_deadline_msec > 11000
		and session._director._pending_donation != null and not session._hud._donation_pending.is_empty() and session._hud._donation_overflow_count > 0
		and audio.requests.count(&"question") == 2 and audio.requests.count(&"donation") == 11
	):
		printerr("crowded setup incomplete: ", session._stream_choice.is_open(), " / ", session._webcam._reply_deadline_msec, " / ", session._director._pending_donation, " / ", session._hud._donation_pending.size(), " / ", audio.requests)
		return false
	var draws := controller.draw_count
	_tick(session, 12000, 2)
	var frozen := session._results
	if not (
		frozen != null and frozen.elapsed_seconds == 12.0 and frozen.audience.step_count == 12
		and frozen.donation_count == 11 and frozen.donation_total == 55 and controller.draw_count == draws
		and frozen.choice_totals == Vector4i(2, 1, 0, 1)
		and session._stream_choice.get_last_resolution().outcome == &"cancelled"
		and session._director._pending_donation == null and session._hud._donation_pending.is_empty()
		and session._webcam.get_node("CaptionLabel").text == "Спасибо за эфир! До встречи!"
		and audio.requests.count(&"finish") == 1 and audio.active_cue == &"finish"
	):
		printerr("cutoff accounting or cue mismatch")
		return false
	session._finish_session(session.now)
	session._on_donation_received(latest.id, latest.group_index, latest.amount, latest.nick, latest.message, true)
	session._on_board_rect_changed(Rect2(0, 0, 500, 300))
	_tick(session, 12500)
	if session._results != frozen or audio.requests.count(&"finish") != 1:
		return false
	_key(KEY_ENTER, true)
	if audio.active_cue != &"finish":
		return false
	_key(KEY_ENTER)
	if audio.active_cue != &"" or session._results != frozen:
		return false
	_key(KEY_M)
	if not session.muted or session.get_stream_time_msec() != 12000:
		return false
	_key(KEY_ENTER)
	return (
		session.is_stream_active() and session._results == null and session.muted
		and session._hud.get_node("MarginContainer/VBoxContainer/Header/Stats/MuteLabel").text == "M — звук: выкл."
		and session._webcam.get_node("CaptionLabel").text.is_empty()
		and controller.get_count() == 0 and session.get_audience_snapshot().counts == Vector3i(10, 10, 10)
		and session._next_choice_id == 1 and session._next_stream_event_id == 1 and session._high_score == 0
		and session._audience_causes.is_empty() and audio.requests.count(&"finish") == 1
		and frozen.choice_totals == Vector4i(2, 1, 0, 1) and frozen.donation_total == 55
	)


func _pause_and_mute() -> bool:
	var session := await _session()
	if session == null:
		return false
	var audio := session._stream_audio as AudioSpy
	var controller := session.get_node("DonationController") as Donations.ScriptedController
	_tick(session, 1000, 1)
	var passed := audio.active_cue == &"donation" and session.pause_session() and audio.active_cue == &""
	_tick(session, 9000, 1)
	passed = passed and controller.get_count() == 1 and session.get_stream_time_msec() == 1000
	_key(KEY_M, true)
	passed = passed and not session.muted
	_key(KEY_M)
	passed = passed and session.muted and session.get_stream_time_msec() == 1000
	passed = passed and session.resume_session() and audio.active_cue == &""
	_tick(session, 10000, 1)
	passed = passed and audio.requests.count(&"donation") == 2 and audio.active_cue == &""
	_key(KEY_M)
	passed = passed and not session.muted and audio.active_cue == &"" and session.get_stream_time_msec() == 2000
	_tick(session, 11000, 1)
	passed = passed and audio.active_cue == &"donation"
	_key(KEY_M)
	passed = passed and session.muted and audio.active_cue == &""
	session.free()
	return passed


func _wave_assets() -> bool:
	var player := Audio.new()
	root.add_child(player)
	var passed := (
		player._question != null and player._donation != null and player._finish != null
		and is_equal_approx(player._question.get_length(), 0.15)
		and is_equal_approx(player._donation.get_length(), 0.3)
		and is_equal_approx(player._finish.get_length(), 0.5)
	)
	player.free()
	return passed
