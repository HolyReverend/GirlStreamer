class_name DayState
extends RefCounted
## Owns preparation, evening settlement and morning rollover for one run.

enum Phase { PREPARING, STREAMING, SKIPPED, RESULTS }
enum DayOutcome { STREAMED, SKIPPED }
enum RejectionReason {
	NONE,
	PREPARATION_CLOSED,
	UNKNOWN_ACTIVITY,
	ALREADY_USED,
	MASTERY_CAP,
	INSUFFICIENT_AP,
}

const MORNING_AP := 6
const STARTING_CONDITION := 8
const CONDITION_MAX := 10
const MASTERY_THRESHOLD := 4
const TRAINING_PROGRESS := 2
const STREAM_VIGOR_LOAD := 3
const STREAM_CONCENTRATION_LOAD := 2
const SLEEP_RECOVERY := 3

const ACTIVITY_COSTS: Dictionary[StringName, int] = {
	&"publish_post": 1,
	&"prepare_topic": 1,
	&"train_snake": 2,
	&"watch_anime": 1,
	&"take_nap": 1,
}


class DaySnapshot extends RefCounted:
	var phase: Phase = Phase.PREPARING
	var day_number: int = 1
	var coins: int
	var ap: int
	var vigor: int
	var concentration: int
	var mastery_progress: int
	var mastery_level: int
	var post_published: bool
	var topic_prepared: bool

	func copy() -> DaySnapshot:
		var snapshot := DaySnapshot.new()
		snapshot.phase = phase
		snapshot.day_number = day_number
		snapshot.coins = coins
		snapshot.ap = ap
		snapshot.vigor = vigor
		snapshot.concentration = concentration
		snapshot.mastery_progress = mastery_progress
		snapshot.mastery_level = mastery_level
		snapshot.post_published = post_published
		snapshot.topic_prepared = topic_prepared
		return snapshot


class ActivityResult extends RefCounted:
	var activity_id: StringName
	var ap_cost: int
	var available: bool
	var rejection_reason: RejectionReason
	var resulting_snapshot: DaySnapshot


class DayResult extends RefCounted:
	var day_number: int
	var outcome: DayOutcome
	var balance_before: int
	var income: int
	var balance_after: int
	var vigor_before: int
	var vigor_after: int
	var concentration_before: int
	var concentration_after: int

	func copy() -> DayResult:
		var result := DayResult.new()
		result.day_number = day_number
		result.outcome = outcome
		result.balance_before = balance_before
		result.income = income
		result.balance_after = balance_after
		result.vigor_before = vigor_before
		result.vigor_after = vigor_after
		result.concentration_before = concentration_before
		result.concentration_after = concentration_after
		return result


class LaunchSnapshot extends RefCounted:
	var day_number: int
	var vigor: int
	var concentration: int
	var mastery_level: int
	var post_published: bool
	var topic_prepared: bool

	func copy() -> LaunchSnapshot:
		var snapshot := LaunchSnapshot.new()
		snapshot.day_number = day_number
		snapshot.vigor = vigor
		snapshot.concentration = concentration
		snapshot.mastery_level = mastery_level
		snapshot.post_published = post_published
		snapshot.topic_prepared = topic_prepared
		return snapshot


var _day := DaySnapshot.new()
var _day_result: DayResult


func _init() -> void:
	_day.ap = MORNING_AP
	_day.vigor = STARTING_CONDITION
	_day.concentration = STARTING_CONDITION


func get_snapshot() -> DaySnapshot:
	return _day.copy()


func preview_activity(id: StringName) -> ActivityResult:
	var result := ActivityResult.new()
	result.activity_id = id
	result.ap_cost = ACTIVITY_COSTS.get(id, 0)
	result.resulting_snapshot = get_snapshot()
	result.rejection_reason = _rejection_reason(id, result.ap_cost)
	result.available = result.rejection_reason == RejectionReason.NONE
	if not result.available:
		return result

	var next := result.resulting_snapshot
	next.ap -= result.ap_cost
	match id:
		&"publish_post":
			next.post_published = true
		&"prepare_topic":
			next.topic_prepared = true
			next.concentration = maxi(0, next.concentration - 1)
		&"train_snake":
			next.vigor = maxi(0, next.vigor - 1)
			next.concentration = maxi(0, next.concentration - 2)
			next.mastery_progress = mini(MASTERY_THRESHOLD, next.mastery_progress + TRAINING_PROGRESS)
			next.mastery_level = int(next.mastery_progress >= MASTERY_THRESHOLD)
		&"watch_anime":
			next.concentration = mini(CONDITION_MAX, next.concentration + 2)
		&"take_nap":
			next.vigor = mini(CONDITION_MAX, next.vigor + 2)
	return result


func apply_activity(id: StringName) -> ActivityResult:
	var result := preview_activity(id)
	if result.available:
		_day = result.resulting_snapshot.copy()
	return result


## Capture launch conditions while the day controller tries to start its candidate.
func preview_launch() -> LaunchSnapshot:
	if _day.phase != Phase.PREPARING:
		return null
	var snapshot := LaunchSnapshot.new()
	snapshot.day_number = _day.day_number
	snapshot.vigor = _day.vigor
	snapshot.concentration = _day.concentration
	snapshot.mastery_level = _day.mastery_level
	snapshot.post_published = _day.post_published
	snapshot.topic_prepared = _day.topic_prepared
	return snapshot


## Commit after the stream candidate has started successfully.
func begin_stream() -> bool:
	return _close_preparation(Phase.STREAMING)


func skip_stream() -> bool:
	return _close_preparation(Phase.SKIPPED)


func settle_stream(day: int, donation_total: int) -> DayResult:
	if _day.phase != Phase.STREAMING or _day.day_number != day or donation_total < 0:
		return null
	return _settle(DayOutcome.STREAMED, donation_total)


func settle_skip(day: int) -> DayResult:
	if _day.phase != Phase.SKIPPED or _day.day_number != day:
		return null
	return _settle(DayOutcome.SKIPPED, 0)


func get_day_result() -> DayResult:
	return _day_result.copy() if _day_result != null else null


func preview_morning(completed_day: int) -> DaySnapshot:
	if _day.phase != Phase.RESULTS or _day.day_number != completed_day:
		return null
	var next := get_snapshot()
	next.phase = Phase.PREPARING
	next.day_number += 1
	next.ap = MORNING_AP
	next.vigor = clampi(next.vigor + SLEEP_RECOVERY, 0, CONDITION_MAX)
	next.concentration = clampi(next.concentration + SLEEP_RECOVERY, 0, CONDITION_MAX)
	next.post_published = false
	next.topic_prepared = false
	return next


func advance_morning(completed_day: int) -> DaySnapshot:
	var next := preview_morning(completed_day)
	if next == null:
		return null
	_day = next
	_day_result = null
	return next.copy()


func _settle(outcome: DayOutcome, income: int) -> DayResult:
	var result := DayResult.new()
	result.day_number = _day.day_number
	result.outcome = outcome
	result.balance_before = _day.coins
	result.income = income
	result.balance_after = result.balance_before + income
	result.vigor_before = _day.vigor
	result.vigor_after = result.vigor_before
	result.concentration_before = _day.concentration
	result.concentration_after = result.concentration_before
	if outcome == DayOutcome.STREAMED:
		result.vigor_after = clampi(result.vigor_before - STREAM_VIGOR_LOAD, 0, CONDITION_MAX)
		result.concentration_after = clampi(
			result.concentration_before - STREAM_CONCENTRATION_LOAD, 0, CONDITION_MAX
		)

	_day.coins = result.balance_after
	_day.vigor = result.vigor_after
	_day.concentration = result.concentration_after
	_day.phase = Phase.RESULTS
	_day_result = result
	return result.copy()


func _rejection_reason(id: StringName, ap_cost: int) -> RejectionReason:
	if _day.phase != Phase.PREPARING:
		return RejectionReason.PREPARATION_CLOSED
	if not ACTIVITY_COSTS.has(id):
		return RejectionReason.UNKNOWN_ACTIVITY
	if (id == &"publish_post" and _day.post_published) or (id == &"prepare_topic" and _day.topic_prepared):
		return RejectionReason.ALREADY_USED
	if id == &"train_snake" and _day.mastery_progress >= MASTERY_THRESHOLD:
		return RejectionReason.MASTERY_CAP
	if _day.ap < ap_cost:
		return RejectionReason.INSUFFICIENT_AP
	return RejectionReason.NONE


func _close_preparation(next_phase: Phase) -> bool:
	if _day.phase != Phase.PREPARING:
		return false
	_day.phase = next_phase
	return true
