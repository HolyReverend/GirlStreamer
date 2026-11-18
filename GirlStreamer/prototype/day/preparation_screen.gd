extends Control
## Renders authoritative day snapshots and forwards deliberate button presses.

const DayModel := preload("res://prototype/day/day_state.gd")
const StreamForecast := preload("res://prototype/day/stream_forecast.gd")

signal activity_requested(id: StringName)
signal stream_requested()
signal skip_requested()

const ACTIVITY_IDS: Array[StringName] = [
	&"publish_post", &"prepare_topic", &"train_snake", &"watch_anime", &"take_nap",
]

const ACTIVITY_FEEDBACK: Dictionary[StringName, String] = {
	&"publish_post": "Анонс опубликован. Теперь зрители знают, когда эфир.",
	&"prepare_topic": "Про рекорд точно спросят. Я готова!",
	&"train_snake": "Ещё одна тренировка за плечами.",
	&"watch_anime": "Посмотрела серию. Можно снова сосредоточиться.",
	&"take_nap": "Немного поспала. Пора готовиться к эфиру.",
}

@onready var _activity_buttons: Array[Button] = [
	%PublishPost, %PrepareTopic, %TrainSnake, %WatchAnime, %TakeNap,
]
@onready var _activity_details: Array[Label] = [
	%PublishPostDetails, %PrepareTopicDetails, %TrainSnakeDetails,
	%WatchAnimeDetails, %TakeNapDetails,
]
@onready var _start_button: Button = %StartStream
@onready var _skip_button: Button = %SkipStream
@onready var _feedback: Label = %Feedback

var _actions: Array[Button] = []
var _busy := false
var _preparing := true
var _initial_focus := true
var _previews: Dictionary[StringName, DayModel.ActivityResult] = {}


func _ready() -> void:
	_actions.assign(_activity_buttons)
	_actions.append(_start_button)
	_actions.append(_skip_button)
	for index in ACTIVITY_IDS.size():
		_activity_buttons[index].pressed.connect(activity_requested.emit.bind(ACTIVITY_IDS[index]))
	_start_button.pressed.connect(stream_requested.emit)
	_skip_button.pressed.connect(skip_requested.emit)


func render(
	day: DayModel.DaySnapshot, previews: Dictionary[StringName, DayModel.ActivityResult]
) -> void:
	var previous := get_viewport().gui_get_focus_owner()
	_preparing = day.phase == DayModel.Phase.PREPARING
	_previews = previews
	%DayHeading.text = "День %d" % day.day_number
	%Coins.text = "Монеты: %d" % day.coins
	%ActionPoints.text = "ОД: %d из %d" % [day.ap, DayModel.MORNING_AP]
	var mastery := "уровень %d" % day.mastery_level if day.mastery_level > 0 else (
		"%d из %d" % [day.mastery_progress, DayModel.MASTERY_THRESHOLD]
	)
	%Condition.text = "Бодрость: %d/%d\nКонцентрация: %d/%d\nМастерство аркад: %s" % [
		day.vigor, DayModel.CONDITION_MAX, day.concentration, DayModel.CONDITION_MAX, mastery,
	]
	%Forecast.text = _forecast_text(day)
	for index in ACTIVITY_IDS.size():
		_activity_details[index].text = _activity_text(day, previews[ACTIVITY_IDS[index]])
	var available := _refresh_buttons()
	if available.is_empty():
		return
	if _initial_focus:
		_initial_focus = false
		available.front().grab_focus()
	elif previous in _actions and previous not in available:
		_focus_after(_actions.find(previous))


func set_busy(busy: bool) -> void:
	_busy = busy
	_refresh_buttons()
	if _busy:
		var focused := get_viewport().gui_get_focus_owner()
		if focused in _actions:
			focused.release_focus()
	elif _preparing and is_visible_in_tree():
		_start_button.grab_focus()


func show_activity_result(result: DayModel.ActivityResult) -> void:
	if result.available:
		_feedback.text = ACTIVITY_FEEDBACK[result.activity_id]
	else:
		_feedback.text = _rejection_text(result)


func show_launch_error() -> void:
	_feedback.text = "Не удалось начать стрим. Попробовать ещё раз"


func reset_for_morning() -> void:
	_busy = false
	_initial_focus = true
	_feedback.text = ""


func _refresh_buttons() -> Array[Button]:
	var available: Array[Button] = []
	for index in ACTIVITY_IDS.size():
		var button := _activity_buttons[index]
		var preview := _previews.get(ACTIVITY_IDS[index]) as DayModel.ActivityResult
		button.disabled = _busy or not _preparing or preview == null or not preview.available
		if not button.disabled:
			available.append(button)
	_start_button.disabled = _busy or not _preparing
	_skip_button.disabled = _start_button.disabled
	if not _start_button.disabled:
		available.append(_start_button)
		available.append(_skip_button)
	for index in available.size():
		var button := available[index]
		button.focus_previous = button.get_path_to(available[posmod(index - 1, available.size())])
		button.focus_next = button.get_path_to(available[(index + 1) % available.size()])
	return available


func _focus_after(action_index: int) -> void:
	for index in range(action_index + 1, _actions.size()):
		if not _actions[index].disabled:
			_actions[index].grab_focus()
			return
	_start_button.grab_focus()


func _activity_text(day: DayModel.DaySnapshot, result: DayModel.ActivityResult) -> String:
	var cost := "%d ОД" % result.ap_cost
	if not result.available:
		return "%s · %s" % [cost, _rejection_text(result)]

	var next := result.resulting_snapshot
	match result.activity_id:
		&"publish_post":
			return "%s · +%d зрителя на старте эфира" % [cost, StreamForecast.ANNOUNCEMENT_VIEWERS]
		&"prepare_topic":
			return "%s · Концентрация %+d\n«%s»\n%s" % [
				cost, next.concentration - day.concentration,
				StreamForecast.TOPIC_TITLE, StreamForecast.TOPIC_QUESTION,
			]
		&"train_snake":
			var effects := "%s · Бодрость %+d · Концентрация %+d\nМастерство %+d" % [
				cost, next.vigor - day.vigor, next.concentration - day.concentration,
				next.mastery_progress - day.mastery_progress,
			]
			if next.mastery_level > day.mastery_level:
				effects += " · Откроется контур опасности"
			return effects
		&"watch_anime":
			return "%s · Концентрация %+d" % [cost, next.concentration - day.concentration]
		&"take_nap":
			return "%s · Бодрость %+d" % [cost, next.vigor - day.vigor]
	return cost


func _rejection_text(result: DayModel.ActivityResult) -> String:
	match result.rejection_reason:
		DayModel.RejectionReason.PREPARATION_CLOSED:
			return "Подготовка завершена"
		DayModel.RejectionReason.ALREADY_USED:
			return "Анонс уже опубликован" if result.activity_id == &"publish_post" else "Тема уже подготовлена"
		DayModel.RejectionReason.MASTERY_CAP:
			return "Достигнут уровень 1. Открыт контур опасности"
		DayModel.RejectionReason.INSUFFICIENT_AP:
			return "Не хватает ОД"
		_:
			return "Действие недоступно"


func _forecast_text(day: DayModel.DaySnapshot) -> String:
	var cells := StreamForecast.warning_cells(day.mastery_level, day.vigor)
	var warning := "Контур опасности: 0 клеток"
	if cells > 0:
		warning = "Контур опасности: %d %s" % [cells, "клетка" if cells == 1 else "клетки"]
	elif day.mastery_level < 1:
		warning = "Контур опасности: выключен"
	var scale := StreamForecast.question_window_scale(day.concentration)
	var questions := "Окно ответа: обычное"
	if scale < 1.0:
		questions = "Окно ответа: −%d%% (от %d с)" % [
			roundi((1.0 - scale) * 100.0), roundi(StreamForecast.QUESTION_WINDOW_FLOOR_MSEC / 1000.0),
		]
	var announcement := "Анонс: не опубликован"
	if day.post_published:
		announcement = "Анонс: +%d зрителя на старте" % StreamForecast.ANNOUNCEMENT_VIEWERS
	var topic := "Тема: не подготовлена"
	if day.topic_prepared:
		topic = "Первый вопрос: «%s»" % StreamForecast.TOPIC_QUESTION
	return "\n\n".join([warning, questions, announcement, topic])
