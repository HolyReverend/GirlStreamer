extends RefCounted
## Final values assembled once by the session before closing presentation.

const Audience = preload("res://prototype/stream/audience_state.gd")

class SelectedReaction extends RefCounted:
	var style: StringName
	var source_kind: StringName
	var source_caption: String

class Highlight extends RefCounted:
	var category: StringName
	var source_id: int
	var time_msec: int
	var explanation: String
	var delta: Vector3

var elapsed_seconds: float
var duration_seconds: float
var total_food: int
var attempts_started: int
var collisions: int
var boards_completed: int
var best_score: int
var messages_enabled: bool
var questions_shown: int
var questions_answered: int
var questions_expired: int
var questions_cancelled: int
var answer_times_seconds: Array[float]
var question_latency_seconds: float
var donation_question_latency_seconds: float
var reaction_latency_seconds: float
# Order: shown, answered, expired, cancelled.
var reaction_counts: Vector4i
var donation_question_counts: Vector4i
var choice_totals: Vector4i
var initial_viewers: int
var audience: Audience.Snapshot
var donation_count: int
var donation_total: int
var selected_reactions: Array[SelectedReaction]
var highlights: Array[Highlight]
