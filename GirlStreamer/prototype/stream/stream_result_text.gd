extends RefCounted
## Shared Russian copy for frozen stream results and live audience labels.

const StreamResults = preload("res://prototype/stream/stream_results.gd")
const REACTION_STYLE_LABELS := {
	&"competitive": "Азартно",
	&"humor": "С юмором",
	&"flirt": "Кокетливо",
}
const AUDIENCE_GROUP_NAMES := ["Геймеры", "Любители общения", "Поклонники образа"]


static func format_results(results: StreamResults) -> String:
	var rows := PackedStringArray([
		"Игра",
		"Длительность: %s из %s   |   Лучший счёт: %d" % [
			format_time(results.elapsed_seconds), format_time(results.duration_seconds),
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
			format_time(highlight.time_msec / 1000.0), highlight.explanation,
		])
		if not changes.is_empty():
			rows.append("Впечатление: %s" % " · ".join(changes))
	return "\n".join(rows)


static func _append_audience_results(rows: PackedStringArray, results: StreamResults) -> void:
	var snapshot := results.audience
	rows.append("Зрители: в начале %d   |   В конце %d   |   Пик %d" % [
		results.initial_viewers, snapshot.total, snapshot.peak,
	])
	rows.append("Изменение за эфир: %+d" % (snapshot.total - results.initial_viewers))
	for index in range(AUDIENCE_GROUP_NAMES.size()):
		var impression := snapshot.precise_impressions[index]
		rows.append("%s: %d · %s (%.1f)" % [
			AUDIENCE_GROUP_NAMES[index], snapshot.counts[index],
			impression_description(impression), impression,
		])
	rows.append("Часть зрителей могла прийти или уйти со временем.")


static func _append_communication_results(rows: PackedStringArray, results: StreamResults) -> void:
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


static func _append_choice_counts(
	rows: PackedStringArray, title: String, counts: Vector4i, answer_label: String = "Ответов"
) -> void:
	rows.append("%s: %d   |   %s: %d   |   Истекло: %d   |   Отменено: %d" % [
		title, counts.x, answer_label, counts.y, counts.z, counts.w,
	])


static func impression_description(impression: float) -> String:
	if impression < 40.0:
		return "интерес снижается"
	if impression > 60.0:
		return "увлечены"
	return "спокойный интерес"


static func format_time(seconds: float) -> String:
	var whole_seconds := ceili(maxf(0.0, seconds))
	return "%02d:%02d" % [floori(whole_seconds / 60.0), whole_seconds % 60]
