extends SceneTree

const DayModel = preload("res://prototype/day/day_state.gd")
const Phase = DayModel.Phase
const Outcome = DayModel.DayOutcome
const Reason = DayModel.RejectionReason
const POST := &"publish_post"
const TOPIC := &"prepare_topic"
const TRAIN := &"train_snake"
const ANIME := &"watch_anime"
const NAP := &"take_nap"
const UNKNOWN := &"unknown_activity"


class Fixture extends DayModel:
	func seed_condition(vigor: int, concentration: int) -> void:
		_day.vigor = vigor
		_day.concentration = concentration


func _initialize() -> void:
	var checks: Array[Callable] = [
		_defaults_and_instance_isolation, _activities_and_full_day,
		_rejection_precedence, _stale_preview, _condition_boundaries,
		_activity_snapshot_isolation, _launch_preview_isolation, _evening_decisions,
		_prepared_evening_results, _condition_across_evening_and_morning,
		_settlement_and_morning_gates, _settlement_snapshot_isolation,
		_wallet_across_days,
	]
	for check in checks:
		if not check.call():
			printerr("STAGE01_DAY_MODEL_FAIL ", check.get_method())
			quit(1)
			return
	print("STAGE01_DAY_MODEL_PASS checks=", checks.size())
	quit()


func _defaults_and_instance_isolation() -> bool:
	var day := DayModel.new()
	var other := DayModel.new()
	var initial := _values(day.get_snapshot())
	var snapshot := day.get_snapshot()
	snapshot.ap = 1
	snapshot.vigor = 2
	return (
		initial == _day_values(6, 8, 8, 0, 0, false, false)
		and _values(day.get_snapshot()) == initial
		and _apply_expected(day, POST, 1, _day_values(5, 8, 8, 0, 0, true, false))
		and _values(other.get_snapshot()) == initial
	)


func _activities_and_full_day() -> bool:
	var expected := _day_values(0, 6, 3, 4, 1, true, true)
	for start_stream in [true, false]:
		var day := DayModel.new()
		if not (
			_apply_expected(day, TRAIN, 2, _day_values(4, 7, 6, 2, 0, false, false))
			and _apply_expected(day, TRAIN, 2, _day_values(2, 6, 4, 4, 1, false, false))
			and _apply_expected(day, POST, 1, _day_values(1, 6, 4, 4, 1, true, false))
			and _apply_expected(day, TOPIC, 1, expected)
		):
			return false
		var launch := day.preview_launch()
		if launch == null or _launch_values(launch) != [1, 6, 3, 1, true, true]:
			return false
		if not _close_once(day, start_stream):
			return false
	return true


func _rejection_precedence() -> bool:
	var day := DayModel.new()
	day.apply_activity(POST)
	if not _reject_expected(day, POST, 1, Reason.ALREADY_USED):
		return false
	day.apply_activity(TOPIC)
	if not _reject_expected(day, TOPIC, 1, Reason.ALREADY_USED):
		return false
	day.apply_activity(TRAIN)
	day.apply_activity(TRAIN)
	if day.get_snapshot().ap != 0:
		return false
	if not (
		_reject_expected(day, POST, 1, Reason.ALREADY_USED)
		and _reject_expected(day, TOPIC, 1, Reason.ALREADY_USED)
		and _reject_expected(day, TRAIN, 2, Reason.MASTERY_CAP)
		and _reject_expected(day, UNKNOWN, 0, Reason.UNKNOWN_ACTIVITY)
		and _reject_expected(day, NAP, 1, Reason.INSUFFICIENT_AP)
	):
		return false
	var capped := DayModel.new()
	capped.apply_activity(TRAIN)
	capped.apply_activity(TRAIN)
	return (
		capped.get_snapshot().ap == 2
		and _reject_expected(capped, TRAIN, 2, Reason.MASTERY_CAP)
		and _reject_expected(DayModel.new(), UNKNOWN, 0, Reason.UNKNOWN_ACTIVITY)
	)


func _stale_preview() -> bool:
	var day := DayModel.new()
	day.apply_activity(ANIME)
	day.apply_activity(ANIME)
	day.apply_activity(NAP)
	day.apply_activity(NAP)
	var preview := day.preview_activity(TRAIN)
	if day.get_snapshot().ap != 2 or not preview.available:
		return false
	var predicted := _values(preview.resulting_snapshot)
	day.apply_activity(POST)
	return (
		day.get_snapshot().ap == 1
		and _reject_expected(day, TRAIN, 2, Reason.INSUFFICIENT_AP)
		and _values(preview.resulting_snapshot) == predicted
	)


func _condition_boundaries() -> bool:
	var day := Fixture.new()
	day.seed_condition(9, 0)
	if not (
		_apply_expected(day, NAP, 1, _day_values(5, 10, 0, 0, 0, false, false))
		and _apply_expected(day, NAP, 1, _day_values(4, 10, 0, 0, 0, false, false))
		and _apply_expected(day, ANIME, 1, _day_values(3, 10, 2, 0, 0, false, false))
	):
		return false
	day.seed_condition(10, 9)
	if not (
		_apply_expected(day, ANIME, 1, _day_values(2, 10, 10, 0, 0, false, false))
		and _apply_expected(day, ANIME, 1, _day_values(1, 10, 10, 0, 0, false, false))
	):
		return false
	var exhausted := Fixture.new()
	exhausted.seed_condition(0, 0)
	return _apply_expected(exhausted, TRAIN, 2, _day_values(4, 0, 0, 2, 0, false, false))


func _activity_snapshot_isolation() -> bool:
	var day := DayModel.new()
	var initial := day.get_snapshot()
	var preview := day.preview_activity(POST)
	preview.resulting_snapshot.coins = 50
	preview.resulting_snapshot.ap = 0
	preview.resulting_snapshot.post_published = false
	if _values(day.get_snapshot()) != _day_values(6, 8, 8, 0, 0, false, false):
		return false
	if _values(day.preview_activity(POST).resulting_snapshot) != _day_values(5, 8, 8, 0, 0, true, false):
		return false
	var committed := day.apply_activity(POST)
	committed.resulting_snapshot.coins = 60
	committed.resulting_snapshot.post_published = false
	var expected := _day_values(5, 8, 8, 0, 0, true, false)
	if _values(day.get_snapshot()) != expected:
		return false
	var rejected := day.apply_activity(POST)
	rejected.resulting_snapshot.ap = 0
	return (
		_values(day.get_snapshot()) == expected
		and _values(initial) == _day_values(6, 8, 8, 0, 0, false, false)
	)


func _launch_preview_isolation() -> bool:
	var day := DayModel.new()
	var first := day.preview_launch()
	var second := day.preview_launch()
	if first == null or second == null:
		return false
	if _launch_values(first) != [1, 8, 8, 0, false, false]:
		return false
	first.vigor = 1
	first.topic_prepared = true
	if (
		_values(day.get_snapshot()) != _day_values(6, 8, 8, 0, 0, false, false)
		or _launch_values(second) != [1, 8, 8, 0, false, false]
		or _launch_values(day.preview_launch()) != [1, 8, 8, 0, false, false]
	):
		return false
	day.apply_activity(TRAIN)
	day.apply_activity(TOPIC)
	return (
		_launch_values(second) == [1, 8, 8, 0, false, false]
		and _launch_values(day.preview_launch()) == [1, 7, 5, 0, false, true]
	)


func _evening_decisions() -> bool:
	return _close_once(DayModel.new(), true) and _close_once(DayModel.new(), false)


func _prepared_evening_results() -> bool:
	for streamed in [true, false]:
		var day := _prepared_day()
		var result: DayModel.DayResult
		var expected_result: Array
		var expected_evening: Array
		var expected_morning: Array
		if streamed:
			day.begin_stream()
			result = day.settle_stream(1, 12)
			expected_result = [1, Outcome.STREAMED, 0, 12, 12, 6, 3, 3, 1]
			expected_evening = [Phase.RESULTS, 1, 12, 0, 3, 1, 4, 1, true, true]
			expected_morning = [Phase.PREPARING, 2, 12, 6, 6, 4, 4, 1, false, false]
		else:
			day.skip_stream()
			result = day.settle_skip(1)
			expected_result = [1, Outcome.SKIPPED, 0, 0, 0, 6, 6, 3, 3]
			expected_evening = [Phase.RESULTS, 1, 0, 0, 6, 3, 4, 1, true, true]
			expected_morning = [Phase.PREPARING, 2, 0, 6, 9, 6, 4, 1, false, false]
		if (
			_result_values(result) != expected_result
			or _result_values(day.get_day_result()) != expected_result
			or _values(day.get_snapshot()) != expected_evening
			or _values(day.preview_morning(1)) != expected_morning
			or _values(day.advance_morning(1)) != expected_morning
			or _values(day.get_snapshot()) != expected_morning
		):
			return false
	return true


func _condition_across_evening_and_morning() -> bool:
	var exhausted := Fixture.new()
	exhausted.apply_activity(TRAIN)
	exhausted.seed_condition(1, 1)
	exhausted.begin_stream()
	var zero_donations := exhausted.settle_stream(1, 0)
	if (
		_result_values(zero_donations) != [1, Outcome.STREAMED, 0, 0, 0, 1, 0, 1, 0]
		or _values(exhausted.advance_morning(1)) != [Phase.PREPARING, 2, 0, 6, 3, 3, 2, 0, false, false]
	):
		return false
	var rested := Fixture.new()
	rested.seed_condition(9, 10)
	rested.skip_stream()
	var skipped := rested.settle_skip(1)
	return (
		_result_values(skipped) == [1, Outcome.SKIPPED, 0, 0, 0, 9, 9, 10, 10]
		and _values(rested.advance_morning(1)) == [Phase.PREPARING, 2, 0, 6, 10, 10, 0, 0, false, false]
	)


func _settlement_and_morning_gates() -> bool:
	var day := DayModel.new()
	var preparing := _values(day.get_snapshot())
	if (
		day.settle_stream(1, 12) != null or day.settle_skip(1) != null
		or day.preview_morning(1) != null or day.advance_morning(1) != null
		or day.get_day_result() != null or _values(day.get_snapshot()) != preparing
	):
		return false
	day.skip_stream()
	var skipped := _values(day.get_snapshot())
	if (
		day.settle_skip(2) != null or day.settle_stream(1, 12) != null
		or day.preview_morning(1) != null or day.advance_morning(1) != null
		or day.get_day_result() != null or _values(day.get_snapshot()) != skipped
		or day.settle_skip(1) == null or day.advance_morning(1) == null
	):
		return false
	day.begin_stream()
	var streaming := _values(day.get_snapshot())
	if (
		day.settle_stream(1, 12) != null or day.settle_stream(2, -1) != null
		or day.settle_skip(2) != null
		or day.preview_morning(2) != null or day.advance_morning(2) != null
		or day.get_day_result() != null or _values(day.get_snapshot()) != streaming
	):
		return false
	var result := day.settle_stream(2, 12)
	if result == null:
		return false
	var settled := _values(day.get_snapshot())
	if (
		day.settle_stream(2, 12) != null or day.settle_skip(2) != null
		or day.preview_morning(1) != null or day.advance_morning(1) != null
		or day.preview_launch() != null or day.begin_stream() or day.skip_stream()
		or not _reject_expected(day, NAP, 1, Reason.PREPARATION_CLOSED)
		or _values(day.get_snapshot()) != settled
		or _result_values(day.get_day_result()) != _result_values(result)
	):
		return false
	if day.advance_morning(2) == null:
		return false
	var morning := _values(day.get_snapshot())
	return (
		day.advance_morning(2) == null and day.advance_morning(3) == null
		and day.get_day_result() == null and _values(day.get_snapshot()) == morning
	)


func _settlement_snapshot_isolation() -> bool:
	var day := DayModel.new()
	day.begin_stream()
	var result := day.settle_stream(1, 12)
	var expected := [1, Outcome.STREAMED, 0, 12, 12, 8, 5, 8, 6]
	if _result_values(result) != expected:
		return false
	result.balance_after = 99
	var redisplayed := day.get_day_result()
	if _result_values(redisplayed) != expected:
		return false
	redisplayed.vigor_after = 99
	var before_preview := _values(day.get_snapshot())
	var preview := day.preview_morning(1)
	if _values(preview) != [Phase.PREPARING, 2, 12, 6, 8, 9, 0, 0, false, false]:
		return false
	var expected_morning := _values(preview)
	preview.coins = 99
	preview.vigor = 99
	if (
		_values(day.get_snapshot()) != before_preview
		or _result_values(day.get_day_result()) != expected
		or _values(day.preview_morning(1)) != expected_morning
	):
		return false
	var advanced := day.advance_morning(1)
	if _values(advanced) != expected_morning:
		return false
	advanced.ap = 0
	return _values(day.get_snapshot()) == expected_morning


func _wallet_across_days() -> bool:
	var day := _prepared_day()
	day.begin_stream()
	day.settle_stream(1, 12)
	day.advance_morning(1)
	day.skip_stream()
	if (
		_result_values(day.settle_skip(2)) != [2, Outcome.SKIPPED, 12, 0, 12, 6, 6, 4, 4]
		or _values(day.advance_morning(2)) != [Phase.PREPARING, 3, 12, 6, 9, 7, 4, 1, false, false]
	):
		return false
	day.begin_stream()
	return (
		_result_values(day.settle_stream(3, 4)) == [3, Outcome.STREAMED, 12, 4, 16, 9, 6, 7, 5]
		and day.get_snapshot().coins == 16
	)


func _prepared_day() -> DayModel:
	var day := DayModel.new()
	day.apply_activity(TRAIN)
	day.apply_activity(TRAIN)
	day.apply_activity(POST)
	day.apply_activity(TOPIC)
	return day


func _close_once(day: DayModel, start_stream: bool) -> bool:
	var expected := _values(day.get_snapshot())
	expected[0] = Phase.STREAMING if start_stream else Phase.SKIPPED
	var closed := day.begin_stream() if start_stream else day.skip_stream()
	if not closed or _values(day.get_snapshot()) != expected:
		return false
	var repeated := day.begin_stream() if start_stream else day.skip_stream()
	var conflicting := day.skip_stream() if start_stream else day.begin_stream()
	return (
		not repeated and not conflicting
		and day.preview_launch() == null
		and _reject_expected(day, POST, 1, Reason.PREPARATION_CLOSED)
		and _reject_expected(day, UNKNOWN, 0, Reason.PREPARATION_CLOSED)
		and _values(day.get_snapshot()) == expected
	)


func _apply_expected(day: DayModel, id: StringName, cost: int, expected: Array) -> bool:
	var before := _values(day.get_snapshot())
	var preview := day.preview_activity(id)
	if (
		not _matches_result(preview, id, cost, Reason.NONE, expected)
		or _values(day.get_snapshot()) != before
	):
		printerr("Unexpected preview for ", id)
		return false
	var committed := day.apply_activity(id)
	if (
		not _matches_result(committed, id, cost, Reason.NONE, expected)
		or _values(preview.resulting_snapshot) != _values(committed.resulting_snapshot)
		or _values(day.get_snapshot()) != expected
	):
		printerr("Unexpected commit for ", id)
		return false
	return true


func _reject_expected(day: DayModel, id: StringName, cost: int, reason: int) -> bool:
	var before := _values(day.get_snapshot())
	if (
		not _matches_result(day.preview_activity(id), id, cost, reason, before)
		or _values(day.get_snapshot()) != before
		or not _matches_result(day.apply_activity(id), id, cost, reason, before)
		or _values(day.get_snapshot()) != before
	):
		printerr("Unexpected rejection for ", id, " (expected reason ", reason, ")")
		return false
	return true


func _matches_result(
	result: DayModel.ActivityResult, id: StringName, cost: int, reason: int, expected: Array
) -> bool:
	return (
		result != null and result.resulting_snapshot != null
		and result.activity_id == id and result.ap_cost == cost
		and result.available == (reason == Reason.NONE) and result.rejection_reason == reason
		and _values(result.resulting_snapshot) == expected
	)


func _day_values(
	ap: int, vigor: int, concentration: int, progress: int, level: int, post: bool, topic: bool
) -> Array:
	return [Phase.PREPARING, 1, 0, ap, vigor, concentration, progress, level, post, topic]


func _values(snapshot: DayModel.DaySnapshot) -> Array:
	if snapshot == null:
		return []
	return [
		snapshot.phase, snapshot.day_number, snapshot.coins, snapshot.ap,
		snapshot.vigor, snapshot.concentration, snapshot.mastery_progress,
		snapshot.mastery_level, snapshot.post_published, snapshot.topic_prepared,
	]


func _result_values(result: DayModel.DayResult) -> Array:
	if result == null:
		return []
	return [
		result.day_number, result.outcome, result.balance_before, result.income, result.balance_after,
		result.vigor_before, result.vigor_after, result.concentration_before, result.concentration_after,
	]


func _launch_values(snapshot: DayModel.LaunchSnapshot) -> Array:
	if snapshot == null:
		return []
	return [
		snapshot.day_number, snapshot.vigor, snapshot.concentration, snapshot.mastery_level,
		snapshot.post_published, snapshot.topic_prepared,
	]
