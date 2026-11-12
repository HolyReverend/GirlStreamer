class_name PrototypeHUD
extends Control

signal board_rect_changed(rect: Rect2)

var _messages_enabled := false
var _message_results_text := ""

@onready var _board_area: Control = $MarginContainer/VBoxContainer/PlayArea/BoardArea
@onready var _score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var _status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var _time_label: Label = $MarginContainer/VBoxContainer/TimeLabel
@onready var _session_food_label: Label = $MarginContainer/VBoxContainer/SessionFoodLabel
@onready var _results_panel: PanelContainer = $MarginContainer/VBoxContainer/ResultsPanel
@onready var _results_label: Label = $MarginContainer/VBoxContainer/ResultsPanel/ResultsLabel
@onready var _message_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/PlayArea/MessageArea/MarginContainer/MessageContent
)
@onready var _message_header: Label = _message_content.get_node("HeaderSlot/HeaderLabel")
@onready var _message_prompt: Label = _message_content.get_node("PromptSlot/PromptLabel")
@onready var _message_countdown: Label = _message_content.get_node("CountdownSlot/CountdownLabel")
@onready var _message_feedback: Label = _message_content.get_node("FeedbackSlot/FeedbackLabel")
@onready var _message_options: Array[Label] = [
	_message_content.get_node("Option1Slot/Option1Label") as Label,
	_message_content.get_node("Option2Slot/Option2Label") as Label,
	_message_content.get_node("Option3Slot/Option3Label") as Label,
]


func _ready() -> void:
	_board_area.resized.connect(_report_board_rect, CONNECT_DEFERRED)


func get_board_rect() -> Rect2:
	return _board_area.get_global_rect()


func set_score(score: int) -> void:
	_score_label.text = "Score: %d" % score


func set_status(message: String) -> void:
	_status_label.text = message
	_status_label.visible = not message.is_empty()


func set_remaining_time(seconds: float) -> void:
	_time_label.text = "Time: %s" % _format_time(seconds)


func set_total_food(total: int) -> void:
	_session_food_label.text = "Session food: %d" % total


func show_session_results(
	elapsed_seconds: float, total_food: int, attempts_started: int, collisions: int,
	boards_completed: int
) -> void:
	var session_totals := (
		"Elapsed: %s   |   Total food: %d   |   Attempts started: %d\n"
		+ "Collisions: %d   |   Boards completed: %d"
	) % [_format_time(elapsed_seconds), total_food, attempts_started, collisions, boards_completed]
	_results_label.text = "\n".join([session_totals, _message_results_text, "Enter — new session."])
	_results_panel.show()


func hide_session_results() -> void:
	_results_panel.hide()


func show_question(prompt: String, options: Array[String]) -> void:
	_message_header.text = "Вопрос"
	_message_prompt.text = prompt
	for index in range(_message_options.size()):
		_message_options[index].text = "%d — %s" % [index + 1, options[index]]


func set_question_time(seconds: float) -> void:
	var tenths := ceili(maxf(0.0, seconds) * 10.0)
	_message_countdown.text = "Время: %.1f с" % (tenths / 10.0)


func clear_question(show_idle_status: bool = true) -> void:
	if show_idle_status:
		_message_header.text = "Ожидание вопроса" if _messages_enabled else "Вопросы отключены"
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
	_message_header.text = "Ожидание вопроса" if enabled else "Вопросы отключены"


func set_message_results(
	enabled: bool, shown: int, answered: int, expired: int, cancelled: int,
	answer_times: Array[float]
) -> void:
	var rate := "N/A"
	var rate_count := answered + expired
	if rate_count > 0:
		rate = "%.0f%%" % (float(answered) / rate_count * 100.0)
	var mean := "N/A"
	if not answer_times.is_empty():
		var total_seconds := 0.0
		for seconds in answer_times:
			total_seconds += seconds
		mean = "%.2f s" % (total_seconds / answer_times.size())
	_message_results_text = (
		"Messages: %s   |   Shown: %d   |   Answered: %d   |   Expired: %d   |   Cancelled: %d\n"
		+ "Answer rate: %s   |   Mean response time: %s"
	) % ["on" if enabled else "off", shown, answered, expired, cancelled, rate, mean]


func _format_time(seconds: float) -> String:
	var whole_seconds := ceili(maxf(0.0, seconds))
	return "%02d:%02d" % [floori(whole_seconds / 60.0), whole_seconds % 60]


func _report_board_rect() -> void:
	board_rect_changed.emit(get_board_rect())
