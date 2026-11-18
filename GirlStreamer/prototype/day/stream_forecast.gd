extends RefCounted
## Evening tuning shared by the preparation forecast and stream effects.

const Audience = preload("res://prototype/stream/audience_state.gd")
const ANNOUNCEMENT_VIEWERS_PER_GROUP := 1
const ANNOUNCEMENT_VIEWERS := ANNOUNCEMENT_VIEWERS_PER_GROUP * Audience.GROUP_COUNT
const QUESTION_WINDOW_FLOOR_MSEC := 5000
const TOPIC_TITLE := "Мой рекорд в Змейке"
const TOPIC_QUESTION := "Как собираешься побить свой рекорд в Змейке?"


static func warning_cells(mastery_level: int, vigor: int) -> int:
	if mastery_level < 1 or vigor <= 2:
		return 0
	return 1 if vigor <= 5 else 2


static func question_window_scale(concentration: int) -> float:
	if concentration <= 2:
		return 0.8
	return 0.9 if concentration <= 5 else 1.0
