extends SceneTree

const SessionScene = preload("res://prototype/prototype_session.tscn")
const Timed = preload("res://tests/iteration01/test_timed_session.gd")
const HUD_PATH := "PrototypeHUD/MarginContainer/VBoxContainer/"
const Controller = preload("res://prototype/stream/donation_controller.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const COUNTS := Vector3i(10, 10, 10)
const IMPRESSIONS := Vector3(50, 50, 50)


class ScriptedController extends Controller:
	var draws: Array[float] = []
	var draw_count := 0
	var sampled_impressions: Vector3

	func tick(now_msec: int, counts: Vector3i, impressions: Vector3) -> void:
		sampled_impressions = impressions
		super.tick(now_msec, counts, impressions)

	func _draw_unit() -> float:
		draw_count += 1
		return draws.pop_front() if not draws.is_empty() else 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_sampling_boundaries, _schedule_and_reentry, _deterministic_rotation,
		_payment_routing_and_outcomes, _notification_overflow, _crowded_receipt,
	]
	for check in checks:
		if not await check.call():
			printerr("ITER02_STAGE06_DONATIONS_FAIL ", check.get_method())
			quit(1)
			return
	print("ITER02_STAGE06_DONATIONS_PASS groups=", checks.size())
	quit()


func _sampling_boundaries() -> bool:
	var model := ScriptedController.new()
	model.reset(1729)
	model.start()
	model.draws = [0.249, 0.5, 0.49, 0.299, 0.25, 0.0, 0.0, 0.50, 0.30,
		0.0, 0.99, 0.80, 0.99, 0.0, 0.99, 0.98, 0.99, 0.65, 0.0, 0.5, 0.499, 0.30]
	model.tick(9999, COUNTS, IMPRESSIONS)
	model.tick(10000, Vector3i.ZERO, IMPRESSIONS)
	var valid := model.draw_count == 0 and model.get_count() == 0
	model.tick(20000, COUNTS, IMPRESSIONS)
	var first := model.get_last_donation()
	valid = valid and first != null and first.group_index == 1 and first.amount == 2
	valid = valid and not first.question_template_id.is_empty()
	model.tick(30000, COUNTS, IMPRESSIONS)
	valid = valid and model.draw_count == 5 and model.get_count() == 1
	model.tick(40000, Vector3i(0, 10, 0), IMPRESSIONS)
	var second := model.get_last_donation()
	valid = valid and second.group_index == 1 and second.amount == 5
	valid = valid and second.question_template_id.is_empty()
	model.tick(50000, Vector3i(0, 0, 10), IMPRESSIONS)
	valid = valid and model.get_last_donation().amount == 10
	model.tick(60000, COUNTS, IMPRESSIONS)
	valid = valid and model.get_last_donation().amount == 25
	model.tick(70000, Vector3i(200, 200, 200), IMPRESSIONS)
	valid = valid and model.draw_count == 18 and model.get_count() == 4 and model.get_total() == 42
	# The draw lands exactly at the end of the first positive interval.
	model.tick(80000, Vector3i(10, 0, 10), IMPRESSIONS)
	valid = valid and model.get_last_donation().group_index == 2 and model.get_last_donation().amount == 2
	model.free()
	return valid


func _schedule_and_reentry() -> bool:
	var model := ScriptedController.new()
	model.interval_seconds = 1
	model.reset(1729)
	model.interval_seconds = 10
	model.start()
	model.draws = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var observed: Array[int] = []
	model.donation_received.connect(func(
		id: int, _group: int, amount: int, _nick: String, _message: String, _question: bool
	) -> void:
		var record := model.get_last_donation()
		if model.get_count() == id and model.get_total() == id * amount and record.id == id:
			observed.append(record.received_at_msec)
		record.amount = 25
		model.tick(record.received_at_msec, COUNTS, IMPRESSIONS)
	)
	model.tick(999, COUNTS, IMPRESSIONS)
	model.tick(1000, COUNTS, IMPRESSIONS)
	var valid := model.draw_count == 4 and model.get_last_donation().amount == 2
	model.tick(3500, COUNTS, IMPRESSIONS)
	model.tick(3999, COUNTS, IMPRESSIONS)
	model.tick(4000, COUNTS, IMPRESSIONS)
	model.stop()
	model.tick(5000, COUNTS, IMPRESSIONS)
	valid = valid and model.draw_count == 12 and observed == [1000, 3500, 4000]
	model.reset(1729)
	valid = valid and model.get_count() == 0 and model.get_total() == 0 and model.get_last_donation() == null
	model.free()
	return valid


func _deterministic_rotation() -> bool:
	var first := Controller.new()
	var second := Controller.new()
	first.reset(1729)
	second.reset(1729)
	first.start()
	second.start()
	var valid := Content.validate_donations().is_empty()
	var last_id := 0
	var question_ids: Array[StringName] = []
	for opportunity in range(1, 121):
		first.tick(opportunity * 10000, Vector3i(100, 100, 100), IMPRESSIONS)
		randi()
		second.tick(opportunity * 10000, Vector3i(100, 100, 100), IMPRESSIONS)
		var left := first.get_last_donation()
		var right := second.get_last_donation()
		valid = valid and first.get_total() == second.get_total() and first.get_count() == second.get_count()
		if left == null or right == null or left.id == last_id:
			continue
		last_id = left.id
		valid = valid and left.id == right.id and left.group_index == right.group_index
		valid = valid and left.nick == right.nick and left.message == right.message
		valid = valid and left.amount == right.amount and left.question_template_id == right.question_template_id
		if not left.question_template_id.is_empty():
			var definition := Content.build_donation_question(left)
			valid = valid and definition != null and definition.is_valid_candidate()
			valid = valid and definition.donation_amount == left.amount and definition.prompt == left.message
			question_ids.append(left.question_template_id)
	valid = valid and question_ids.size() >= 7 and question_ids[0] == question_ids[6]
	for index in range(1, question_ids.size()):
		valid = valid and question_ids[index] != question_ids[index - 1]
	first.free()
	second.free()
	return valid


func _donation_session(enabled: bool = true, duration: int = 15) -> Timed.ClockSession:
	var node := SessionScene.instantiate()
	node.set_script(Timed.ClockSession)
	var session := node as Timed.ClockSession
	session.session_duration_seconds = duration
	session.messages_enabled = enabled
	session.question_window_seconds = 2.0
	var controller := session.get_node("DonationController")
	controller.set_script(ScriptedController)
	controller.interval_seconds = 1
	var director := session.get_node("StreamDirector")
	director.first_delay_seconds = 4.0
	director.gap_seconds = 1.0
	root.add_child(session)
	session.set_process(false)
	(session.get_node("SnakeGame") as SnakeGame).set_physics_process(false)
	for frame in range(12):
		if session.is_layout_ready():
			return session if session.start_session() else null
		await process_frame
	return null


func _pay_tick(session: Timed.ClockSession, elapsed: int, question: bool) -> void:
	var controller := session.get_node("DonationController") as ScriptedController
	controller.draws.append_array([0.0, 0.0, 0.50, 0.0 if question else 0.30])
	session.now = 1000 + elapsed
	session._process(0.0)


func _donation_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	root.push_input(event)


func _payment_routing_and_outcomes() -> bool:
	var session := await _donation_session()
	if session == null:
		return false
	var controller := session.get_node("DonationController") as ScriptedController
	var director := session._director
	var choice := session._stream_choice
	_pay_tick(session, 1000, false)
	_pay_tick(session, 2000, true)
	var original := controller.get_last_donation()
	_pay_tick(session, 3000, true)
	var newest := controller.get_last_donation()
	session._on_donation_received(newest.id, newest.group_index, newest.amount, newest.nick, newest.message, true)
	var donor_lines := 0
	for line in session._chat_feed.get_lines():
		if line.context == &"donation":
			donor_lines += 1
	if donor_lines != 3 or controller.get_total() != 15 or director._pending_donation.source_event_id != original.id:
		session.free()
		return false
	_pay_tick(session, 4000, false)
	if (
		not choice.is_open() or choice._active.kind != &"donation_question"
		or choice._active.source_event_id != original.id or choice._active.donation_amount != original.amount
		or choice._active.nick != original.nick or choice._active.prompt != original.message
	):
		session.free()
		return false
	var game := session.get_node("SnakeGame") as SnakeGame
	game._physics_process(4.0)
	if not game.is_waiting_for_retry() or not choice.is_open() or not session.pause_session():
		session.free()
		return false
	session.now = 65000
	session._process(0.0)
	if controller.get_count() != 4 or choice.get_remaining_seconds(4000) != 2.0:
		session.free()
		return false
	session.resume_session()
	_donation_key(KEY_SPACE)
	_donation_key(KEY_1)
	var result := choice.get_last_resolution()
	if result == null or result.outcome != &"answered" or result.donation_amount != 5 or controller.get_total() != 20:
		session.free()
		return false
	var cause := session._audience_causes[-1]
	if not cause.delta.is_equal_approx(result.option.effects * 1.5):
		session.free()
		return false
	controller.draws.append_array([0.0, 0.0, 0.50, 0.0])
	session.now = 66000
	session._process(0.0)
	if not choice.is_open() or choice._active.kind != &"donation_question":
		session.free()
		return false
	controller.draws.append_array([0.0, 0.0, 0.50, 0.0])
	session.now = 68000
	var before_expiry := session.get_audience_snapshot().impressions
	session._process(0.0)
	result = choice.get_last_resolution()
	if result.outcome != &"expired" or controller.get_total() != 30:
		session.free()
		return false
	var expected := Vector3.ZERO
	expected[result.source_group_index] = -2.0
	var passive := Vector3(
		move_toward(before_expiry.x, 50.0, 0.2), move_toward(before_expiry.y, 50.0, 0.2),
		move_toward(before_expiry.z, 50.0, 0.2)
	)
	if session._audience_causes[-1].delta != expected or not controller.sampled_impressions.is_equal_approx(passive + expected):
		session.free()
		return false
	if not choice.is_open() or choice._active.kind != &"donation_question":
		session.free()
		return false
	var consumed := controller.draw_count
	var cause_count := session._audience_causes.size()
	session.now = 76000
	session._process(0.0)
	var passed := (
		controller.draw_count == consumed and session._results.donation_count == 6
		and session._results.donation_total == 30
		and session._results.donation_question_counts == Vector4i(3, 1, 1, 1)
		and choice.get_last_resolution().outcome == &"cancelled"
		and session._audience_causes.size() == cause_count
	)
	_donation_key(KEY_ENTER)
	_donation_key(KEY_ENTER)
	passed = passed and controller.get_count() == 0 and controller.get_total() == 0
	session.free()
	return passed


func _notification_overflow() -> bool:
	var session := await _donation_session(false, 20)
	if session == null:
		return false
	for second in range(1, 11):
		_pay_tick(session, second * 1000, true)
	var hud := session.get_node("PrototypeHUD") as PrototypeHUD
	var controller := session.get_node("DonationController") as ScriptedController
	var overflow_seen := false
	for second in range(11, 17):
		_pay_tick(session, second * 1000, true)
		overflow_seen = overflow_seen or hud._donation_notification.text == "Ещё 11 донатов — 55 монет"
		if hud._donation_pending.size() > 3:
			session.free()
			return false
	var donor_lines := 0
	for line in session._chat_feed.get_lines():
		if line.context == &"donation":
			donor_lines += 1
	var passed := (
		overflow_seen and controller.get_total() == 80 and donor_lines == 16
		and not session._stream_choice.is_open() and session._audience_causes.is_empty()
	)
	session.free()
	return passed


func _crowded_receipt() -> bool:
	for collision_first in [true, false]:
		var session := await _donation_session()
		if session == null:
			return false
		var controller := session.get_node("DonationController") as ScriptedController
		var game := session.get_node("SnakeGame") as SnakeGame
		game._state.set("_score", 5)
		game._state.set("_food_cell", Vector2i.ZERO)
		session.now = 5000
		session._process(0.0)
		var choice := session._stream_choice
		if not choice.is_open() or choice._active.kind != &"question":
			session.free()
			return false
		var open_id := choice._active.id
		session.now = 6000
		if collision_first:
			game._physics_process(4.0)
			_pay_tick(session, 5000, true)
		else:
			_pay_tick(session, 5000, true)
			game._physics_process(4.0)
		var received := controller.get_last_donation()
		var pending := session._director._pending_donation
		var sampled := controller.sampled_impressions
		var passed := (
			game.is_waiting_for_retry() and choice.is_open() and choice._active.id == open_id
			and controller.get_count() == 1 and received != null and pending != null
			and pending.source_event_id == received.id
			and sampled.x == (48.0 if collision_first else 50.0)
		)
		session.free()
		if not passed:
			return false
	return true
