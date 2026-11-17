extends Node

const Content = preload("res://prototype/stream/stream_content.gd")
const Audience = preload("res://prototype/stream/audience_state.gd")

signal donation_received(id: int, group_index: int, amount: int, nick: String, message: String, has_question: bool)

@export_range(1, 60) var interval_seconds := 10

var _interval_msec := 10000
var _next_due_msec := 0
var _enabled := false
var _count := 0
var _total := 0
var _last_donation: Content.DonationRecord
var _rng := RandomNumberGenerator.new()
var _questions := Content.get_donation_questions()
var _messages := Content.get_templates(&"donation")
var _question_index := 0
var _message_index := 0


func has_valid_settings() -> bool:
	return interval_seconds >= 1 and interval_seconds <= 60


func reset(seed: int) -> void:
	_enabled = false
	_interval_msec = interval_seconds * 1000 if has_valid_settings() else 0
	_next_due_msec = 0
	_count = 0
	_total = 0
	_last_donation = null
	_question_index = 0
	_message_index = 0
	_rng.seed = seed


func start() -> void:
	if _next_due_msec == 0 and _interval_msec > 0:
		_enabled = true
		_next_due_msec = _interval_msec


func stop() -> void:
	_enabled = false


func get_total() -> int:
	return _total


func get_count() -> int:
	return _count


func get_last_donation() -> Content.DonationRecord:
	return _last_donation.snapshot() if _last_donation != null else null


func tick(now_msec: int, counts: Vector3i, impressions: Vector3) -> void:
	if not _enabled or now_msec < _next_due_msec:
		return
	_next_due_msec = now_msec - posmod(now_msec, _interval_msec) + _interval_msec
	if (
		not impressions.is_finite()
		or impressions.clamp(Vector3.ZERO, Vector3.ONE * 100.0) != impressions
		or counts.clamp(Vector3i.ZERO, Vector3i.ONE * Audience.MAX_VIEWERS) != counts
	):
		push_error("Invalid donation audience snapshot.")
		return

	var weights: Array[float] = []
	var total_weight := 0.0
	for group in range(Audience.GROUP_COUNT):
		var weight := counts[group] * float(impressions[group]) / 100.0
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0 or _draw_unit() >= minf(total_weight / 60.0, 0.65):
		return

	var group_index := _sample_group(weights, total_weight)
	var amount := _sample_amount()
	var has_question := _draw_unit() < 0.30
	var template_id: StringName = &""
	var message: String
	if has_question:
		var question := _questions[_question_index]
		template_id = question.id
		message = question.prompt
		_question_index = (_question_index + 1) % _questions.size()
	else:
		message = _messages[_message_index].text
		_message_index = (_message_index + 1) % _messages.size()
	var nick := Content.NICKNAMES[_count % Content.NICKNAMES.size()]
	var id := _count + 1
	_last_donation = Content.DonationRecord.new(id, now_msec, group_index, amount, nick, message, template_id)
	_count = id
	_total += amount
	donation_received.emit(id, group_index, amount, nick, message, has_question)


func _sample_group(weights: Array[float], total_weight: float) -> int:
	var target := _draw_unit() * total_weight
	var upper := 0.0
	var last_positive := -1
	for group in range(weights.size()):
		if weights[group] <= 0.0:
			continue
		last_positive = group
		upper += weights[group]
		if target < upper:
			return group
	return last_positive


func _sample_amount() -> int:
	var draw := _draw_unit()
	if draw < 0.50:
		return 2
	if draw < 0.80:
		return 5
	if draw < 0.98:
		return 10
	return 25


func _draw_unit() -> float:
	# randf() can return 1.0. Map a uint32 to a half-open interval instead.
	return _rng.randi() / 4294967296.0
