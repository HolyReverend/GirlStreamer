class_name StreamDirector
extends Node

const Content = preload("res://prototype/stream/stream_content.gd")
const Event = preload("res://prototype/stream/stream_event.gd")
const QUESTION_CONTEXT_TTL_MSEC := 15000
const REACTION_WINDOW_MSEC := 3000
const DEFAULT_QUESTION_WINDOW_MSEC := 6000

@export_range(1.0, 120.0, 0.1) var first_delay_seconds := 20.0
## Minimum active time between successful openings.
@export_range(1.0, 120.0, 0.1) var gap_seconds := 20.0
@export_range(1.0, 30.0, 0.1) var reaction_ttl_seconds := 8.0
@export_range(1.0, 120.0, 0.1) var donation_ttl_seconds := 45.0
@export_range(1.0, 120.0, 0.1) var reaction_cooldown_seconds := 60.0
@export_range(1, 8) var opening_cap := 8

var _open_request: Callable
var _viewer_count_provider: Callable
var _enabled := false
var _next_open_msec := 0
var _gap_msec := 0
var _reaction_ttl_msec := 0
var _donation_ttl_msec := 0
var _reaction_cooldown_msec := 0
var _opening_limit := 0
var _question_window_msec := DEFAULT_QUESTION_WINDOW_MSEC

var _pending_reaction: Event
var _pending_donation: Content.ChoiceDefinition
var _donation_created_msec := 0
var _question_context_event: Event
var _question_templates: Array[Content.QuestionTemplate] = []
var _reaction_templates: Array[Content.QuestionTemplate] = []
var _used_question_templates: Dictionary[StringName, bool] = {}
var _next_reaction_variant: Dictionary[StringName, int] = {}
var _opened_count := 0
var _active_choice_id := 0
var _attempt_id := 0
var _next_reaction_msec := 0
var _latest_event_id := 0
var _latest_donation_id := 0


func configure(open_request: Callable) -> void:
	_open_request = open_request


func set_viewer_count_provider(provider: Callable) -> void:
	_viewer_count_provider = provider


func has_valid_settings() -> bool:
	return (
		_is_valid_seconds(first_delay_seconds, 120.0) and _is_valid_seconds(gap_seconds, 120.0)
		and _is_valid_seconds(reaction_ttl_seconds, 30.0) and _is_valid_seconds(donation_ttl_seconds, 120.0)
		and _is_valid_seconds(reaction_cooldown_seconds, 120.0) and opening_cap >= 1 and opening_cap <= 8
	)


func reset() -> void:
	stop()
	_question_context_event = null
	_used_question_templates.clear()
	_next_reaction_variant.clear()
	_opened_count = 0
	_active_choice_id = 0
	_attempt_id = 0
	_next_reaction_msec = 0
	_latest_event_id = 0
	_latest_donation_id = 0


func start(enabled: bool, question_window_msec: int = DEFAULT_QUESTION_WINDOW_MSEC) -> void:
	if not has_valid_settings():
		stop()
		return
	_next_open_msec = roundi(first_delay_seconds * 1000.0)
	_gap_msec = roundi(gap_seconds * 1000.0)
	_reaction_ttl_msec = roundi(reaction_ttl_seconds * 1000.0)
	_donation_ttl_msec = roundi(donation_ttl_seconds * 1000.0)
	_reaction_cooldown_msec = roundi(reaction_cooldown_seconds * 1000.0)
	_opening_limit = opening_cap
	# A non-default Inspector value is a fixed window for this stream.
	_question_window_msec = question_window_msec
	_question_templates = Content.get_questions()
	_reaction_templates = Content.get_reactions()
	_enabled = enabled


func stop() -> void:
	_enabled = false
	_clear_pending()


func submit_event(event: Event) -> void:
	if event == null or event.id <= _latest_event_id:
		return
	_latest_event_id = event.id
	_prune_pending(event.time_msec)
	if event.kind == Event.Kind.FOOD or event.attempt_id != _attempt_id:
		return
	var event_copy := Event.new(event.id, event.kind, event.time_msec, event.score, event.reason, event.attempt_id)
	_question_context_event = event_copy
	if not _can_admit() or _pending_reaction != null or event.time_msec < _next_reaction_msec:
		return
	if event.kind in [Event.Kind.COLLISION, Event.Kind.RECORD] and event.score < 5:
		return
	_pending_reaction = event_copy
	_next_reaction_msec = event.time_msec + _reaction_cooldown_msec


func submit_donation_question(definition: Content.ChoiceDefinition, now_msec: int) -> void:
	if definition == null or definition.kind != &"donation_question":
		return
	if definition.source_event_id <= _latest_donation_id:
		return
	_latest_donation_id = definition.source_event_id
	_prune_pending(now_msec)
	if _can_admit() and _pending_donation == null and definition.id == 0 and definition.is_valid_candidate():
		_pending_donation = definition.snapshot()
		_donation_created_msec = now_msec


func on_attempt_started(attempt_id: int) -> void:
	_attempt_id = attempt_id
	if _pending_reaction != null and _pending_reaction.attempt_id != attempt_id:
		_pending_reaction = null
	if _question_context_event != null and _question_context_event.kind != Event.Kind.COLLISION:
		if _question_context_event.attempt_id != attempt_id:
			_question_context_event = null


func on_choice_resolved(resolution: Content.ChoiceResolution) -> void:
	if resolution == null or _active_choice_id == 0 or resolution.choice_id != _active_choice_id:
		return
	_active_choice_id = 0


func tick(now_msec: int, snake_playing: bool) -> void:
	_prune_pending(now_msec)
	if not _can_admit() or _active_choice_id != 0 or now_msec < _next_open_msec or not _open_request.is_valid():
		return
	if snake_playing and _pending_donation != null:
		var definition := _pending_donation.snapshot()
		definition.window_msec = _sample_question_window_msec()
		if _try_open(definition, now_msec):
			_pending_donation = null
		return
	if _pending_reaction != null and _reaction_can_open(_pending_reaction, snake_playing):
		_try_open_reaction(now_msec)
		return
	if snake_playing:
		_try_open_question(now_msec)


func _try_open_reaction(now_msec: int) -> void:
	var event := _pending_reaction
	var category := _context_for(event)
	var variant: int = _next_reaction_variant.get(category, 0)
	var variants: Array[Content.QuestionTemplate] = []
	for template in _reaction_templates:
		if template.context == category:
			variants.append(template)
	if variants.is_empty():
		return
	var template := variants[variant]
	var caption := template.prompt
	if event.kind == Event.Kind.BOARD_COMPLETED:
		caption = "Поле заполнено"
	elif event.kind == Event.Kind.RECORD:
		caption = "Новый рекорд"
	var definition := Content.ChoiceDefinition.new(
		0, template.id, &"reaction", caption, "Стрим", template.options,
		REACTION_WINDOW_MSEC, event.id, -1, event.attempt_id, _kind_name(event)
	)
	if _try_open(definition, now_msec):
		_pending_reaction = null
		_next_reaction_variant[category] = (variant + 1) % variants.size()


func _try_open_question(now_msec: int) -> void:
	var template: Content.QuestionTemplate
	var event: Event
	if _question_context_event != null and now_msec - _question_context_event.time_msec <= QUESTION_CONTEXT_TTL_MSEC:
		template = _find_unused_question(_context_for(_question_context_event))
		if template != null:
			event = _question_context_event
	if template == null:
		template = _find_unused_question(&"general")
	if template == null:
		return
	var definition := Content.ChoiceDefinition.new(
		0, template.id, &"question", template.prompt, "", template.options, _sample_question_window_msec(),
		event.id if event != null else 0, -1, event.attempt_id if event != null else 0,
		_kind_name(event) if event != null else &""
	)
	if _try_open(definition, now_msec):
		_used_question_templates[template.id] = true


func _sample_question_window_msec() -> int:
	if _question_window_msec != DEFAULT_QUESTION_WINDOW_MSEC or not _viewer_count_provider.is_valid():
		return _question_window_msec
	var total_viewers: int = _viewer_count_provider.call()
	return clampi(DEFAULT_QUESTION_WINDOW_MSEC - maxi(0, total_viewers - 30) * 10, 5000, 6000)


func _try_open(definition: Content.ChoiceDefinition, now_msec: int) -> bool:
	if not _open_request.call(definition, now_msec):
		return false
	_active_choice_id = definition.id
	_opened_count += 1
	_next_open_msec = now_msec + _gap_msec
	if _opened_count >= _opening_limit:
		_clear_pending()
	return true


func _find_unused_question(context: StringName) -> Content.QuestionTemplate:
	for template in _question_templates:
		if template.context == context and not _used_question_templates.has(template.id):
			return template
	return null


func _prune_pending(now_msec: int) -> void:
	if _pending_reaction != null and (
		_pending_reaction.attempt_id != _attempt_id
		or now_msec >= _pending_reaction.time_msec + _reaction_ttl_msec
	):
		_pending_reaction = null
	if _pending_donation != null and now_msec >= _donation_created_msec + _donation_ttl_msec:
		_pending_donation = null


func _clear_pending() -> void:
	_pending_reaction = null
	_pending_donation = null


func _can_admit() -> bool:
	return _enabled and _opened_count < _opening_limit


static func _is_valid_seconds(seconds: float, maximum: float) -> bool:
	return is_finite(seconds) and seconds >= 1.0 and seconds <= maximum


static func _reaction_can_open(event: Event, snake_playing: bool) -> bool:
	var terminal := event.kind in [Event.Kind.COLLISION, Event.Kind.BOARD_COMPLETED]
	return not snake_playing if terminal else snake_playing


static func _context_for(event: Event) -> StringName:
	return &"loss" if event.kind == Event.Kind.COLLISION else &"achievement"


static func _kind_name(event: Event) -> StringName:
	return StringName(Event.Kind.keys()[event.kind].to_lower())
