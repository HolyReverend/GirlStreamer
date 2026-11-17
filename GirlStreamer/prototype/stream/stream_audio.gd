extends Node

const QUESTION_PATH := "res://prototype/audio/question.wav"
const DONATION_PATH := "res://prototype/audio/donation.wav"
const FINISH_PATH := "res://prototype/audio/finish.wav"

var _muted := false
var _gameplay_player: AudioStreamPlayer
var _finish_player: AudioStreamPlayer
var _question: AudioStreamWAV
var _donation: AudioStreamWAV
var _finish: AudioStreamWAV


func _ready() -> void:
	_gameplay_player = AudioStreamPlayer.new()
	_finish_player = AudioStreamPlayer.new()
	add_child(_gameplay_player)
	add_child(_finish_player)
	_question = _load_cue(QUESTION_PATH)
	_donation = _load_cue(DONATION_PATH)
	_finish = _load_cue(FINISH_PATH)


func _exit_tree() -> void:
	stop_all()


func set_muted(value: bool) -> void:
	_muted = value
	if _muted:
		stop_all()


func play_question() -> void:
	_play_gameplay(_question)


func play_donation() -> void:
	_play_gameplay(_donation)


func play_finish() -> void:
	_gameplay_player.stop()
	if not _muted and _finish != null:
		_finish_player.stream = _finish
		_finish_player.play()


func stop_all() -> void:
	_gameplay_player.stop()
	_finish_player.stop()


func _play_gameplay(cue: AudioStreamWAV) -> void:
	if _muted or cue == null:
		return
	_gameplay_player.stop()
	_gameplay_player.stream = cue
	_gameplay_player.play()


func _load_cue(path: String) -> AudioStreamWAV:
	# A standalone test can run before the WAV assets have been imported.
	if FileAccess.file_exists(path):
		return AudioStreamWAV.load_from_file(path)
	if ResourceLoader.exists(path, "AudioStreamWAV"):
		return load(path) as AudioStreamWAV
	return null