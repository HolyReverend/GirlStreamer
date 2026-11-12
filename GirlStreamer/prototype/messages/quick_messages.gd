class_name QuickMessages
extends Node

signal question_opened(id: int, prompt: String, options: Array[String])
signal question_resolved(id: int, answer_index: int, elapsed_seconds: float, outcome: StringName)

enum ChoiceState { IDLE, OPEN }

const FEEDBACK_MSEC := 1000
const ANSWER_ACTIONS: Array[StringName] = [
	&"message_answer_1", &"message_answer_2", &"message_answer_3",
]


class Question extends RefCounted:
	var prompt: String
	var options: Array[String]

	func _init(question_prompt: String, question_options: Array[String]) -> void:
		prompt = question_prompt
		options = question_options


var _questions: Array[Question] = [
	Question.new("Какой цвет выберешь?", ["Красный", "Зелёный", "Синий"]),
	Question.new("Какой напиток выберешь?", ["Чай", "Кофе", "Вода"]),
	Question.new("Какую погоду выберешь?", ["Солнце", "Дождь", "Снег"]),
]
var _state: ChoiceState = ChoiceState.IDLE
var _enabled := false
var _time_sampler: Callable
var _current_id := 0
var _next_id := 1
var _content_cursor := 0
var _current_question: Question
var _opened_at_msec := 0
var _answer_deadline_msec := 0
var _next_due_msec := 0
var _gap_msec := 0
var _window_msec := 0
var _feedback_text := ""
var _feedback_until_msec := 0


func set_time_sampler(sampler: Callable) -> void:
	_time_sampler = sampler


func has_valid_content() -> bool:
	if _questions.is_empty():
		return false
	for question in _questions:
		if question.prompt.strip_edges().is_empty() or question.options.size() != ANSWER_ACTIONS.size():
			return false
		for option in question.options:
			if option.strip_edges().is_empty():
				return false
	return true


func reset_for_session(enabled: bool, first_delay: float, gap: float, window: float) -> void:
	_enabled = enabled
	_state = ChoiceState.IDLE
	_current_id = 0
	_next_id = 1
	_content_cursor = 0
	_current_question = null
	_opened_at_msec = 0
	_answer_deadline_msec = 0
	_next_due_msec = roundi(first_delay * 1000.0)
	_gap_msec = roundi(gap * 1000.0)
	_window_msec = roundi(window * 1000.0)
	_clear_feedback()


func tick(now_msec: int, can_open: bool) -> void:
	if not _enabled:
		return
	if now_msec >= _feedback_until_msec:
		_clear_feedback()
	if is_open():
		if now_msec >= _answer_deadline_msec:
			_resolve(&"expired", -1, now_msec)
		return
	if can_open and now_msec >= _next_due_msec:
		_open_question(now_msec)


func stop_for_session_end(now_msec: int) -> void:
	_enabled = false
	if is_open():
		_resolve(&"cancelled", -1, now_msec)
	else:
		_clear_feedback()


func is_open() -> bool:
	return _state == ChoiceState.OPEN


func get_remaining_seconds(now_msec: int) -> float:
	if not is_open():
		return 0.0
	return maxi(0, _answer_deadline_msec - now_msec) / 1000.0


func get_feedback_text() -> String:
	return _feedback_text


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or not is_open() or not event.is_pressed() or event.is_echo():
		return
	for index in range(ANSWER_ACTIONS.size()):
		if not event.is_action_pressed(ANSWER_ACTIONS[index]):
			continue
		if not _time_sampler.is_valid():
			push_error("QuickMessages requires an authorized time sampler.")
			return
		var now_msec: int = _time_sampler.call()
		# Sampling can synchronously cancel the choice at the session deadline.
		if now_msec < 0:
			return
		get_viewport().set_input_as_handled()
		if now_msec >= _answer_deadline_msec:
			_resolve(&"expired", -1, now_msec)
		else:
			_resolve(&"answered", index, now_msec)
		return


func _open_question(now_msec: int) -> void:
	_current_question = _questions[_content_cursor]
	_content_cursor = (_content_cursor + 1) % _questions.size()
	_current_id = _next_id
	_next_id += 1
	_opened_at_msec = now_msec
	_answer_deadline_msec = now_msec + _window_msec
	_state = ChoiceState.OPEN
	_clear_feedback()
	question_opened.emit(_current_id, _current_question.prompt, _current_question.options.duplicate())


func _resolve(outcome: StringName, answer_index: int, now_msec: int) -> void:
	var id := _current_id
	var latency := clampi(now_msec - _opened_at_msec, 0, _window_msec) / 1000.0
	var question := _current_question
	_state = ChoiceState.IDLE
	_current_id = 0
	_current_question = null
	_opened_at_msec = 0
	_answer_deadline_msec = 0
	if outcome == &"cancelled":
		_next_due_msec = 0
		_clear_feedback()
	else:
		_next_due_msec = now_msec + _gap_msec
		_feedback_until_msec = now_msec + FEEDBACK_MSEC
		if outcome == &"answered":
			_feedback_text = "Выбрано: %s" % question.options[answer_index]
		else:
			_feedback_text = "Время вышло"
	question_resolved.emit(id, answer_index, latency, outcome)


func _clear_feedback() -> void:
	_feedback_text = ""
	_feedback_until_msec = 0
