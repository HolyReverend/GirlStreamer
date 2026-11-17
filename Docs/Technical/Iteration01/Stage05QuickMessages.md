# Stage 5: Quick Questions and Keyboard Answers — Detailed Implementation Plan

Date: 2026-11-12. Status: implemented and technically verified; manual playtest acceptance open.

**Goal:** Let the player read a short question and choose one of three answers with keys 1–3 while Snake continues normally, then assess whether this interaction is manageable.

**Architecture:** Add one session-owned `QuickMessages` Node for scheduling, question state and answer input. It uses the session's existing monotonic time, reports typed events and never changes Snake. The HUD reserves a separate message region; the session accumulates a few in-memory measurements and includes them in its existing results.

**Tech stack:** Godot 4.7 Standard, typed GDScript, native scenes/Control layout and Input Map. Preserve the existing renderer, Snake timing and keyboard actions.

**Specification:** [Iteration roadmap](../Iteration01ImplementationPlan.md), Stage 5 and iteration evaluation; [Stage 4](Stage04TimedSession.md); [Streaming gameplay](../../GameDesign/Mechanics/StreamingGameplay.md), simultaneous play and single-choice constraints; [Minigames](../../GameDesign/Mechanics/Minigames.md), chat compatibility. The user's deliberately simplified question experiment takes precedence over the complete streaming design.

Stage 5 extends the accepted Stage 1–4 implementation.

## 1. Scope and initial settings

Include timed placeholder questions, three short options, number-key selection, neutral expiration, brief feedback, session cancellation and minimal evaluation results. Exclude background chat, donations, event-triggered reactions, answer correctness, personality/relationship effects, skills, audience, rewards, sound/voice, character animation, queues and persistence.

| Setting / rule | Initial behavior |
| --- | --- |
| Enable switch | `messages_enabled: bool = true` on PrototypeSession; false gives the message-free baseline. |
| First question | 45 seconds after session start, provided Snake is playable. |
| Response window | 5 seconds from actual opening, not from a missed scheduled time. |
| Gap | 45 seconds after a question is resolved; no overlapping questions or backlog. |
| Selection | Top-row 1, 2, 3 map to answer indices 0, 1, 2. No mouse, typing or numpad requirement. |
| Consequences | All options are valid preferences. Selection/miss never changes Snake, score or session duration. |
| Waiting after failure | An already open question remains answerable and keeps its original deadline. New questions wait until Snake is PLAYING again. |
| Retry | Space affects only the attempt. It does not reset question ID, response window, gap or message measurements. |
| Session expiry | Cancel an active question, stop scheduling and hide message feedback before final results are published. |
| New session | Clear questions/measurements, reset IDs/content order and schedule the first question from the new session start. |

Export `first_question_delay_seconds = 45.0` (range 1–120), `question_gap_seconds = 45.0` (range 1–120) and `question_window_seconds = 5.0` (range 1–15) beside the enable switch on PrototypeSession. Validate finite in-range settings before a new session and snapshot them for that run, as Stage 4 does for duration. Inspector changes apply only to the next session. Feedback lasts one second, a presentation constant rather than another balance setting.

These are experiment defaults, not a new production quota or the reaction system's proposed three-second QTE. Long retry waits can reduce the number of questions shown; do not compensate by generating a burst later.

### Minimal content

Cycle deterministically through this small Russian-language set so the playtest measures reading in the user's language. Keep option order fixed per question; all options have equal mechanical value.

| Prompt | 1 | 2 | 3 |
| --- | --- | --- | --- |
| `Какой цвет выберешь?` | `Красный` | `Зелёный` | `Синий` |
| `Какой напиток выберешь?` | `Чай` | `Кофе` | `Вода` |
| `Какую погоду выберешь?` | `Солнце` | `Дождь` | `Снег` |

Store these in `quick_messages.gd` as a typed array of small script-local records (prompt String, options Array[String]); a nested RefCounted data class is sufficient. Validate exactly three nonempty options per record. No external content database, custom Resource schema, dialogue graph or random selection system is required.

## 2. Planned files and scene composition

Paths are relative to `GirlStreamer/` (`res://`).

| File | Change |
| --- | --- |
| `prototype/messages/quick_messages.gd` (new) | Typed placeholder data, IDLE/OPEN state, scheduling, number input and single resolution. |
| `prototype/prototype_session.tscn` | Add one `QuickMessages` Node child of the existing session root. |
| `prototype/prototype_session.gd` | Snapshot message settings, inject time access, drive message updates, connect lifecycle/metrics and finalize cancellation before results. |
| `prototype/ui/prototype_hud.tscn` | Reserve a message column beside BoardArea with prompt, countdown, three options and feedback. Extend existing results labels. |
| `prototype/ui/prototype_hud.gd` | Typed message presentation methods and message-results formatting; retain existing board/time/score methods. |
| `project.godot` | Add `message_answer_1`, `message_answer_2`, `message_answer_3`. |
| `tests/iteration01/test_quick_messages.gd` (new) | Focused controlled-time scheduling, answer/lifecycle and integration checks. |
| `tests/iteration01/test_timed_session.gd` | Keep timer-only fixtures explicitly message-disabled; add/adjust expectations for message reset/cancellation integration where needed. |

No Snake model/controller or movement algorithm change is required. Keep the existing session/board instances, local signal wiring and keyboard ownership. If layout node paths change, update only the HUD's owned references and preserve its external rectangle-reporting contract.

## 3. QuickMessages contracts

Use `class_name QuickMessages`, one `enum ChoiceState { IDLE, OPEN }`, and a separate session-enabled flag. Disabled/stopped means no scheduling or input, not an additional choice. Runtime fields include current ID, next ID, content cursor, integer `opened_at_msec`, `answer_deadline_msec`, `next_due_msec` and feedback expiry. Convert validated configured seconds once at reset with `roundi(seconds * 1000.0)`; feedback lasts 1000 ms. Compare only integer elapsed milliseconds so floating-point addition cannot admit a key exactly at the deadline. Convert differences to seconds only for display/latency. IDs start at 1 each session and increment only when a question actually opens.

Preserve the roadmap's signals:

```gdscript
signal question_opened(id: int, prompt: String, options: Array[String])
signal question_resolved(id: int, answer_index: int, elapsed_seconds: float, outcome: StringName)
```

Outcomes are `&"answered"`, `&"expired"` and `&"cancelled"`. Only answered uses indices 0–2; the others use -1. `elapsed_seconds` measures time since actual opening, clamped to the quantized response window. For expiration it equals `window_msec / 1000.0`; cancellation is not a response-time sample.

| Method | Contract |
| --- | --- |
| `set_time_sampler(sampler: Callable) -> void` | Store a no-argument callback returning authorized elapsed milliseconds as int, or -1 if inactive/expired. Install once before startup. |
| `reset_for_session(enabled: bool, first_delay: float, gap: float, window: float) -> void` | Receive validated settings in seconds, quantize them once to milliseconds, clear state/feedback, reset IDs/cursor and set the first due time. Do not emit a resolution for old state; normal finish must already have cancelled it. |
| `tick(now_msec: int, can_open: bool) -> void` | Advance expiration, feedback and scheduling from an already authorized elapsed-millisecond sample; caller is PrototypeSession only. |
| `stop_for_session_end(now_msec: int) -> void` | Receive final elapsed milliseconds, disable scheduling/input first, cancel one open question synchronously if any, and clear feedback. Repeated calls do nothing. |
| `is_open() -> bool` | Whether one choice is active. |
| `get_remaining_seconds(now_msec: int) -> float` | Convert `maxi(0, answer_deadline_msec - now_msec) / 1000.0` to presentation seconds, or return zero when idle. |
| `get_feedback_text() -> String` | Current short feedback or empty; tick clears it after its deadline. |
| `_unhandled_input(event: InputEvent) -> void` | Accept only a recognized, pressed, non-echo number action for an open enabled question. |

Do not run an independent `_process`, Timer or asynchronous `await` chain in QuickMessages. The parent drives `tick`; number input reads the same clock through the injected callback. Dependencies remain explicit; no `/root` lookup, sibling search, scene-global group or event bus.

### Scheduling and resolving

On tick, update/clear old feedback. If OPEN and `now_msec >= answer_deadline_msec`, resolve once as expired and return without opening another question in that call. If IDLE, enabled, due and `can_open`, open exactly one record with `opened_at_msec = now_msec`, `answer_deadline_msec = now_msec + window_msec`. Opening clears prior feedback and emits a copied option array. If Snake is not playable, retain a single due time; do not enqueue records or advance the content cursor. The next playable tick may open the one pending question immediately.

Opening never pauses, slows or creates invulnerability for Snake. A question may open near session end and be cancelled before its full window; do not extend the session or hide this case from measurements.

Use one internal `_resolve(outcome: StringName, answer_index: int, now_msec: int) -> void` path. Capture ID/content/timing, leave OPEN and invalidate the current ID. Schedule `next_due_msec = now_msec + gap_msec` for answered/expired, based on actual resolution processing time; this prevents bursts after stalls. Cancellation schedules nothing. Compute signal latency as `clampi(now_msec - opened_at_msec, 0, window_msec) / 1000.0`. Set answered feedback to `Выбрано: <option>` or expired feedback to `Время вышло` until `now_msec + 1000`; cancellation clears it. Only after all these fields are finalized emit `question_resolved`, so its synchronous listener reads the new feedback and state.

State changes precede synchronous notification, so a second key, expiration tick or cancellation cannot resolve the same ID again. No handler may open a replacement question recursively. Answer input while IDLE never opens a question: that key cannot both create and answer a prompt the player has not seen.

## 4. One session clock and exact deadline rules

Reuse Stage 4's `PrototypeSession._sample_running_time_msec() -> int` as the injected time callback. It reads `_now_msec()` once, returns -1 unless the session is live, and finishes an expired session before returning -1. Otherwise it returns elapsed milliseconds from that same sample. Do not add a separate message clock, duplicate session authorization method or later getter read for the same decision.

The parent calls this sampler once per update. On -1 return without ticking; otherwise use that one value for the session countdown (convert to seconds for the label) and `quick_messages.tick(now_msec, snake_game.is_playing())`. This extends Stage 4's existing update rather than appending another clock read/expiry check. Number-key input obtains its own authorized sample when the key arrives, so it does not depend on parent/child processing order.

For an open question, the input handler:

1. Recognizes only the three answer actions, pressed/non-echo. Ignore all other keys, release and echo; idle/disabled input is ignored.
2. Reads the authorized elapsed-millisecond sample. The sampler may synchronously finish the session and cancel the question. If it returns -1, return immediately; never restore OPEN or resolve again.
3. If `now_msec >= answer_deadline_msec`, resolve expired with index -1; otherwise resolve answered with the matching index. Mark only this recognized active-choice event handled. A boundary-late key cannot become an answer to the next question.

Session expiry takes priority over question expiry/answer. If both are discovered in the same callback, cancel the open question. After a long stall past session end, an unresolved OPEN question is cancelled even if its own deadline also passed while callbacks were suspended; do not synthesize a historical answer or additional expiration. If the session is still live when a late question is processed, expire it normally.

Keep top-row digits separate from WASD/arrows, Space and Enter. Use physical top-row key bindings so the selected keyboard language does not change their locations. Do not poll held keys or use `ui_*` actions. An ignored number event must not consume steering, retry or new-session input. Changing focus is unnecessary because all message widgets are nonfocusable Labels/Controls.

## 5. Lifecycle integration and measurements

### Start, retry and finish

Validate all message settings/content before discarding an old session result. Install sampler and signal connections once. On a successful new session start, reset message measurements and call `reset_for_session(...)` after Snake startup succeeds but before the first update. On startup failure leave messages disabled and clear their display. No question opens synchronously during startup because first delay is positive.

Do not call any message reset/stop method from attempt retry, collision or board completion. Existing questions continue during WAITING_FOR_RETRY; new ones require `snake_game.is_playing()`. A failed attempt restart also leaves the message state/clock alone.

Extend Stage 4's finish order: set FINISHED and freeze session elapsed, stop Snake, then call `stop_for_session_end(duration_seconds * 1000)` using the run's snapshotted duration. Account its synchronous cancellation, clear the active message display, and **only then** snapshot/publish the combined results. Repeated finish paths must not add cancellations or republish a different summary. Cancellation must not call the time sampler again, which would reenter finishing.

### Session-owned metrics

Add `questions_shown`, `questions_answered`, `questions_expired`, `questions_cancelled` and `Array[float] answer_times_seconds` to PrototypeSession. Keep Snake totals from Stage 4. Do not duplicate these counters in QuickMessages.

The session tracks at most one open question ID. On `question_opened`, record the ID/options, increment shown and display the prompt. On matching `question_resolved`, clear the tracked ID first and increment exactly the matching outcome. Append elapsed time only for answered. Ignore/report a mismatched or duplicate resolution rather than counting it again. IDs may restart from 1 because new-session reset clears tracked state, and connections remain synchronous.

Normal opens/resolutions are accepted only during RUNNING. The finish path is the explicit exception: a matching `cancelled` resolution is accepted synchronously during FINISHED **before** the final snapshot. Reject other late outcomes. This extends Stage 4's “ignore late notifications” rule solely for the cancellation that the session itself requested.

At final results require `shown = answered + expired + cancelled`; no OPEN question remains. Compute answer rate with floating-point division, `float(answered) / (answered + expired)`, and mean response time from answered samples only. When either denominator is zero show `N/A`, not a false zero performance score. The compact summary shows counts, answer rate and mean response time; keep individual samples in the existing in-memory array for optional debugger inspection/playtest notes. Do not build a scrollable history viewer or export system. Disabled runs show `Messages: off` and zero counts; their rate/time remain N/A.

These are diagnostic results only. No target percentage, leaderboard, reward or automatic difficulty adjustment is implied.

## 6. Stable message layout and feedback

Within the HUD's existing VBox, replace the standalone BoardArea slot with an expanding HBox containing BoardArea (expand/fill) and a MessageArea (initial minimum width 300 logical pixels). Put a MarginContainer/VBox in MessageArea with a header, wrapped prompt, countdown, three fixed option Labels and feedback Label. Keep time/score/status/results outside that play-area row as in Stage 4.

Reserve the message column throughout the session, including IDLE and disabled baseline runs. Use a plain Control wrapper for MessageArea with minimum size 300×300 logical pixels and no horizontal expand flag; let only BoardArea absorb spare row width. A full-rect MarginContainer/VBox inside that wrapper cannot propagate text-driven minimum sizes into the outer HBox, so the explicit outer minimum must fit all children. Reserve slots for header (24 high), prompt (56), countdown (24), three options (28 each) and feedback (40), with 16-pixel outer margins and 4-pixel gaps: the total is 284 pixels high. Use full-rect Labels in plain Control slots and keep the slots allocated when empty. At the supported 1024×768 window, adjust all states uniformly if real font metrics require more room. Showing/hiding text must not resize the board at question onset. Disabled mode displays `Вопросы отключены`; idle mode can display `Ожидание вопроса`. Both baseline modes use the same board geometry.

Do not overlay the board or create a modal panel. Keep controls nonfocusable and avoid mouse-driven answer buttons. Verify the short strings at the supported minimum window, adjusting fixed sizing uniformly without changing stretch settings or shrinking text to illegibility. At a fixed viewport compare BoardArea's rectangle across idle, prompts, answered/expired feedback and disabled state during the focused editor check; no separate exhaustive layout test is needed. Keep the combined final summary compact enough to leave the board visible at 1024×768. One resize above that minimum is sufficient; smaller windows and a device matrix are outside this prototype.

Add HUD methods:

- `show_question(prompt: String, options: Array[String]) -> void`: fill exactly three labeled rows `1 — ...`, `2 — ...`, `3 — ...`.
- `set_question_time(seconds: float) -> void`: show response time remaining, rounded up to tenths and clamped at zero. No timing decisions in the HUD.
- `clear_question() -> void`: clear prompt/countdown/option text while retaining layout space.
- `set_message_feedback(text: String) -> void`: show controller-supplied feedback; empty clears it.
- `set_messages_enabled(enabled: bool) -> void`: select baseline/idle heading without changing column geometry.
- `set_message_results(enabled: bool, shown: int, answered: int, expired: int, cancelled: int, answer_times: Array[float]) -> void`: prepare compact summary lines from copied data without showing the panel. Call this after cancellation accounting, then call Stage 4's existing `show_session_results(...)` to populate its section and reveal the combined summary once.

On resolution, the parent clears the choice and reads feedback from QuickMessages. After each authorized tick it refreshes remaining time/feedback. On session finish or startup clear both immediately; do not leave a feedback timer or deferred callback capable of repainting an old question in a new session. Metrics remain in the parent; formatting averages/labels in HUD must not modify them.

## 7. Implementation sequence

### A. Question controller and input

- [x] Inspect actual Stage 4 startup/finish/time sampling and HUD wiring; preserve its expiry-before-action contract.
- [x] Add the focused controller checks from Section 8 and confirm failures against missing question behavior.
- [x] Implement typed content/state, finite scheduling, one resolution path and injected time sampling.
- [x] Register the three answer actions and implement event-based input with exact question/session deadline behavior.

### B. Integrate session and presentation

- [x] Add the controller Node, parent-driven ticking and once-only signal connections; integrate start/finish without touching attempt reset.
- [x] Add counters and response-time samples; account cancellation before summary generation and reset metrics only on new session.
- [x] Reserve the stable message column, add choice/feedback/results presentation and preserve BoardArea rectangle reporting.
- [x] Run focused integration checks and the shortened standalone graphical scenario.
- [ ] Run the short interactive editor scenario.
- [x] Preserve the normal preset and record verification limits.
- [ ] Perform the paired human evaluation below.

## 8. Necessary verification

Use one new runner `tests/iteration01/test_quick_messages.gd` with the existing small runner style. Reuse Stage 4's test-local session subclass/fake clock; standalone controller tests supply explicit time callbacks and drive `tick` directly. Input cases use actual InputEventKey presses with explicit keycode/physical keycode and echo flags matching the Input Map, through the real handler. Do not bypass deadline checks by calling `_resolve` as the test action.

Use these five case groups; assert concrete IDs, outcomes, indices, timings and counts:

1. **Scheduling and no backlog:** defaults do not open at 44.999 seconds and open ID 1 at 45 when playable, with deadline 50. Repeated ticks while OPEN never open a second choice. In a separate fixture keep Snake waiting past the due time: no opening; at the next playable tick open one question with a fresh five-second window, not a shortened overdue one. Resolve and verify the next due time is processing time plus 45; a late tick never emits a burst. Disabled mode never opens even if time advances beyond several due times.
2. **Answer mapping, once-only resolution and expiry:** use a fresh question for each digit and verify indices 0/1/2. While the choice is OPEN, send an echo event before any genuine answer and assert no resolution/state change; ignoring echo only after IDLE would not prove filtering. At 46.25 after opening at 45, accept one fresh answer with latency 1.25; duplicate press, echo and later expiration tick cannot resolve it again. For the exact-boundary subcase, open at elapsed 59002 ms and send a number event at 64002 ms before a tick: it must expire with index -1. This non-whole-second opening catches accidental floating-point deadline comparisons. Without input the tick also expires once. After that, no question opens before its gap. Idle number input opens nothing; unrelated keys are not handled.
3. **Retry independence and concurrent play:** with a real session/controller fixture open a question, save ID/deadline and Snake tick interval/accumulator. Opening itself changes none of Snake's simulation state. Advance a normal movement tick and answer: movement/score follow Snake's unchanged rules. Cause a collision while the question is open, then retry through Space at a controlled time: ID/deadline stay unchanged and the question is answerable while waiting and after retry. Expiration while waiting remains timed; no new question opens until playable. Use separate fixtures for mutually exclusive answer/expire paths.
4. **Session expiry/cancellation ordering:** with an OPEN question, advance the fake clock to session expiry and send a number key before any parent update. Expect one cancelled outcome (-1), no answer/expired count, disabled scheduling, cleared question/feedback and a final summary that already includes cancellation. Test equal question/session deadlines and a stall beyond both as subcases. Repeated updates/keys cannot recount it. After Enter starts a new session, state/counters/timing reset and no old feedback or resolution reappears; scene IDs/connections are reused.
5. **Metrics and baseline:** use shortened valid settings to produce three prompts: one answered after 1.25 seconds, one expired, one cancelled by session end. Expect shown 3, answered 1, expired 1, cancelled 1, answer times `[1.25]`, rate 50%, mean 1.25 seconds. Route these through real tick/input/finish paths, not direct counter writes. After a new disabled session expect zero counts, empty samples and N/A rate/time. Content/range validation and snapshotted tuning remain startup code-review checks, not an additional malformed-content or live-Inspector test matrix.

All controller tick/sampler fixture values are integer elapsed milliseconds; second-based examples above are readable timing descriptions, not argument units. For shortened fixtures use first delay/gap 1 second and window 2 seconds, with a suitable session duration; set precise fake times to keep each intended question open/expired/cancelled. Initialize all settings before auto-start and bound scene/layout waits. During final metrics checks, assert active ID cleared and `shown = answered + expired + cancelled`. Test runtime outcomes, not just connection counts.

Print `STAGE05_MESSAGES_PASS groups=5` only after all assertions/subcases pass; exit nonzero on failure and reject unexpected engine errors. Reuse established runner reporting; no new test framework or sleep-based timing harness. Resolve the real Godot 4.7 console executable, verify flags, then execute the equivalent of:

```powershell
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_quick_messages.gd
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_timed_session.gd
```

Capture each command's output/exit code separately. The session regression is relevant because its start/finish/input integration changes. Pure Snake tests need not be rerun unless their owning code changes or new failures justify it. Follow project single-editor/import rules for scene checks.

### Short editor scenario

Temporarily shorten the first delay/gap and session duration. While steering continuously, answer one question with each of 1, 2, 3; confirm head movement, speed and controls remain available and every option is readable. Let one expire, retry during another, and end the session with a question open. Check feedback, cancellation/results and Enter reset. Verify question onset/resolution does not change board geometry; resize once and confirm no overlap/clipping at the prototype window size. Check for debugger errors, then restore 360/45/45/5 settings.

## 9. Paired playtest and iteration acceptance

After functional checks pass, run one six-minute baseline with messages disabled and one with messages enabled, keeping grid, tick interval, window layout and other Snake settings equal. Use the same fixed-seed setting for comparability; do not claim identical difficulty once the player's routes diverge. These are actual human play sessions: synthetic button presses/headless success cannot establish reading comfort.

Record settings, run order, food/attempt/collision results, question counts, mean response time and answer rate with its sample count. Individual times remain available in the session's in-memory array; inspect/copy them only if needed to explain observations. Ask the player to note readability, ability to find keys while steering, interruption/frustration and whether mistakes felt recoverable. The prompts require choosing a preference, not blindly pressing any digit to maximize rate. Record fewer opportunities caused by long retry waits as a limitation rather than evidence that answering during play is easy.

Write observations after play in a new `Reports/Doc/Report_Doc_YYYY_MM_DD_HH_mm_JobName.md` (future evaluation artifact, not created by this planning task). Keep the record concise; no runtime export or storage system is required. If manual play is unavailable, mark it NotRun and leave experiential acceptance open.

There is no predeclared pass-rate threshold or statistical claim from two runs. A difficult result is valid evidence: adjust one of window, gap, wording or Snake speed at a time and repeat only the relevant comparison. Stage-based Snake remains a potential next-iteration decision, not an automatic scope expansion here.

- [x] One question at a time is readable in a separate stable region, with exactly three options selected by 1–3.
- [x] Answering never changes Snake speed/rules or pauses it; retry never resets an open question or its deadline.
- [x] Answer, expiration and cancellation each resolve once with the defined priority and metrics.
- [x] Session finish/reset closes old input/state cleanly and produces a consistent summary; disabled baseline remains playable.
- [ ] Focused automated checks and the short editor scenario have recorded evidence; normal settings are restored.
- [x] Paired human playtest findings and limitations are recorded, or experiential acceptance is explicitly NotRun.

Report actual changed files, performed checks and remaining decisions. Completing the functional prototype does not validate the full streaming system, final balance or comfort without the playtest evidence.

The remaining comfort evaluation is carried forward into [OI-003](../../OpenItems/Items/OI-003-StreamPlaytest.md) for the current combined stream; this historical plan does not require a duplicate playtest of the replaced controller.
