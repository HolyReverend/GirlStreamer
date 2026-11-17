class_name StreamChoice
extends Node

const Content = preload("res://prototype/stream/stream_content.gd")
const ANSWER_ACTIONS: Array[StringName] = [&"message_answer_1", &"message_answer_2", &"message_answer_3"]

signal opened(definition: Content.ChoiceDefinition)
signal resolved(choice_id: int, option_index: int, outcome: StringName)

var _time_sampler: Callable
var _active: Content.ChoiceDefinition
var _last_resolution: Content.ChoiceResolution
var _opened_at_msec := 0
var _deadline_msec := 0


func set_time_sampler(sampler: Callable) -> void:
	_time_sampler = sampler


func reset() -> void:
	_active = null
	_last_resolution = null
	_opened_at_msec = 0
	_deadline_msec = 0


func try_open(definition: Content.ChoiceDefinition, now_msec: int) -> bool:
	if is_open() or now_msec < 0 or definition == null or not definition.is_valid():
		return false
	_active = definition.snapshot()
	_opened_at_msec = now_msec
	_deadline_msec = now_msec + _active.window_msec
	opened.emit(_active.snapshot())
	return true


func tick(now_msec: int) -> void:
	if is_open() and now_msec >= _deadline_msec:
		_resolve(&"expired", -1, now_msec)


func cancel(now_msec: int) -> void:
	if is_open():
		_resolve(&"cancelled", -1, now_msec)


func is_open() -> bool:
	return _active != null


func get_remaining_seconds(now_msec: int) -> float:
	return maxi(0, _deadline_msec - now_msec) / 1000.0 if is_open() else 0.0


func get_last_resolution() -> Content.ChoiceResolution:
	return _last_resolution.snapshot() if _last_resolution != null else null


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event.is_pressed() or event.is_echo():
		return
	for index in range(ANSWER_ACTIONS.size()):
		if not event.is_action_pressed(ANSWER_ACTIONS[index]):
			continue
		if not _time_sampler.is_valid():
			return
		var choice_id := _active.id
		var now_msec: int = _time_sampler.call()
		# The session can synchronously cancel the choice while sampling time.
		if now_msec < 0 or not is_open() or _active.id != choice_id:
			return
		get_viewport().set_input_as_handled()
		if now_msec >= _deadline_msec:
			_resolve(&"expired", -1, now_msec)
		else:
			_resolve(&"answered", index, now_msec)
		return


func _resolve(outcome: StringName, option_index: int, now_msec: int) -> void:
	var record := Content.ChoiceResolution.new()
	record.choice_id = _active.id
	record.template_id = _active.template_id
	record.kind = _active.kind
	record.source_event_id = _active.source_event_id
	record.source_group_index = _active.source_group_index
	record.source_attempt_id = _active.source_attempt_id
	record.source_event_kind = _active.source_event_kind
	record.donation_amount = _active.donation_amount
	record.outcome = outcome
	record.option_index = option_index
	record.opened_at_msec = _opened_at_msec
	record.resolved_at_msec = now_msec
	record.elapsed_msec = clampi(now_msec - _opened_at_msec, 0, _active.window_msec)
	if option_index >= 0:
		record.option = _active.options[option_index].snapshot()
	_active = null
	_last_resolution = record
	resolved.emit(record.choice_id, option_index, outcome)
