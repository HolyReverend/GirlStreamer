extends Node
## Owns the room, one evening settlement, and the transition to the next morning.

const DayModel = preload("res://prototype/day/day_state.gd")
const Session = preload("res://prototype/prototype_session.gd")
const Preparation = preload("res://prototype/day/preparation_screen.gd")
const ResultsView = preload("res://prototype/day/day_results.gd")
const StreamResults = preload("res://prototype/stream/stream_results.gd")
const LAYOUT_WAIT_FRAMES := 12

@export var stream_scene: PackedScene

var _day := DayModel.new()
var _transitioning := false
var _candidate: Session
var _active_session: Session
var _completion_handler: Callable
var _layout_wait_frames := 0
var _shown_day := 0
var _muted := false
var _enter_down := false
var _block_enter_release := false
var _ignore_next_double_click := false
var _ignore_mouse_release := false

@onready var _stream_host: Node = $StreamHost
@onready var _preparation: Preparation = $PreparationScreen
@onready var _results: ResultsView = $DayResults


func _ready() -> void:
	get_window().min_size = Session.MIN_WINDOW_SIZE
	set_process(false)
	_preparation.activity_requested.connect(_on_activity_requested)
	_preparation.stream_requested.connect(_on_stream_requested)
	_preparation.skip_requested.connect(_on_skip_requested)
	_results.continue_requested.connect(_on_continue_requested)
	get_window().focus_exited.connect(_clear_input_state)
	_refresh_preparation()


func _refresh_preparation() -> void:
	var previews: Dictionary[StringName, DayModel.ActivityResult] = {}
	for id in Preparation.ACTIVITY_IDS:
		previews[id] = _day.preview_activity(id)
	_preparation.render(_day.get_snapshot(), previews)


func _on_activity_requested(id: StringName) -> void:
	if _transitioning or _day.get_snapshot().phase != DayModel.Phase.PREPARING:
		return
	var result := _day.apply_activity(id)
	_refresh_preparation()
	_preparation.show_activity_result(result)


func _on_stream_requested() -> void:
	if _transitioning or _day.get_snapshot().phase != DayModel.Phase.PREPARING:
		return
	_transitioning = true
	_preparation.set_busy(true)
	get_viewport().set_input_as_handled()
	_mount_candidate.call_deferred()


func _mount_candidate() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not _transitioning:
		return
	var instance := stream_scene.instantiate() if stream_scene != null else null
	_candidate = instance as Session
	if _candidate == null:
		if instance != null:
			instance.free()
		_fail_launch()
		return
	# Keep the candidate laid out behind the room with its entire input subtree disabled.
	_candidate.process_mode = Node.PROCESS_MODE_DISABLED
	_candidate.muted = _muted
	_stream_host.add_child(_candidate)
	_layout_wait_frames = LAYOUT_WAIT_FRAMES
	set_process(true)


func _process(_delta: float) -> void:
	if not is_instance_valid(_candidate) or _candidate.is_queued_for_deletion():
		_fail_launch()
	elif _candidate.is_layout_ready():
		_start_candidate()
	else:
		_layout_wait_frames -= 1
		if _layout_wait_frames == 0:
			_fail_launch()


func _start_candidate() -> void:
	var launch := _day.preview_launch()
	if launch == null:
		_fail_launch()
		return
	_completion_handler = _on_stream_completed.bind(launch.day_number, _candidate)
	_candidate.managed_completed.connect(_completion_handler)
	if not _candidate.start_session(launch) or not _day.begin_stream():
		_fail_launch()
		return
	set_process(false)
	_preparation.hide()
	_active_session = _candidate
	_active_session.process_mode = Node.PROCESS_MODE_INHERIT
	_candidate = null
	_transitioning = false


func _fail_launch() -> void:
	set_process(false)
	if is_instance_valid(_candidate):
		_dispose_session(_candidate)
	_candidate = null
	_transitioning = false
	_refresh_preparation()
	_preparation.set_busy(false)
	_preparation.show_launch_error()


func _on_skip_requested() -> void:
	if _transitioning or not _day.skip_stream():
		return
	get_viewport().set_input_as_handled()
	var day := _day.get_snapshot().day_number
	_show_results(_day.settle_skip(day), null)


func _on_stream_completed(frozen: StreamResults, day: int, source: Session) -> void:
	var snapshot := _day.get_snapshot()
	if (
		not is_instance_valid(source) or source != _active_session or day != snapshot.day_number
		or snapshot.phase != DayModel.Phase.STREAMING or not source.is_finished()
	):
		return
	if frozen == null or frozen != source.build_results_snapshot():
		push_error("Managed stream finished without frozen results.")
		source._hud.set_status("Не удалось получить итоги стрима")
		return
	var result := _day.settle_stream(day, frozen.donation_total)
	if result == null:
		push_error("Managed stream settlement rejected.")
		source._hud.set_status("Не удалось подвести итоги дня")
		return
	source.process_mode = Node.PROCESS_MODE_DISABLED
	_show_results(result, frozen)


func _show_results(result: DayModel.DayResult, frozen: StreamResults) -> void:
	_shown_day = result.day_number
	_ignore_next_double_click = true
	_preparation.hide()
	_results.render(result, _day.preview_morning(_shown_day), frozen)
	_results.show()
	_results.focus_continue()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_ignore_mouse_release = _ignore_next_double_click and event.double_click
			_ignore_next_double_click = false
		if _ignore_mouse_release:
			get_viewport().set_input_as_handled()
			_ignore_mouse_release = event.pressed
		return
	if not event.is_action(&"session_restart"):
		return
	var fresh_press := event.is_pressed() and not event.is_echo() and not _enter_down
	_enter_down = event.is_pressed()
	if not _results.visible and not _block_enter_release:
		return
	get_viewport().set_input_as_handled()
	if not _enter_down:
		_block_enter_release = false
	elif _results.visible and fresh_press:
		_on_continue_requested()


func _clear_input_state() -> void:
	_enter_down = false
	_block_enter_release = false
	_ignore_next_double_click = false
	_ignore_mouse_release = false


func _on_continue_requested() -> void:
	if _transitioning or _shown_day == 0:
		return
	_transitioning = true
	_block_enter_release = _enter_down
	_ignore_next_double_click = true
	get_viewport().set_input_as_handled()
	# Switch screens after the input dispatch so the release cannot activate a room button.
	_continue_to_morning.call_deferred(_shown_day)


func _continue_to_morning(day: int) -> void:
	if _day.advance_morning(day) == null:
		_transitioning = false
		return
	if is_instance_valid(_active_session):
		_muted = _active_session.muted
		_dispose_session(_active_session)
		_active_session = null
	_shown_day = 0
	_results.hide()
	_preparation.reset_for_morning()
	_preparation.show()
	_refresh_preparation()
	_transitioning = false


func _dispose_session(session: Session) -> void:
	if _completion_handler.is_valid():
		session.managed_completed.disconnect(_completion_handler)
		_completion_handler = Callable()
	session.queue_free()
	if session.get_parent() == _stream_host:
		_stream_host.remove_child(session)
