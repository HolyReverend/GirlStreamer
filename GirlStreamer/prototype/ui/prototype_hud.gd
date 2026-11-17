class_name PrototypeHUD
extends Control

signal board_rect_changed(rect: Rect2)

const WebcamView = preload("res://prototype/ui/hero_webcam.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const Audience = preload("res://prototype/stream/audience_state.gd")
const StreamResults = preload("res://prototype/stream/stream_results.gd")
const REACTION_STYLE_LABELS := {
	&"competitive": "Азартно",
	&"humor": "С юмором",
	&"flirt": "Кокетливо",
}
const AUDIENCE_GROUP_NAMES := ["Геймеры", "Любители общения", "Поклонники образа"]
const DONATION_NOTIFICATION_MSEC := 3000
const DONATION_PENDING_LIMIT := 3

const RUNNING_INSTRUCTIONS := (
	"Стрелки / WASD — движение. 1–3 — ответ.\nПробел — новая попытка. Esc — пауза."
)

var _status := ""
var _paused := false
var _messages_enabled := false
var _donation_pending: Array[Content.DonationRecord] = []
var _donation_deadline_msec := 0
var _donation_overflow_count := 0
var _donation_overflow_amount := 0

@onready var _main_area: Control = $MarginContainer/VBoxContainer/MainArea
@onready var _board_area: Control = $MarginContainer/VBoxContainer/MainArea/BoardArea
@onready var _webcam: WebcamView = (
	$MarginContainer/VBoxContainer/MainArea/SideColumn/WebcamSlot/HeroWebcam
)
@onready var _chat_history: RichTextLabel = (
	$MarginContainer/VBoxContainer/MainArea/SideColumn/ChatSlot/ChatContent/ChatHistory
)
@onready var _donation_strip: VBoxContainer = _chat_history.get_parent().get_node("DonationStrip")
@onready var _donation_total: Label = _donation_strip.get_node("Total")
@onready var _donation_notification: Label = _donation_strip.get_node("NotificationSlot/Notification")
@onready var _audience_strip: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/SideColumn/ChatSlot/ChatContent/AudienceStrip
)
@onready var _audience_totals: Label = _audience_strip.get_node("Totals")
@onready var _audience_explanation: Label = _audience_strip.get_node("Explanation")
@onready var _audience_groups: Array[Label] = [
	_audience_strip.get_node("Gamers") as Label,
	_audience_strip.get_node("Social") as Label,
	_audience_strip.get_node("Image") as Label,
]
@onready var _score_label: Label = $MarginContainer/VBoxContainer/Header/Stats/ScoreLabel
@onready var _status_label: Label = $MarginContainer/VBoxContainer/Header/StatusLabel
@onready var _time_label: Label = $MarginContainer/VBoxContainer/Header/Stats/TimeLabel
@onready var _session_food_label: Label = $MarginContainer/VBoxContainer/Header/Stats/SessionFoodLabel
@onready var _choice_area: Control = $MarginContainer/VBoxContainer/ChoiceArea
@onready var _instructions: Label = $MarginContainer/VBoxContainer/Instructions
@onready var _results_panel: PanelContainer = $MarginContainer/VBoxContainer/ResultsPanel
@onready var _mute_label: Label = $MarginContainer/VBoxContainer/Header/Stats/MuteLabel
@onready var _results_scroll: ScrollContainer = _results_panel.get_node("ResultsScroll")
@onready var _results_label: Label = _results_scroll.get_node("ResultsLabel")
@onready var _message_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/ChoiceArea/MessageContent
)
@onready var _message_header: Label = _message_content.get_node("HeaderLabel")
@onready var _message_prompt: Label = _message_content.get_node("PromptLabel")
@onready var _message_countdown: Label = _message_content.get_node("CountdownLabel")
@onready var _message_feedback: Label = _message_content.get_node("FeedbackLabel")
@onready var _message_options: Array[Label] = [
	_message_content.get_node("Option1Label") as Label,
	_message_content.get_node("Option2Label") as Label,
	_message_content.get_node("Option3Label") as Label,
]


func _ready() -> void:
	_board_area.resized.connect(_report_board_rect, CONNECT_DEFERRED)


func get_board_rect() -> Rect2:
	return _board_area.get_global_rect()


func get_webcam() -> WebcamView:
	return _webcam


func set_chat_lines(lines: Array[Content.ChatLine]) -> void:
	var rows := PackedStringArray()
	for line in lines:
		rows.append("%s: %s" % [line.nick, line.text])
	_chat_history.text = "\n".join(rows)
	_chat_history.scroll_to_line(maxi(0, _chat_history.get_line_count() - 1))


func set_donation_total(total: int) -> void:
	_donation_total.text = "Донаты: %d" % total


func enqueue_donation(record: Content.DonationRecord) -> void:
	if _donation_deadline_msec == 0 and _donation_pending.is_empty() and _donation_overflow_count == 0:
		_show_donation(record, record.received_at_msec)
	elif _donation_overflow_count == 0 and _donation_pending.size() < DONATION_PENDING_LIMIT:
		_donation_pending.append(record)
	else:
		# Keep an existing summary behind the records that were queued first.
		_donation_overflow_count += 1
		_donation_overflow_amount += record.amount


func tick_donation_notifications(now_msec: int) -> void:
	if _donation_deadline_msec == 0 or now_msec < _donation_deadline_msec:
		return
	if not _donation_pending.is_empty():
		_show_donation(_donation_pending.pop_front(), now_msec)
	elif _donation_overflow_count > 0:
		_donation_notification.text = "Ещё %d донатов — %d монет" % [
			_donation_overflow_count, _donation_overflow_amount,
		]
		_donation_deadline_msec = now_msec + DONATION_NOTIFICATION_MSEC
		_donation_overflow_count = 0
		_donation_overflow_amount = 0
	else:
		_donation_deadline_msec = 0
		_donation_notification.text = ""


func clear_donation_notifications() -> void:
	_donation_pending.clear()
	_donation_deadline_msec = 0
	_donation_overflow_count = 0
	_donation_overflow_amount = 0
	_donation_notification.text = ""


func _show_donation(record: Content.DonationRecord, now_msec: int) -> void:
	var message := record.message if not record.message.is_empty() else "Поддержка эфира"
	_donation_notification.text = "%d монет · %s\n%s" % [record.amount, record.nick, message]
	_donation_deadline_msec = now_msec + DONATION_NOTIFICATION_MSEC


func set_audience(snapshot: Audience.Snapshot, explanation: String) -> void:
	_audience_strip.visible = snapshot != null
	if snapshot == null:
		_audience_totals.text = ""
		_audience_explanation.text = ""
		for label in _audience_groups:
			label.text = ""
		return
	_audience_totals.text = "Зрители: %d   |   Пик: %d" % [snapshot.total, snapshot.peak]
	for index in range(_audience_groups.size()):
		_audience_groups[index].text = "%s: %d · %s" % [
			AUDIENCE_GROUP_NAMES[index], snapshot.counts[index],
			_impression_description(snapshot.precise_impressions[index]),
		]
	_audience_explanation.text = explanation


func _impression_description(impression: float) -> String:
	if impression < 40.0:
		return "интерес снижается"
	if impression > 60.0:
		return "увлечены"
	return "спокойный интерес"


func set_score(score: int) -> void:
	_score_label.text = "Счёт: %d" % score


func set_status(message: String) -> void:
	_status = message
	_update_status()


func show_ready() -> void:
	_paused = false
	_results_panel.hide()
	_main_area.show()
	_choice_area.show()
	set_status("Готова к эфиру")
	_instructions.text = "Enter — начать стрим"


func set_paused(paused: bool) -> void:
	_paused = paused
	_update_status()


func set_muted(muted: bool) -> void:
	_mute_label.text = "M — звук: выкл." if muted else "M — звук: вкл."


func show_closing() -> void:
	_paused = false
	set_status("Эфир завершён")
	_instructions.text = "Enter — перейти к итогам"


func _update_status() -> void:
	_status_label.text = "Пауза — Esc, чтобы продолжить" if _paused else _status


func set_remaining_time(seconds: float) -> void:
	_time_label.text = "Время: %s" % _format_time(seconds)


func set_total_food(total: int) -> void:
	_session_food_label.text = "Еда за эфир: %d" % total


func show_stream_results(results: StreamResults) -> void:
	var rows := PackedStringArray([
		"Игра",
		"Длительность: %s из %s   |   Лучший счёт: %d" % [
			_format_time(results.elapsed_seconds), _format_time(results.duration_seconds),
			results.best_score,
		],
		"Собрано еды: %d   |   Начато попыток: %d   |   Столкновения: %d   |   Заполнено полей: %d" % [
			results.total_food, results.attempts_started, results.collisions, results.boards_completed,
		],
		"", "Аудитория",
	])
	if results.audience != null:
		_append_audience_results(rows, results)
	else:
		rows.append("нет данных")
	rows.append_array(PackedStringArray([
		"", "Донаты",
		"Донаты: %d   |   Получено монет: %d" % [results.donation_count, results.donation_total],
		"", "Общение",
	]))
	_append_communication_results(rows, results)
	rows.append_array(PackedStringArray(["", "Моменты эфира", "Моменты, понравившиеся зрителям"]))
	if results.highlights.is_empty():
		rows.append("нет данных")
	for highlight in results.highlights:
		var changes := PackedStringArray()
		for index in range(AUDIENCE_GROUP_NAMES.size()):
			if not is_zero_approx(highlight.delta[index]):
				changes.append("%s: %+.1f" % [AUDIENCE_GROUP_NAMES[index], highlight.delta[index]])
		rows.append("%s · %s" % [
			_format_time(highlight.time_msec / 1000.0), highlight.explanation,
		])
		if not changes.is_empty():
			rows.append("Впечатление: %s" % " · ".join(changes))
	_results_label.text = "\n".join(rows)
	_paused = false
	set_status("Итоги эфира")
	_instructions.text = "Enter — новый стрим"
	_main_area.hide()
	_choice_area.hide()
	_results_panel.show()
	_results_scroll.scroll_vertical = 0


func _append_audience_results(rows: PackedStringArray, results: StreamResults) -> void:
	var snapshot := results.audience
	rows.append("Зрители: в начале %d   |   В конце %d   |   Пик %d" % [
		results.initial_viewers, snapshot.total, snapshot.peak,
	])
	for index in range(AUDIENCE_GROUP_NAMES.size()):
		var impression := snapshot.precise_impressions[index]
		rows.append("%s: %d · %s (%.1f)" % [
			AUDIENCE_GROUP_NAMES[index], snapshot.counts[index],
			_impression_description(impression), impression,
		])
	rows.append("Часть зрителей могла прийти или уйти со временем.")


func _append_communication_results(rows: PackedStringArray, results: StreamResults) -> void:
	var donors := results.donation_question_counts
	var answered := results.questions_answered + donors.y
	var resolved := answered + results.questions_expired + donors.z
	var latency := results.question_latency_seconds + results.donation_question_latency_seconds
	var rate := "%.0f%%" % (float(answered) / resolved * 100.0) if resolved > 0 else "нет данных"
	var mean := "%.2f с" % (latency / answered) if answered > 0 else "нет данных"
	rows.append("Вопросы: %s" % ("включены" if results.messages_enabled else "отключены"))
	rows.append("Доля ответов: %s   |   Среднее время ответа: %s" % [rate, mean])
	_append_choice_counts(rows, "Обычные вопросы", Vector4i(
		results.questions_shown, results.questions_answered,
		results.questions_expired, results.questions_cancelled,
	))
	_append_choice_counts(rows, "Вопросы с донатом", donors)
	_append_choice_counts(rows, "Реакции", results.reaction_counts, "Выбрано")
	_append_choice_counts(rows, "Все обращения", results.choice_totals)
	rows.append("Выбранные реакции")
	if results.selected_reactions.is_empty():
		rows.append("нет данных")
	for reaction in results.selected_reactions:
		var style: String = REACTION_STYLE_LABELS.get(reaction.style, String(reaction.style))
		var source := reaction.source_caption
		if source.is_empty():
			source = "Событие в игре"
		rows.append("• %s — %s" % [style, source])


func _append_choice_counts(
	rows: PackedStringArray, title: String, counts: Vector4i, answer_label: String = "Ответов"
) -> void:
	rows.append("%s: %d   |   %s: %d   |   Истекло: %d   |   Отменено: %d" % [
		title, counts.x, answer_label, counts.y, counts.z, counts.w,
	])


func hide_session_results() -> void:
	_paused = false
	_results_panel.hide()
	_main_area.show()
	_choice_area.show()
	set_status("")
	_instructions.text = RUNNING_INSTRUCTIONS


func show_question(definition: Content.ChoiceDefinition) -> void:
	match definition.kind:
		&"reaction":
			_message_header.text = "Как отреагировать?"
		&"donation_question":
			_message_header.text = "Донат %d монет · %s спрашивает" % [
				definition.donation_amount, definition.nick,
			]
		_:
			_message_header.text = "%s спрашивает" % definition.nick
	_message_prompt.text = definition.prompt
	for index in range(_message_options.size()):
		_message_options[index].text = "%d — %s" % [index + 1, definition.options[index].label]


func set_question_time(seconds: float) -> void:
	var tenths := ceili(maxf(0.0, seconds) * 10.0)
	_message_countdown.text = "Время: %.1f с" % (tenths / 10.0)


func clear_question(show_idle_status: bool = true) -> void:
	if show_idle_status:
		_clear_idle_heading()
	else:
		_message_header.text = ""
	_message_prompt.text = ""
	_message_countdown.text = ""
	for option in _message_options:
		option.text = ""


func set_message_feedback(text: String) -> void:
	_message_feedback.text = text


func set_messages_enabled(enabled: bool) -> void:
	_messages_enabled = enabled
	_clear_idle_heading()


func _clear_idle_heading() -> void:
	_message_header.text = "Ожидание обращения" if _messages_enabled else "Интерактивные обращения отключены"


func _format_time(seconds: float) -> String:
	var whole_seconds := ceili(maxf(0.0, seconds))
	return "%02d:%02d" % [floori(whole_seconds / 60.0), whole_seconds % 60]


func _report_board_rect() -> void:
	board_rect_changed.emit(get_board_rect())
