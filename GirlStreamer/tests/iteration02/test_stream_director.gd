extends SceneTree

const Director = preload("res://prototype/stream/stream_director.gd")
const Choice = preload("res://prototype/stream/stream_choice.gd")
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
	_test_concentration_windows()
	_test_donation_during_question()
	_test_priority_and_copy()
	_test_expiry_and_watermarks()
	_test_attempts_and_variants()
	_test_cap_and_lifecycle()
	_test_prepared_content()
	_test_prepared_priority()
	_test_prepared_rejection_and_retry()
	_test_prepared_cap_and_lifecycle()
	_director.free()
	if _failures == 0:
		print("ITER02_STAGE04_DIRECTOR_PASS (%d checks)" % _checks)
	quit(1 if _failures else 0)


func _setup(
	cap: int = 8, enabled: bool = true, window_msec: int = 6000, scale: float = 1.0,
	prepared: Content.QuestionTemplate = null
) -> void:
	if _director != null:
		_director.free()
	_director = Director.new()
	_director.configure(_open)
	_director.opening_cap = cap
	_director.reset()
	_director.start(enabled, window_msec, scale, prepared)
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


func _test_concentration_windows() -> void:
	var scales: Array[float] = [1.0, 0.9, 0.8]
	var viewers: Array[int] = [30, 60, 130]
	var expected := [[6000, 5400, 5000], [5700, 5130, 5000], [5000, 5000, 5000]]
	for viewer_index in range(viewers.size()):
		var viewer_count := viewers[viewer_index]
		for tier in range(scales.size()):
			_setup(8, true, 6000, scales[tier])
			_director.set_viewer_count_provider(func() -> int: return viewer_count)
			_director.tick(20000, true)
			_check(
				_opened.size() == 1 and _opened[0].window_msec == expected[viewer_index][tier],
				"Ordinary window for %d viewers at scale %.2f" % [viewer_count, scales[tier]]
			)
	_setup(8, true, 6000, 0.9)
	_director.tick(20000, true)
	_check(_opened.size() == 1 and _opened[0].window_msec == 5400, "No provider uses the 6000 ms base")
	_setup(8, true, 4000, 0.8)
	_director.set_viewer_count_provider(func() -> int: return 130)
	_director.tick(20000, true)
	_check(_opened.size() == 1 and _opened[0].window_msec == 4000, "Custom window bypasses scale and floor")


func _test_donation_during_question() -> void:
	_setup(8, true, 6000, 0.9)
	var viewers := [30]
	_director.set_viewer_count_provider(func() -> int: return viewers[0])
	_director.tick(30000, true)
	_director.submit_donation_question(_donation(1), 31000)
	_director.tick(32000, true)
	_check(_opened.size() == 1, "Donation does not replace an open question")
	_resolve(1, 35400, &"expired")
	_director.tick(49999, true)
	_check(_opened.size() == 1, "Donation respects the shared gap")
	viewers[0] = 60
	_director.tick(50000, true)
	_check(_opened.size() == 2 and _opened.back().kind == &"donation_question", "Donation survives question and gap")
	_check(_opened.back().window_msec == 5130 and _opened.back().donation_amount == 5, "Donor window samples latest audience and keeps amount")
	var choice := Choice.new()
	_check(choice.try_open(_opened.back(), 50000), "Choice controller admits the sampled donor question")
	viewers[0] = 130
	_director.on_attempt_started(2)
	choice.tick(55129)
	_check(choice.is_open(), "Donor question stays open one millisecond before its sampled deadline")
	choice.tick(55130)
	var resolution := choice.get_last_resolution()
	_check(
		resolution != null and resolution.outcome == &"expired" and resolution.elapsed_msec == 5130,
		"Donor question expires at the sampled deadline after audience change and retry"
	)
	choice.free()
	_setup(8, true, 6000, 0.8)
	_director.tick(30000, true)
	_resolve(1, 33000)
	_event(1, Event.Kind.RECORD, 49000, 6)
	_director.tick(49999, true)
	_check(_opened.size() == 1, "Fresh reaction waits for the shared gap")
	_director.tick(50000, true)
	_check(
		_opened.size() == 2 and _opened.back().kind == &"reaction" and _opened.back().window_msec == 3000,
		"Fresh reaction opens at the shared boundary and keeps its window at low concentration"
	)


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


func _test_prepared_content() -> void:
	var ordinary := Content.get_questions()
	var prepared := Content.get_prepared_topic()
	_check(ordinary.size() == 12, "Prepared topic stays outside the ordinary catalog")
	_check(Content.validate_prepared_topic(prepared, ordinary).is_empty(), "Prepared content validates")
	var copy := prepared.options[0].snapshot()
	prepared.options[0].hint = ""
	_check(not copy.hint.is_empty() and copy.effects.x > 0, "Copied hint retains its gaming benefit")
	_check(not Content.validate_prepared_topic(prepared, ordinary).is_empty(), "Missing hint rejected")
	prepared = Content.get_prepared_topic()
	prepared.options[1].hint = copy.hint
	_check(not Content.validate_prepared_topic(prepared, ordinary).is_empty(), "Second hint rejected")
	prepared = Content.get_prepared_topic()
	prepared.options[0].effects = Vector3.ZERO
	_check(not Content.validate_prepared_topic(prepared, ordinary).is_empty(), "Hint without gaming benefit rejected")
	prepared = Content.get_prepared_topic()
	prepared.id = ordinary[0].id
	_check(not Content.validate_prepared_topic(prepared, ordinary).is_empty(), "Duplicate template ID rejected")
	prepared = Content.get_prepared_topic()
	prepared.options.pop_back()
	_check(not Content.validate_prepared_topic(prepared, ordinary).is_empty(), "Prepared topic needs three replies")
	_check(not Content.validate_prepared_topic(null, ordinary).is_empty(), "Missing prepared template rejected")


func _test_prepared_priority() -> void:
	var prepared := Content.get_prepared_topic()
	var hint := prepared.options[0].hint
	_setup(8, true, 6000, 0.9, prepared)
	prepared.options[0].hint = ""
	_director.set_viewer_count_provider(func() -> int: return 60)
	_director.submit_donation_question(_donation(1), 19990)
	_event(1, Event.Kind.RECORD, 19990)
	_director.tick(19999, true)
	_check(_requests.is_empty(), "Reservation waits for the common first delay")
	_director.tick(20000, true)
	_check(
		_opened.size() == 1 and _opened[0].template_id == prepared.id and _opened[0].kind == &"question",
		"Prepared ordinary question wins over an eligible donor and a nonterminal reaction"
	)
	_check(
		_opened.size() == 1 and _opened[0].source_event_id == 0 and _opened[0].source_attempt_id == 0
		and _opened[0].source_event_kind.is_empty() and _opened[0].options[0].hint == hint
		and _opened[0].window_msec == 5130,
		"Prepared opening has copied hint, live window and no attempt source"
	)
	_check(_director._pending_reaction != null, "Prepared opening leaves the fresh reaction pending")
	_resolve(1, 21000)
	_director.tick(40000, true)
	_check(
		_opened.size() == 2 and _opened.back().kind == &"donation_question" and _opened.back().donation_amount == 5,
		"Donor remains eligible after the prepared opening"
	)


func _test_prepared_rejection_and_retry() -> void:
	var prepared := Content.get_prepared_topic()
	_setup(8, true, 4000, 0.8, prepared)
	_director.submit_donation_question(_donation(1), 19800)
	_event(1, Event.Kind.COLLISION, 19900)
	_reject = true
	_director.tick(20000, false)
	_check(
		_requests.size() == 1 and _requests[0].template_id == prepared.id and _opened.is_empty(),
		"Rejection while waiting offers only the reserved topic"
	)
	_reject = false
	_director.tick(22000, false)
	_check(
		_opened.size() == 1 and _opened[0].template_id == prepared.id and _opened[0].window_msec == 4000,
		"Delayed admission wins over the terminal reaction and preserves a fixed window"
	)
	_director.on_attempt_started(2)
	_check(_director._pending_reaction == null, "Retry invalidates the pending terminal reaction")
	_resolve(1, 26000, &"expired")
	_director.tick(41999, true)
	_check(_opened.size() == 1, "Gap starts at successful admission")
	_director.tick(42000, true)
	_check(
		_opened.size() == 2 and _opened.back().kind == &"donation_question",
		"The donor resumes at the exact delayed gap boundary after Snake retry"
	)
	_setup(8, true, 6000, 1.0, prepared)
	_director.submit_donation_question(_donation(1), 19800)
	_director.tick(20000, false)
	_resolve(1, 26000, &"expired")
	_director.tick(65000, true)
	_check(
		_opened.size() == 2 and _opened.back().kind == &"question" and _opened.back().template_id != prepared.id,
		"Expired donor yields to an ordinary question"
	)


func _test_prepared_cap_and_lifecycle() -> void:
	var prepared := Content.get_prepared_topic()
	_setup(8, true, 6000, 1.0, prepared)
	for index in range(8):
		var now_msec := (index + 1) * 20000
		if index > 0:
			_director.submit_donation_question(_donation(index), now_msec)
		_director.tick(now_msec, true)
		_resolve(index + 1, now_msec + 1000)
	_director.tick(180000, true)
	_check(_opened.size() == 8, "Prepared opening consumes one of the eight slots")
	var prepared_count := 0
	for definition in _opened:
		if definition.template_id == prepared.id:
			prepared_count += 1
	_check(prepared_count == 1, "Repeated resolutions cannot rearm the topic")
	_setup(8, false, 6000, 1.0, prepared)
	_director.tick(20000, false)
	_check(_requests.is_empty(), "Disabled messages never offer a prepared topic")
	_setup(8, true, 6000, 1.0, prepared)
	_director.stop()
	_director.tick(20000, false)
	_check(_requests.is_empty(), "Stopped director cannot open a reserved question")
	_director.reset()
	_director.start(true)
	_director.tick(20000, true)
	_check(
		_opened.size() == 1 and _opened[0].template_id != prepared.id,
		"Ordinary restart has no reservation from the preceding stream"
	)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr(message)
