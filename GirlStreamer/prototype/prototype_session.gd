extends Node

enum SessionState { READY, RUNNING, PAUSED, CLOSING, FINISHED }

const MIN_WINDOW_SIZE := Vector2i(1024, 768)
const CLOSING_DURATION_MSEC := 2000
const FOOD_FEEDBACK_GAP_MSEC := 3000
const MILESTONES := [5, 10, 20]
const INVALID_SNAKE_SETTINGS := "Не удалось начать: проверьте настройки Змейки"
const QUESTION_FEEDBACK_MSEC := 1000
const AUDIENCE_CAUSE_LIMIT := 20
const Audience = preload("res://prototype/stream/audience_state.gd")
const Donations = preload("res://prototype/stream/donation_controller.gd")
const Director = preload("res://prototype/stream/stream_director.gd")
const Choice = preload("res://prototype/stream/stream_choice.gd")
const Event = preload("res://prototype/stream/stream_event.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const Feed = preload("res://prototype/stream/chat_feed.gd")
const Webcam = preload("res://prototype/ui/hero_webcam.gd")
const StreamResults = preload("res://prototype/stream/stream_results.gd")
const StreamAudio = preload("res://prototype/stream/stream_audio.gd")

class AudienceCause:
	var kind: StringName
	var source_id: int
	var time_msec: int
	var explanation: String
	var delta: Vector3

@export_range(1, 600, 1, "suffix:s") var session_duration_seconds: int = 180
@export var messages_enabled: bool = true
@export_range(1.0, 15.0, 0.1, "suffix:s") var question_window_seconds: float = 6.0
@export_range(1.0, 120.0, 0.1, "suffix:s") var record_reward_interval_seconds: float = 60.0

var _session_state: SessionState = SessionState.READY
var _layout_ready := false
var _elapsed_before_run_msec := 0
var _run_started_msec := 0
var _duration_msec := 0
var _closing_started_msec := 0
var _results: StreamResults
var _total_food := 0
var _attempts_started := 0
var _collisions := 0
var _boards_completed := 0
var _last_attempt_score := 0
var _high_score := 0
var _session_messages_enabled := false
var _active_question_id := 0
var _questions_shown := 0
var _questions_answered := 0
var _questions_expired := 0
var _questions_cancelled := 0
var _answer_times_seconds: Array[float] = []
var _choice_counts: Dictionary[StringName, Vector4i] = {}
var _next_choice_id := 1
var _question_feedback_until_msec := 0
var _choice_resolutions: Array[Content.ChoiceResolution] = []
var _snake_action_time_msec := 0
var _next_stream_event_id := 1
var _presented_milestones: Dictionary[int, bool] = {}
var _next_food_feedback_msec := 0
var _audience := Audience.new()
var _next_audience_step_msec := 1000
var _audience_time_msec := 0
var _last_audience_event_id := 0
var _last_audience_choice_id := 0
var _next_audience_effect_id := 1
var _next_record_reward_msec := 0
var _record_reward_interval_msec := 0
var _rewarded_milestones: Dictionary[int, bool] = {}
var _rewarded_completion := false
var _rewarded_loss_reactions := 0
var _audience_causes: Array[AudienceCause] = []
var _last_routed_donation_id := 0
var muted := false

@onready var _snake_game: SnakeGame = $SnakeGame
@onready var _hud: PrototypeHUD = $PrototypeHUD
@onready var _stream_choice: Choice = $StreamChoice
@onready var _director: Director = $StreamDirector
@onready var _chat_feed: Feed = $ChatFeed
@onready var _donations: Donations = $DonationController
@onready var _webcam: Webcam = _hud.get_webcam()
@onready var _stream_audio: StreamAudio = $StreamAudio


func _ready() -> void:
	get_window().min_size = MIN_WINDOW_SIZE
	_hud.board_rect_changed.connect(_on_board_rect_changed)
	_snake_game.score_changed.connect(_on_score_changed)
	_snake_game.attempt_finished.connect(_on_attempt_finished)
	_snake_game.set_action_authorizer(_authorize_snake_action)
	_stream_choice.set_time_sampler(_sample_running_time_msec)
	_stream_choice.opened.connect(_on_question_opened)
	_stream_choice.resolved.connect(_on_question_resolved)
	_director.configure(_request_choice_open)
	_director.set_viewer_count_provider(_get_viewer_count)
	_chat_feed.set_viewer_count_provider(_get_viewer_count)
	_chat_feed.lines_changed.connect(_hud.set_chat_lines)
	_donations.donation_received.connect(_on_donation_received)
	_hud.show_ready()
	_hud.set_muted(muted)
	_apply_initial_layout.call_deferred()


func _apply_initial_layout() -> void:
	_on_board_rect_changed(_hud.get_board_rect())


func _on_board_rect_changed(rect: Rect2) -> void:
	_snake_game.set_board_rect(rect)
	if rect.has_area():
		_layout_ready = true


func is_layout_ready() -> bool:
	return _layout_ready


func is_stream_active() -> bool:
	return _session_state == SessionState.RUNNING


func start_session() -> bool:
	if not _layout_ready:
		return false
	if _session_state != SessionState.READY and _session_state != SessionState.FINISHED:
		return false
	if session_duration_seconds < 1 or session_duration_seconds > 600:
		push_error("PrototypeSession requires a duration between 1 and 600 seconds.")
		_hud.set_status("Не удалось начать: проверьте настройки длительности")
		return false
	if not is_finite(record_reward_interval_seconds) or not (
		record_reward_interval_seconds >= 1.0 and record_reward_interval_seconds <= 120.0
	):
		push_error("PrototypeSession requires a record reward interval between 1 and 120 seconds.")
		_hud.set_status("Не удалось начать: проверьте настройки аудитории")
		return false
	var question_errors := Content.validate_questions(Content.get_questions())
	question_errors.append_array(Content.validate_reactions(Content.get_reactions()))
	if not _has_valid_message_settings() or not question_errors.is_empty():
		push_error("PrototypeSession requires valid question timing and content.")
		if not question_errors.is_empty():
			push_error(" ".join(question_errors))
		_hud.set_status("Не удалось начать: проверьте настройки вопросов")
		return false
	var content_errors := Content.validate()
	if not content_errors.is_empty():
		push_error("Invalid stream chat content: %s" % "; ".join(content_errors))
		_hud.set_status("Не удалось начать: проверьте настройки чата")
		return false
	var donation_errors := Content.validate_donations()
	if not _donations.has_valid_settings() or not donation_errors.is_empty():
		push_error("PrototypeSession requires valid donation timing and content. " + " ".join(donation_errors))
		_hud.set_status("Не удалось начать: проверьте настройки донатов")
		return false

	_results = null
	_stream_audio.stop_all()
	_total_food = 0
	_attempts_started = 0
	_collisions = 0
	_boards_completed = 0
	_last_attempt_score = 0
	_high_score = 0
	_hud.hide_session_results()
	_hud.set_total_food(0)
	_elapsed_before_run_msec = 0
	_run_started_msec = _now_msec()
	_duration_msec = session_duration_seconds * 1000
	_closing_started_msec = 0
	_snake_action_time_msec = 0
	_next_stream_event_id = 1
	_presented_milestones.clear()
	_next_food_feedback_msec = 0
	_chat_feed.reset(_run_started_msec)
	_webcam.reset()
	_director.reset()
	_reset_choices()
	_reset_audience()
	_reset_donations()
	_session_state = SessionState.RUNNING
	_snake_game.start()
	if not _snake_game.is_playing():
		_session_state = SessionState.READY
		_duration_msec = 0
		_run_started_msec = 0
		_hud.clear_question(false)
		_hud.set_score(0)
		_hud.set_remaining_time(0.0)
		_hud.show_ready()
		_hud.set_status(INVALID_SNAKE_SETTINGS)
		return false
	_attempts_started = 1
	_session_messages_enabled = messages_enabled
	_hud.set_messages_enabled(_session_messages_enabled)
	_director.start(_session_messages_enabled, roundi(question_window_seconds * 1000.0))
	_director.on_attempt_started(_attempts_started)
	_show_audience()
	_chat_feed.start(0)
	_donations.start()
	_webcam.set_playing(true)
	_hud.set_remaining_time(_duration_msec / 1000.0)
	return true


func _has_valid_message_settings() -> bool:
	return (
		_director.has_valid_settings()
		and is_finite(question_window_seconds) and question_window_seconds >= 1.0
		and question_window_seconds <= 15.0
	)


func _reset_choices() -> void:
	_session_messages_enabled = false
	_active_question_id = 0
	_questions_shown = 0
	_questions_answered = 0
	_questions_expired = 0
	_questions_cancelled = 0
	_answer_times_seconds.clear()
	_stream_choice.reset()
	_choice_counts.clear()
	_choice_resolutions.clear()
	_next_choice_id = 1
	_question_feedback_until_msec = 0
	_hud.set_messages_enabled(_session_messages_enabled)
	_hud.clear_question()
	_hud.set_message_feedback("")


func get_stream_time_msec() -> int:
	match _session_state:
		SessionState.RUNNING:
			return _running_elapsed_msec(_now_msec())
		SessionState.PAUSED, SessionState.CLOSING, SessionState.FINISHED:
			return _elapsed_before_run_msec
	return 0


func get_elapsed_seconds() -> float:
	return get_stream_time_msec() / 1000.0


func get_remaining_seconds() -> float:
	if _session_state != SessionState.RUNNING and _session_state != SessionState.PAUSED:
		return 0.0
	return (_duration_msec - get_stream_time_msec()) / 1000.0


func _now_msec() -> int:
	return Time.get_ticks_msec()


func _sample_running_time_msec() -> int:
	if _session_state != SessionState.RUNNING:
		return -1
	var now_msec := _now_msec()
	var elapsed := _running_elapsed_msec(now_msec)
	if elapsed >= _duration_msec:
		_finish_session(now_msec)
		return -1
	return elapsed


func _running_elapsed_msec(now_msec: int) -> int:
	return mini(_duration_msec, _elapsed_before_run_msec + maxi(0, now_msec - _run_started_msec))


func pause_session() -> bool:
	var elapsed := _sample_running_time_msec()
	if elapsed < 0:
		return false
	_advance_audience(elapsed)
	_expire_choice_presentation(elapsed)
	_elapsed_before_run_msec = elapsed
	_session_state = SessionState.PAUSED
	_stream_audio.stop_all()
	_snake_game.clear_pending_turn()
	_hud.set_remaining_time((_duration_msec - elapsed) / 1000.0)
	if _stream_choice.is_open():
		_hud.set_question_time(_stream_choice.get_remaining_seconds(elapsed))
	_hud.set_paused(true)
	return true


func resume_session() -> bool:
	if _session_state != SessionState.PAUSED:
		return false
	_run_started_msec = _now_msec()
	_snake_game.clear_pending_turn()
	_session_state = SessionState.RUNNING
	_hud.set_paused(false)
	return true


func _authorize_snake_action() -> bool:
	_snake_action_time_msec = _sample_running_time_msec()
	return _snake_action_time_msec >= 0


func _process(_delta: float) -> void:
	if _session_state == SessionState.CLOSING:
		if _now_msec() - _closing_started_msec >= CLOSING_DURATION_MSEC:
			_complete_closing()
		return
	var elapsed := _sample_running_time_msec()
	if elapsed < 0:
		return
	_advance_audience(elapsed)
	_hud.set_remaining_time((_duration_msec - elapsed) / 1000.0)
	_expire_choice_presentation(elapsed)
	var audience := get_audience_snapshot()
	_donations.tick(elapsed, audience.counts, audience.impressions)
	_director.tick(elapsed, _snake_game.is_playing())
	if _stream_choice.is_open():
		_hud.set_question_time(_stream_choice.get_remaining_seconds(elapsed))
	_chat_feed.tick(elapsed, _snake_game.is_playing())
	_hud.tick_donation_notifications(elapsed)


func _expire_choice_presentation(elapsed: int) -> void:
	_stream_choice.tick(elapsed)
	if _question_feedback_until_msec > 0 and elapsed >= _question_feedback_until_msec:
		_question_feedback_until_msec = 0
		_hud.set_message_feedback("")
	_webcam.tick(elapsed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"stream_mute"):
		get_viewport().set_input_as_handled()
		muted = not muted
		_stream_audio.set_muted(muted)
		_hud.set_muted(muted)
	elif event.is_action_pressed(&"session_restart"):
		get_viewport().set_input_as_handled()
		match _session_state:
			SessionState.READY, SessionState.FINISHED:
				start_session()
			SessionState.RUNNING:
				_sample_running_time_msec()
			SessionState.CLOSING:
				_complete_closing()
	elif event.is_action_pressed(&"session_pause"):
		get_viewport().set_input_as_handled()
		match _session_state:
			SessionState.RUNNING:
				pause_session()
			SessionState.PAUSED:
				resume_session()
	elif event.is_action_pressed(&"attempt_retry"):
		_try_retry_attempt()


func _try_retry_attempt() -> bool:
	if _sample_running_time_msec() < 0 or not _snake_game.is_waiting_for_retry():
		return false
	get_viewport().set_input_as_handled()
	var previous_score := _last_attempt_score
	_last_attempt_score = 0
	if not _snake_game.restart_attempt():
		_last_attempt_score = previous_score
		_hud.set_status(INVALID_SNAKE_SETTINGS)
		return false
	_attempts_started += 1
	_director.on_attempt_started(_attempts_started)
	_hud.set_status("")
	_webcam.set_playing(true)
	return true


func _finish_session(now_msec: int) -> void:
	if _session_state != SessionState.RUNNING:
		return
	_session_state = SessionState.CLOSING
	_donations.stop()
	_snake_game.stop()
	_director.stop()
	_hud.clear_donation_notifications()
	_elapsed_before_run_msec = _duration_msec
	_advance_audience(_duration_msec)
	_closing_started_msec = now_msec
	# Cancellation emits synchronously and must be counted before the summary.
	_stream_choice.cancel(_elapsed_before_run_msec)
	_results = build_results_snapshot()
	_chat_feed.stop()
	_webcam.show_goodbye("Спасибо за эфир! До встречи!")
	_hud.clear_question(false)
	_hud.set_message_feedback("")
	_hud.set_remaining_time(0.0)
	_hud.show_closing()
	_stream_audio.play_finish()


func _complete_closing() -> void:
	if _session_state != SessionState.CLOSING:
		return
	_session_state = SessionState.FINISHED
	_stream_audio.stop_all()
	_hud.show_stream_results(_results)


func build_results_snapshot() -> StreamResults:
	if _results != null:
		return _results
	if _session_state != SessionState.CLOSING:
		return null
	var result := StreamResults.new()
	result.audience = get_audience_snapshot()
	result.initial_viewers = Audience.INITIAL_TOTAL
	result.donation_count = _donations.get_count()
	result.donation_total = _donations.get_total()
	result.elapsed_seconds = get_elapsed_seconds()
	result.duration_seconds = _duration_msec / 1000.0
	result.total_food = _total_food
	result.best_score = _high_score
	result.attempts_started = _attempts_started
	result.collisions = _collisions
	result.boards_completed = _boards_completed
	result.messages_enabled = _session_messages_enabled
	result.questions_shown = _questions_shown
	result.questions_answered = _questions_answered
	result.questions_expired = _questions_expired
	result.questions_cancelled = _questions_cancelled
	result.answer_times_seconds = _answer_times_seconds.duplicate()
	result.reaction_counts = _choice_counts.get(&"reaction", Vector4i.ZERO)
	result.donation_question_counts = _choice_counts.get(&"donation_question", Vector4i.ZERO)
	result.choice_totals = (
		Vector4i(_questions_shown, _questions_answered, _questions_expired, _questions_cancelled)
		+ result.reaction_counts + result.donation_question_counts
	)
	for resolution in _choice_resolutions:
		if resolution.outcome != &"answered":
			continue
		var latency := resolution.elapsed_msec / 1000.0
		match resolution.kind:
			&"question":
				result.question_latency_seconds += latency
			&"donation_question":
				result.donation_question_latency_seconds += latency
			&"reaction":
				result.reaction_latency_seconds += latency
				var selected := StreamResults.SelectedReaction.new()
				selected.style = resolution.option.style_id
				selected.source_kind = resolution.source_event_kind
				selected.source_caption = _reaction_source_caption(resolution.source_event_kind)
				result.selected_reactions.append(selected)
	result.highlights = _select_highlights()
	return result


func _reaction_source_caption(kind: StringName) -> String:
	match kind:
		&"milestone": return "Новый рубеж"
		&"record": return "Новый рекорд"
		&"board_completed": return "Поле заполнено"
		&"collision": return "Попытка закончилась"
	return "Игровое событие"


func _select_highlights() -> Array[StreamResults.Highlight]:
	var best: Dictionary[StringName, AudienceCause] = {}
	var scores: Dictionary[StringName, float] = {}
	for cause in _audience_causes:
		var category: StringName
		match cause.kind:
			&"milestone", &"record", &"board_completed": category = &"achievement"
			&"question", &"donation_question": category = &"question"
			&"reaction": category = &"reaction"
			_: continue
		var positive := cause.delta.max(Vector3.ZERO)
		var score := positive.x + positive.y + positive.z
		# Causal history is in authorized time order, so strict comparison keeps the earlier tie.
		if score > scores.get(category, 0.0):
			best[category] = cause
			scores[category] = score
	var highlights: Array[StreamResults.Highlight] = []
	for cause in _audience_causes:
		for category in best:
			if best[category] != cause:
				continue
			var highlight := StreamResults.Highlight.new()
			highlight.category = category
			highlight.source_id = cause.source_id
			highlight.time_msec = cause.time_msec
			highlight.explanation = cause.explanation
			highlight.delta = cause.delta
			highlights.append(highlight)
	return highlights


func _on_score_changed(score: int) -> void:
	if _session_state != SessionState.RUNNING:
		return
	if score < _last_attempt_score:
		push_error("Attempt score decreased outside the session reset path.")
		return
	var gained := score - _last_attempt_score
	var is_record := score > _high_score and score >= 5
	_high_score = maxi(_high_score, score)
	_total_food += gained
	_last_attempt_score = score
	_hud.set_total_food(_total_food)
	_hud.set_score(score)
	# The full-board outcome owns feedback for the final food and score update.
	if gained == 0 or not _snake_game.is_playing():
		return
	var kind := Event.Kind.FOOD
	if score in MILESTONES and not _presented_milestones.has(score):
		_presented_milestones[score] = true
		kind = Event.Kind.MILESTONE
	elif is_record:
		kind = Event.Kind.RECORD
	_publish_stream_event(kind, score)


func _on_attempt_finished(reason: StringName, score: int) -> void:
	if _session_state != SessionState.RUNNING:
		return
	match reason:
		&"wall_collision":
			_collisions += 1
			_hud.set_status("Столкновение со стеной — пробел для новой попытки")
		&"self_collision":
			_collisions += 1
			_hud.set_status("Столкновение с собой — пробел для новой попытки")
		&"board_full":
			_boards_completed += 1
			_hud.set_status("Поле заполнено — пробел для новой попытки")
		_:
			return
	var kind := Event.Kind.BOARD_COMPLETED if reason == &"board_full" else Event.Kind.COLLISION
	_publish_stream_event(kind, score, reason)


func _publish_stream_event(kind: Event.Kind, score: int, reason: StringName = &"") -> void:
	var event := Event.new(_next_stream_event_id, kind, _snake_action_time_msec, score, reason, _attempts_started)
	_next_stream_event_id += 1
	_route_stream_event(event)


func _route_stream_event(event: Event) -> void:
	if not is_stream_active() or event.id <= _last_audience_event_id or event.time_msec >= _duration_msec:
		return
	if not _advance_audience(event.time_msec):
		return
	_last_audience_event_id = event.id
	_apply_game_audience_effect(event)
	_director.submit_event(event)
	# Keep the accepted step timestamp and never finish the session inside its callbacks.
	var now_msec := get_stream_time_msec()
	if now_msec >= _duration_msec:
		return
	match event.kind:
		Event.Kind.FOOD, Event.Kind.RECORD:
			if now_msec < _next_food_feedback_msec:
				return
			_next_food_feedback_msec = now_msec + FOOD_FEEDBACK_GAP_MSEC
			_present_feedback(&"food" if event.kind == Event.Kind.FOOD else &"achievement", &"happy", now_msec)
		Event.Kind.MILESTONE:
			_present_feedback(&"achievement", &"happy", now_msec)
		Event.Kind.BOARD_COMPLETED:
			_webcam.set_playing(false)
			_present_feedback(&"achievement", &"happy", now_msec)
		Event.Kind.COLLISION:
			_webcam.set_playing(false)
			_present_feedback(&"loss", &"sad", now_msec)


func _present_feedback(context: StringName, emotion: StringName, now_msec: int) -> void:
	_chat_feed.append_context(context, now_msec)
	_webcam.show_automatic(emotion, now_msec)


func _request_choice_open(definition: Content.ChoiceDefinition, now_msec: int) -> bool:
	if not is_stream_active():
		return false
	definition.id = _next_choice_id
	if definition.kind == &"question":
		definition.nick = Content.NICKNAMES[(_next_choice_id - 1) % Content.NICKNAMES.size()]
	if not _stream_choice.try_open(definition, now_msec):
		definition.id = 0
		return false
	_next_choice_id += 1
	return true


func _on_question_opened(definition: Content.ChoiceDefinition) -> void:
	if _session_state != SessionState.RUNNING or _active_question_id != 0:
		return
	_active_question_id = definition.id
	if definition.kind == &"question":
		_questions_shown += 1
	else:
		# Components are shown, answered, expired and cancelled, in summary order.
		var counts: Vector4i = _choice_counts.get(definition.kind, Vector4i.ZERO)
		counts.x += 1
		_choice_counts[definition.kind] = counts
	_question_feedback_until_msec = 0
	_hud.set_message_feedback("")
	_hud.show_question(definition)
	if definition.kind in [&"question", &"donation_question"]:
		_stream_audio.play_question()


func _on_question_resolved(id: int, _answer_index: int, outcome: StringName) -> void:
	if _session_state != SessionState.RUNNING:
		if _session_state != SessionState.CLOSING or outcome != &"cancelled":
			return
	if _active_question_id == 0 or id != _active_question_id:
		return
	var resolution := _stream_choice.get_last_resolution()
	if resolution == null or resolution.choice_id != id or resolution.outcome != outcome:
		return
	_active_question_id = 0
	_choice_resolutions.append(resolution)
	_director.on_choice_resolved(resolution)
	_count_choice_resolution(resolution)
	if is_stream_active():
		_apply_choice_audience_effect(resolution)
	_hud.clear_question()
	if outcome == &"cancelled":
		return
	# The accepted result is already recorded even if cosmetics reach stream cutoff.
	var now_msec := get_stream_time_msec()
	if now_msec >= _duration_msec:
		return
	if outcome == &"expired" and resolution.kind == &"reaction":
		return
	_question_feedback_until_msec = resolution.resolved_at_msec + QUESTION_FEEDBACK_MSEC
	if outcome == &"answered":
		_hud.set_message_feedback("Реакция выбрана" if resolution.kind == &"reaction" else "Ответ отправлен")
		_chat_feed.append_answer_response(resolution.option, now_msec)
		_webcam.show_reply(resolution.option.reply, resolution.option.emotion, now_msec)
	else:
		_hud.set_message_feedback("Время вышло")


func _count_choice_resolution(resolution: Content.ChoiceResolution) -> void:
	var outcome := resolution.outcome
	if resolution.kind != &"question":
		var counts: Vector4i = _choice_counts.get(resolution.kind, Vector4i.ZERO)
		match outcome:
			&"answered": counts.y += 1
			&"expired": counts.z += 1
			&"cancelled": counts.w += 1
		_choice_counts[resolution.kind] = counts
		return
	match outcome:
		&"answered":
			_questions_answered += 1
			_answer_times_seconds.append(resolution.elapsed_msec / 1000.0)
		&"expired":
			_questions_expired += 1
		&"cancelled":
			_questions_cancelled += 1


func get_audience_snapshot() -> Audience.Snapshot:
	return _audience.get_snapshot()


func _get_viewer_count() -> int:
	return get_audience_snapshot().total


func _reset_audience() -> void:
	_audience.reset()
	_next_audience_step_msec = 1000
	_audience_time_msec = 0
	_last_audience_event_id = 0
	_last_audience_choice_id = 0
	_next_audience_effect_id = 1
	_next_record_reward_msec = 0
	_record_reward_interval_msec = roundi(record_reward_interval_seconds * 1000.0)
	_rewarded_milestones.clear()
	_rewarded_completion = false
	_rewarded_loss_reactions = 0
	_audience_causes.clear()
	_hud.set_audience(null, "")


func _advance_audience(time_msec: int) -> bool:
	if time_msec < _audience_time_msec:
		push_error("Audience cannot apply a source with a past active timestamp.")
		return false
	_audience_time_msec = mini(time_msec, _duration_msec)
	var stepped := _next_audience_step_msec <= _audience_time_msec
	while _next_audience_step_msec <= _audience_time_msec:
		_audience.advance_second()
		_next_audience_step_msec += 1000
	if stepped:
		_show_audience()
	return true


func _apply_game_audience_effect(event: Event) -> void:
	var kind: StringName
	var reason: String
	var delta: Vector3
	match event.kind:
		Event.Kind.MILESTONE:
			if event.score not in MILESTONES or _rewarded_milestones.has(event.score):
				return
			_rewarded_milestones[event.score] = true
			kind = &"milestone"
			reason = "Игровой рубеж"
			delta = Vector3(8, 2, 2)
		Event.Kind.RECORD:
			if event.score < 5 or event.time_msec < _next_record_reward_msec:
				return
			kind = &"record"
			reason = "Новый рекорд"
			delta = Vector3(8, 2, 2)
		Event.Kind.BOARD_COMPLETED:
			if _rewarded_completion:
				return
			_rewarded_completion = true
			kind = &"board_completed"
			reason = "Поле заполнено"
			delta = Vector3(10, 3, 3)
		Event.Kind.COLLISION:
			_apply_audience_effect(&"collision", event.time_msec, "Столкновение", Vector3(-2, -1, -1), &"", event.id)
			return
		_:
			return
	_next_record_reward_msec = event.time_msec + _record_reward_interval_msec
	_apply_audience_effect(kind, event.time_msec, reason, delta, &"", event.id)


func _apply_choice_audience_effect(resolution: Content.ChoiceResolution) -> void:
	if resolution.choice_id <= _last_audience_choice_id:
		return
	if resolution.resolved_at_msec >= _duration_msec or not _advance_audience(resolution.resolved_at_msec):
		return
	_last_audience_choice_id = resolution.choice_id
	var group := resolution.source_group_index
	if resolution.kind == &"donation_question" and resolution.outcome == &"expired":
		if group in [0, 1, 2]:
			var penalty := Vector3.ZERO
			penalty[group] = -2
			_apply_audience_effect(
				resolution.kind, resolution.resolved_at_msec, "Вопрос остался без ответа",
				penalty, &"", resolution.choice_id
			)
		return
	if resolution.outcome != &"answered" or resolution.option == null or not resolution.option.is_valid():
		return
	var delta := resolution.option.effects
	var style: StringName = &""
	var reason := "Ответ зрителю"
	match resolution.kind:
		&"reaction":
			style = resolution.option.style_id
			if style not in [&"competitive", &"humor", &"flirt"]:
				return
			reason = "Реакция: %s" % resolution.option.label.to_lower()
			if resolution.source_event_kind == &"collision":
				if _rewarded_loss_reactions < 2:
					_rewarded_loss_reactions += 1
				else:
					delta = delta.min(Vector3.ZERO)
		&"donation_question":
			if group not in [0, 1, 2]:
				return
			delta *= 1.5
		&"question":
			pass
		_:
			return
	_apply_audience_effect(resolution.kind, resolution.resolved_at_msec, reason, delta, style, resolution.choice_id)


func _apply_audience_effect(
	kind: StringName, time_msec: int, reason: String, delta: Vector3, style: StringName, source_id: int
) -> void:
	var before := get_audience_snapshot()
	if not _audience.apply_effect(_next_audience_effect_id, delta, style):
		return
	_next_audience_effect_id += 1
	var after := get_audience_snapshot()
	var actual := Vector3.ZERO
	for group in range(3):
		actual[group] = after.precise_impressions[group] - before.precise_impressions[group]
	if actual == Vector3.ZERO:
		return
	var change := AudienceCause.new()
	change.kind = kind
	change.source_id = source_id
	change.time_msec = time_msec
	change.delta = actual
	change.explanation = reason
	if not style.is_empty() and after.style_uses.get(style, 0) > 1 and actual.max(Vector3.ZERO) != Vector3.ZERO:
		change.explanation += " (повтор действует слабее)"
	if _audience_causes.size() == AUDIENCE_CAUSE_LIMIT:
		_audience_causes.pop_front()
	_audience_causes.append(change)
	_show_audience()


func _show_audience() -> void:
	var explanation := ""
	if not _audience_causes.is_empty():
		var change := _audience_causes[-1]
		explanation = "%s\nИнтерес: игра %+.1f · чат %+.1f · образ %+.1f" % [
			change.explanation, change.delta.x, change.delta.y, change.delta.z,
		]
	_hud.set_audience(get_audience_snapshot(), explanation)


func _reset_donations() -> void:
	_last_routed_donation_id = 0
	_donations.reset(_run_started_msec ^ 0x444F4E41)
	_hud.clear_donation_notifications()
	_hud.set_donation_total(0)


func _on_donation_received(
	id: int, _group_index: int, _amount: int, _nick: String, _message: String, _has_question: bool
) -> void:
	if not is_stream_active() or id <= _last_routed_donation_id:
		return
	var record := _donations.get_last_donation()
	if record == null or record.id != id:
		return
	_last_routed_donation_id = id
	_chat_feed.append_donation(record, record.received_at_msec)
	_hud.set_donation_total(_donations.get_total())
	_hud.enqueue_donation(record)
	_stream_audio.play_donation()
	var question := Content.build_donation_question(record)
	if question != null:
		_director.submit_donation_question(question, record.received_at_msec)
