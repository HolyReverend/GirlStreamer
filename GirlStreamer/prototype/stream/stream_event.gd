class_name StreamEvent
extends RefCounted

enum Kind { FOOD, MILESTONE, RECORD, COLLISION, BOARD_COMPLETED }

var id: int
var kind: Kind
var time_msec: int
var score: int
var reason: StringName
var attempt_id: int


func _init(
	event_id: int, event_kind: Kind, at_msec: int, event_score: int,
	event_reason: StringName, event_attempt_id: int = 0
) -> void:
	id = event_id
	kind = event_kind
	time_msec = at_msec
	score = event_score
	reason = event_reason
	attempt_id = event_attempt_id
