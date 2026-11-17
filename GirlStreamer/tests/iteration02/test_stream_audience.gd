extends SceneTree

const Audience = preload("res://prototype/stream/audience_state.gd")
const Choice = preload("res://prototype/stream/stream_choice.gd")
const Timed = preload("res://tests/iteration01/test_timed_session.gd")
const SESSION = preload("res://prototype/prototype_session.tscn")
const TICK_MSEC := 200
const SEED := 1729


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var checks: Array[Callable] = [
		_initial_reset_and_snapshot, _signed_fraction_and_step_order,
		_clamps_recovery_and_peak, _style_usage_and_invalid_input, _scenarios,
	]
	for check in checks:
		if not await check.call():
			printerr("ITER02_STAGE05_AUDIENCE_FAIL ", check.get_method())
			quit(1)
			return
	print("ITER02_STAGE05_AUDIENCE_PASS groups=", checks.size())
	quit()


func _initial_reset_and_snapshot() -> bool:
	var model := Audience.new()
	var initial := model.get_snapshot()
	if (
		initial.counts != Vector3i(10, 10, 10) or initial.impressions != Vector3(50, 50, 50)
		or initial.carries != [0.0, 0.0, 0.0] or initial.total != 30 or initial.peak != 30
		or initial.step_count != 0 or not initial.style_uses.is_empty()
	):
		return false
	initial.counts.x = 99
	initial.impressions.y = 4
	initial.carries[0] = 0.9
	initial.precise_impressions[1] = 4
	initial.style_uses[&"flirt"] = 7
	model.apply_effect(1, Vector3(2, 2, 2), &"flirt")
	model.advance_second()
	var changed := model.get_snapshot()
	if (
		changed.counts != Vector3i(10, 10, 10) or changed.style_uses.get(&"flirt") != 1
		or not _near(changed.precise_impressions[1], 51.9) or not _near(changed.carries[0], 0.06)
	):
		return false
	model.reset()
	var reset := model.get_snapshot()
	return (
		reset.counts == Vector3i(10, 10, 10) and reset.impressions == Vector3(50, 50, 50)
		and reset.carries == [0.0, 0.0, 0.0] and reset.step_count == 0 and reset.peak == 30
		and reset.style_uses.is_empty() and model.apply_effect(1, Vector3.ZERO)
	)


func _signed_fraction_and_step_order() -> bool:
	var model := Audience.new()
	# Pin one group at 30 before each update with an exactly representable target.
	for second in range(20):
		model.apply_effect(second * 2 + 1, Vector3(0, -100, 0))
		model.apply_effect(second * 2 + 2, Vector3(0, 30, 0))
		model.advance_second()
		var snapshot := model.get_snapshot()
		if second < 19 and snapshot.counts != Vector3i(10, 10, 10):
			return false
		if not _near(snapshot.precise_impressions[1], 30.1):
			return false
	var final := model.get_snapshot()
	if final.counts != Vector3i(11, 9, 11) or final.carries != [0.0, 0.0, 0.0]:
		return false
	model.reset()
	model.apply_effect(1, Vector3(10, -10, 0))
	model.advance_second()
	var step := model.get_snapshot()
	if not _near(step.carries[0], 0.1) or not _near(step.precise_impressions[0], 59.9):
		return false
	_advance(model, 9)
	step = model.get_snapshot()
	return _near(step.carries[0], 0.9775) and _near(step.precise_impressions[0], 59.0)


func _clamps_recovery_and_peak() -> bool:
	var model := Audience.new()
	# Repeated large deltas pin the first two groups at opposite impression bounds.
	for id in range(1, 701):
		model.apply_effect(id, Vector3(100, -100, 0))
		model.advance_second()
	var bounded := model.get_snapshot()
	if bounded.counts != Vector3i(200, 0, 45) or bounded.carries[0] != 0 or bounded.carries[1] != 0:
		return false
	# Reverse the first two groups. The cap must allow inward carry immediately.
	for id in range(701, 707):
		model.apply_effect(id, Vector3(-100, 100, -100))
		model.advance_second()
	var recovered := model.get_snapshot()
	return (
		recovered.counts == Vector3i(199, 1, 44)
		and _near(recovered.carries[0], -0.2) and _near(recovered.carries[1], 0.8)
		and recovered.peak == 246 and recovered.total == 244
		and recovered.impressions.is_equal_approx(Vector3(0.1, 99.9, 0.1))
	)


func _style_usage_and_invalid_input() -> bool:
	var model := Audience.new()
	if model.apply_effect(0, Vector3.ONE, &"flirt"):
		return false
	if not model.apply_effect(2, Vector3(4, 1, -2), &"competitive"):
		return false
	if model.apply_effect(2, Vector3.ONE, &"competitive") or model.apply_effect(1, Vector3.ONE, &"humor"):
		return false
	# These expected diagnostics verify rejection before any mutation.
	if model.apply_effect(3, Vector3(INF, 1, 1), &"competitive"):
		return false
	if model.apply_effect(3, Vector3.ONE, &"invalid"):
		return false
	model.apply_effect(3, Vector3(4, 1, -2), &"competitive")
	model.apply_effect(4, Vector3(4, 1, -2), &"competitive")
	model.apply_effect(5, Vector3(4, 1, 0), &"humor")
	var snapshot := model.get_snapshot()
	if (
		not _near(snapshot.precise_impressions[0], 61.33333333333333)
		or not _near(snapshot.precise_impressions[1], 52.83333333333333)
		or snapshot.impressions.z != 44.0 or snapshot.style_uses.size() != 2
		or snapshot.style_uses.get(&"competitive") != 3 or snapshot.style_uses.get(&"humor") != 1
	):
		return false
	model.apply_effect(6, Vector3(100, 0, 0))
	model.apply_effect(7, Vector3(4, 0, 0), &"competitive")
	snapshot = model.get_snapshot()
	return snapshot.impressions.x == 100.0 and snapshot.style_uses.get(&"competitive") == 4


func _advance(model: Audience, steps: int) -> void:
	for second in range(steps):
		model.advance_second()


func _near(first: float, second: float) -> bool:
	return absf(first - second) <= 1e-9


func _scenarios() -> bool:
	var model := Audience.new()
	_advance(model, 180)
	var baseline := model.get_snapshot()
	print("AUDIENCE_SCENARIO baseline initial=30 counts=", baseline.counts, " peak=", baseline.peak,
		" impressions=", baseline.impressions)
	if baseline.counts != Vector3i(19, 19, 19) or baseline.peak != 57:
		return false
	for strategy: StringName in [&"achievement", &"communication", &"repeated_loss"]:
		var result := await _play_scenario(strategy)
		var replay := await _play_scenario(strategy)
		print("AUDIENCE_SCENARIO ", strategy, " ", result)
		if result.is_empty() or result != replay or not _valid_scenario_result(strategy, result):
			return false
	return true


func _play_scenario(strategy: StringName) -> Dictionary:
	var node := SESSION.instantiate()
	node.set_script(Timed.ClockSession)
	var session := node as Timed.ClockSession
	if strategy == &"repeated_loss":
		# Leave the shared window available at three spaced loss events to exercise suppression.
		session.session_duration_seconds = 360
		var director := session.get_node("StreamDirector") as StreamDirector
		director.first_delay_seconds = 85.2
		director.gap_seconds = 84.0
	var duration_msec := session.session_duration_seconds * 1000
	var game := session.get_node("SnakeGame") as SnakeGame
	var choice := session.get_node("StreamChoice") as Choice
	game.columns = 64
	game.rows = 8
	game.use_fixed_seed = true
	game.food_seed = SEED
	root.add_child(session)
	session.set_process(false)
	game.set_physics_process(false)
	for frame in range(12):
		if session.is_layout_ready():
			break
		await process_frame
	if not session.start_session():
		session.free()
		return {}
	# Keep this comparison scoped to the Stage 5 event and ordinary-choice strategies.
	session._donations.stop()
	var milestones: Array[int] = []
	var records: Array[int] = []
	var styles: Array[StringName] = []
	var losses: Array[int] = []
	var loss_bonuses := 0
	var loss_suppressions := 0
	var last_cause: RefCounted
	for time in range(TICK_MSEC, duration_msec + 1, TICK_MSEC):
		session.now = 1000 + time
		if time < duration_msec:
			_drive_snake(session, game, strategy, time)
		if not session._audience_causes.is_empty() and last_cause != session._audience_causes[-1]:
			last_cause = session._audience_causes[-1]
			match last_cause.kind:
				&"milestone":
					milestones.append(session._last_attempt_score)
				&"record":
					records.append(session._last_attempt_score)
				&"collision":
					losses.append(time)
		session._process(0.0)
		if choice.is_open() and time - choice._opened_at_msec >= 400:
			var active := choice._active
			var is_reaction := active.kind == &"reaction"
			var is_loss := is_reaction and active.source_event_kind == &"collision"
			var option := -1
			match strategy:
				&"achievement":
					option = 0 if is_reaction else -1
				&"communication":
					if not is_reaction:
						option = 0
						for index in range(1, active.options.size()):
							if active.options[index].effects.y > active.options[option].effects.y:
								option = index
				&"repeated_loss":
					option = 0 if is_loss else -1
			if option >= 0:
				var before := session.get_audience_snapshot()
				var key := InputEventKey.new()
				key.physical_keycode = KEY_1 + option as Key
				key.pressed = true
				root.push_input(key)
				if not choice.is_open() and is_reaction:
					styles.append(active.options[option].style_id)
					if is_loss:
						if session.get_audience_snapshot().impressions.x > before.impressions.x:
							loss_bonuses += 1
						else:
							loss_suppressions += 1
		if not session._audience_causes.is_empty():
			last_cause = session._audience_causes[-1]
	var results := session._results
	var data := {}
	if results != null:
		data = {
			"initial": 30, "counts": results.audience.counts, "peak": results.audience.peak,
			"impressions": results.audience.impressions, "steps": results.audience.step_count,
			"questions": Vector2i(results.questions_shown, results.questions_answered),
			"reactions": Vector2i(results.reaction_counts.x, results.reaction_counts.y),
			"milestones": milestones, "records": records, "styles": styles, "loss_bonuses": loss_bonuses,
			"loss_suppressions": loss_suppressions, "collisions": results.collisions, "loss_times": losses,
		}
	session.free()
	return data


func _drive_snake(session: Timed.ClockSession, game: SnakeGame, strategy: StringName, time: int) -> void:
	# Retry shortly before each intended scored loss, so no ordinary choice preempts it.
	if game.is_waiting_for_retry():
		if strategy != &"repeated_loss" or time not in [24400, 142000, 207000, 260000, 275000, 290000, 305000, 320000, 335000, 350000]:
			return
		session._try_retry_attempt()
	var state := game._state
	var head := state.get_body_cells()[0]
	var direction := state.get_direction()
	var target := direction
	var collect := false
	var hit_wall := false
	match strategy:
		&"achievement":
			collect = (
				(time >= 29200 and time <= 30000) or (time >= 94200 and time <= 95000)
				or (time >= 158200 and time <= 160000) or time == 225000
			)
		&"communication":
			collect = time == 200
		&"repeated_loss":
			collect = game._state.get_score() < 5 and time < 214000 and time >= 24400
			hit_wall = (
				time < 8000 or (time >= 85000 and time < 100000)
				or (time >= 169000 and time < 178000) or (time >= 253000 and time < 260000)
				or time >= 260000
			)
	# Safe rectangular circuit except when deliberately missing a corner.
	if hit_wall and time >= 85000 and direction.x != 0:
		target = Vector2i.UP if head.y < 4 else Vector2i.DOWN
	elif not hit_wall:
		if direction == Vector2i.RIGHT and head.x == 60:
			target = Vector2i.DOWN
		elif direction == Vector2i.DOWN and head.y == 6:
			target = Vector2i.LEFT
		elif direction == Vector2i.LEFT and head.x == 3:
			target = Vector2i.UP
		elif direction == Vector2i.UP and head.y == 1:
			target = Vector2i.RIGHT
	if target != direction:
		state.request_turn(target)
	state.set("_food_cell", head + target if collect else Vector2i.ZERO)
	game._physics_process(game._active_tick_seconds)


func _valid_scenario_result(strategy: StringName, result: Dictionary) -> bool:
	var counts: Vector3i = result.counts
	var impressions: Vector3 = result.impressions
	if (
		result.steps != (360 if strategy == &"repeated_loss" else 180) or counts.clamp(Vector3i.ZERO, Vector3i(200, 200, 200)) != counts
		or impressions.clamp(Vector3.ZERO, Vector3(100, 100, 100)) != impressions
		or result.questions.x + result.reactions.x > 8
	):
		return false
	match strategy:
		&"achievement":
			return result.milestones == [5, 10, 20] and result.records == [6, 11] and result.reactions.y > 0
		&"communication":
			return result.questions == Vector2i(6, 6) and result.reactions == Vector2i.ZERO
		&"repeated_loss":
			return result.loss_bonuses == 2 and result.loss_suppressions >= 1 and result.collisions >= 4
	return false
