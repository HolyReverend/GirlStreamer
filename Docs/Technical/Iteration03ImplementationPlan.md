# Iteration 03 Implementation Plan

> For whole-stage execution, follow the project workflow and use `stage-orchestrator`. Checkboxes track implementation and acceptance.

**Status:** Iteration 03 accepted by the user on 2026-11-18. Technical and manual checks passed.
**Goal:** Play from a single preparation screen through a streamed or skipped evening into the next morning, with visible consequences for preparation.
**Design:** [Iteration 03 scope](../GameDesign/Iteration03Scope.md), [Action points and condition](../GameDesign/Mechanics/ActionPointsAndCondition.md), [Skills and training](../GameDesign/Mechanics/SkillsAndTraining.md).
**Baseline:** [Architecture](Architecture.md), [Iterations 1 and 2 corrections](Iteration01And02Corrections.md). Godot 4.7 Standard, typed GDScript, Russian UI and existing SceneTree runners.

## Ownership and constraints

Add a day-cycle scene as the normal startup entry point. It owns the day model, preparation/results navigation and exactly one stream settlement per day. Keep `prototype_session.tscn` directly runnable with its current defaults and test entry points. The day controller reads a detached launch snapshot while PREPARING, starts the candidate with that snapshot, then commits the evening decision only on success. The stream freezes results at cutoff and hands them to the controller once closing finishes. The session retains its authority over active time, pause, Snake retry, choice cancellation and donation accounting. Per-stream state resets at every launch. Day number, condition, mastery and cumulative fictional coins live only in the running day scene.

Runtime paths below are relative to `GirlStreamer/`. New paths are proposed ownership boundaries. Use existing project validators and retain the 180 active-second duration, 20-second opening cadence, eight-opening cap, additive Snake acceleration, minimum 1024 × 768 UI, and stream keyboard/audio behavior. This iteration covers five preparation activities, Snake, donation settlement and skipping. Outfits belong to next-iteration planning. Rent and paid subscriptions are outside the iteration.

## Stage 1 — Day model

Follow the [detailed Stage 1 plan](Iteration03/Stage01DayModel.md) for the model contract, implementation sequence and acceptance cases.

- [x] Add `prototype/day/day_state.gd` as an instance-owned model. Expose a copied day snapshot, preview and commit by activity ID, and a copied launch snapshot. Use one calculation for preview and commit. Apply AP and effects atomically, clamp each condition change to 0–10, and reject invalid IDs, insufficient AP and unavailable activities without mutation.
- [x] Use 6 AP per morning. Post costs 1 and queues promotion once per day. Snake training costs 2 and changes vigor/concentration by −1/−2. Topic preparation costs 1 and changes concentration by −1. Nap costs 1 for +2 vigor, anime costs 1 for +2 concentration. Mark post and topic as one-use preparation flags. Rest uses AP even when recovery is capped. Stream and skip remain available at zero AP.
- [x] Use proposed defaults of day 1, 0 coins, vigor/concentration 8/8 and general game mastery 0. Snake is the first consumer. For this slice, only daytime training grants mastery progress. Training grants +2 progress to the first threshold at 4, then disables at the prototype cap. Use a distinct per-day phase so actions cannot commit after launch or skip. Define settlement and morning transitions for Stage 5.
- [x] Add `tests/iteration03/test_day_state.gd` for action costs, duplicate flags, insufficient AP, capped recovery, zero-condition recovery, training threshold and detached snapshots. Example: train twice, post and prepare a topic from 8/8 leaves 0 AP, condition 6/3 and mastery unlocked.

## Stage 2 — Unified preparation UI

Follow the [detailed Stage 2 plan](Iteration03/Stage02PreparationScreen.md) for the room layout, activity interactions, evening transitions and acceptance checks.

- [x] Add `prototype/day/day_cycle.tscn` and its controller plus a preparation Control scene under `prototype/day/`. Compose a single morning/preparation screen and make the day scene the startup scene in `project.godot`. Instantiate the existing stream as a child on launch and wait for its existing layout-readiness contract before starting. Keep preparation available if initialization fails, with the day's snapshot still usable.
- [x] Display day, coins, AP, both condition values, Snake progress, all five activities and their actual preview effects, active preparation flags, and the effects of condition on the coming stream. Show unavailable actions and their reason. Refresh from model snapshots after every accepted action. Provide start and skip controls independently of activity availability.
- [x] Show a short Russian heroine response after a committed activity. Inspect 1024 × 768 and 1280 × 900 in a live run. Check that costs and capped gains remain readable, zero AP still allows both evening decisions, and a single input cannot launch twice or leak into the stream. Stage 5 completes the skip and rollover path.

## Stage 3 — Snake mastery and question timing

Follow the [detailed Stage 3 plan](Iteration03/Stage03MasteryAndConcentration.md) for collision prediction, question timing and the checks tying both effects to the room forecast.

- [x] At launch, snapshot mastery and vigor/concentration tiers (6–10, 3–5, 0–2). Pass the captured assistance to `prototype/snake/snake_game.gd`. For the proposed first-threshold benefit, show an advisory danger outline for up to two projected forward cells at good vigor, one at moderate fatigue and zero at strong fatigue. Before mastery the outline is absent. Reuse the state model's wall/body legality, including the vacating tail rule, and render guidance in `snake_board.gd`. Only the first hazard within range is marked. Its location follows the predicted forward path, respects a queued turn and grants no collision rescue. Clear stale guidance on stop and rebuild it on retry using the same captured tier.
- [x] In `prototype/stream/stream_director.gd`, sample the existing viewer-based question window at opening and apply the captured concentration multiplier (1.0, 0.9, 0.8), then the proposed 5000 ms floor. Apply to normal-preset ordinary and donor questions through the same sampler. Stage 4 also uses the sampler for the prepared topic. Preserve custom standalone windows and the fixed reaction window. A retry or pause cannot recalculate the captured tier.
- [x] Check mastery below/at threshold across all tiers, valid tail movement, collision/score equivalence, lookahead reset and retry continuity. Extend `test_stream_director.gd` for tier boundaries, viewer-based sampling, floor, custom window and reaction timing. Rerun existing Snake movement, food and collision runners.

## Stage 4 — Post and prepared topic

Follow the [detailed Stage 4 plan](Iteration03/Stage04PostAndPreparedTopic.md) for opening audience counts, prepared-question priority, reply hints and acceptance checks.

- [x] Seed `prototype/stream/audience_state.gd` through the session's per-stream reset path. Proposed post effect is three additional starting viewers, one per audience group. Establish this before initial audience presentation and the first audience/donation step. Keep promotion separate from stream-attributed growth. Make start count visible and verify post-free and next-day streams use their ordinary baseline.
- [x] Author one Russian topic question in `prototype/stream/stream_content.gd` and reserve it in `stream_director.gd` when the launch snapshot is prepared. Open it on the first scheduled opening, including while waiting for Snake retry. At that opening it wins over queued donor and reaction candidates. Consume the reservation only on successful admission through the usual choice path. Count it as one ordinary opening and advance cadence from the actual opening time. Afterward, apply the regular donor → reaction → ordinary order and existing freshness and attempt checks.
- [x] In the choice HUD, mark one prepared reply with «Ты это репетировала» and a short hint describing its audience effect. Keep all three options selectable. Label the initial audience gain from the post separately from live audience changes. Test both cues with and without their corresponding activity at the minimum window size.
- [x] Extend director and integration checks for simultaneous topic/donor/reaction availability, a waiting-for-retry first opening, rejected admission followed by retry, pause/cutoff, question counters, reservation consumption and the eight-opening cap. Check equal-seed initial audience snapshots with and without post, and confirm that skipping creates no session. Stage 5 verifies next-day flag reset.

## Stage 5 — Settlement and next morning

Follow the [detailed Stage 5 plan](Iteration03/Stage05DayResultsAndNextMorning.md) for the two evening outcomes, wallet and condition calculations, results UI, input handoff and multi-day checks.

- [x] Add an explicit managed completion handoff to `prototype_session.gd` once frozen `StreamResults` are available after closing. Continue to support closing skip. In managed runs, advance through the day controller from results, including the relevant Enter path. In standalone runs, keep Enter restart. Drive settlement from the frozen donation total rather than receipt notifications or reconstruction from displayed rows.
- [x] On full stream completion, credit coins once and apply −3 vigor/−2 concentration. On skip, bypass stream creation and settle with zero stream income and load. Show day results with income, total coins and condition changes. On continuing, apply sleep (+3/+3) once, advance the day number, refill AP to 6 and clear post/topic flags. Carry mastery, resulting condition and coins in memory. Clamp stream load and sleep separately.
- [x] Add a `tests/iteration03/test_day_cycle.gd` integration runner covering completion, repeated completion signal and repeated continue input, closing skip, idle skip, skip after preparations, launch from 0 AP, two-day rollover and child teardown. Run existing timed-session, lifetime and integration suites to verify standalone use and cleanup.

## Stage 6 — Playtests and acceptance

Use the [full-day playtest and acceptance protocol](Iteration03/Stage06FullDayPlaytest.md) for the unassisted run, matched comparisons, evidence sheet and decision criteria.

- [x] Run each focused runner and affected Iteration 1/2 suites with the installed Godot executable. Example from the repository root: `& $godotExe --headless --path GirlStreamer --script res://tests/iteration03/test_day_state.gd`. Check command status and diagnostics against the runner's documented expectations.
- [x] Play paired 180-second streams with and without training/post/topic. Also compare strong fatigue to rested play, and run a skip recovery path. Use controlled condition fixtures for launch tiers unreachable in normal play; record the resulting balance limitation separately. Include one first-opening collision/retry scenario and one two-morning sequence. Record activity choices, preparation and rollover values, starting viewers, topic occurrence/time, choice windows, donation payout, player understanding of hints, and willingness to vary the day's actions.
- [x] Check preparation/results readability, physical keys and audio across Prep → Stream → Results → Morning, including the standalone window and current HUD. Review the applicable [open items](../OpenItems/Index.md) for window/input, stream pacing, day balance, skill progression, economy and result feedback. Record unresolved validation in the owning cards. Update [Architecture](Architecture.md) and current stage status when implementation and checks establish actual behavior.

Technical evidence covers both three-minute comparison arms, both skip orders, condition fixtures and rendered layouts. The user confirmed the manual checklist. See the acceptance table in the [Stage 6 protocol](Iteration03/Stage06FullDayPlaytest.md#current-verification-and-acceptance).
