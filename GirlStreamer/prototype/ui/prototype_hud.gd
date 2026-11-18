class_name PrototypeHUD
extends Control

signal board_rect_changed(rect: Rect2)

const WebcamView = preload("res://prototype/ui/hero_webcam.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const Audience = preload("res://prototype/stream/audience_state.gd")
const StreamResults = preload("res://prototype/stream/stream_results.gd")
const ResultText = preload("res://prototype/stream/stream_result_text.gd")
const DONATION_NOTIFICATION_MSEC := 3000
const DONATION_PENDING_LIMIT := 3
const CHOICE_OPTION_TWO_LINE_HEIGHT := 40
const CHOICE_OPTION_ONE_LINE_HEIGHT := 20

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
@onready var _board_area: Control = $MarginContainer/VBoxContainer/MainArea/LeftColumn/BoardArea
@onready var _webcam: WebcamView = (
	$MarginContainer/VBoxContainer/MainArea/SideColumn/WebcamSlot/HeroWebcam
)
@onready var _chat_history: RichTextLabel = (
	$MarginContainer/VBoxContainer/MainArea/SideColumn/ChatSlot/ChatContent/ChatHistory
)
@onready var _statistics_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/SideColumn/StatisticsPanel/StatisticsContent
)
@onready var _donation_strip: VBoxContainer = _statistics_content.get_node("DonationStrip")
@onready var _donation_total: Label = _donation_strip.get_node("Total")
@onready var _donation_notification: Label = _donation_strip.get_node("NotificationSlot/Notification")
@onready var _audience_strip: VBoxContainer = _statistics_content.get_node("AudienceStrip")
@onready var _audience_totals: Label = _audience_strip.get_node("Totals")
@onready var _opening_audience: Label = _audience_strip.get_node("Opening")
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
@onready var _choice_area: Control = $MarginContainer/VBoxContainer/MainArea/LeftColumn/ChoiceArea
@onready var _results_instructions: Label = $MarginContainer/VBoxContainer/ResultsInstructions
@onready var _instructions: Label = $MarginContainer/VBoxContainer/MainArea/LeftColumn/Instructions
@onready var _results_panel: PanelContainer = $MarginContainer/VBoxContainer/ResultsPanel
@onready var _mute_label: Label = $MarginContainer/VBoxContainer/Header/Stats/MuteLabel
@onready var _results_scroll: ScrollContainer = _results_panel.get_node("ResultsScroll")
@onready var _results_label: Label = _results_scroll.get_node("ResultsLabel")
@onready var _message_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/LeftColumn/ChoiceArea/MessageContent
)
@onready var _message_header: Label = _message_content.get_node("Heading/HeaderLabel")
@onready var _message_prompt: Label = _message_content.get_node("PromptLabel")
@onready var _message_countdown: Label = _message_content.get_node("Heading/CountdownLabel")
@onready var _message_feedback: Label = _message_content.get_node("FeedbackLabel")
@onready var _message_option_grid: GridContainer = _message_content.get_node("Options")
@onready var _message_options: Array[Label] = [
	_message_content.get_node("Options/Option1Label") as Label,
	_message_content.get_node("Options/Option2Label") as Label,
	_message_content.get_node("Options/Option3Label") as Label,
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


func set_opening_audience(initial_viewers: int, announcement_gain: int) -> void:
	_opening_audience.visible = announcement_gain > 0
	_opening_audience.text = "На старте: %d · От анонса: +%d" % [
		initial_viewers, announcement_gain,
	] if announcement_gain > 0 else ""


func set_audience(snapshot: Audience.Snapshot, explanation: String) -> void:
	if snapshot == null:
		_audience_totals.text = ""
		_audience_explanation.text = ""
		for label in _audience_groups:
			label.text = ""
		return
	_audience_totals.text = "Зрители: %d   |   Пик: %d" % [snapshot.total, snapshot.peak]
	for index in range(_audience_groups.size()):
		_audience_groups[index].text = "%s: %d · %s" % [
			ResultText.AUDIENCE_GROUP_NAMES[index], snapshot.counts[index],
			ResultText.impression_description(snapshot.precise_impressions[index]),
		]
	_audience_explanation.text = explanation


func set_score(score: int) -> void:
	_score_label.text = "Счёт: %d" % score


func set_status(message: String) -> void:
	_status = message
	_update_status()


func show_ready() -> void:
	_paused = false
	_results_panel.hide()
	_results_instructions.hide()
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
	_time_label.text = "Время: %s" % ResultText.format_time(seconds)


func set_total_food(total: int) -> void:
	_session_food_label.text = "Еда за эфир: %d" % total


func show_stream_results(results: StreamResults, can_restart: bool = true) -> void:
	_results_label.text = ResultText.format_results(results)
	_paused = false
	set_status("Итоги эфира")
	_results_instructions.visible = can_restart
	_main_area.hide()
	_choice_area.hide()
	_results_panel.show()
	_results_scroll.scroll_vertical = 0


func hide_session_results() -> void:
	_paused = false
	_results_panel.hide()
	_results_instructions.hide()
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
	var has_hint := false
	for option in definition.options:
		if not option.hint.strip_edges().is_empty():
			has_hint = true
			break
	# Give a hinted reply the full width for its label and explanation.
	_message_option_grid.columns = 1 if has_hint else 2
	for index in range(_message_options.size()):
		var option := definition.options[index]
		var label := _message_options[index]
		var hint := option.hint.strip_edges()
		label.text = "%d — %s" % [index + 1, option.label]
		label.custom_minimum_size.y = CHOICE_OPTION_TWO_LINE_HEIGHT
		if not hint.is_empty():
			label.text += "\n%s" % hint
		elif has_hint:
			label.custom_minimum_size.y = CHOICE_OPTION_ONE_LINE_HEIGHT


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
	_message_option_grid.columns = 2
	for option in _message_options:
		option.text = ""
		option.custom_minimum_size.y = CHOICE_OPTION_TWO_LINE_HEIGHT


func set_message_feedback(text: String) -> void:
	_message_feedback.text = text


func set_messages_enabled(enabled: bool) -> void:
	_messages_enabled = enabled
	_clear_idle_heading()


func _clear_idle_heading() -> void:
	_message_header.text = "Ожидание обращения" if _messages_enabled else "Интерактивные обращения отключены"


func _report_board_rect() -> void:
	board_rect_changed.emit(get_board_rect())
