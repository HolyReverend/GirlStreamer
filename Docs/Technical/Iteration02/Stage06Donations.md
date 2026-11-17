# Stage 6: Donations and Priority Questions — Detailed Implementation Plan

Plan date: 2026-11-13. Implemented and headless-verified on 2026-11-16.

> **For agentic workers:** Use `stage-orchestrator` for whole-stage execution and `executing-plans` for its tasks, subject to AGENTS.md. One writer owns session/content integration; one owner controls the live editor. No automatic commits or pushes.

**Goal:** Generate fictional in-game donations from the current audience, credit each once, show readable notifications and route donor questions through the existing shared choice scheduler.

**Architecture:** DonationController owns sampling, its independent RNG, payment IDs and authoritative totals. Session supplies authorized active time and audience snapshots and routes committed records to chat, presentation and director. StreamDirector/StreamChoice retain all question scheduling/input ownership; UI never credits money.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, local content, native Control UI and existing native test runners. No payment service or network integration.

**Specification:** [Iteration roadmap](../Iteration02ImplementationPlan.md), Stage 6; [scope](../../GameDesign/Iteration02Scope.md); [Stage 4 director](Stage04ReactionsAndDirector.md); [Stage 5 audience](Stage05AudienceConsequences.md); [Stage 3 choices](Stage03MeaningfulQuestions.md); [economy design](../../GameDesign/Mechanics/Economy.md). Read workflow/implementation rules before engine work and select relevant Godot specialists.

## 1. Dependencies and limits

The user accepted Stages 1–5 before this stage. Stage 6 connects committed receipts to the existing audience and shared choice systems.

Include audience-based donation opportunities, amounts, donor identities, optional messages/questions, one-time credit, bounded notifications, visible total and final count/total. Activate the donation-question impression rules already planned in Stage 5.

Exclude real payments, refunds, purchases, expenses, subscriptions, permanent wallet, cross-stream progression, external services, audio and additional reaction types. A good answer improves audience impression through existing rules but never directly issues another payment. Donations without questions do not create a mandatory response/QTE. Stage 7 adds sound and full experience evaluation.

All amounts/probabilities/timings are proposed initial tuning, not guaranteed earnings or validated balance. A short period without donations is allowed; no hidden minimum-income supplement is added.

## 2. Files and ownership

Runtime paths are relative to `GirlStreamer/`.

| File | Planned change |
| --- | --- |
| `prototype/stream/donation_controller.gd` (new) | Opportunity schedule, probability/group/amount sampling, committed payment records and totals |
| `prototype/stream/stream_content.gd` | Typed DonationRecord and donation content/question templates; validation |
| `prototype/prototype_session.gd`, `.tscn` | Own controller, order updates, route payments once, freeze final totals |
| `prototype/stream/stream_director.gd` | Connect real donor-question submissions to existing priority slot; sample question window at actual opening |
| `prototype/stream/chat_feed.gd` | Append literal donor line through bounded history, independently of notification queue |
| `prototype/ui/prototype_hud.gd`, `.tscn` | Donation total, bounded notifications and overflow summary in fixed space |
| `tests/iteration02/test_stream_donations.gd` (new) | Sampling boundaries, exact-once credit, question/notification overflow and lifecycle integration |
| `tests/iteration02/test_stream_director.gd`, `test_stream_audience.gd`, `test_stream_lifetime.gd` | Preserve focused synthetic fixtures. Adapt an earlier runner only if a contract it uses changes. |
| `Docs/Technical/Architecture.md` | Update actual ownership after execution |

Reuse StreamChoice and webcam selected-reply behavior. Do not add a second question UI/input controller or a second money accumulator in session/HUD. The controller's integer count/total are authoritative; session copies them only for frozen results.

## 3. Typed payment and controller contracts

Add immutable-after-creation `StreamContent.DonationRecord` with `id: int`, `received_at_msec: int`, `group_index: int`, `amount: int`, `nick: String`, `message: String`, `question_template_id: StringName` (empty when no question). The question text is already frozen in message; options/source metadata are copied into a pending ChoiceDefinition on receipt. A delayed choice must not refer to a different question or donor.

Add `donation_amount: int` to ChoiceDefinition and copy it into ChoiceResolution: positive for donor questions, zero for other kinds. Copy amount from the committed record at submission, then snapshot it again with the opened definition. Never look up the controller's last donation to render a pending/open question; a newer receipt may have replaced that record. Validate donor amount against the committed source during construction and retain it for later presentation only, never as a second payment instruction.

| Controller interface | Contract |
| --- | --- |
| `reset(seed: int) -> void` | Disable; reset IDs, next opportunity, count/total and last record; seed a private RNG |
| `start() -> void` | Enable first opportunity at the snapshotted interval (default 10000 active ms); no payment at time zero |
| `tick(now_msec: int, counts: Vector3i, impressions: Vector3) -> void` | Session calls only with RUNNING-authorized time and current snapshot; process at most one due opportunity, no independent wall-clock sampling |
| `stop() -> void` | Disable sampling without altering committed totals |
| `get_total() -> int`, `get_count() -> int` | Read-only authoritative integer totals |
| `get_last_donation() -> StreamContent.DonationRecord` | Defensive copy; available before donation_received is emitted |
| `donation_received(id: int, group_index: int, amount: int, nick: String, message: String, has_question: bool)` | Existing roadmap signature; emitted only after credit and last-record assignment |

Only the controller's internal commit path may credit: advance next_due before any synchronous notification, allocate increasing ID starting at 1, construct immutable record, increment count/total, store last record, then emit once. A same-time reentrant tick cannot consume the same opportunity again. It accepts no arbitrary externally supplied “credit this ID” command. Session stores a last-routed donation ID and ignores repeated/out-of-order notification delivery before appending chat, HUD items or director requests. Tests replay a notification and prove neither credit nor secondary presentation repeats.

A sparse positive increasing source ID is valid for director submissions because donations without questions consume payment IDs too. Use the payment ID as source_event_id, source_group_index as the donor's group, kind `donation_question`, source_event_kind `donation`, source_attempt_id 0 (not attempt-bound). Choice ID remains a separate identifier assigned only on opening. All counters reset only for a new stream, never on retry.

## 4. Sampling rules and controlled randomness

For each due opportunity, compute three nonnegative weights `count_i × impression_i /100`. Validate finite snapshot values within Stage 5 bounds; invalid input produces an explicit diagnostic and no payment/RNG advance. With total weight zero, create no donation and consume no random samples. Otherwise success probability is `clamp(total_weight /60, 0, 0.65)`.

Use a private RandomNumberGenerator plus a narrow test seam `_draw_unit() -> float` returning [0,1). Tests may override this method with a sequence; do not add a new RNG framework. Draw in this order:

1. Success: donate only if draw < probability. On failure stop sampling this opportunity.
2. Group: multiply draw by total weight, choose first cumulative interval whose upper boundary is strictly greater; zero-weight groups cannot win. Handle the final positive group safely against floating-point rounding.
3. Amount: draw <0.50 →2 coins; <0.80 →5; <0.98 →10; otherwise 25. Identical distribution for all groups.
4. Question flag: draw <0.30 gives a question; otherwise a non-interactive message.
5. Content/nickname selection: use bounded indices from subsequent private draws or deterministic local rotation; choose deterministic rotation for this implementation to keep the four gameplay draws stable. Neither chat nor Snake RNG is used.

Normal opportunities are at active 10000,20000,… ms, one possible payment each. Advance the opportunity even on zero weight or a failed success roll. On a delayed update crossing multiple opportunities, process only the latest due slot using the current snapshot and stamp receipt with now; skip older missed slots and set next_due to the next boundary of the snapshotted interval grid (10 seconds by default). This explicit no-burst policy avoids retroactively generating payments from unknown historical audience. It does not claim frame-partition invariance under arbitrarily long stalls; deterministic tests compare identical tick/sample sequences. Pause does not cause this skipping because active time stops.

Use a validated configurable interval 1–60 seconds for focused testing, default 10; all paths use its snapshotted value. Do not change current settings mid-stream. At stream cutoff, do not sample any due opportunity, including one exactly on the cutoff or older missed opportunities first noticed after cutoff. A normal 360-second run has opportunities 10…350 seconds. Stage 5 still integrates the last completed passive audience second at 360 before freezing, without allowing a donation then.

## 5. Content and donor questions

Reuse Stage 2 nicknames and at least three dormant donation-message templates, but select through the donation owner's independent rotation. Non-question messages must not claim specific unseen achievements; examples: «Спасибо за эфир!», «На хорошее настроение», «Поддержу канал». Every record contains a message in this initial implementation; optional empty text remains a legal validated presentation fallback («Поддержка эфира»).

Provide six general donor-question templates suitable at receipt and up to 45 seconds later, each with three distinct short answer intents, full heroine replies, supported emotions, raw three-group vectors and two compatible chat responses per option. Proposed prompts:

1. «Что тебе больше всего нравится в этой игре?»
2. «Какой момент стрима радует тебя сильнее всего?»
3. «Что помогает тебе не сдаваться?»
4. «Какой совет дашь новичку в Змейке?»
5. «Что для тебя значит поддержка зрителей?»
6. «Каким ты хочешь сделать этот эфир?»

General wording avoids stale achievement/loss references. Preserve Stage 3 raw-vector bounds −2…+4, no universally dominant choice, no guaranteed-payoff labels and short readable text. Use unique donation-template/option IDs separate from ordinary questions; share schema/validation, not a second answer system. Rotate without immediate repetition; cycling after six is permitted because the total of donor receipts can exceed the shared opening cap. This does not change ordinary-question once-per-stream selection rules.

Build/copy a pending definition on receipt, but calculate its normal question window at actual opening from then-current audience using Stage 5's 5–6-second formula. Waiting time never shortens the opened window. A supported explicit test window override still applies; source nick/text/amount/group remain frozen while waiting. Include the donated amount in the dedicated question heading so a question opening after its toast disappears remains identifiable.

## 6. Credit, questions and impression effects

Receipt is already paid before the session handler runs. In that handler copy the record immediately, deduplicate routing, append the donor line, update total display/notification and submit its optional question to StreamDirector. No caller samples a finishing clock again while handling this accepted payment. Later cosmetic cutoff can suppress a late toast, but must not reverse committed money.

Director retains Stage 4 behavior: one pending donor question, 45-second TTL from receipt, donor priority only for a next eligible opening, no preemption, ordinary playing requirement, shared gap/cap and exact-expiry pruning on submission. Waiting for retry does not block an eligible pending loss reaction merely because a donor question is waiting.

- Answered shown donor question: Stage 5 applies its copied raw vector ×1.5 once; heroine/chat react via existing selected-reply pipeline. No second payment.
- Expired shown donor question: −2 impression only to source group; original payment unchanged.
- Cancelled at finish: no penalty, payment unchanged.
- Never shown because of occupied slot, expiry, disabled interactions or opening cap: no answer outcome, no penalty, no refund; original donor text remains in the bounded feed while retained.
- Repeated donation notification/duplicate director submission cannot produce another line, choice or impression effect.

Interactive mode disabled suppresses donor questions along with all other choices, but donations, totals and non-interactive feedback still work. No automatic webcam thank-you is added for every receipt: the notification/feed communicate receipt, and an answered question gets the deliberate reply. This avoids interrupting selected reactions and does not introduce another QTE or promised response.

## 7. Bounded notification presentation

Reserve a compact donation strip inside ChatSlot beside/under its existing audience header; the remaining feed scrolls. No overlay covers board or choice options, no row insertion resizes the board. Display nickname, amount and message with wrapping/ellipsis within the fixed strip, and total as «Донаты: N». Full donor text stays in the bounded feed even if the strip truncates it.

HUD owns presentation-only state: one current notification lasting 3000 active ms, at most three pending records and one overflow aggregate (count/amount). If current is empty and no older pending item exists, show immediately; otherwise enqueue up to three. Further records add to overflow count/amount without storing their full texts again. Once an overflow aggregate exists, route all further arrivals into it even when pending slots become free, until the records already ahead of it drain. Then display «Ещё N донатов — M монет» for 3000 ms and clear the pending aggregate. This fixes its FIFO position and prevents sustained arrivals from starving the summary. During the displayed summary, new arrivals may fill the next pending queue/aggregate independently. No payment is dropped because the presentation queue is full.

Add `enqueue_donation(record: DonationRecord)`, `tick_donation_notifications(now_msec: int)`, `clear_donation_notifications()` to HUD; enqueue uses record receipt time/current authorized tick for initial presentation, and starting a queued item uses the current tick, never its old receipt deadline. At most one displayed transition per update; no burst of already-expired toasts after a long frame. Notification timing never controls the director TTL or payment accounting.

Add `ChatFeed.append_donation(record: DonationRecord, now_msec: int) -> void`, routing through existing 60-line history and ambient-rescheduling rules, using stable `donation_<id>` identity and literal text. Each retained line includes that individual nickname, amount and full message, even if its toast was aggregated. Do not lose a donor line to ordinary food throttling. Eviction of old history is allowed and does not change controller totals.

Pause freezes notifications and pending candidates. Retry preserves them. At finish clear current/pending/overflow UI without showing deferred receipts during CLOSING; frozen final total/count includes all committed payments regardless of visibility. Restart clears everything. Sound remains Stage 7.

## 8. Update order and lifetime

Session's RUNNING update order:

1. Obtain one authorized active-time sample; cutoff stops all sampling/work and follows the existing finish path.
2. Advance passive audience steps to that sample, then tick StreamChoice. A due question expiration may change impression at this same timestamp.
3. Read the now-current audience snapshot and call DonationController.tick once. Commit/route any payment synchronously, including candidate submission.
4. Tick director to select the next eligible choice; a newly arrived donor question participates before an ordinary question can open on this update.
5. Update ambient feed/webcam/notification presentation with the same active sample, retaining existing cosmetic bounds.

Already-authorized Snake events and input answers are applied synchronously before the next update that observes their effects; do not invent a deferred same-frame reorder. When collision and payment are both delivered at the same active timestamp, delivery order determines which audience snapshot is sampled, but neither may preempt an open choice or credit twice. Test the actual process order and a controlled alternate delivery order for safety, not identical random outcomes.

Start validates content/settings before mutation, resets controller with its own seed, enables only after successful session start. On finish stop donation sampling before director stop/choice cancellation, perform Stage 5's final passive flush, freeze payment totals alongside other metrics and clear presentation. Source IDs/seed/counters/next opportunity reset only on a fresh session. No duplicate signal connections or asynchronous callbacks survive restart.

## 9. Ordered implementation tasks

- [ ] **A — Inspect dependencies and define failing checks.** Confirm Stage 4 donor slot and Stage 5 effects/timing exist. Add `test_stream_donations.gd` with scripted draws and controlled time; validate runner failure output without building generic RNG infrastructure.
- [ ] **B — Implement sampling and commit owner.** Add validated records/settings, private RNG/test seam, interval/no-burst policy, weighted group/amount/question selection and authoritative count/total. Check boundary draws before integration.
- [ ] **C — Author/validate content.** Activate three donation messages and six donor questions with complete replies/options. Ensure source identities, finite raw effects and readability; no question depends on a past attempt context.
- [ ] **D — Integrate payment routing and question priority.** Wire copy/dedup/feed/director paths, opening-time window sampling, existing impression effects and no-payment-on-answer behavior.
- [ ] **E — Add notification UI and summaries.** Implement fixed donation strip, queue/overflow aggregate, current total and final count/total; verify money is independent of display capacity.
- [ ] **F — Verify and record.** Run focused and affected integration checks, load scenes, perform forced-example manual scenarios, then update actual Architecture/roadmap and report remaining balance/readability questions.

## 10. Required checks

| Case | Expected behavior |
| --- | --- |
| Probability | Initial counts/impressions give total weight 15 and p=0.25. Draw 0.249 succeeds, 0.25 fails. Zero weight consumes no RNG/payment; high weight caps p at 0.65 |
| Group boundaries | Weights (5,0,5) and group draw 0.5 select the third group; zero-weight group never selected; all positive groups are reachable |
| Amount/flag | Amount draws 0.499/0.50/0.80/0.98 select 2/5/10/25; question draw 0.299 selects question, 0.30 does not; rules identical for every group |
| Once-only credit | Signal observers see already-incremented count/total; replaying receipt notification changes neither totals nor downstream lines/choices |
| Schedule | No sample at 9999, one at 10000; same tick repeated cannot sample twice. Jump to 35000 processes only latest due slot, next due 40000, with receipt timestamp 35000 |
| Short interval/reentry | With interval 1000 ms first opportunity is 1000, not 10000; a receipt callback calling tick again at the same time cannot produce another payment |
| Audience monotonicity | Increasing valid counts/impressions never lowers computed p, up to cap; test the function/draw boundaries, not a flaky finite-run income comparison |
| Independent RNG | Same tick/snapshot/seed sequence reproduces payments; changing chat/Snake RNG consumption does not alter donation draws |
| Crowded receipt | An open choice survives same-time collision and paid receipt. Credit once and preserve donor submission. Under default timings the loss stays automatic because it cannot survive the post-resolution gap. The Stage 4 director fixture covers a fresh loss opening while Snake waits and a donor candidate is ineligible. |
| Suppressed paid question | Drive one actual paid receipt into an occupied donor slot and confirm chat/credit remain and no penalty or refund follows. Exact TTL replacement and slot ordering stay in the Stage 4 director runner. |
| Opened outcomes | Answer ×1.5, expiry −2 to source group, cancellation zero; none changes received money; duplicate resolution cannot repeat effect |
| Delay and identity | Donor waits, audience changes and a newer payment arrives; older question opens with fresh 5–6-second window and original nick/text/amount/group. Payment ID and choice ID remain separate typed fields/namespaces even if both happen to equal 1 |
| Notification overflow | Force ≥6 receipts with display busy: at most three pending full records plus aggregate; all totals/lines credited, aggregate count/amount correct after draining |
| Sustained arrivals | Successful receipts every second cannot indefinitely postpone an existing aggregate; it displays after the full records already ahead of it, before later receipts' notifications |
| Disabled interactions | Donor receipts still credit/display; no choices open and no missed-donor penalty applies |
| Pause/retry | Paused wall time advances no opportunity/TTL/toast; retry preserves total/pending work; no catch-up burst on resume |
| Cutoff/restart | Due donation at exact cutoff rejected; prior committed payment retained even if its notification is suppressed; CLOSING cannot sample, restart resets all payment and UI state |
| Visual bounds | Long valid donor name/text and overflow summary fit at 1024 × 768 without moving/covering game or answer regions |

New success marker: `ITER02_STAGE06_DONATIONS_PASS`; failures identify the case and exit nonzero. Require explicit PASS, zero exit code and no unexpected diagnostics; label deliberate invalid-input errors. Resolve `$godotExe` from actual project configuration. Intended commands from repository root:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_donations.gd
# Earlier runners below are regression candidates when this stage changes a contract they exercise.
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_director.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_audience.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd
```

If shared choice/feed APIs change, run their owning Stage 3/2 checks as well. Do not repeat pure Snake tests without a relevant change/failure. Load affected scenes through installed-engine validation.

Manual scenario uses deterministic fixture/seed to guarantee one message donation and at least two opened donor questions, without adding a permanent debug menu: answer one question, let the other expire, and provide an additional receipt while a choice is open to exercise waiting. Pause, retry, finish and restart. Inspect notification/choice readability and confirm totals match committed records. Forced successes prove behavior, not natural income balance. Record fixture settings and actual checks in this stage's execution notes; full natural six-minute balance is Stage 7.
