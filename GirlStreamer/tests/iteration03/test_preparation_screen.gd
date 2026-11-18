extends SceneTree

const DayModel = preload("res://prototype/day/day_state.gd")
const Session = preload("res://prototype/prototype_session.gd")
const STREAM = preload("res://prototype/prototype_session.tscn")
const DAY_PATH := "res://prototype/day/day_cycle.tscn"
const ACTIVITIES := [
	"%PublishPost", "%PrepareTopic", "%TrainSnake", "%WatchAnime", "%TakeNap",
]
const ACTIVITY_REASONS := [
	"Анонс уже опубликован", "Тема уже подготовлена", "Открыт контур опасности",
	"Не хватает ОД", "Не хватает ОД",
]
const EVENING := ["%StartStream", "%SkipStream"]
const FAIL_TEXT := "Не удалось начать стрим"
const RESTART_HINT := "PrototypeHUD/MarginContainer/VBoxContainer/ResultsInstructions"

var _days: PackedScene
var _cycle: Node
var _room: Control
var _host: Node


class NeverReadySession extends Session:
	var readiness_checks := 0
	var start_attempts := 0

	func is_layout_ready() -> bool:
		readiness_checks += 1
		return false

	func start_session(launch: DayModel.LaunchSnapshot = null) -> bool:
		start_attempts += 1
		return super.start_session(launch)


class RejectStartSession extends Session:
	var attempted_when_ready := false

	func start_session(_snapshot: DayModel.LaunchSnapshot = null) -> bool:
		attempted_when_ready = is_layout_ready()
		return false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if ProjectSettings.get_setting("application/run/main_scene") != DAY_PATH:
		_fail("day cycle is not the normal startup scene")
		return
	_days = load(DAY_PATH) as PackedScene
	if _days == null:
		_fail("day cycle cannot be loaded")
		return
	var checks: Array[Callable] = [
		_initial_room_and_navigation, _capped_activity_and_rejection, _full_day_and_start,
		_fresh_start, _fresh_skip, _zero_ap_skip, _missing_layout_and_retry,
		_start_rejection_and_retry, _standalone_compatibility,
	]
	for check in checks:
		var passed: bool = await check.call()
		if is_instance_valid(_cycle):
			_cycle.free()
		if not passed:
			_fail(str(check.get_method()))
			return
	print("STAGE02_PREPARATION_SCREEN_PASS checks=", checks.size())
	quit(0)


func _fail(detail: String) -> void:
	printerr("STAGE02_PREPARATION_SCREEN_FAIL ", detail)
	quit(1)


func _mount_day(stream_scene: PackedScene = STREAM) -> void:
	_cycle = _days.instantiate()
	_cycle.set("stream_scene", stream_scene)
	_room = _cycle.get_node("PreparationScreen") as Control
	_host = _cycle.get_node("StreamHost")
	root.add_child(_cycle)
	await process_frame


func _snapshot() -> DayModel.DaySnapshot:
	var day := _cycle.get("_day") as DayModel
	return day.get_snapshot()


func _values() -> Array:
	var day := _snapshot()
	return [
		day.phase, day.day_number, day.coins, day.ap, day.vigor, day.concentration,
		day.mastery_progress, day.mastery_level, day.post_published, day.topic_prepared,
	]


func _button(path: String) -> Button:
	return _room.get_node(path) as Button


func _text(path: String) -> String:
	return (_room.get_node(path) as Label).text


func _press(path: String) -> void:
	_button(path).pressed.emit()


func _send_key(code: Key, pressed: bool, shift := false, echo := false) -> void:
	var input := InputEventKey.new()
	input.keycode = code
	input.physical_keycode = code
	input.pressed = pressed
	input.shift_pressed = shift
	input.echo = echo
	root.push_input(input)


func _tap_key(code: Key, shift := false) -> void:
	_send_key(code, true, shift)
	_send_key(code, false, shift)


func _initial_room_and_navigation() -> bool:
	await _mount_day()
	var before := _values()
	if (
		before != [DayModel.Phase.PREPARING, 1, 0, 6, 8, 8, 0, 0, false, false]
		or not _room.visible or _host.get_child_count() != 0
		or root.min_size != Vector2i(1024, 768)
		or not _text("%DayHeading").contains("1")
		or not _text("%Coins").contains("0")
		or not _text("%ActionPoints").contains("6")
		or not _text("%Condition").contains("Бодрость: 8/10")
		or not _text("%Condition").contains("Концентрация: 8/10")
		or not _text("%Condition").contains("0 из 4")
	):
		return false
	var order: Array = ACTIVITIES + EVENING
	for path: String in order:
		var button := _button(path)
		if button.disabled or not button.has_focus():
			return false
		_tap_key(KEY_TAB)
	_tap_key(KEY_TAB, true)
	await process_frame
	return _button(order[-1]).has_focus() and _values() == before


func _capped_activity_and_rejection() -> bool:
	await _mount_day()
	_button("%WatchAnime").grab_focus()
	_tap_key(KEY_ENTER)
	var anime := _button("%WatchAnime")
	if _snapshot().concentration != 10 or _snapshot().ap != 5 or not anime.has_focus():
		return false
	var capped_preview := _text("%WatchAnimeDetails").contains("Концентрация +0")
	_tap_key(KEY_ENTER)
	if not capped_preview or _snapshot().concentration != 10 or _snapshot().ap != 4:
		return false
	_button("%PublishPost").grab_focus()
	_tap_key(KEY_ENTER)
	var before := _values()
	var success_text := _text("%Feedback")
	_room.emit_signal("activity_requested", &"publish_post")
	return (
		_snapshot().ap == 3 and _snapshot().post_published and _values() == before
		and _button("%PublishPost").disabled and _button("%PrepareTopic").has_focus()
		and not success_text.is_empty() and _text("%Feedback") == "Анонс уже опубликован"
	)


func _spend_all_ap() -> bool:
	for path in ["%TrainSnake", "%TrainSnake", "%PublishPost", "%PrepareTopic"]:
		_press(path)
	if _values() != [DayModel.Phase.PREPARING, 1, 0, 0, 6, 3, 4, 1, true, true]:
		return false
	for index in ACTIVITIES.size():
		var path: String = ACTIVITIES[index]
		var details := _room.get_node(path + "Details") as Label
		if not _button(path).disabled or not details.visible:
			return false
		if not details.text.contains(ACTIVITY_REASONS[index]):
			return false
	var forecast := _text("%Forecast")
	return (
		forecast.contains("Контур опасности: 2 клетки") and forecast.contains("−10%")
		and forecast.contains("+3 зрителя") and forecast.contains("Первый вопрос:")
		and _button("%StartStream").is_visible_in_tree() and not _button("%StartStream").disabled
		and _button("%SkipStream").is_visible_in_tree() and not _button("%SkipStream").disabled
	)


func _full_day_and_start() -> bool:
	await _mount_day()
	return _spend_all_ap() and await _start_and_check()


func _fresh_start() -> bool:
	await _mount_day()
	return await _start_and_check()


func _start_and_check() -> bool:
	var before := _values()
	_button("%StartStream").grab_focus()
	_tap_key(KEY_ENTER)
	if not _button("%StartStream").disabled or _host.get_child_count() != 0:
		return false
	_room.emit_signal("stream_requested")
	_room.emit_signal("skip_requested")
	for frame in 16:
		_send_key(KEY_ENTER, true, false, true)
		await process_frame
	_send_key(KEY_ENTER, false)
	before[0] = DayModel.Phase.STREAMING
	if _host.get_child_count() != 1 or _room.visible or _values() != before:
		return false
	var stream := _host.get_child(0) as Session
	if stream == null or not stream.is_stream_active() or _button("%StartStream").has_focus():
		return false
	var launch := stream.get("_launch_snapshot") as DayModel.LaunchSnapshot
	if launch == null or [
		launch.day_number, launch.vigor, launch.concentration,
		launch.mastery_level, launch.post_published, launch.topic_prepared,
	] != [before[1], before[4], before[5], before[7], before[8], before[9]]:
		return false
	# The runner skips closing immediately, so keep the finish cue out of this fixture.
	_tap_key(KEY_M)
	if not stream.muted:
		return false
	stream._finish_session(Time.get_ticks_msec())
	_tap_key(KEY_ENTER)
	before[0] = DayModel.Phase.RESULTS
	before[4] = maxi(0, before[4] - 3)
	before[5] = maxi(0, before[5] - 2)
	return (
		stream._session_state == Session.SessionState.FINISHED
		and not (stream.get_node(RESTART_HINT) as Label).visible
		and _values() == before
		and _cycle.get_node("DayResults").visible
	)


func _fresh_skip() -> bool:
	await _mount_day()
	return await _skip_and_check()


func _zero_ap_skip() -> bool:
	await _mount_day()
	return _spend_all_ap() and await _skip_and_check()


func _skip_and_check() -> bool:
	var before := _values()
	_press("%SkipStream")
	_room.emit_signal("skip_requested")
	_room.emit_signal("stream_requested")
	await process_frame
	before[0] = DayModel.Phase.RESULTS
	return (
		_values() == before and _host.get_child_count() == 0
		and not _room.visible and _cycle.get_node("DayResults").visible
	)


func _missing_layout_and_retry() -> bool:
	return await _recover_and_retry(NeverReadySession, false)


func _start_rejection_and_retry() -> bool:
	return await _recover_and_retry(RejectStartSession, true)


func _recover_and_retry(script: GDScript, should_attempt: bool) -> bool:
	var fixture := _pack_fixture(script)
	if fixture == null:
		return false
	await _mount_day(fixture)
	_press("%PublishPost")
	var before := _values()
	_button("%StartStream").grab_focus()
	var attempted_when_ready: Array[bool] = []
	var readiness_checks: Array[int] = []
	var start_attempts: Array[int] = []
	var blocked_at_mount: Array[bool] = []
	_host.child_entered_tree.connect(func(node: Node) -> void:
		blocked_at_mount.append(not node.can_process())
		var candidate := node as RejectStartSession
		if candidate != null:
			candidate.tree_exiting.connect(func() -> void:
				attempted_when_ready.append(candidate.attempted_when_ready)
			)
		var never_ready := node as NeverReadySession
		if never_ready != null:
			never_ready.tree_exiting.connect(func() -> void:
				readiness_checks.append(never_ready.readiness_checks)
				start_attempts.append(never_ready.start_attempts)
			)
	, CONNECT_ONE_SHOT)
	_press("%StartStream")
	for frame in 16:
		await process_frame
		if frame == 3 and not should_attempt:
			if _host.get_child_count() != 1:
				return false
			var candidate := _host.get_child(0)
			if candidate.get_node("SnakeGame").can_process() or candidate.get_node("StreamChoice").can_process():
				return false
			_tap_key(KEY_ENTER)
	if (
		blocked_at_mount != [true]
		or attempted_when_ready != ([true] if should_attempt else [])
		or readiness_checks != ([] if should_attempt else [12])
		or start_attempts != ([] if should_attempt else [0])
		or _values() != before or _host.get_child_count() != 0
		or not _room.visible or _button("%StartStream").disabled
		or not _button("%StartStream").has_focus() or not _text("%Feedback").contains(FAIL_TEXT)
	):
		return false
	_cycle.set("stream_scene", STREAM)
	return await _start_and_check()


func _pack_fixture(script: GDScript) -> PackedScene:
	var session := STREAM.instantiate()
	session.scene_file_path = ""
	session.set_script(script)
	var fixture := PackedScene.new()
	var result := fixture.pack(session)
	session.free()
	return fixture if result == OK else null


func _standalone_compatibility() -> bool:
	var session := STREAM.instantiate() as Session
	_cycle = session
	root.add_child(session)
	for frame in 16:
		if session.is_layout_ready():
			break
		await process_frame
	if not session.is_layout_ready() or session._session_state != Session.SessionState.READY:
		return false
	_tap_key(KEY_ENTER)
	if not session.is_stream_active():
		return false
	_tap_key(KEY_ESCAPE)
	if session._session_state != Session.SessionState.PAUSED:
		return false
	_tap_key(KEY_ESCAPE)
	if not session.is_stream_active():
		return false
	_tap_key(KEY_M)
	if not session.muted:
		return false
	session._finish_session(Time.get_ticks_msec())
	_tap_key(KEY_ENTER)
	if (
		session._session_state != Session.SessionState.FINISHED
		or not (session.get_node(RESTART_HINT) as Label).visible
	):
		return false
	_tap_key(KEY_ENTER)
	return session.is_stream_active()
