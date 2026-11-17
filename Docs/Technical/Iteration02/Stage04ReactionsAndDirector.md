# Stage 4: Reactions and One Interaction Scheduler — Detailed Implementation Plan

> **Current corrections (2026-11-17):** [Iterations 1–2 correction plan](../Iteration01And02Corrections.md) supersedes this document where duration, interaction cadence, Snake speed or HUD placement conflicts. Apply its 180-second preset to future acceptance runs. See the correction plan for current implementation and acceptance status.

Plan date: 2026-11-13. Implemented.

> **For agentic workers:** Use `stage-orchestrator` for whole-stage execution and `executing-plans` for its tasks, subject to AGENTS.md. One writer owns session/content integration and one owner controls the editor. No automatic commits or pushes.

**Goal:** Add short player-selected reactions to significant Snake events and combine them with ordinary questions under one bounded, predictable interaction schedule.

**Architecture:** StreamDirector owns candidate eligibility, freshness, priorities, opening budget and cooldowns. StreamChoice remains the sole timed input owner. The session owns gameplay time, canonical events, outcome accounting and presentation; the director opens choices through an explicitly injected request callback, never by locating sibling nodes.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, native UI, local authored text and existing keyboard actions.

**Specification:** [Iteration roadmap](../Iteration02ImplementationPlan.md), Stage 4; [iteration scope](../../GameDesign/Iteration02Scope.md); [Stage 2 event classification](Stage02ChatAndWebcam.md); [Stage 3 choices](Stage03MeaningfulQuestions.md); [Stage 1 lifetime](Stage01StreamShell.md). Before implementation read project workflow/implementation rules and select relevant specialists through `Codex/GodotSkills.md`.

## 1. Dependencies and scope

The user accepted Stages 1–3 before this stage. Stage 4 replaces the temporary Stage 3 question schedule and keeps StreamChoice as the input owner.

Include reaction choices, two execution variants per style for achievement and loss, canonical record detection, one scheduler, bounded pending reaction/donation slots and integration tests. Keep questions, selected replies, automatic webcam feedback and local chat already planned in earlier stages.

No audience, money, actual donation generation, paid subscriptions, new mini-game, art or audio. Synthetic donation-question candidates are test inputs only; normal play must not fabricate donor events or display dummy donations. Stage 5 applies numerical effects; Stage 6 supplies real in-game donation events.

The values below operationalize provisional roadmap tuning. First opening is at least 30 active seconds after start, at least 25 seconds follow each resolution, at most eight choices open per stream, reactions last 3 seconds, reaction candidates live 8 seconds, donation candidates 45 seconds and reaction eligibility cooldown is 60 seconds. Ordinary question windows remain 6 seconds. Six to eight choices is an observation target, not guaranteed filler.

## 2. Files and ownership

Runtime paths are relative to `GirlStreamer/`.

| File | Planned work |
| --- | --- |
| `prototype/stream/stream_director.gd` (new) | One scheduler, bounded candidates, shared gate, reaction cooldown, ordinary catalog/context eligibility |
| `prototype/stream/stream_content.gd` | Reaction templates, fixed style IDs and validation; extend definitions/resolutions to preserve reaction/source metadata |
| `prototype/stream/stream_event.gd` | Preserve canonical event fields; add attempt identity for candidate relevance |
| `prototype/prototype_session.gd`, `.tscn` | Own director; transfer Stage 3 scheduling to it; canonical record detection, ID assignment, lifecycle wiring and outcome routing |
| `prototype/stream/stream_choice.gd` | Accept reaction/donation_question kind in existing generic definition; retain single input/deadline contract |
| `prototype/ui/prototype_hud.gd` | Kind-specific heading and neutral reaction-expiry feedback, same reserved layout |
| `prototype/ui/hero_webcam.gd`, `prototype/stream/chat_feed.gd` | Reuse selected-reply and compatible response APIs; only narrow integration changes if required |
| `tests/iteration02/test_stream_director.gd` (new) | Scheduling, priority, bounded slots, context/cooldown/budget and reaction integration |
| `tests/iteration02/test_stream_choices.gd`, `test_stream_feedback.gd`, `test_stream_lifetime.gd` | Migrate scheduling ownership and kind-specific assertions; preserve core coverage |
| `Docs/Technical/Architecture.md` | Update actual ownership after implementation |

Delete Stage 3's temporary scheduling fields/logic from the session after transfer. Do not keep both a session question timer and a director timer. No new Input Map actions, global bus, Autoload, coroutines or Timer-node queue.

## 3. Contracts and state

Use StreamContent.ChoiceDefinition/ChoiceResolution from Stage 3. Add `style_id: StringName` on options (empty for ordinary answers, `competitive`, `humor`, `flirt` for reactions), `source_attempt_id: int` and `source_event_kind: StringName` on definitions and copy both into resolution. The source kind is an immutable named event kind such as `collision`, not a lookup in the latest context. Stage 5 must still recognize an answered loss reaction after retry and newer events. Add `attempt_id: int` to StreamEvent; session increments it on each successful attempt start, never on pause. IDs for canonical events and opened choices remain separate increasing sequences reset only on a new stream.

The director stores at most one pending reaction, one pending donation question, one latest ordinary-context event, the bounded set of used ordinary template IDs, opening count, last resolution time, next reaction eligibility time and the latest accepted event ID. Canonical game event IDs are delivered in increasing order; ignore duplicate/out-of-order IDs rather than growing an unbounded deduplication log. Keep stable reaction variant counters per category/style, reset per stream.

| Director interface | Contract |
| --- | --- |
| `configure(open_request: Callable) -> void` | Inject `(definition, now_msec) -> bool`, implemented by session, which assigns the next choice ID and calls StreamChoice.try_open |
| `reset() -> void` | Clear all candidate/schedule/content-selection state and disable until explicit start |
| `start(enabled: bool) -> void` | Enable interactive scheduling for this stream; disabled mode leaves automatic webcam/chat running |
| `submit_event(event: StreamEvent) -> void` | Update factual ordinary context and consider a reaction; no opening or lifecycle resampling in the synchronous source callback |
| `submit_donation_question(definition: StreamContent.ChoiceDefinition, now_msec: int) -> void` | Copy a not-yet-opened donation-question definition into the pending slot; this API neither issues nor refunds money, which Stage 6 credits before submission |
| `on_attempt_started(attempt_id: int) -> void` | Update current attempt and invalidate pending reaction from the prior attempt; retain fresh retrospective ordinary loss context per Stage 3 |
| `on_choice_resolved(resolution: StreamContent.ChoiceResolution) -> void` | Clear tracked active ID once; update shared gap from the supplied authorized resolution timestamp; no immediate opening |
| `tick(now_msec: int, snake_playing: bool) -> void` | Called by session only in RUNNING with one authorized time sample; prune, arbitrate and request at most one opening |
| `stop() -> void` | Disable and clear pending work without resolving hidden candidates as player misses |

The session reports successful openings synchronously through the open-request return and the populated definition ID; director tracks that ID. Only a successful try_open increments the budget or commits used template/variant selection. Immediately clear remaining pending slots if that accepted opening reaches the snapshotted cap. A rejected request does not lose its candidate or consume an ID; it can retry on a later tick if still relevant. Avoid random selection side effects before acceptance; stable ordered catalog/variant selection suffices.

Reuse session's existing `messages_enabled` Inspector flag, relabel its player-facing meaning to «Интерактивные обращения» if exposed: in this stage it disables all questions/reaction choices, including synthetic candidates, while ambient feedback continues. Validate/snapshot director tuning at stream start: first delay/gap 1–120 seconds, reaction TTL 1–30, donation TTL 1–120, eligibility cooldown 1–120, cap 1–8; normal defaults above. Ordinary question window keeps Stage 3 bounds; reaction window is fixed at 3000 ms. Tests may use explicit shorter values without changing shipped defaults.

## 4. Canonical event classification

Keep the Stage 2 session-side adapter as the single producer. Preserve accepted score/outcome accounting before cosmetic cutoff; never invoke a finishing clock sampler from those synchronous callbacks. Submit event data to the director without opening a choice there. The next authorized session tick decides whether an event is still usable.

Session high score begins at zero, survives retries and updates on every real score increase. A new high score qualifies as RECORD only at score ≥5. Event precedence for one step is BOARD_COMPLETED > first-time MILESTONE > RECORD > FOOD. A qualifying milestone/record still advances high score, but emits only the strongest event. Final-food/full-board ordering remains collapsed into one completion event. Record/achievement classification is independent of whether a QTE is offered.

Route RECORD's automatic happy emotion and achievement-context chat line through the same session-owned 3000 ms cosmetic gate as ordinary FOOD. A rapid series of intermediate records cannot bypass that gate; only milestones/completion keep their Stage 2 bypass. Canonical records still reach the director even when their cosmetics are suppressed. An answered record reaction may produce its separate selected reply, but merely admitting a pending candidate emits no second recognition line.

Eligible reaction sources: first-time milestone at 5/10/20, qualified RECORD, BOARD_COMPLETED, or COLLISION with final attempt score ≥5. Lesser collisions still cause automatic sad feedback but no reaction candidate. No reward or audience change is computed in this stage.

Proposed cooldown semantics: the 60-second eligibility cooldown starts when a candidate is successfully placed in the pending reaction slot. It is not refreshed by every new score, rejection or automatic fallback. At equality with next eligibility time a new eligible source may be admitted. Admission that later expires still consumes this cooldown, preventing constant retrying of a missed moment. An occupied slot retains its older candidate; rejected newer events retain ordinary automatic feedback and do not restart cooldown.

Both submission methods prune expired or attempt-ineligible incumbents before checking slot occupancy, using the supplied active timestamp (event.time_msec for a game event). This pruning does not resample the wall clock or open choices. A new submission exactly at the incumbent's TTL may replace it even if no director tick has occurred. Apply stopped/disabled/cap rejection without accumulating candidates; retain the deduplication watermark rules.

At most one eligible reaction is reserved even before the first opening time. An early event can expire before 30 seconds; this is an intentional automatic-only moment, not a player miss. Record is allowed to become another canonical event on a later new high score; the separate 60-second reaction gate prevents a QTE per food. Numerical reward deduplication/limits remain Stage 5 responsibilities.

## 5. Arbitration and freshness

Each RUNNING update uses this order:

1. Authorize session time. If it finishes the stream, perform no director work.
2. Tick StreamChoice first so an exact-deadline resolution updates the director's gap before candidate selection.
3. Director discards candidates whose TTL has expired or whose attempt relevance has been lost. Expiry uses `now >= created_at + TTL`; a pending item at its expiry instant cannot open.
4. If a choice is active, first-opening gate/gap has not elapsed, interactive mode is disabled, or the snapshotted opening cap has been reached, open nothing. Reaching the cap clears pending slots immediately on the last accepted opening; later submissions cannot grow work.
5. Consider eligible donation question, then eligible reaction, then an eligible ordinary question. Skip an ineligible higher-priority candidate rather than letting it block a lower eligible kind. Request at most one opening and return.

Shared next opening time is the snapshotted first delay initially, then `last_resolution.resolved_at_msec + configured_gap_msec` for answered or expired outcomes of any kind (defaults 30000 and 25000 ms). All gates, TTLs, cooldown and cap use snapshotted configured values; numeric examples in this document use the normal defaults. Cancellations happen at session end and schedule nothing. A reaction counts toward the same budget and delays ordinary questions; there is no remaining Stage 3 45-second timer. If no unused/context-valid ordinary template exists, remain idle and reconsider on later ticks without creating a backlog.

| Candidate | Creation, relevance and disposition |
| --- | --- |
| Donation question | At most one, TTL 45 seconds from submission; requires Snake PLAYING to open. Keep older on overflow, reject duplicate IDs. Dropped/expired work is not a shown unanswered question; preserve the source association for Stage 6 |
| Reaction | At most one, TTL 8 seconds from source event time; requires same attempt ID. Achievement/record opens while PLAYING; loss or board completion can open while WAITING_FOR_RETRY. Any retry clears a still-pending old-attempt reaction; an already-open reaction survives retry |
| Ordinary question | Select at opening from unused templates; PLAYING only. Fresh context lasts 15 seconds, with Stage 3 retrospective loss retained across retry and achievement invalidated. No queued ordinary windows |

Donation/choice IDs are different: Stage 6 supplies a stable increasing source ID in `source_event_id`; test fixtures do the same. Donation IDs never share the game-event deduplication watermark. Track one last-seen donation source ID, rejecting duplicates/out-of-order submissions; update it even for overflow/suppression so a repeated submission cannot become a second opportunity later. Stage 6 delivers new donations in source-ID order and accounts for every payment independently of whether its question fits. No unbounded deduplication set or separate payment cap is needed.

A reaction arriving during an open choice cannot survive the normal 25-second post-resolution gap with an 8-second TTL. It therefore remains automatic-only. A reaction arriving near the end of an idle gap can open while fresh. Donation TTL 45 seconds allows a normal six-second question plus the shared gap. Tests must exercise both paths, not assume all events become choices.

Priority is for pending openings, never interrupts an existing question/reaction or selected reply. Stage 3's reply-display priority remains independent of the choice scheduler. A new QTE does not pause, slow or otherwise protect Snake.

## 6. Reaction content and outcomes

Use two achievement variants and two loss variants. Each variant contains exactly three options in invariant order: 1 «Азартно», 2 «С юмором», 3 «Кокетливо». Thus the catalog contains twelve complete reaction replies (two categories × two variants × three styles), each with supported emotion, stable style ID and two compatible chat responses. Cycle variants per category only after a successful opening; ordinary question option ordering remains its authored order.

| Category | Example intent for the three styles |
| --- | --- |
| Achievement | «Ещё один рубеж!» / «Сама удивилась!» / «Жду ваших комплиментов» |
| Loss | «Разберусь с этим поворотом» / «Так и было задумано. Почти» / «Вы меня отвлекли своей милотой» |

Examples guide authoring; keep captions short, Russian and compatible with the actual source event. A board-completion variant must not promise continuing an already completed attempt. Reaction header: «Как отреагировать?»; include a short source caption such as «Новый рубеж» or «Попытка закончилась». No caller may use fixed style ordering as ordinary-question answer correctness.

Authored extra-effect vectors remain provisional data: competitive (4,1,0), humor (1,4,1), flirt (0,1,4), in gamer/social/image order. Carry style and source metadata into the copied resolution so Stage 5 can attenuate repeated styles and cap profitable loss reactions. Do not execute these vectors or replace base event effects here.

- Answered reaction: one outcome, one selected webcam reply and compatible chat response through Stage 3 APIs; feedback says «Реакция выбрана». Record chosen style/source independently of ordinary question answers.
- Expired reaction: record expired with index -1 and no chosen option/effect. Clear the panel; neutral automatic handling means return to current automatic/baseline presentation, without an extra sad response, fabricated reply or penalty. Existing source-event emotion already happened; do not replay it solely because the choice expired.
- Suppressed/expired pending reaction: no StreamChoice opening/outcome and no player-miss count. Source automatic feedback is sufficient; no additional fallback popup.
- Cancelled reaction: counted as cancellation only if it was open, silent presentation cleanup, no style/effect. Session finish retains priority over an answer at the same deadline.

Extend summary accounting to distinguish questions and reactions: maintain shown/answered/expired/cancelled per kind and choice-wide totals. Existing question answer rate/mean excludes reactions; a reaction result must not improve the question answer rate. All-kind total after finish equals answered + expired + cancelled. Suppressed pending items are excluded from both denominators. Donation-question statistics become usable later; synthetic tests may assert them without exposing dummy runtime results.

## 7. Lifecycle and integration

On start validate catalog/director settings before session mutation, reset director/choice and session high score/milestones/IDs, then enable the director only after Snake starts successfully. A failed start leaves no enabled scheduler.

Session forwards canonical events exactly once and reports attempt starts after successful start/retry. Director updates ordinary context independently of reaction admission; rejecting a QTE must not erase the factual event used by an ordinary question. Attempt retry does not reset shared gap, budget, reaction cooldown, used templates, high score or an open choice.

On resolution, session immediately copies the StreamChoice record, accounts it once, notifies director with that timestamp and then dispatches eligible presentation. No new choice opens recursively in that callback. Pause freezes all TTLs/cooldowns/windows because they use active time; ignored inputs cannot enqueue work. Resume produces at most one opening at the next allowed tick, never catch-up.

At finish first disable/clear director candidates, then cancel the open choice and freeze metrics under the existing CLOSING rules. The cancellation may notify the stopped director to clear its tracked active ID but cannot re-enable it or schedule anything. Stop/reset selected and automatic presentation via existing paths. Restart must restore all director gates and IDs without adding signal connections.

## 8. Ordered implementation tasks

- [ ] **A — Confirm prerequisites and add failing checks.** Inspect Stage 1–3 implementation, source classification and scheduled-question tests; create `test_stream_director.gd` with controlled active time and a fake open-request callback. Verify failures correspond to missing behavior, not runner errors.
- [ ] **B — Extend canonical metadata/content.** Add attempt IDs and high-score record classification with same-step precedence; add reaction variants/style IDs. Test final-food completion collapse and records without changing Snake rules.
- [ ] **C — Implement director.** Add bounded slots, eligibility cooldown, shared gate/budget, ordinary context selection and test-only donation contract. Use deterministic selection; no side effects on rejected opening requests.
- [ ] **D — Transfer scheduling.** Remove Stage 3 timer/state duplicates, wire one director and opening adapter, route choices/resolutions and preserve sampler/cancellation ordering. Update old scheduling assertions to the new owner and timing.
- [ ] **E — Integrate reaction presentation and metrics.** Reuse existing selected reply/feed pipeline, fixed style positions and neutral expiry; extend per-kind outcomes and summary without audience claims.
- [ ] **F — Verify and record.** Run focused/affected checks, load scenes and perform the short crowded-event manual scenario; update actual Architecture and roadmap status, documenting remaining limits.

## 9. Required checks

| Case | Required assertions |
| --- | --- |
| Shared gate/cap | No opening at 29999, first possible at 30000; resolve at 33000 → next at 58000. All kinds share cap eight; rejected try_open consumes neither ID nor budget |
| Busy choice | Collision/record cannot replace an active question; short-lived pending reaction expires without a shown/missed count |
| Fresh near gap | Previous resolution at 30000, qualifying source at 51000 → may open at 55000; at source+8000 it is stale |
| Eligibility cooldown | Admit at 51000 → reject eligible sources before 111000, allow at 111000 if slots/gates permit; suppressed events never continually push that boundary forward |
| Eligible priority | When idle and all candidates valid: donation, reaction, ordinary. While waiting for retry, a blocked donation cannot prevent an eligible loss/completion reaction |
| Donation waiting | Submission during a six-second question survives its resolution plus 25-second gap; overflow retains older, TTL/duplicate/cap rejection never represents a missed shown question |
| Submission before tick | Submit a fresh candidate exactly at incumbent expiry without a prior director tick: stale incumbent clears and fresh candidate is admitted. Repeat for a reaction with shortened configured cooldown |
| Retry relevance | Pending prior-attempt reaction disappears on retry; open reaction survives; ordinary retrospective loss stays fresh without refreshing its 15-second timestamp |
| Canonical events | First score 5 qualifying as milestone+record emits milestone only; new high score later emits record; score zero emits none; full board outranks coincident food/record |
| Controls/window | 1/2/3 keep fixed reaction styles; answer just before 3000 ms succeeds, at deadline expires; stream deadline wins; steering continues |
| Neutral outcomes | Expired/suppressed reaction has no selected vector/chat reply/penalty; base event record and automatic feedback remain intact |
| Kind accounting | Reaction answer increments reaction counters only; ordinary rate/mean unchanged; cancellation reconciles totals before frozen summary |
| Source snapshot | Open loss reaction, retry, generate a newer record, then answer: stored source kind remains collision with the original attempt/event IDs |
| Record cosmetics | Fast consecutive new high scores preserve canonical event routing but share FOOD's 3000 ms cosmetic gate; no per-score happy refresh or unthrottled achievement feed |
| Pause/reset | Paused wall time ages no pending TTL or cooldown. Restart clears high score, candidates, deduplication, budget and used templates; no duplicate callbacks |
| Short tuning | Configured shorter gaps apply to every path without retaining a hidden 45-second question timer; selected-reply replacement still follows Stage 3 |
| Lowered cap | Configure cap two: second accepted opening immediately clears other pending work; subsequent submissions/open attempts cannot exceed two |
| Boundary pair | Extend the Stage 2 fixture to assert that the director receives at most one canonical completion and never opens from that callback. Keep score/outcome accounting assertions in the original fixture. |

Resolve `$godotExe` from actual project configuration. Intended commands from repository root:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_director.gd
# Earlier runners below are regression candidates when this stage changes a contract they exercise.
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_choices.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_feedback.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd
```

New marker: `ITER02_STAGE04_DIRECTOR_PASS`. Require explicit PASS, zero exit and no unexpected diagnostics; name expected invalid-content/configuration errors separately. Migrate Stage 3 scheduling tests rather than deleting coverage or asserting both old/new schedules. Pure Snake regression suites are unnecessary unless owning rules change or a failure warrants them.

Manual scenario with shortened settings: question active when Snake collides; observe no overlap, then retry; trigger a qualifying event near the end of an idle gap; choose each style across multiple openings; let one reaction expire; pause while a candidate waits; finish with a choice open and restart. Test donation priority only through controlled fixtures, not a new player-facing debug mode. Verify stable 1024 × 768 layout, readable three-second options and uninterrupted movement. Full six-minute balance acceptance remains Stage 7.
