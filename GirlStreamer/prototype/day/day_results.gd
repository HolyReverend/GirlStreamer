extends Control
## Renders the settled evening and the model's projected morning.

signal continue_requested

const DayModel = preload("res://prototype/day/day_state.gd")
const StreamResults = preload("res://prototype/stream/stream_results.gd")
const ResultText = preload("res://prototype/stream/stream_result_text.gd")

@onready var _heading: Label = %Heading
@onready var _income: Label = %Income
@onready var _balance: Label = %Balance
@onready var _condition: Label = %Condition
@onready var _recovery: Label = %Recovery
@onready var _morning: Label = %Morning
@onready var _details_panel: PanelContainer = %DetailsPanel
@onready var _details_scroll: ScrollContainer = %DetailsScroll
@onready var _details: Label = %Details
@onready var _continue_button: Button = %ContinueButton


func render(
	result: DayModel.DayResult, morning: DayModel.DaySnapshot, stream_results: StreamResults
) -> void:
	var streamed := result.outcome == DayModel.DayOutcome.STREAMED
	var outcome := "Эфир завершён" if streamed else "Сегодня без эфира"
	_heading.text = "Итоги дня %d · %s" % [result.day_number, outcome]
	if streamed:
		_income.text = "Донаты за эфир: %+d" % result.income
		_balance.text = "Баланс: %d → %d" % [result.balance_before, result.balance_after]
		_condition.text = "Бодрость: %d → %d (%+d)\nКонцентрация: %d → %d (%+d)" % [
			result.vigor_before, result.vigor_after, result.vigor_after - result.vigor_before,
			result.concentration_before, result.concentration_after,
			result.concentration_after - result.concentration_before,
		]
	else:
		_income.text = "Доход за вечер: %d" % result.income
		_balance.text = "Баланс: %d" % result.balance_after
		_condition.text = "Бодрость: %d   ·   Концентрация: %d\nНагрузка от эфира: 0" % [
			result.vigor_after, result.concentration_after,
		]

	_recovery.text = "Восстановление за сон: бодрость %+d, концентрация %+d" % [
		morning.vigor - result.vigor_after, morning.concentration - result.concentration_after,
	]
	_morning.text = "После сна: бодрость %d, концентрация %d" % [
		morning.vigor, morning.concentration,
	]

	_details_panel.visible = streamed and stream_results != null
	_details.text = ResultText.format_results(stream_results) if _details_panel.visible else ""
	_details_scroll.scroll_vertical = 0


func focus_continue() -> void:
	_continue_button.grab_focus()


func _on_continue_pressed() -> void:
	continue_requested.emit()
