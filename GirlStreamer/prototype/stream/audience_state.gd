extends RefCounted

const GROUP_COUNT := 3
const INITIAL_COUNT := 10
const INITIAL_TOTAL := INITIAL_COUNT * GROUP_COUNT
const MAX_VIEWERS := 200
const WHOLE_UNIT_TOLERANCE := 1e-9
const REACTION_STYLES: Array[StringName] = [&"competitive", &"humor", &"flirt"]


class Snapshot extends RefCounted:
	var counts: Vector3i
	var impressions: Vector3
	var precise_impressions: Array[float]
	var carries: Array[float]
	var total: int
	var peak: int
	var step_count: int
	var style_uses: Dictionary[StringName, int]


var _counts: Vector3i
var _impressions: Array[float]
var _carries: Array[float]
var _style_uses: Dictionary[StringName, int]
var _last_effect_id: int
var _step_count: int
var _peak: int


func _init() -> void:
	reset()


func reset(opening_bonus_per_group: int = 0) -> void:
	var opening_count := INITIAL_COUNT + clampi(opening_bonus_per_group, 0, MAX_VIEWERS - INITIAL_COUNT)
	_counts = Vector3i.ONE * opening_count
	_impressions = [50.0, 50.0, 50.0]
	_carries = [0.0, 0.0, 0.0]
	_style_uses.clear()
	_last_effect_id = 0
	_step_count = 0
	_peak = _get_total()


func apply_effect(effect_id: int, effects: Vector3, repeat_key: StringName = &"") -> bool:
	if effect_id <= _last_effect_id:
		return false
	if not effects.is_finite():
		push_error("AudienceState: non-finite effect")
		return false
	if repeat_key != &"" and repeat_key not in REACTION_STYLES:
		push_error("AudienceState: invalid reaction style")
		return false
	var uses := 1
	if repeat_key != &"":
		uses = _style_uses.get(repeat_key, 0) + 1
		_style_uses[repeat_key] = uses
	for group in range(GROUP_COUNT):
		var change: float = effects[group]
		if change > 0.0:
			change /= uses
		_impressions[group] = clampf(_impressions[group] + change, 0.0, 100.0)
	_last_effect_id = effect_id
	return true


func advance_second() -> void:
	for group in range(GROUP_COUNT):
		var impression := _impressions[group]
		var accumulated := _carries[group] + (impression - 40.0) / 200.0
		var whole := int(accumulated + signf(accumulated) * WHOLE_UNIT_TOLERANCE)
		var carry := accumulated - whole
		var count := clampi(_counts[group] + whole, 0, MAX_VIEWERS)
		# Snap only the rounding residue from crossing an integer boundary.
		if whole != 0 and absf(carry) <= WHOLE_UNIT_TOLERANCE:
			carry = 0.0
		if (count == 0 and carry < 0.0) or (count == MAX_VIEWERS and carry > 0.0):
			carry = 0.0
		_counts[group] = count
		_carries[group] = carry
		_impressions[group] = move_toward(impression, 50.0, 0.1)
	_step_count += 1
	_peak = maxi(_peak, _get_total())


func get_snapshot() -> Snapshot:
	var snapshot := Snapshot.new()
	snapshot.counts = _counts
	snapshot.impressions = Vector3(_impressions[0], _impressions[1], _impressions[2])
	snapshot.precise_impressions = _impressions.duplicate()
	snapshot.carries = _carries.duplicate()
	snapshot.style_uses = _style_uses.duplicate()
	snapshot.total = _get_total()
	snapshot.peak = _peak
	snapshot.step_count = _step_count
	return snapshot


func _get_total() -> int:
	return _counts.x + _counts.y + _counts.z
