class_name HeroWebcam
extends Control

const AUTOMATIC_DURATION_MSEC := 2000
const REPLY_DURATION_MSEC := 3000
const AUTOMATIC_PRIORITY := {&"happy": 1, &"shy": 2, &"sad": 3}
const STATE_LABELS := {
	&"neutral": "Спокойна",
	&"focused": "Сосредоточена",
	&"happy": "Радуется",
	&"sad": "Огорчена",
	&"shy": "Смущена",
}
const CAPTIONS := {&"happy": "Есть!", &"sad": "Эх, ещё раз!", &"shy": "Спасибо за вопрос!"}
const FACE_COLOR := Color("#ecc0a3")
const HAIR_COLOR := Color("#464064")
const FEATURE_COLOR := Color("#352936")

var _playing := false
var _stopped := false
var _emotion: StringName = &"neutral"
var _transient: StringName = &""
var _deadline_msec := 0
var _goodbye := ""
var _reply := ""
var _reply_emotion: StringName = &""
var _reply_deadline_msec := 0

@onready var _state_label: Label = $StateLabel
@onready var _caption_label: Label = $CaptionLabel


func _ready() -> void:
	resized.connect(queue_redraw)
	_update_view()


func reset() -> void:
	_playing = false
	_stopped = false
	_clear_presentation()


func get_emotion() -> StringName:
	return _emotion


func set_playing(playing: bool) -> void:
	if _stopped:
		return
	_playing = playing
	_update_view()


func show_automatic(emotion: StringName, now_msec: int) -> void:
	if _stopped:
		return
	tick(now_msec)
	if not AUTOMATIC_PRIORITY.has(emotion):
		return
	if _reply.is_empty() and AUTOMATIC_PRIORITY[emotion] < AUTOMATIC_PRIORITY.get(_transient, 0):
		return
	_transient = emotion
	_deadline_msec = now_msec + AUTOMATIC_DURATION_MSEC
	_update_view()


func show_reply(text: String, emotion: StringName, now_msec: int) -> void:
	if _stopped or text.is_empty() or not STATE_LABELS.has(emotion):
		return
	tick(now_msec)
	_reply = text
	_reply_emotion = emotion
	_reply_deadline_msec = now_msec + REPLY_DURATION_MSEC
	_update_view()


func show_goodbye(text: String) -> void:
	_playing = false
	_stopped = true
	_clear_presentation()
	_goodbye = text
	_update_view()


func tick(now_msec: int) -> void:
	var changed := false
	if _transient != &"" and now_msec >= _deadline_msec:
		_transient = &""
		_deadline_msec = 0
		changed = true
	if not _reply.is_empty() and now_msec >= _reply_deadline_msec:
		_reply = ""
		_reply_emotion = &""
		_reply_deadline_msec = 0
		changed = true
	if changed:
		_update_view()


func stop() -> void:
	_playing = false
	_stopped = true
	_clear_presentation()


func _clear_presentation() -> void:
	_goodbye = ""
	_transient = &""
	_deadline_msec = 0
	_reply = ""
	_reply_emotion = &""
	_reply_deadline_msec = 0
	_update_view()


func _update_view() -> void:
	if not _goodbye.is_empty():
		_emotion = &"happy"
	elif not _reply.is_empty():
		_emotion = _reply_emotion
	elif _transient != &"":
		_emotion = _transient
	else:
		_emotion = &"focused" if _playing else &"neutral"
	if is_node_ready():
		_state_label.text = STATE_LABELS[_emotion]
		if not _goodbye.is_empty():
			_caption_label.text = _goodbye
		else:
			_caption_label.text = _reply if not _reply.is_empty() else CAPTIONS.get(_emotion, "")
		queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5, 53.0)
	draw_circle(center + Vector2(0, -2), 42.0, HAIR_COLOR, true, -1.0, true)
	draw_circle(center + Vector2(0, 3), 32.0, FACE_COLOR, true, -1.0, true)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-33, -7), center + Vector2(-25, -29), center + Vector2(0, -38),
		center + Vector2(25, -29), center + Vector2(32, -13), center + Vector2(4, -23),
	]), HAIR_COLOR)

	for side: int in [-1, 1]:
		var eye := center + Vector2(13 * side, 1)
		var brow := eye + Vector2(0, -9)
		if _emotion == &"focused":
			draw_line(brow + Vector2(5 * side, -2), brow + Vector2(-5 * side, 2),
				FEATURE_COLOR, 2.0, true)
			draw_line(eye - Vector2(4, 0), eye + Vector2(4, 0), FEATURE_COLOR, 3.0, true)
		elif _emotion == &"shy":
			draw_line(eye + Vector2(-4, -1), eye + Vector2(4, 2), FEATURE_COLOR, 2.0, true)
			draw_circle(eye + Vector2(5 * side, 8), 4.0, Color("#d98281"), true, -1.0, true)
		else:
			var brow_slant := 4 if _emotion == &"sad" else 0
			draw_line(brow + Vector2(5 * side, 0), brow + Vector2(-5 * side, -brow_slant),
				FEATURE_COLOR, 2.0, true)
			draw_circle(eye, 3.0, FEATURE_COLOR, true, -1.0, true)

	match _emotion:
		&"happy":
			draw_arc(center + Vector2(0, 12), 9.0, 0.0, PI, 16, FEATURE_COLOR, 2.5, true)
		&"sad":
			draw_arc(center + Vector2(0, 23), 9.0, PI, TAU, 16, FEATURE_COLOR, 2.5, true)
		&"shy":
			draw_arc(center + Vector2(0, 14), 4.0, 0.0, PI, 12, FEATURE_COLOR, 2.0, true)
		_:
			draw_line(center + Vector2(-6, 16), center + Vector2(6, 16), FEATURE_COLOR, 2.0, true)
