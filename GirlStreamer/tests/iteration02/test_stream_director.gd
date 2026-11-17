extends SceneTree

const Director = preload("res://prototype/stream/stream_director.gd")
const Content = preload("res://prototype/stream/stream_content.gd")
const Event = preload("res://prototype/stream/stream_event.gd")

var _director: Director
var _requests: Array[Content.ChoiceDefinition] = []
var _opened: Array[Content.ChoiceDefinition] = []
var _reject := false
var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_timing()
	_test_donation_during_question()
	_test_priority_and_copy()
	_test_expiry_and_watermarks()
	_test_attempts_and_variants()
	_test_cap_and_lifecycle()
	_director.free()
	if _failures == 0:
		print("ITER02_STAGE04_DIRECTOR_PASS (%d checks)" % _checks)
	quit(1 if _failures else 0)


func _setup(cap: int = 8, enabled: bool = true) -> void:
	if _director != null:
		_director.free()
	_director = Director.new()
	_director.configure(_open)
	_director.opening_cap = cap
	_director.reset()
	_director.start(enabled)
	_director.on_attempt_started(1)
	_requests.clear()
	_opened.clear()
	_reject = false


func _open(definition: Content.ChoiceDefinition, _now: int) -> bool:
	_requests.append(definition.snapshot())
	if _reject:
		return false
	if definition.kind == &"question":
		definition.nick = "Chat"
	definition.id = _opened.size() + 1
	_check(definition.is_valid(), "Accepted definition validates")
	_opened.append(definition.snapshot())
	return true


func _resolve(id: int, at_msec: int, outcome: StringName = &"answered") -> void:
	var result := Content.ChoiceResolution.new()
	result.choice_id = id
	result.resolved_at_msec = at_msec
	result.outcome = outcome
	_director.on_choice_resolved(result)


func _event(id: int, kind: Event.Kind, at_msec: int, score: int = 5, attempt: int = 1) -> void:
	_director.submit_event(Event.new(id, kind, at_msec, score, &"", attempt))


func _donation(id: int) -> Content.ChoiceDefinition:
	var question := Content.get_questions()[0]
	return Content.ChoiceDefinition.new(
		0, question.id, &"donation_question", question.prompt, "Donor", question.options, 6000, id, 0,
		0, &"donation", 5
	)


func _test_timing() -> void:
	for outcome in [&"answered", &"expired"]:
		_setup()
		_director.first_delay_seconds = 1.0
		_director.gap_seconds = 1.0
		_director.tick(19999, true)
		_check(_requests.is_empty(), "First delay is snapshotted")
		_director.tick(20000, true)
		_resolve(99, 21000)
		_director.tick(39999, true)
		_check(_opened.size() == 1, "First opening at equality and no overlap")
		_resolve(1, 21000 if outcome == &"answered" else 26000, outcome)
		_director.tick(39999, true)
		_check(_opened.size() == 1, "Opening gap is snapshotted")
		_director.tick(40000, true)
		_check(_opened.size() == 2, "Resolution time does not move the opening deadline")
	_setup()
	_director.tick(20000, true)
	_resolve(1, 21000)
	_director.tick(40000, false)
	_director.tick(47000, true)
	_resolve(2, 48000)
	_director.tick(66999, true)
	_check(_opened.size() == 2, "Delayed opening anchors its own gap")
	_director.tick(67000, true)
	_check(_opened.size() == 3, "No missed openings are replayed")


func _test_donation_during_question() -> void:
	_setup()
	var viewers := [30]
	_director.set_viewer_count_provider(func() -> int: return viewers[0])
	_director.tick(30000, true)
	_director.submit_donation_question(_donation(1), 31000)
	_director.tick(32000, true)
	_check(_opened.size() == 1, "Donation does not replace an open question")
	_resolve(1, 36000, &"expired")
	_director.tick(49999, true)
	_check(_opened.size() == 1, "Donation respects the shared gap")
	viewers[0] = 80
	_director.tick(50000, true)
	_check(_opened.size() == 2 and _opened.back().kind == &"donation_question", "Donation survives question and gap")
	_check(_opened.back().window_msec == 5500 and _opened.back().donation_amount == 5, "Donor window samples latest audience and keeps amount")
	_setup()
	_director.tick(30000, true)
	_resolve(1, 33000)
	_event(1, Event.Kind.RECORD, 49000, 6)
	_director.tick(49999, true)
	_check(_opened.size() == 1, "Fresh reaction waits for the shared gap")
	_director.tick(50000, true)
	_check(_opened.size() == 2 and _opened.back().kind == &"reaction", "Fresh reaction opens at the shared boundary")


func _test_priority_and_copy() -> void:
	_setup()
	var donation := _donation(1)
	_director.submit_donation_question(donation, 29000)
	donation.nick = "Changed"
	_director.submit_donation_question(_donation(2), 29001)
	_event(1, Event.Kind.MILESTONE, 29000)
	_check(_requests.is_empty(), "Submissions do not open synchronously")
	_reject = true
	_director.tick(30000, true)
	_check(_requests.size() == 1 and _requests.back().kind == &"donation_question", "Only donation requested on rejection")
	_reject = false
	_director.tick(30001, true)
	_check(
		_opened.size() == 1 and _opened.back().source_event_id == 1 and _opened.back().nick == "Donor",
		"Retry retains the older copied candidate"
	)
	_resolve(1, 31000)
	_director.submit_donation_question(_donation(2), 55000)
	_check(_director._pending_donation == null, "An overflowed donation ID cannot be resubmitted")
	_director.submit_donation_question(_donation(3), 88000)
	_event(2, Event.Kind.COLLISION, 89000, 4)
	_event(3, Event.Kind.BOARD_COMPLETED, 89500)
	_director.tick(89500, false)
	_check(_opened.size() == 2 and _opened.back().kind == &"reaction" and _opened.back().source_event_kind == &"board_completed", "Ineligible donation and low-score loss do not block board completion")


func _test_expiry_and_watermarks() -> void:
	_setup()
	_director.reaction_cooldown_seconds = 1.0
	_director.reaction_ttl_seconds = 1.0
	_director.donation_ttl_seconds = 1.0
	_director.reset()
	_director.start(true)
	_director.on_attempt_started(1)
	_event(1, Event.Kind.RECORD, 29000)
	_event(2, Event.Kind.RECORD, 30000)
	_event(1, Event.Kind.COLLISION, 30000)
	_director.submit_donation_question(_donation(1), 29000)
	_director.submit_donation_question(_donation(2), 30000)
	_director.tick(30000, true)
	_check(_opened.size() == 1 and _opened.back().source_event_id == 2, "Donation replacement at exact TTL")
	_setup()
	_director.reaction_cooldown_seconds = 1.0
	_director.reaction_ttl_seconds = 1.0
	_director.reset()
	_director.start(true)
	_director.on_attempt_started(1)
	_event(1, Event.Kind.RECORD, 29000)
	_event(2, Event.Kind.RECORD, 30000)
	_event(1, Event.Kind.COLLISION, 30000)
	_director.tick(30000, true)
	_check(
		_opened.size() == 1 and _opened.back().kind == &"reaction" and _opened.back().source_event_id == 2,
		"Reaction replacement at exact TTL/cooldown with out-of-order event ignored"
	)


func _test_attempts_and_variants() -> void:
	_setup()
	_event(1, Event.Kind.COLLISION, 29000)
	_director.on_attempt_started(2)
	_director.tick(30000, true)
	_check(
		_opened.size() == 1 and _opened.back().kind == &"question" and _opened.back().source_attempt_id == 1,
		"Retry drops pending reaction and retains retrospective loss"
	)
	_resolve(1, 31000)
	_event(2, Event.Kind.COLLISION, 88999, 5, 2)
	_director.tick(88999, false)
	_check(_opened.size() == 1, "Cooldown survives retry and early rejection does not refresh it")
	_event(3, Event.Kind.COLLISION, 89000, 5, 2)
	_director.tick(89000, false)
	_check(
		_opened.size() == 2 and _opened.back().template_id == &"loss_1" and _opened.back().window_msec == 3000
		and _opened.back().source_event_kind == &"collision" and _opened.back().source_attempt_id == 2,
		"Loss reaction uses first variant and snapshots its source"
	)
	_director.on_attempt_started(3)
	_event(4, Event.Kind.RECORD, 90000, 6, 3)
	_director.tick(90000, true)
	_check(_opened.size() == 2, "An already-open reaction survives retry")
	_resolve(2, 91000)
	_event(5, Event.Kind.COLLISION, 149000, 5, 3)
	_director.tick(149000, false)
	_check(_opened.size() == 3 and _opened.back().template_id == &"loss_2", "Accepted loss advances its variant")


func _test_cap_and_lifecycle() -> void:
	_setup(2)
	_director.tick(30000, true)
	_resolve(1, 31000)
	_event(1, Event.Kind.RECORD, 55000)
	_director.submit_donation_question(_donation(1), 55000)
	_director.tick(56000, true)
	_check(_opened.size() == 2 and _director._pending_reaction == null, "Final opening clears other pending work")
	_resolve(2, 57000)
	_event(2, Event.Kind.COLLISION, 120000)
	_director.submit_donation_question(_donation(2), 120000)
	_director.tick(120000, true)
	_check(_opened.size() == 2 and _director._pending_donation == null, "Cap prevents later admission")
	_director.stop()
	_director.reset()
	_director.start(true)
	_director.on_attempt_started(1)
	_event(1, Event.Kind.RECORD, 29000)
	_director.tick(30000, true)
	_check(_opened.size() == 3 and _opened.back().template_id == &"achievement_1", "Reset clears cap use and watermarks")
	_setup(8, false)
	_event(1, Event.Kind.RECORD, 29000)
	_director.submit_donation_question(_donation(1), 29000)
	_director.tick(30000, true)
	_check(_requests.is_empty() and _director._pending_reaction == null and _director._pending_donation == null, "Disabled mode does not queue")
	_director.opening_cap = 9
	_check(not _director.has_valid_settings(), "Invalid opening cap rejected")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr(message)
