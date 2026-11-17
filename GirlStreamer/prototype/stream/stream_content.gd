class_name StreamContent
extends RefCounted

const NICKNAMES: Array[String] = [
	"Лис", "Иней", "Чиж", "Пиксель", "Мята", "Север", "Луна", "Кедр",
]

# Each row pairs a stable template ID with its authored text.
const _POOLS := {
	&"start": [
		[&"start_arrival", "О, успел к началу!"],
		[&"start_hello", "Всем привет!"],
		[&"start_ready", "Уже здесь, можно начинать!"],
	],
	&"ambient_playing": [
		[&"playing_turns", "Слежу за поворотами вместе с тобой."],
		[&"playing_focus", "Я тоже тут сосредоточился."],
		[&"playing_route", "Интересно, куда змейка свернёт."],
	],
	&"ambient_waiting": [
		[&"waiting_retry", "Давай ещё попытку!"],
		[&"waiting_ready", "Готов смотреть следующий заход."],
		[&"waiting_pause", "Можно выдохнуть перед новым заходом."],
	],
	&"food": [
		[&"food_bite", "Ещё кусочек!"],
		[&"food_pickup", "Подобрала!"],
		[&"food_growth", "Змейка стала длиннее!"],
	],
	&"achievement": [
		[&"achievement_attempt", "Вот это попытка!"],
		[&"achievement_result", "Круто получилось!"],
		[&"achievement_cheer", "Ого! Аплодирую!"],
	],
	&"loss": [
		[&"loss_next", "Бывает, давай ещё раз."],
		[&"loss_turn", "Сложный был поворот."],
		[&"loss_support", "Я всё ещё болею за тебя!"],
	],
	&"answer": [
		[&"answer_thanks", "Спасибо, что ответила!"],
		[&"answer_heard", "Услышали, спасибо!"],
		[&"answer_chat", "Здорово, что читаешь чат."],
	],
	&"donation": [
		[&"donation_thanks", "Спасибо за эфир!"],
		[&"donation_support", "Хочу поддержать стрим."],
		[&"donation_extra", "Немного поддержки для канала."],
	],
}

const _REQUIRED_CONTEXTS: Array[StringName] = [
	&"start", &"ambient_playing", &"ambient_waiting", &"food",
	&"achievement", &"loss", &"answer", &"donation",
]


class DonationRecord extends RefCounted:
	var id: int
	var received_at_msec: int
	var group_index: int
	var amount: int
	var nick: String
	var message: String
	var question_template_id: StringName

	func _init(
		payment_id: int, at_msec: int, donor_group: int, coins: int, nickname: String,
		text: String, template_id: StringName = &""
	) -> void:
		id = payment_id
		received_at_msec = at_msec
		group_index = donor_group
		amount = coins
		nick = nickname
		message = text
		question_template_id = template_id

	func snapshot() -> DonationRecord:
		return DonationRecord.new(id, received_at_msec, group_index, amount, nick, message, question_template_id)

	func is_valid() -> bool:
		return (
			id > 0 and received_at_msec >= 0 and group_index in [0, 1, 2]
			and amount in [2, 5, 10, 25] and not nick.strip_edges().is_empty()
			and (question_template_id.is_empty() or not message.strip_edges().is_empty())
		)


class ChatTemplate extends RefCounted:
	var id: StringName
	var context: StringName
	var text: String

	func _init(template_id: StringName, template_context: StringName, template_text: String) -> void:
		id = template_id
		context = template_context
		text = template_text


class ChatLine extends RefCounted:
	var template_id: StringName
	var nick: String
	var text: String
	var context: StringName
	var time_msec: int

	func _init(id: StringName, nickname: String, message: String, line_context: StringName, at_msec: int) -> void:
		template_id = id
		nick = nickname
		text = message
		context = line_context
		time_msec = at_msec


static func get_templates(context: StringName) -> Array[ChatTemplate]:
	var templates: Array[ChatTemplate] = []
	var rows: Array = _POOLS.get(context, [])
	for row: Array in rows:
		templates.append(ChatTemplate.new(row[0], context, row[1]))
	return templates


static func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if NICKNAMES.size() < 8:
		errors.append("At least eight chat nicknames are required.")
	for nickname in NICKNAMES:
		if nickname.strip_edges().is_empty():
			errors.append("Empty chat nickname.")

	for context in _REQUIRED_CONTEXTS:
		if not _POOLS.has(context):
			errors.append("Missing chat context: %s." % context)

	var ids: Dictionary[StringName, bool] = {}
	for context: StringName in _POOLS:
		var templates := get_templates(context)
		if context in _REQUIRED_CONTEXTS and templates.size() < 3:
			errors.append("Chat context %s requires at least three templates." % context)

		var texts: Dictionary[String, bool] = {}
		for template in templates:
			if ids.has(template.id):
				errors.append("Duplicate chat template ID: %s." % template.id)
			ids[template.id] = true

			var message := template.text.strip_edges()
			if message.is_empty():
				errors.append("Empty chat template text: %s." % template.id)
			elif texts.has(message):
				errors.append("Duplicate chat text in context %s: %s." % [context, message])
			texts[message] = true
	return errors


const _QUESTION_CONTEXTS: Array[StringName] = [&"general", &"achievement", &"loss"]
const _EMOTIONS: Array[StringName] = [&"focused", &"neutral", &"happy", &"shy", &"sad"]


const _REACTION_STYLES: Array[StringName] = [&"competitive", &"humor", &"flirt"]
const _REACTION_LABELS: Array[String] = ["Азартно", "С юмором", "Кокетливо"]
const _REACTION_EFFECTS: Array[Vector3] = [
	Vector3(4, 1, 0), Vector3(1, 4, 1), Vector3(0, 1, 4)
]


class ChoiceOption extends RefCounted:
	var id: StringName
	var label: String
	var reply: String
	var emotion: StringName
	var effects: Vector3
	var chat_responses: Array[String]
	var style_id: StringName

	func _init(
		option_id: StringName, intent: String, reply_text: String, reply_emotion: StringName,
		effect_vector: Vector3, responses: Array[String], option_style_id: StringName = &""
	) -> void:
		id = option_id
		label = intent
		reply = reply_text
		emotion = reply_emotion
		effects = effect_vector
		chat_responses = responses.duplicate()
		style_id = option_style_id

	func snapshot() -> ChoiceOption:
		return ChoiceOption.new(id, label, reply, emotion, effects, chat_responses, style_id)

	func is_valid() -> bool:
		return (
			not id.is_empty() and not label.strip_edges().is_empty()
			and not reply.strip_edges().is_empty() and emotion in _EMOTIONS
			and effects.is_finite()
			and effects.min(Vector3(4, 4, 4)) == effects
			and effects.max(Vector3(-2, -2, -2)) == effects
			and chat_responses.size() == 2
			and not chat_responses[0].strip_edges().is_empty()
			and not chat_responses[1].strip_edges().is_empty()
			and chat_responses[0].strip_edges() != chat_responses[1].strip_edges()
		)


class QuestionTemplate extends RefCounted:
	var id: StringName
	var prompt: String
	var context: StringName
	var options: Array[ChoiceOption]

	func _init(
		question_id: StringName, question_prompt: String, question_context: StringName,
		question_options: Array[ChoiceOption]
	) -> void:
		id = question_id
		prompt = question_prompt
		context = question_context
		options = question_options


class ChoiceDefinition extends RefCounted:
	var id: int
	var template_id: StringName
	var kind: StringName
	var prompt: String
	var nick: String
	var options: Array[ChoiceOption]
	var window_msec: int
	var source_event_id: int
	var source_group_index: int
	var source_attempt_id: int
	var source_event_kind: StringName
	var donation_amount: int

	func _init(
		opening_id: int, catalog_id: StringName, choice_kind: StringName, question_prompt: String,
		nickname: String, choice_options: Array[ChoiceOption], duration_msec: int,
		event_id: int, group_index: int, attempt_id: int = 0, event_kind: StringName = &"",
		donor_amount: int = 0
	) -> void:
		id = opening_id
		template_id = catalog_id
		kind = choice_kind
		prompt = question_prompt
		nick = nickname
		options = choice_options
		window_msec = duration_msec
		source_event_id = event_id
		source_group_index = group_index
		source_attempt_id = attempt_id
		source_event_kind = event_kind
		donation_amount = donor_amount

	func is_valid() -> bool:
		return id > 0 and is_valid_candidate()

	func is_valid_candidate() -> bool:
		if not (
			id >= 0 and not template_id.is_empty() and kind in [&"question", &"reaction", &"donation_question"]
			and not prompt.strip_edges().is_empty() and not nick.strip_edges().is_empty()
			and window_msec > 0 and source_event_id >= 0 and source_group_index in [-1, 0, 1, 2]
			and source_attempt_id >= 0 and options_are_valid(options)
		):
			return false
		if kind == &"donation_question":
			if (
				donation_amount not in [2, 5, 10, 25] or source_event_id <= 0 or source_group_index < 0
				or source_attempt_id != 0 or source_event_kind != &"donation"
			):
				return false
		elif donation_amount != 0:
			return false
		if kind == &"reaction":
			return (
				window_msec == 3000 and source_event_id > 0 and source_attempt_id > 0
				and source_event_kind in [&"milestone", &"record", &"board_completed", &"collision"]
				and reaction_options_are_valid(options)
			)
		for option in options:
			if not option.style_id.is_empty():
				return false
		return true

	func snapshot() -> ChoiceDefinition:
		var copied_options: Array[ChoiceOption] = []
		for option in options:
			copied_options.append(option.snapshot())
		return ChoiceDefinition.new(
			id, template_id, kind, prompt, nick, copied_options, window_msec,
			source_event_id, source_group_index, source_attempt_id, source_event_kind, donation_amount
		)


	static func options_are_valid(options: Array[ChoiceOption]) -> bool:
		if options.size() != 3:
			return false
		var labels: Array[String] = []
		var effects: Array[Vector3] = []
		var ids: Array[StringName] = []
		for option in options:
			if option == null or not option.is_valid():
				return false
			var label := option.label.strip_edges()
			if label in labels or option.effects in effects or option.id in ids:
				return false
			labels.append(label)
			effects.append(option.effects)
			ids.append(option.id)
		return true


	static func reaction_options_are_valid(options: Array[ChoiceOption]) -> bool:
		if not options_are_valid(options):
			return false
		for index in range(_REACTION_STYLES.size()):
			if (
				options[index].style_id != _REACTION_STYLES[index]
				or options[index].label != _REACTION_LABELS[index]
				or options[index].effects != _REACTION_EFFECTS[index]
			):
				return false
		return true


class ChoiceResolution extends RefCounted:
	var choice_id: int
	var template_id: StringName
	var kind: StringName
	var source_event_id: int
	var source_group_index: int
	var source_attempt_id: int
	var source_event_kind: StringName
	var donation_amount: int
	var outcome: StringName
	var option_index := -1
	var opened_at_msec: int
	var resolved_at_msec: int
	var elapsed_msec: int
	var option: ChoiceOption

	func snapshot() -> ChoiceResolution:
		var copy := ChoiceResolution.new()
		copy.choice_id = choice_id
		copy.template_id = template_id
		copy.kind = kind
		copy.source_event_id = source_event_id
		copy.source_group_index = source_group_index
		copy.source_attempt_id = source_attempt_id
		copy.source_event_kind = source_event_kind
		copy.donation_amount = donation_amount
		copy.outcome = outcome
		copy.option_index = option_index
		copy.opened_at_msec = opened_at_msec
		copy.resolved_at_msec = resolved_at_msec
		copy.elapsed_msec = elapsed_msec
		copy.option = option.snapshot() if option != null else null
		return copy


static func validate_questions(questions: Array[QuestionTemplate]) -> PackedStringArray:
	var errors := PackedStringArray()
	if questions.size() != 12:
		errors.append("Нужно ровно 12 вопросов.")

	var question_ids: Dictionary[StringName, bool] = {}
	var option_ids: Dictionary[StringName, bool] = {}
	for question in questions:
		if question == null:
			errors.append("В каталоге есть пустой вопрос.")
			continue
		if question.id.is_empty() or question_ids.has(question.id):
			errors.append("Пустой или повторяющийся идентификатор вопроса: %s." % question.id)
		question_ids[question.id] = true
		if question.prompt.strip_edges().is_empty() or question.context not in _QUESTION_CONTEXTS:
			errors.append("Проверьте текст и контекст вопроса %s." % question.id)
		if not ChoiceDefinition.options_are_valid(question.options):
			errors.append("Проверьте варианты ответа и эффекты вопроса %s." % question.id)
		for option in question.options:
			if option == null:
				continue
			if not option.style_id.is_empty():
				errors.append("У обычного ответа %s не должно быть стиля реакции." % option.id)
			if option_ids.has(option.id):
				errors.append("Повторяющийся идентификатор ответа: %s." % option.id)
			option_ids[option.id] = true
	return errors


static func validate_reactions(reactions: Array[QuestionTemplate]) -> PackedStringArray:
	var errors := PackedStringArray()
	var category_counts := {&"achievement": 0, &"loss": 0}
	var ids: Dictionary[StringName, bool] = {}
	for reaction in reactions:
		if reaction == null or not category_counts.has(reaction.context):
			errors.append("Проверьте категорию реакции.")
			continue
		category_counts[reaction.context] += 1
		if (
			reaction.id.is_empty() or ids.has(reaction.id) or reaction.prompt.strip_edges().is_empty()
			or not ChoiceDefinition.reaction_options_are_valid(reaction.options)
		):
			errors.append("Проверьте варианты реакции %s." % reaction.id)
		ids[reaction.id] = true
	if category_counts[&"achievement"] != 2 or category_counts[&"loss"] != 2:
		errors.append("Нужно по два варианта реакции на достижение и проигрыш.")
	return errors


static func get_reactions() -> Array[QuestionTemplate]:
	return [
		QuestionTemplate.new(&"achievement_1", "Новый рубеж", &"achievement", [
			_reaction_option(&"achievement_1", 0, "Вот это результат!", &"focused",
				["Сильный заход!", "Красиво сыграла!"]),
			_reaction_option(&"achievement_1", 1, "Даже змейка удивилась!", &"happy",
				["И весь чат тоже!", "Змейка в шоке."]),
			_reaction_option(&"achievement_1", 2, "Принимаю комплименты!", &"shy",
				["Ты отлично сыграла!", "Заслуженные аплодисменты!"]),
		]),
		QuestionTemplate.new(&"achievement_2", "Новый рубеж", &"achievement", [
			_reaction_option(&"achievement_2", 0, "Вот что значит точный поворот!", &"focused",
				["Точные ходы решают.", "Хорошо держала маршрут."]),
			_reaction_option(&"achievement_2", 1, "Змейка сегодня явно в форме.", &"happy",
				["Ещё в какой!", "Змейке отдельные аплодисменты."]),
			_reaction_option(&"achievement_2", 2, "Ну что, удалось вас впечатлить?", &"shy",
				["Ещё как!", "Я до сих пор под впечатлением."]),
		]),
		QuestionTemplate.new(&"loss_1", "Попытка закончилась", &"loss", [
			_reaction_option(&"loss_1", 0, "Разберусь с этим поворотом.", &"focused",
				["В следующий раз получится!", "Поворот и правда был сложный."]),
			_reaction_option(&"loss_1", 1, "Так и было задумано. Почти.", &"happy",
				["Почти поверил!", "Финал с сюрпризом."]),
			_reaction_option(&"loss_1", 2, "Улыбнулась вам и пропустила ход.", &"shy",
				["Мы тоже улыбаемся.", "Улыбку заметили!"]),
		]),
		QuestionTemplate.new(&"loss_2", "Попытка закончилась", &"loss", [
			_reaction_option(&"loss_2", 0, "В следующий раз оставлю больше места.", &"focused",
				["Да, там было тесно.", "Болеем за следующий заход!"]),
			_reaction_option(&"loss_2", 1, "Змейка решила взять перерыв.", &"happy",
				["Вот это срочный перерыв!", "Пусть отдохнёт."]),
			_reaction_option(&"loss_2", 2, "Утешите меня добрым словом?", &"shy",
				["Ты всё равно молодец!", "Мы с тобой."]),
		]),
	]


static func _reaction_option(
	variant_id: StringName, index: int, reply: String, emotion: StringName, responses: Array[String]
) -> ChoiceOption:
	var style := _REACTION_STYLES[index]
	return ChoiceOption.new(
		StringName("%s_%s" % [variant_id, style]), _REACTION_LABELS[index], reply, emotion,
		_REACTION_EFFECTS[index], responses, style
	)


static func get_questions() -> Array[QuestionTemplate]:
	return [
		QuestionTemplate.new(&"q01", "Что сегодня важнее: рекорд или уют?", &"general", [
			ChoiceOption.new(
				&"q01_record", "Побить рекорд", "Хочу обойти свой лучший счёт.", &"focused",
				Vector3(4, 1, 0), ["Следим за счётом!", "Пора бить рекорд!"]
			),
			ChoiceOption.new(
				&"q01_laugh", "Посмеяться вместе", "Хочу смеяться вместе с вами.", &"happy",
				Vector3(1, 4, 1), ["Уже улыбаюсь.", "Смех важнее очков."]
			),
			ChoiceOption.new(
				&"q01_charm", "Очаровать чат", "Мой план — вас очаровать.", &"shy",
				Vector3(0, 1, 4), ["План уже работает.", "Чат очарован!"]
			),
		]),
		QuestionTemplate.new(&"q02", "Давно играешь в Змейку?", &"general", [
			ChoiceOption.new(
				&"q02_train", "Люблю тренироваться", "Иногда тренируюсь вне эфира.", &"focused",
				Vector3(4, 0, 1), ["Видно по поворотам.", "Вот откуда такой контроль."]
			),
			ChoiceOption.new(
				&"q02_style", "Главное — подача", "Змейка простая, зато какая подача!", &"happy",
				Vector3(0, 2, 4), ["Подача что надо.", "За стиль отдельное очко."]
			),
			ChoiceOption.new(
				&"q02_learn", "Учусь на ходу", "Учусь прямо на ваших глазах.", &"neutral",
				Vector3(2, 4, 0), ["Учимся вместе!", "Буду замечать прогресс."]
			),
		]),
		QuestionTemplate.new(&"q03", "Почему выбрала именно эту игру?", &"general", [
			ChoiceOption.new(
				&"q03_relax", "Хочу отдохнуть с вами", "С вами хочется немного выдохнуть.", &"neutral",
				Vector3(0, 4, 2), ["Выдыхаем вместе.", "Уютный сегодня эфир."]
			),
			ChoiceOption.new(
				&"q03_challenge", "Люблю испытания", "Люблю игры, где важен каждый ход.", &"focused",
				Vector3(4, 1, 0), ["Даже один поворот решает.", "Уважаю этот выбор."]
			),
			ChoiceOption.new(
				&"q03_surprise", "Хотела вас удивить", "Соскучились по сюрпризам?", &"shy",
				Vector3(1, 0, 4), ["Меня уже удивила.", "Люблю такие сюрпризы."]
			),
		]),
		QuestionTemplate.new(&"q04", "Будешь рисковать ради очков?", &"general", [
			ChoiceOption.new(
				&"q04_watch", "Ради ваших взглядов", "За такой поворот взгляды стоят риска.", &"shy",
				Vector3(0, 1, 4), ["Глаз не оторвать.", "Теперь смотрю ещё внимательнее."]
			),
			ChoiceOption.new(
				&"q04_safe", "Поберегу наши нервы", "Побережём нервы и хвост.", &"neutral",
				Vector3(2, 4, 0), ["Мои нервы благодарны.", "Хвост тоже за осторожность."]
			),
			ChoiceOption.new(
				&"q04_risk", "Если есть шанс", "Рискну, если вижу выход.", &"focused",
				Vector3(4, 0, 1), ["Главное оставить выход.", "Риск с расчётом, одобряю."]
			),
		]),
		QuestionTemplate.new(&"q05", "Как справляешься с волнением?", &"general", [
			ChoiceOption.new(
				&"q05_route", "Слежу за маршрутом", "Считаю повороты наперёд.", &"focused",
				Vector3(4, 1, 0), ["План — половина успеха.", "Я тоже считаю повороты."]
			),
			ChoiceOption.new(
				&"q05_joke", "Шучу над собой", "Смеюсь, и руки уже спокойнее.", &"happy",
				Vector3(0, 4, 1), ["Твои шутки и нас успокаивают.", "Посмеялись, теперь легче."]
			),
			ChoiceOption.new(
				&"q05_smile", "Улыбаюсь в камеру", "Улыбнусь вам, и сразу легче.", &"shy",
				Vector3(0, 2, 4), ["Улыбаюсь в ответ.", "Вот и стало спокойнее."]
			),
		]),
		QuestionTemplate.new(&"q06", "Что тебе нравится в стримах?", &"general", [
			ChoiceOption.new(
				&"q06_talk", "Болтать с вами", "Люблю разговоры между ходами.", &"happy",
				Vector3(0, 4, 1), ["Мы тоже любим поболтать.", "Разговоры украшают эфир."]
			),
			ChoiceOption.new(
				&"q06_praise", "Ловить комплименты", "От добрых слов я расцветаю.", &"shy",
				Vector3(0, 2, 4), ["Лови ещё один: ты чудо.", "Тогда добрых слов будет больше."]
			),
			ChoiceOption.new(
				&"q06_progress", "Делиться прогрессом", "Люблю видеть, как растёт счёт.", &"focused",
				Vector3(4, 2, 0), ["И нам нравится видеть рост.", "Следим за каждым очком."]
			),
		]),
		QuestionTemplate.new(&"q07", "Как удалось так далеко зайти?", &"achievement", [
			ChoiceOption.new(
				&"q07_inspire", "Вы вдохновляете", "Ваши слова помогли собраться.", &"shy",
				Vector3(1, 2, 4), ["Рады были помочь.", "Мы с тобой!"]
			),
			ChoiceOption.new(
				&"q07_turns", "Продумала повороты", "Оставляла место для разворота.", &"focused",
				Vector3(4, 1, 0), ["Запомню про запас места.", "Вот в чём секрет!"]
			),
			ChoiceOption.new(
				&"q07_surprised", "Сама удивилась", "Я сама не верю, что прошла так далеко.", &"happy",
				Vector3(1, 4, 0), ["Мы тоже не ожидали!", "Тем приятнее результат."]
			),
		]),
		QuestionTemplate.new(&"q08", "Дальше будет ещё лучше?", &"achievement", [
			ChoiceOption.new(
				&"q08_best", "Попробую превзойти", "Попробую ещё поднять планку.", &"focused",
				Vector3(4, 0, 2), ["Удачи с новой планкой.", "Болею за новый максимум!"]
			),
			ChoiceOption.new(
				&"q08_look", "Смотрите внимательно", "Смотрите, я ещё могу удивить.", &"happy",
				Vector3(1, 0, 4), ["Всё внимание на экран.", "Смотрю в оба!"]
			),
			ChoiceOption.new(
				&"q08_wait", "Не будем загадывать", "Посмотрим, куда выведет змейка.", &"neutral",
				Vector3(2, 4, 0), ["Без спешки, мы рядом.", "Пусть игра удивит."]
			),
		]),
		QuestionTemplate.new(&"q09", "Гордишься этой попыткой?", &"achievement", [
			ChoiceOption.new(
				&"q09_celebrate", "Празднуем вместе", "Это наш общий повод для радости!", &"happy",
				Vector3(1, 4, 1), ["Аплодисменты всем!", "Ура, празднуем!"]
			),
			ChoiceOption.new(
				&"q09_practice", "Тренировка помогла", "Да, повороты стали точнее.", &"focused",
				Vector3(4, 2, 0), ["Тренировка окупилась.", "Точность прямо заметна."]
			),
			ChoiceOption.new(
				&"q09_compliment", "Жду комплиментов", "Да, и комплимент приму.", &"shy",
				Vector3(0, 1, 4), ["Лови: красиво сыграла!", "Ты заслужила похвалу."]
			),
		]),
		QuestionTemplate.new(&"q10", "Обидно было проиграть прошлую попытку?", &"loss", [
			ChoiceOption.new(
				&"q10_mistake", "Поняла свою ошибку", "Я слишком поздно свернула.", &"sad",
				Vector3(4, 1, 0), ["В следующий раз свернёшь раньше.", "Теперь понятно, где ошиблась."]
			),
			ChoiceOption.new(
				&"q10_chat", "Засмотрелась на чат", "Зачиталась вами и пропустила ход.", &"shy",
				Vector3(-1, 2, 4), ["Понимаю, чат затягивает.", "Пока смотри на змейку, мы тут."]
			),
			ChoiceOption.new(
				&"q10_funny", "Смешно получилось", "Ну и кульбит у змейки вышел!", &"happy",
				Vector3(0, 4, 2), ["Кульбит запомнился.", "Да, было забавно."]
			),
		]),
		QuestionTemplate.new(&"q11", "Что изменишь после прошлой ошибки?", &"loss", [
			ChoiceOption.new(
				&"q11_support", "Нужна ваша поддержка", "Мне хочется, чтобы вы поболели.", &"shy",
				Vector3(0, 3, 4), ["Болею за тебя!", "Чат на твоей стороне."]
			),
			ChoiceOption.new(
				&"q11_breathe", "Выдохну и продолжу", "Выдохну и спокойно начну заново.", &"neutral",
				Vector3(2, 4, 0), ["Выдыхаем вместе.", "Спокойно, времени хватит."]
			),
			ChoiceOption.new(
				&"q11_reroute", "Выберу другой маршрут", "Объеду тесный угол по широкой дуге.", &"focused",
				Vector3(4, 0, 1), ["Широкая дуга звучит разумно.", "Там будет больше места."]
			),
		]),
		QuestionTemplate.new(&"q12", "Этот заход будет реваншем?", &"loss", [
			ChoiceOption.new(
				&"q12_again", "Ещё одна попытка!", "Просто попробую ещё раз с вами.", &"happy",
				Vector3(1, 4, 0), ["Мы остаёмся на ещё один заход.", "Играем дальше вместе."]
			),
			ChoiceOption.new(
				&"q12_revenge", "Обязательно попробую", "Попробую взять реванш за тот поворот.", &"focused",
				Vector3(4, 1, 1), ["Теперь поворот под контролем.", "Болеем за реванш!"]
			),
			ChoiceOption.new(
				&"q12_cheer", "Если поболеете за меня", "С вашей поддержкой попробую!", &"shy",
				Vector3(0, 2, 4), ["Поддержка на месте.", "Весь чат за тебя!"]
			),
		]),
	]


static func validate_donations() -> PackedStringArray:
	var errors := PackedStringArray()
	var questions := get_donation_questions()
	if questions.size() != 6:
		errors.append("Нужно ровно шесть вопросов от доноров.")
	var ids: Dictionary[StringName, bool] = {}
	var existing := get_questions()
	existing.append_array(get_reactions())
	for question in existing:
		ids[question.id] = true
		for option in question.options:
			ids[option.id] = true
	for question in questions:
		if (
			question.id.is_empty() or ids.has(question.id) or question.prompt.strip_edges().is_empty()
			or question.context != &"general" or not ChoiceDefinition.options_are_valid(question.options)
		):
			errors.append("Проверьте вопрос донора %s." % question.id)
			continue
		ids[question.id] = true
		for option in question.options:
			if ids.has(option.id) or not option.style_id.is_empty():
				errors.append("Проверьте вариант ответа донору %s." % option.id)
			ids[option.id] = true
	return errors


static func build_donation_question(record: DonationRecord) -> ChoiceDefinition:
	if record == null or not record.is_valid() or record.question_template_id.is_empty():
		return null
	for question in get_donation_questions():
		if question.id != record.question_template_id:
			continue
		return ChoiceDefinition.new(
			0, question.id, &"donation_question", record.message, record.nick,
			question.options, 5000, record.id, record.group_index, 0, &"donation", record.amount
		)
	return null


static func get_donation_questions() -> Array[QuestionTemplate]:
	return [
		QuestionTemplate.new(&"donor_game", "Что тебе больше всего нравится в этой игре?", &"general", [
			ChoiceOption.new(&"donor_game_route", "Искать маршрут", "Мне нравится искать путь даже в тесноте.",
				&"focused", Vector3(4, 1, 0), ["С маршрутом интереснее.", "Теснота заставляет думать."]),
			ChoiceOption.new(&"donor_game_surprise", "Неожиданные повороты", "Обожаю, когда игра меня удивляет.",
				&"happy", Vector3(1, 4, 1), ["И мы удивляемся вместе.", "За это и смотрю!"]),
			ChoiceOption.new(&"donor_game_talk", "Ваши комментарии", "С вами я даже на простых ходах улыбаюсь.",
				&"shy", Vector3(0, 1, 4), ["Пишем ради улыбки.", "Улыбаемся в ответ!"]),
		]),
		QuestionTemplate.new(&"donor_joy", "Какой момент стрима радует тебя сильнее всего?", &"general", [
			ChoiceOption.new(&"donor_joy_move", "Точный ход", "Радуюсь, когда сложный поворот удаётся.",
				&"focused", Vector3(4, 1, 0), ["Знакомое чувство.", "Такие ходы приятно смотреть."]),
			ChoiceOption.new(&"donor_joy_laugh", "Общий смех", "Люблю момент, когда мы смеёмся над одним и тем же.",
				&"happy", Vector3(1, 4, 1), ["Общий смех сближает.", "Хорошо смеяться вместе!"]),
			ChoiceOption.new(&"donor_joy_hello", "Первые приветствия", "Когда вы здороваетесь, я сразу чувствую себя среди друзей.",
				&"shy", Vector3(0, 1, 4), ["Буду здороваться первым.", "И тебе всегда рады."]),
		]),
		QuestionTemplate.new(&"donor_keep", "Что помогает тебе не сдаваться?", &"general", [
			ChoiceOption.new(&"donor_keep_goal", "Маленькая цель", "Ставлю себе маленькую цель и пробую снова.",
				&"focused", Vector3(4, 1, 0), ["Так легче начать.", "Шаг за шагом."]),
			ChoiceOption.new(&"donor_keep_joke", "Шутка над ошибкой", "Пошучу над ошибкой, и пробовать снова уже легче.",
				&"happy", Vector3(1, 4, 1), ["Шутки правда выручают.", "Ошибки переживём."]),
			ChoiceOption.new(&"donor_keep_words", "Добрые слова", "Ваши добрые слова возвращают мне уверенность.",
				&"shy", Vector3(0, 1, 4), ["Мы в тебя верим.", "Всегда есть доброе слово."]),
		]),
		QuestionTemplate.new(&"donor_advice", "Какой совет дашь новичку в Змейке?", &"general", [
			ChoiceOption.new(&"donor_advice_room", "Оставляй место", "Поворачивай так, чтобы осталось место для следующего хода.",
				&"focused", Vector3(4, 1, 0), ["Смотрю на ход вперёд.", "Запомню про запас места."]),
			ChoiceOption.new(&"donor_advice_fun", "Играй в радость", "Выбирай ходы, которые интересно пробовать.",
				&"happy", Vector3(1, 4, 1), ["Пора попробовать новое.", "С интересом легче учиться."]),
			ChoiceOption.new(&"donor_advice_share", "Позови друзей", "Позови друга посмотреть, вместе веселее учиться.",
				&"shy", Vector3(0, 1, 4), ["Есть кого позвать.", "Вместе точно веселее."]),
		]),
		QuestionTemplate.new(&"donor_support", "Что для тебя значит поддержка зрителей?", &"general", [
			ChoiceOption.new(&"donor_support_grow", "Помогает расти", "Ваши наблюдения помогают мне замечать, чему ещё поучиться.",
				&"focused", Vector3(4, 1, 0), ["Будем делиться наблюдениями.", "Продолжай в своём темпе."]),
			ChoiceOption.new(&"donor_support_energy", "Добавляет энергии", "От ваших шуток у меня прибавляется сил.",
				&"happy", Vector3(1, 4, 1), ["У чата ещё есть шутки.", "Тогда продолжим смешить."]),
			ChoiceOption.new(&"donor_support_company", "Даёт чувство компании", "Когда вы пишете, я чувствую, что мы проводим время вместе.",
				&"shy", Vector3(0, 1, 4), ["Мы рядом.", "Я тоже чувствую компанию."]),
		]),
		QuestionTemplate.new(&"donor_stream", "Каким ты хочешь сделать этот эфир?", &"general", [
			ChoiceOption.new(&"donor_stream_challenge", "С испытанием", "Хочу устроить себе испытание и посмотреть, чему научусь.",
				&"focused", Vector3(4, 1, 0), ["Интересно увидеть прогресс.", "Следим за испытанием!"]),
			ChoiceOption.new(&"donor_stream_fun", "Весёлым", "Хочу, чтобы у каждого нашёлся повод посмеяться.",
				&"happy", Vector3(1, 4, 1), ["Отличный план.", "Я готов смеяться!"]),
			ChoiceOption.new(&"donor_stream_warm", "Дружеским", "Хочу, чтобы вы чувствовали себя как в гостях у друга.",
				&"shy", Vector3(0, 1, 4), ["Уже уютно.", "Здорово у тебя в гостях."]),
		]),
	]
