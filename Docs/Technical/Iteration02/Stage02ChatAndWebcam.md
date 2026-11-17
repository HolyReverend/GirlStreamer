# Stage 2: Contextual Chat and Automatic Webcam — Detailed Implementation Plan

Plan date: 2026-11-12. Implemented and headless-verified on 2026-11-13.

> **For agentic workers:** Use `stage-orchestrator` for whole-stage execution and `executing-plans` for its tasks, subject to AGENTS.md. Keep one writer for session/HUD integration and one owner of the live editor. No automatic commits or pushes.

**Goal:** Make the existing Snake session feel like a broadcast through a contextual spectator feed and a visibly responsive geometric heroine placeholder, without introducing audience rewards or new player choices.

**Architecture:** PrototypeSession translates existing game notifications into typed local events and explicitly routes them to a chat owner and a webcam view. Both consume Stage 1 active stream time; neither owns game rules, deadlines or input. Content is local and immutable, with no network service or global event bus.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, native Control/Container UI, procedural placeholder drawing and seeded local randomness.

**Specification:** [Iteration roadmap](../Iteration02ImplementationPlan.md), Stage 2; [iteration scope](../../GameDesign/Iteration02Scope.md); [Stage 1](Stage01StreamShell.md); [current architecture](../Architecture.md). Read project workflow and implementation rules before engine work; use `Codex/GodotSkills.md` for the relevant scene/UI/signal specialists.

## 1. Prerequisites and scope

Stage 1 supplies explicit start, pause-aware time, RUNNING authorization, clean restart, CLOSING and reserved WebcamSlot/ChatSlot. The user confirmed Stage 1 acceptance before Stage 2 implementation.

Include:

- Local nicknames and short contextual Russian chat lines, a bounded scrollable feed and a slow ambient cadence.
- Automatic feedback for stream start, food, first-time milestones, collision, board completion and an answered existing placeholder question.
- A geometric webcam portrait with five labelled states, finite automatic emotions, short character captions and a return to the appropriate baseline.
- Shared event classification, reset/pause/finish handling and focused tests.

Exclude new questions/options, reaction QTEs, audience counts/impression, money, donation generation, reply effect vectors, audio, actual portraits, animation assets, external APIs and persistent history. Stage 3 adds meaningful replies; Stage 4 adds chosen reactions; Stage 5 audience; Stage 6 donations. Keep QuickMessages, its three placeholder questions and timings unchanged.

The roadmap's three-second selected-reply priority is a later integration contract. Do not build an unused reply queue or fake player selections now. This stage implements two-second automatic presentation; Stage 3 introduces `show_reply` and its priority when a real caller exists.

## 2. Current source constraints

- SnakeGame emits `score_changed(0)` during start/retry; this is initialization, not food collection.
- A terminal full-board step publishes its board and enters WAITING_FOR_RETRY, then emits the final score followed synchronously by `attempt_finished(&"board_full", score)`. Avoid a food/milestone popup followed by a second completion popup for that same step.
- Existing session score/accounting handlers already track `_last_attempt_score`; compute event eligibility before updating that value. Preserve totals rather than adding another score accumulator.
- QuickMessages emits answered/expired/cancelled outcomes. Only `answered` produces positive social-looking feedback here; expiration/cancellation must not claim a response occurred.
- The active-time authorization sampler can finish the session synchronously. Do not call it again inside already-authorized Snake/question outcome handlers: it could split a terminal score/outcome pair and freeze incomplete totals. Complete accepted accounting first; use the read-only stream clock for cosmetic cutoff checks as specified below.
- Stage 1 reserves a 280 px side column and 160 px webcam region. Work within those regions; do not grow the window minimum or shrink the board to fit text.

## 3. Files and scene ownership

Paths below are relative to `GirlStreamer/` and are planned, not existing implementation claims.

| File | Responsibility |
| --- | --- |
| `prototype/stream/stream_event.gd` (new) | `StreamEvent extends RefCounted`: immutable-after-creation local game event |
| `prototype/stream/stream_content.gd` (new) | ChatTemplate/ChatLine types, authored text, nicknames, validation; only Stage 2 content fields |
| `prototype/stream/chat_feed.gd` (new) | Cadence, contextual selection, repeat prevention, seeded RNG, bounded history |
| `prototype/ui/hero_webcam.gd`, `.tscn` (new) | Five geometric expressions, state label, automatic caption deadline and baseline |
| `prototype/prototype_session.gd`, `.tscn` | Own ChatFeed, classify and route events, initialize/reset/gate all feedback |
| `prototype/ui/prototype_hud.gd`, `.tscn` | Instance HeroWebcam inside WebcamSlot; render bounded chat history inside ChatSlot; explicit typed access from parent |
| `tests/iteration02/test_stream_feedback.gd` (new) | Event routing, content/cadence, lifecycle and presentation-state assertions |
| `Docs/Technical/Architecture.md` | Update after implementation to describe actual ownership |

No Snake source modification is expected. Reuse its current notifications. Add `get_webcam() -> HeroWebcam` on HUD so the session can explicitly bind the view; no sibling searches or `/root` paths. Feed history reaches HUD through one signal connection made at setup, not on every restart.

## 4. Minimal data and interfaces

`StreamEvent` fields: `id: int`, `kind: Kind`, `time_msec: int`, `score: int`, `reason: StringName`. Kind declares FOOD, MILESTONE, RECORD, COLLISION, BOARD_COMPLETED for the roadmap contract, but Stage 2 produces no RECORD event. IDs start at 1 for each fresh stream, increase per canonical event and never reset on retry. Consumers do not mutate the record. Cache the successful active-time sample in the session's Snake authorizer and use it for the synchronous score/outcome pair. A separate read-only sample may suppress cosmetic output at cutoff. Canonical events and accepted accounting retain the original authorized timestamp. Optional audience association is deferred until needed.

`StreamContent.ChatTemplate`: `id: StringName`, `context: StringName`, `text: String`. `StreamContent.ChatLine`: `template_id: StringName`, `nick: String`, `text: String`, `context: StringName`, `time_msec: int`. Use typed arrays; no mutable runtime state in the content catalog. Rich text markup is unnecessary; render nicknames and text as literal strings.

| Owner / method | Contract |
| --- | --- |
| `StreamContent.validate() -> PackedStringArray` | Return explicit errors for duplicate IDs, missing required contexts, empty template text or nickname pool entries or fewer than three templates in a required context |
| `ChatFeed.reset(seed: int) -> void` | Clear history, last template ID, context freshness and cadence; reseed its own RNG |
| `ChatFeed.start(now_msec: int) -> void` | Enable feed and append one start line; schedule first ambient line at now + 4000 ms |
| `ChatFeed.tick(now_msec: int, snake_playing: bool) -> void` | At most one ambient line when due; choose only a currently valid context, then schedule from now, without catch-up |
| `ChatFeed.append_context(context: StringName, now_msec: int) -> void` | Append one eligible contextual line; the session applies the shared food throttle before calling. Unknown contexts safely reject without RNG/history mutation |
| `ChatFeed.stop() -> void` | Disable append/tick, retain history for the final screen until reset |
| `ChatFeed.get_lines() -> Array[StreamContent.ChatLine]` | Return copied records; external mutation must not alter owned history |
| `ChatFeed.lines_changed(lines: Array[StreamContent.ChatLine])` | Emit after accepted append/reset, not every frame; renderer rebuilds from bounded snapshot |
| `HeroWebcam.reset() -> void` | Clear active caption/deadline and show neutral baseline |
| `HeroWebcam.set_playing(playing: bool) -> void` | Baseline focused while playing, neutral while waiting; active transient remains until its deadline |
| `HeroWebcam.show_automatic(emotion: StringName, now_msec: int) -> void` | Show supported automatic state/caption for 2000 active milliseconds; use rules below for interruption |
| `HeroWebcam.tick(now_msec: int) -> void` | Expire transient and return to current baseline at deadline; no own timers |
| `HeroWebcam.stop() -> void` | Clear transient, settle to neutral without a new caption; no further changes until reset/start routing |

The session calls reset before Snake.start can emit notifications, then calls ChatFeed.start only after successful session initialization. A failed start produces no fake greeting. For Stage 2 keep cadence fixed at 4000 ms; Stage 5 supplies viewer-dependent timing clamped to the roadmap's 1500–6000 ms. No fake viewer counter or unused audience simulation now.

## 5. Event classification and routing

Maintain a session-local set of presented milestones {5,10,20}, cleared only on full stream restart. This marks once-per-stream presentation eligibility, not rewards. Stage 4 reuses this canonical classification rather than independently emitting a second milestone; its QTE eligibility/cooldown remains separate.

| Trigger | Canonical event / presentation |
| --- | --- |
| Score reset to zero or unchanged score | No event, no food line, no happy emotion; preserve normal accounting/reset behavior |
| Ordinary real +1 score while PLAYING | FOOD; optional throttled food line and happy transient |
| First reach of 5/10/20 this stream | One MILESTONE instead of FOOD; achievement line and happy transient |
| Later attempt reaches an already presented milestone | Ordinary FOOD, no extra milestone message |
| Final score notification while waiting for full-board outcome | Account food normally but defer all feedback; synchronous BOARD_COMPLETED outcome supplies the single canonical event |
| Wall/self collision | One COLLISION with reason; loss line and sad transient; baseline becomes neutral while waiting |
| Board full | One BOARD_COMPLETED; achievement line and happy transient; no second FOOD/MILESTONE for that step |
| Fresh retry | Baseline focused; no greeting, no score-zero feedback, no history/event-ID reset |
| Existing question answered | One answer-context line and shy transient; no claimed semantic agreement with the arbitrary color/drink/weather answer |
| Existing question expired/cancelled | No answer-context line or shy transient; existing question feedback remains unchanged |

Produce canonical events independently of cosmetic throttling. Route each accepted game occurrence once from the existing handler, without a second connection to the same Snake signal. Keep new event IDs distinct from QuickMessages question IDs; question outcomes retain their existing single-resolution guard. Start/answer are feed contexts, not invented Snake event kinds.

Use the controller's terminal state/reason flow, not a timer or frame delay, to suppress final-food presentation. In the score handler, a score increase while Snake is already WAITING_FOR_RETRY has no immediate feedback; the immediately following board-full outcome completes the classification. If future source changes invalidate that ordering, revise this adapter explicitly rather than adding deferred callbacks that can survive restart.

## 6. Chat content, cadence and repetition

Required active contexts: `start`, `ambient_playing`, `ambient_waiting`, `food`, `achievement`, `loss`, `answer`. Provide at least three unique short templates for each and at least eight neutral nicknames. Also author and validate a dormant `donation` pool of three lines to meet the iteration content inventory, but never select or display it until Stage 6 has an actual donation trigger. No invented donation messages during ordinary play.

Examples of tone (implementation may refine wording within this contract):

| Context | Suitable example | Constraint |
| --- | --- | --- |
| start | «О, успел к началу!» | Once at actual stream start, not retry |
| ambient_playing | «Слежу за поворотами вместе с тобой» | No unsupported claim of a record or victory |
| ambient_waiting | «Давай ещё попытку» | Only when waiting for retry |
| food | «Ещё кусочек!» | Actual collection only |
| achievement | «Вот это попытка!» | Milestone or completion, not every food |
| loss | «Бывает, следующий заход получится» | Short, recoverable tone rather than repeated insults |
| answer | «Спасибо, что ответила!» | No fabricated quote, opinion or reward |

Store at most 60 lines, removing oldest on append. Each append creates a new line; no unbounded debug/history mirror. Exclude the immediately previous template ID before selecting from the requested pool. Keep all IDs globally unique; identical text in multiple templates does not count as variety. Validate duplicate text within a context. Use one private seeded RNG for chat template/nickname selection, never Snake's food RNG.

Proposed first-pass cosmetic controls:

- Ambient emission occurs every 4000 active ms, only while RUNNING. Waiting for retry uses `ambient_waiting` rather than freezing the chat. No delayed catch-up loop after a long frame.
- Each accepted contextual line reschedules ambient emission to at least now + 4000 ms, avoiding an ambient line immediately after an event. Co-occurring contextual events can produce distinct lines; bounded history prevents memory growth.
- Ordinary FOOD feedback has a 3000 ms shared cosmetic cooldown owned by the session for both its chat line and happy transient. The session makes one eligibility decision before dispatching either view. Milestone/completion bypass this food cooldown. No pending food queue; suppressed food still counts in the game.
- Ambient selection uses only playing/waiting status, never stale loss/achievement/answer context. Event-specific lines append at the event time and do not linger as a later random pool.
- Text is concise enough for the 280 px column: target ≤70 characters plus nickname, wrap long words and keep the panel clipped/scrollable. The HUD displays all retained lines with newest at bottom and follows new messages automatically; it does not request keyboard focus.

These settings control readability, not future interaction frequency, audience preference or money. They are provisional and can be tuned after the manual check without increasing scope.

## 7. Webcam behavior and visual bounds

Use simple local drawing (head silhouette, eyes, eyebrows and mouth) inside the 160 px webcam slot. No image generation, downloaded art or imported character asset is required. Emotion must be legible by face geometry plus Russian label, not color alone. Reserve fixed label/caption height so text never changes the board rectangle.

| State | Label / visual cue | Automatic caption |
| --- | --- | --- |
| neutral | «Спокойна»; relaxed mouth/eyebrows | Empty at rest |
| focused | «Сосредоточена»; narrowed eyes/angled brows | Empty at rest |
| happy | «Радуется»; clear smile | «Есть!» |
| sad | «Огорчена»; downturned mouth | «Эх, ещё раз!» |
| shy | «Смущена»; bashful eyes/blush plus label | «Спасибо за вопрос!» |

Automatic transient priority: sad > shy > happy. A higher-priority transient replaces the visible lower-priority one. Equal priority replaces and refreshes its deadline; lower priority while a higher one is active is dropped, not queued. Before comparison, expire any old transient using the supplied active time. Food cooldown prevents constant happy refresh from ordinary collections. Baseline always tracks current playing/waiting state even during a transient.

Return to focused after the two-second transient if Snake is playing, otherwise neutral. Pause freezes the remaining transient duration and caption; resume does not replay it. Final stop clears the transient and settles the portrait to neutral. Stage 7 may replace that closing appearance with a deliberate goodbye.

Stage 3 will add `show_reply(text, emotion, now_msec)` with a 3000 ms selected-reply deadline and higher priority than automatic emotions. When that stage is implemented, retain only the latest eligible automatic state rather than a queue, and discard stale presentation on expiry. This future rule is documented here but not implemented or tested with artificial player replies in Stage 2.

## 8. Lifecycle and integration ordering

1. During setup, bind ChatFeed.lines_changed to HUD and obtain the typed webcam reference once.
2. Before a fresh start, validate the content catalog without consuming RNG or mutating current results. On validation failure show a Russian configuration error and remain READY/FINISHED, preserving Stage 1 failure rules.
3. Reset feed/webcam/event counter/milestone set/food cooldown before starting Snake. On success start the feed at elapsed zero and set focused baseline. Failed start leaves empty feed, neutral webcam and no enabled updates.
4. The regular session update obtains one authorized elapsed-time sample and calls feed.tick and webcam.tick with it. Denied authorization means no update. Inside synchronous Snake/question handlers, preserve the producer-authorized accounting before cosmetics; never invoke a finishing sampler from those handlers or presentation callbacks. Read `get_stream_time_msec()` without side effects: if it has reached the duration, suppress only new cosmetic output, leaving the already accepted score/outcome pair to complete before the next regular authorization finishes the stream. Route an eligible cosmetic occurrence to both views with the same read-only sample. No deferred callbacks or reentrant lifecycle changes may split the accepted pair.
5. PAUSED performs no feed/webcam tick, append or state-reset operations. Resize may redraw the same snapshot but must not age content.
6. CLOSING stops feed/webcam before presenting final state. Synchronous question cancellation updates existing metrics but produces no social feedback. Late notifications cannot append lines or alter the portrait.
7. Retry preserves history, RNG state, event IDs, milestone eligibility and cosmetic cooldown; it only updates the webcam baseline after successful retry.
8. Full restart clears all those states and produces exactly one fresh greeting. Do not reconnect signals, use fire-and-forget coroutines or retain callbacks from the previous stream.

## 9. Implementation sequence

- [x] **A — Verify dependency and focused failure.** The baseline check failed because the session did not own a chat feed.
- [x] **B — Add typed catalog and event adapter.** Validate the catalog and classify score and outcome events.
- [x] **C — Implement feed owner and history view.** Connect the bounded seeded feed to the HUD once.
- [x] **D — Implement geometric webcam.** Draw five states and use active time for automatic priority and expiry.
- [x] **E — Integrate lifetime boundaries.** Preserve Stage 1 accounting, input and pause behavior through finish and restart.
- [x] **F — Validate and record.** Run focused and affected integration checks, load scenes and write the observed results to a new local work report.

## 10. Focused verification

| Case | Required observation/assertion |
| --- | --- |
| Reset vs food | Start/retry `score_changed(0)` causes no FOOD event or happy caption; a real increment emits one canonical event and retains correct session total |
| Milestone reuse | First score 5 presents one milestone; reaching 5 again after retry is ordinary food; full restart restores milestone eligibility |
| Full board | Final score plus board-full outcome yields one BOARD_COMPLETED presentation, no preceding FOOD/MILESTONE; existing food/completion totals remain correct |
| Context and repeats | No immediate template repeat; playing/waiting ambient pools are selected correctly; no unsupported donation, record or answer claim |
| Bounded history | After 75 accepted appends, 60 records remain in order; mutating a returned record does not alter owned history |
| Cadence/throttle | Start at 0, ambient at 4000, one late tick at 16000 appends only one ambient line; ordinary food within 3000 ms is suppressed cosmetically; milestone bypass works |
| Independent RNG | Same fixed Snake seed and identical movement yield identical food positions with feed enabled or disabled; feed tests use an independent fixed seed |
| Webcam | Five distinct labelled states; sad replaces happy, lower-priority happy does not erase active sad; at exact 2000 ms expiry return to current baseline |
| Answer outcomes | Accepted existing answer produces one generic answer line/shy transient; expired, cancelled and rejected input produce none |
| Pause/retry | Sixty wall seconds paused change neither history nor transient deadline; retry preserves history/IDs and updates baseline without a greeting |
| Cutoff/restart | At exact stream expiry no new feedback; late callbacks ignored; restart clears history/transients and adds one greeting with no duplicate subscriptions |
| Accepted boundary pair | A Snake step authorized just before expiry emits final score then board-full while the test clock crosses the cutoff. Both accepted accounting changes survive; cosmetic output at/after cutoff is suppressed; the next session authorization freezes complete totals. No handler initiates CLOSING between those signals. Apply the same accounting-first rule to an already accepted question answer |
| Minimum layout | 1024 × 768, wrapped line and full history do not overlap questions, displace board or enlarge minimum window; resizing preserves current state |

Resolve `$godotExe` from project configuration at execution time. Intended commands from repository root:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_feedback.gd
# Earlier runners below are regression candidates when this stage changes a contract they exercise.
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_quick_messages.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_timed_session.gd
```

New marker: `ITER02_STAGE02_FEEDBACK_PASS`; failures identify a case and exit nonzero. Require zero exit code and no unexpected diagnostics. Deliberate invalid-catalog cases must label their expected validation errors. Extend the focused runner for full-board event ordering and seeded independence; do not rerun every pure Snake rule suite unless its owning code changed or new evidence requires it.

Also load touched scenes with the installed engine's supported workflow. Manual scenario: start, collect food, reach a milestone, collide, wait for retry, answer one placeholder question, pause with a transient, resize, resume, finish and restart. Verify readability and that looking at the webcam/chat does not obscure steering. Use a controlled fixture for rare board completion; do not require a human to fill the board. A full six-minute balance comparison belongs to Stage 7.
