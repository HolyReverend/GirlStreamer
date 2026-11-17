class_name ChatFeed
extends Node

const Content = preload("res://prototype/stream/stream_content.gd")

signal lines_changed(lines: Array[Content.ChatLine])

const _AMBIENT_INTERVAL_MSEC := 4000
const _HISTORY_LIMIT := 60
const _EVENT_CONTEXTS: Array[StringName] = [&"food", &"achievement", &"loss"]

var _rng := RandomNumberGenerator.new()
var _viewer_count_provider: Callable
var _lines: Array[Content.ChatLine] = []
var _last_template_id: StringName = &""
var _next_ambient_msec := 0
var _started := false
var _enabled := false


func set_viewer_count_provider(provider: Callable) -> void:
	_viewer_count_provider = provider


func reset(seed: int) -> void:
	_lines.clear()
	_last_template_id = &""
	_next_ambient_msec = 0
	_started = false
	_enabled = false
	_rng.seed = seed
	lines_changed.emit(get_lines())


func start(now_msec: int) -> void:
	if _started:
		return
	_started = true
	_enabled = true
	_append(&"start", now_msec)


func tick(now_msec: int, snake_playing: bool) -> void:
	if not _enabled or now_msec < _next_ambient_msec:
		return
	var context := &"ambient_playing" if snake_playing else &"ambient_waiting"
	_append(context, now_msec)


func append_context(context: StringName, now_msec: int) -> void:
	if _enabled and context in _EVENT_CONTEXTS:
		_append(context, now_msec)


func append_answer_response(option: Content.ChoiceOption, now_msec: int) -> void:
	if not _enabled or option == null or not option.is_valid():
		return
	var template_ids: Array[StringName] = [
		StringName("%s_response_0" % option.id),
		StringName("%s_response_1" % option.id),
	]
	var response_index := _rng.randi_range(0, 1)
	if template_ids[response_index] == _last_template_id:
		response_index = 1 - response_index
	_append_line(template_ids[response_index], option.chat_responses[response_index], &"answer", now_msec)


func append_donation(record: Content.DonationRecord, now_msec: int) -> void:
	if not _enabled or record == null:
		return
	var message := record.message if not record.message.is_empty() else "Поддержка эфира"
	_store_line(Content.ChatLine.new(
		StringName("donation_%d" % record.id), record.nick,
		"%d монет — %s" % [record.amount, message], &"donation", now_msec
	))


func stop() -> void:
	_enabled = false


func get_lines() -> Array[Content.ChatLine]:
	var snapshot: Array[Content.ChatLine] = []
	for line in _lines:
		snapshot.append(Content.ChatLine.new(
			line.template_id, line.nick, line.text, line.context, line.time_msec
		))
	return snapshot


func _append(context: StringName, now_msec: int) -> void:
	var candidates: Array[Content.ChatTemplate] = []
	for template in Content.get_templates(context):
		if template.id != _last_template_id:
			candidates.append(template)
	if candidates.is_empty():
		return

	var template := candidates[_rng.randi_range(0, candidates.size() - 1)]
	_append_line(template.id, template.text, context, now_msec)


func _append_line(template_id: StringName, message: String, context: StringName, now_msec: int) -> void:
	var nicknames := Content.NICKNAMES
	var nickname := nicknames[_rng.randi_range(0, nicknames.size() - 1)]
	_last_template_id = template_id
	_store_line(Content.ChatLine.new(template_id, nickname, message, context, now_msec))


func _store_line(line: Content.ChatLine) -> void:
	_lines.append(line)
	if _lines.size() > _HISTORY_LIMIT:
		_lines.pop_front()
	_next_ambient_msec = line.time_msec + _ambient_interval_msec()
	lines_changed.emit(get_lines())


func _ambient_interval_msec() -> int:
	if not _viewer_count_provider.is_valid():
		return _AMBIENT_INTERVAL_MSEC
	var total_viewers: int = _viewer_count_provider.call()
	return roundi(clampf(4000.0 * 30.0 / maxi(1, total_viewers), 1500.0, 6000.0))
