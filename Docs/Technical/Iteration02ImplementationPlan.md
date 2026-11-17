# Iteration 02 Implementation Plan

> **Current corrections (2026-11-17):** [Iterations 1–2 correction plan](Iteration01And02Corrections.md) supersedes this document where duration, interaction cadence, Snake speed or HUD placement conflicts. Apply its 180-second preset to future acceptance runs. See the correction plan for current implementation and acceptance status.

> **For agentic workers:** Use the project's `stage-orchestrator` skill for whole-iteration execution and `executing-plans` for task-by-task implementation. Delegate only suitable bounded work under AGENTS.md; retain one owner of shared session/UI files and the live editor. This document authorizes no automatic commits or pushes.

**Goal:** Deliver one complete playable stream with a placeholder webcam, contextual chat, questions, donations, reactions and observable audience consequences.

**Architecture:** Extend the existing prototype composition and reuse Snake. The session owns lifetime and gameplay time; a single choice controller owns all timed input choices. Separate audience, donation, chat and character-presentation responsibilities, wired explicitly by the session without global services.

**Tech Stack:** Existing Godot 4.7 Standard / GDScript, GL Compatibility, geometric placeholder graphics and local authored text.

**Spec:** [Iteration 02 scope](../GameDesign/Iteration02Scope.md). Scope is user-approved; numeric defaults and scheduling details are proposed first-pass tuning, not approved final balance. Stages 1–6 are accepted and Stage 7 is implemented. Final acceptance remains open: [audio](../OpenItems/Items/OI-001-AudioAcceptance.md), [window/input checks](../OpenItems/Items/OI-002-WindowAcceptance.md), and [human playtest/tuning](../OpenItems/Items/OI-003-StreamPlaytest.md). Date: 2026-11-12.

## Global constraints

- Read `Codex/Workflow.md`, this spec, `Architecture.md`, and `ImplementationRules.md` before engine implementation; use `Codex/GodotSkills.md` to select specialists only for the current stage.
- Preserve the existing engine, renderer, 1024 × 768 minimum window and Snake rules. No new framework, Autoload, external service, production art, new minigame or career systems.
- All player-facing text is Russian. Design documents are Russian; technical documents are English.
- One active choice; top-row 1–3 answer all choice kinds. Arrow keys/WASD steer; Space retries. Enter starts from READY, skips CLOSING to results, or restarts from FINISHED; Escape toggles pause during an active stream.
- Stream duration 360 seconds, hard cutoff, no overtime. All stream time excludes user pause. Retries never reset stream time, audience or an open choice.
- Donation credit precedes answering and occurs exactly once. Finish cancels open choices without penalties and freezes all results before presentation.
- Each restart resets all session state. No persistent record, audience loyalty, subscriptions, saves or real payments.
- Validate focused behavior and changed dependencies; do not rerun every prior test after unrelated edits. Record actual checks and NotRun honestly.

## Baseline inspected and changes required

`prototype_session.gd` currently owns READY/RUNNING/FINISHED, starts automatically after initial layout, samples monotonic milliseconds, and wires Snake, QuickMessages and HUD. QuickMessages currently combines placeholder content, scheduling, deadlines, input and feedback. Its replacement must remove that old scheduler rather than run two input owners.

Stage 5 of iteration 01 records technical verification but leaves the paired six-minute human playtest NotRun. The user's completion statement is respected; missing recorded comfort evidence must not be treated as proof that denser interactions are comfortable. Iteration 02's final playtest covers the new combined experience; the remaining work is tracked in [OI-003](../OpenItems/Items/OI-003-StreamPlaytest.md).

`Architecture.md` describes existing implementation; update it after implementation stages, not now to portray this plan as delivered.

## File ownership and contracts

All runtime paths below are relative to `GirlStreamer/`; all new paths are planned.

| Files | Ownership |
| --- | --- |
| `prototype/prototype_session.gd`, `.tscn` | Composition, state transitions, pause-aware clock, event routing, frozen summary, seeded independent RNG streams |
| `prototype/ui/prototype_hud.gd`, `.tscn` | Board/webcam/chat/choice layout, start/pause/closing/results presentation; no game rules |
| `prototype/stream/stream_event.gd` | Typed local event record: unique session-local ID, kind, authorized active timestamp, score and reason, with attempt ID added in Stage 4; no global bus |
| `prototype/stream/stream_content.gd` | Authored questions, options, replies, chat templates and effect vectors; validates identifiers and required fields |
| `prototype/stream/stream_director.gd` | Game-event eligibility, question/reaction candidates, bounded pending slots, shared cooldown and event budget |
| `prototype/stream/stream_choice.gd` | Single open choice, deadline, 1–3 input, one resolution; replaces `messages/quick_messages.gd` |
| `prototype/stream/audience_state.gd` | RefCounted group counts, impression, fixed-step arrivals/departures, repeat attenuation and snapshots |
| `prototype/stream/donation_controller.gd` | Seeded donation sampling, donor/group/content selection, unique payment records and total |
| `prototype/stream/chat_feed.gd` | Context selection, no immediate template repeats, bounded visible/history buffer |
| `prototype/ui/hero_webcam.gd`, `.tscn` | Placeholder face/pose, emotion label and reply presentation priority |
| `prototype/stream/stream_audio.gd`, `prototype/audio/` | Local placeholder sounds, mute; playback is not authoritative timing |
| `project.godot` | Start/pause actions; preserve movement/retry/answer mappings |
| `tests/iteration02/test_*.gd` | Small engine-native checks owned by stages below |

Use typed local records in `stream_content.gd`: ChoiceDefinition (ID, kind, prompt, three options, window), ChoiceOption (label, reply, emotion, three-group effect), ChatLine (nick, text, context). Avoid untyped cross-system dictionaries. Shared content stays immutable; mutable session state stays on its owner.

Contracts to define in the owning stage and keep consistent:

- Session: `get_stream_time_msec() -> int`, `is_stream_active() -> bool`; paused time does not advance. Existing Snake authorization remains session-owned.
- Event: kinds FOOD, MILESTONE, RECORD, COLLISION, BOARD_COMPLETED; one ID per source occurrence. FOOD is ordinary feedback; milestones at attempt scores 5/10/20 are awarded once each per session. Combine simultaneous milestone/record into one significant event.
- Choice: `try_open(definition: StreamContent.ChoiceDefinition, now_msec: int) -> bool`, `tick(now_msec: int) -> void`, `cancel(now_msec: int) -> void`; `resolved(choice_id: int, option_index: int, outcome: StringName)` with answered/expired/cancelled and -1 for no option. Definition retains source-event/group association until resolution.
- Director: `submit_event(event: StreamEvent) -> void`, `submit_donation_question(definition: StreamContent.ChoiceDefinition, now_msec: int) -> void`, `tick(now_msec: int, snake_playing: bool) -> void`, `reset() -> void`. It requests opening only through the choice owner.
- Audience: `reset() -> void`, `apply_effect(effect_id: int, effects: Vector3, repeat_key: StringName) -> void`, `advance_second() -> void`; expose copied group/count/impression snapshots. Empty repeat_key means no style attenuation. The session deduplicates sources in separate namespaces and assigns strictly increasing effect IDs. Base and reaction effects receive separate IDs.
- Donations: `reset(seed: int) -> void`, `tick(now_msec: int, counts: Vector3i, impressions: Vector3) -> void`; `donation_received(id: int, group_index: int, amount: int, nick: String, message: String, has_question: bool)`. Credit is committed before emitting this signal.
- Chat: `append_context(context: StringName, now_msec: int) -> void`, `reset(seed: int) -> void`; audience/chat randomness never consumes Snake's RNG.
- Webcam: `show_automatic(emotion: StringName, now_msec: int) -> void`, `show_reply(text: String, emotion: StringName, now_msec: int) -> void`, `reset() -> void`. Finite presentation deadlines use stream time; closing has a separate non-gameplay presentation lifecycle.

## Review focus

1. Stage 1 owns the pause clock. Stage 4 checks pending-choice freshness, Stage 6 checks donation scheduling, and Stage 7 checks audio stop/resume behavior.
2. Donation, collision and question arriving together must not displace an open choice or lose credit — Stages 4 and 6.
3. Waiting for retry must not freeze the stream, open ordinary questions, or erase an existing choice — Stages 3 and 4.
4. Repeated losses/style spam must not produce duplicate rewards or profitable reaction farming — Stages 4 and 5.
5. Finish/restart during pending presentation must not mutate frozen results or replay old notifications — Stage 7.

## Stage 1 — Stream shell and pause-aware lifetime

**Detailed plan:** [Stage01StreamShell.md](Iteration02/Stage01StreamShell.md).

**Files:** modify session, HUD, Snake controller/model (pending-turn clearing only), `project.godot`, and affected iteration 01 fixtures; create `tests/iteration02/test_stream_lifetime.gd`.

- [x] Add focused clock/lifetime checks. Confirm the initial readiness check fails on the old automatic start.
- [x] Replace automatic start after layout with a READY screen and brief Russian controls. Keep layout readiness as a start prerequisite.
- [x] Implement READY → RUNNING ↔ PAUSED → CLOSING → FINISHED and use active gameplay elapsed time for action authorization.
- [x] Route existing message deadlines to the stream clock and clear pending direction input across pause.
- [x] Reserve board, webcam, feed and choice regions. Verify bounds and board stability at 1024 × 768 and 1280 × 900 in the lifetime runner.
- [x] Run lifetime checks and iteration 01 regressions, including the migrated explicit-start, clock and Russian HUD assertions.
- [x] Implement minimal two-second CLOSING. Stage 7 will extend this lifecycle with presentation and expanded results.
- [x] Complete windowed acceptance. The user confirmed the remaining checks in the stage record.

**Deliverable:** current Snake/questions inside a manually startable, pausable stream shell. Existing choice behavior remains until Stage 3.

## Stage 2 — Contextual chat and automatic webcam

**Detailed plan:** [Stage02ChatAndWebcam.md](Iteration02/Stage02ChatAndWebcam.md).

**Files:** create event, content, chat and webcam files; modify session/HUD composition; create `tests/iteration02/test_stream_feedback.gd`.

- [x] Verify context eligibility, bounded storage and no consecutive identical template.
- [x] Route canonical events from existing Snake signals. Score reset produces no event. A terminal full-board step produces one completion event.
- [x] Implement five webcam states, short captions and two-second automatic emotions with priority. Selected replies are Stage 3 work.
- [x] Add three templates per context, a fixed four-second ambient cadence and a 60-line limit. Viewer-dependent timing is Stage 5 work.
- [x] Run feedback and affected lifecycle checks.
- [x] Verify minimum-window readability, chat wrapping and separation from the board and choice area.
- [x] User accepted Stage 2 after their own play check.

**Deliverable:** Snake feels like a broadcast through contextual spectators and automatic character feedback, without audience rewards yet.

## Stage 3 — Meaningful questions and shared choice input

**Detailed plan:** [Stage03MeaningfulQuestions.md](Iteration02/Stage03MeaningfulQuestions.md).

**Files:** create choice controller; extend content; replace QuickMessages in session/scene; adapt HUD; create `tests/iteration02/test_stream_choices.gd`.

- [x] Verify deadlines, repeated keys, cancellation, retry and copied outcomes.
- [x] Replace QuickMessages with the typed StreamChoice and migrate its coverage.
- [x] Author twelve questions and schedule them with the configured spacing and contextual eligibility.
- [x] Present the chosen reply and compatible chat response. Store provisional group effects for Stage 5.
- [x] Use a six-second default window and snapshot it when opening.
- [x] Run the focused and affected regression suites.
- [x] User accepted Stage 3 after their own play check.

**Deliverable:** authored conversations with visible character responses and one authoritative choice lifecycle.

## Stage 4 — Reactions and one interaction scheduler

**Detailed plan:** [Stage04ReactionsAndDirector.md](Iteration02/Stage04ReactionsAndDirector.md).

**Files:** create director; extend content/session/webcam wiring; create `tests/iteration02/test_stream_director.gd`.

- [x] Verify contention, expiry, cooldown, cap, and retry eligibility with synthetic donation candidates.
- [x] Transfer all candidate scheduling to StreamDirector. Defaults are 30 seconds to the first opening, 25 seconds after each resolution, and at most eight openings.
- [x] Bound the pending reaction and donation-question slots and arbitrate donation → reaction → ordinary question.
- [x] Offer reactions for first-time milestones, qualifying records, completion and losses. Start the 60-second eligibility cooldown on admission and preserve canonical event precedence.
- [x] Use fixed style positions, a three-second window, two variants per category and neutral expiry.
- [x] Open eligible loss and completion reactions while waiting for retry. Ordinary and donation questions require a playing attempt.
- [x] User accepted Stage 4 after their own play check.

**Deliverable:** questions and reactions share one readable rhythm, with no interruption of the current choice or Snake motion.

## Stage 5 — Audience consequences

**Detailed plan:** [Stage05AudienceConsequences.md](Iteration02/Stage05AudienceConsequences.md).

**Files:** create audience state; extend content/director/session/HUD; create `tests/iteration02/test_stream_audience.gd`.

Proposed initial numerical model, isolated for tuning:

- Start with counts (10,10,10), impressions (50,50,50), bounds 0–200 viewers per group and 0–100 impression. No cross-session loyalty.
- Each whole gameplay second accumulate per-group viewer change `(impression - 40) / 200`; consume whole positive/negative units into arrivals/departures, retaining signed fractions. At a population bound discard the blocked fraction. Decay impression toward 50 by 0.1 per second. Use fixed steps, not render-frame increments.
- Effects in gamer/social/image order: first milestone or qualified record (+8,+2,+2), ordinary collision (−2,−1,−1). Award a board completion (+10,+3,+3) only once per session; collapse it with a coincident record/milestone into one strongest achievement.
- Proposed record protection: after a rewarded milestone, record or first completion, delay the next base RECORD reward by 60 active seconds; intermediate records do not extend that delay. Milestones/completion retain their own once-per-stream eligibility. This numerical gate is separate from Stage 4 reaction eligibility and cosmetic feedback.
- Reaction vectors: азарт (+4,+1,0), юмор (+1,+4,+1), флирт (0,+1,+4). For the nth use of a style multiply its positive extra effect by `1/n`; at most two loss reactions can grant a positive effect per stream. Further losses remain visible without positive reaction income hooks.
- Ordinary authored answer effects stay within −2…+4 per group and must differ by context; donate-question effects use the same base vector ×1.5. Expired ordinary question: zero; expired shown donation question: −2 to its source group. No penalty for pending questions never shown.

- [x] Verify deterministic steps, bounded state, effect identity and loss/style repeat limits.
- [x] Route effects through the session and expose copied audience snapshots.
- [x] Show current/peak viewers, group impressions and measured causes. Retain the newest 20 causes.
- [x] Record the fixed-seed scenarios and provisional tuning observations in the local work reports (write-only; see Codex/Workflow.md).

**Deliverable:** choices and play measurably change the audience, with visible reasons and repeat protection.

## Stage 6 — Donations and priority questions

**Detailed plan:** [Stage06Donations.md](Iteration02/Stage06Donations.md).

**Files:** create donation controller; extend director/content/chat/HUD/session; create `tests/iteration02/test_stream_donations.gd`.

Proposed sampler: on the 10-second active-time grid, sample at most the latest due slot per update and compute group weights `count × impression / 100`. With zero total weight, no donation. Otherwise probability is `clamp(total_weight / 60, 0, 0.65)`; sample at most one donation and choose group proportional to weight. Amount distribution is identical across groups: 2/5/10/25 coins with probabilities 50/30/18/2 percent. Thirty percent contain a question; the rest may contain non-interactive text. No guaranteed income floor or direct payout per answer. Higher impression after a significant event naturally improves subsequent sampling rather than adding a second reward channel.

- [x] Verify seeded sampling, weight/probability and amount boundaries, and one credit per payment ID.
- [x] Commit payment before routing its chat line, notification and optional question.
- [x] Route donor questions through shared priority. Bound notifications to one visible and three pending, with an overflow summary.
- [x] Verify crowded receipt, outcomes, pause, cutoff and restart.
- [x] User accepted Stage 6 after their own play check.

**Deliverable:** donations are generated from audience state, credited once, and integrated into the shared interaction rhythm.

## Stage 7 — Complete stream and acceptance

**Detailed plan:** [Stage07CompleteStream.md](Iteration02/Stage07CompleteStream.md).

**Files:** create audio owner/assets and `tests/iteration02/test_stream_integration.gd`; finish session/HUD/webcam; update `Architecture.md`; create a new `Reports/Doc/Report_Doc_YYYY_MM_DD_HH_mm_JobName.md` during actual evaluation.

- [x] Verify crowded finish, frozen results, restart, pause and audio routing in the integration runner.
- [x] Extend closing with a webcam goodbye, finish cue and a scrollable frozen summary.
- [x] Add three original cues and process-local mute. Pause stops active effects and resume does not replay them.
- [x] Load touched scenes and audio in Godot 4.7.2 and pass the integration and Stage 1–6 owning runners.
- [ ] Manually play full three-minute gameplay-focused and communication-focused sessions with matching initial settings/seeds. Record reading/steering comfort, perceived causes of viewer changes, donation behavior and recovery after mistakes. Add one short repeated-loss abuse scenario.
- [ ] Verify start, pause, resizing at the supported minimum, ending, restart and mute in a standalone run. Packaging/export is not a separate deliverable of this iteration.
- [x] Record technical evidence and open play checks. Update the architecture to actual ownership.

**Deliverable:** one complete stream that a player can start, understand, finish and replay, with all scope acceptance scenarios covered.

## Verification procedure and execution boundaries

Stage 1 owns clock and shell boundaries; Stage 2 owns canonical event routing and automatic feedback; Stage 3 owns the choice lifecycle; Stage 4 replaces Stage 3's temporary scheduling checks with arbitration checks; Stage 5 owns audience arithmetic; Stage 6 owns payment and its routing; Stage 7 owns the combined frozen snapshot and audio. Extend an existing fixture when a later stage adds an assertion to the same scenario. Add a separate integration case when a new interaction between owners would otherwise go unchecked. Command lists in stage plans identify the owning runner and regression candidates.

Use the existing engine-native SceneTree runner convention. For each meaningful new rule, run its focused check before implementation to confirm the expected failure, then after implementation to confirm success. Resolve the actual Godot executable through project instructions; do not invent an installation path. Intended invocation: `& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd` (substitute the owning stage's runner). Expected result: exit code 0, explicit success output and no parser/runtime errors. Use the installed binary's supported flags.

Stages are sequential because later systems consume earlier contracts. A bounded reader/content reviewer can work independently; concurrent edits to session/HUD/content or concurrent editor access cannot. Before each stage, inspect the current owning files rather than assuming this plan is a record of implementation.

See the individual stage plans and Architecture.md for current implementation and acceptance status. Final coefficient tuning remains subject to the recorded playtest; changes to approved scope require a new user decision.
