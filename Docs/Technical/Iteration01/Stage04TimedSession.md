# Stage 4: Timed Session and Session Results — Detailed Implementation Plan

Date: 2026-11-12. Status: planned; implementation and runtime acceptance are not claimed.

**Goal:** Combine multiple Snake attempts into one 360-second session, retain aggregate results across retries, stop at the deadline and allow a fresh session from the results screen.

**Architecture:** `PrototypeSession` owns the session lifecycle, monotonic deadline and aggregate counters. `SnakeGame` retains attempt simulation and consults a parent-supplied authorization callback before gameplay actions. Existing HUD controls display time/results; neither the model nor HUD owns session time.

**Tech stack:** Godot 4.7 Standard, typed GDScript, existing scenes, native Control UI and Input Map.

**Specification:** [Iteration 1 roadmap](../Iteration01ImplementationPlan.md), Stage 4 and shared contracts; [Stage 3](Stage03CollisionsAndRetries.md); [Stage 2](Stage02FoodAndGrowth.md); [Core gameplay loop](../../GameDesign/Mechanics/CoreGameplayLoop.md), session duration section.

This is a documentation-only plan. Before implementation, follow the project workflow, engine implementation rules and whole-stage workflow. Inspect actual Stage 1–3 code and validation evidence; plans do not prove implementation. Reconcile implemented interfaces before editing. Checkboxes below describe future work.

## 1. Scope and player-visible behavior

| Situation | Behavior |
| --- | --- |
| First launch | Automatically start one session after the initial board layout is usable, preserving the existing launch flow. |
| Session duration | 360 seconds by default. Finish at expiry without waiting for collision, full board or a round boundary. |
| Collision or full board before expiry | End only the attempt; continue counting session time while waiting for Space. |
| Space before expiry | Reset only Snake's attempt state; retain session start/deadline and totals. |
| Time expires during play | Stop Snake on its last valid state, freeze results and show the session summary. |
| Time expires while waiting | Replace the retry prompt with session results; Space can no longer start an attempt. |
| Finished session | Show elapsed duration, total food, attempts started, collisions and completed boards. Keep the final board visible. |
| Fresh Enter after results appear | Start a new full session in the same scene instances, clearing all previous session and attempt state. |

The immediate cutoff follows the iteration roadmap's explicit simplification of the design's proposed bounded overtime. Do not add overtime, pause/resume, persistent records, economy, rewards, analytics infrastructure, questions, reaction logic or menus in this stage.

Export `session_duration_seconds: int = 360` on PrototypeSession with an Inspector range of 1–600 seconds. Short values are for targeted checks; six minutes remains the normal preset. Validate the range before a new session and snapshot its duration then. Changing an Inspector value during play does not alter the current deadline. Invalid configuration produces a diagnostic and a readable error, not a partially running session.

## 2. Planned file changes

Paths are relative to `GirlStreamer/` (`res://`). Extend existing files.

| File | Change |
| --- | --- |
| `prototype/prototype_session.gd` | Session enum, clock/deadline, totals, expiry/start paths, action authorization and new-session input. |
| `prototype/snake/snake_game.gd` | Inject/check action authorization before steering and each simulation step; preserve existing attempt/model behavior. |
| `prototype/ui/prototype_hud.tscn` | Add a time label, session-food label and a hidden results panel using existing Containers. |
| `prototype/ui/prototype_hud.gd` | Typed display methods for remaining time, total food and final results; retain score/status/layout methods. |
| `project.godot` | Add `session_restart` mapped to Enter; preserve Space and movement actions. |
| `tests/iteration01/test_timed_session.gd` (new) | Bounded session/deadline/accounting/reset checks with a controlled clock. |
| `tests/iteration01/test_snake_collisions.gd` | Adapt parent-scene retry tests to a controlled, unexpired session clock. |
| `tests/iteration01/test_snake_food.gd` | Supply an explicit allow callback in standalone SnakeGame fixtures. |

Standalone SnakeGame fixtures in any affected runner also receive an explicit allow callback. The pure model runners require no clock. Do not change SnakeState collision/growth rules or the board snapshot format. No new service, Autoload, Timer scene, Resource schema or results scene is required.

## 3. Session lifecycle and public contracts

Use one authoritative enum:

```gdscript
enum SessionState { READY, RUNNING, FINISHED }
```

Initial state is READY. The first settled positive-size layout triggers `start_session()` once. FINISHED remains stable until a fresh authorized new-session action; subsequent layout events only update drawing geometry.

| Method | Contract |
| --- | --- |
| `start_session() -> bool` | Allowed from READY or FINISHED only. Validate settings, initialize clock/counters, start Snake and return success. Reject calls while RUNNING without resetting anything. |
| `get_elapsed_seconds() -> float` | Zero in READY; clamped monotonic elapsed time in RUNNING; captured elapsed duration in FINISHED. |
| `get_remaining_seconds() -> float` | Current snapshotted duration minus elapsed, clamped at zero; zero in READY/FINISHED. |
| `_sample_running_time_msec() -> int` | Read `_now_msec()` once; return integer elapsed milliseconds from that same authorized sample. Return -1 unless RUNNING, finishing an expired session before returning -1. |
| `_authorize_snake_action() -> bool` | Return whether `_sample_running_time_msec()` is nonnegative. Used by Snake and retry routing; do not implement a second deadline policy. |
| `_try_retry_attempt() -> bool` | First authorize against session state/current time, then require WAITING_FOR_RETRY and invoke Snake's existing restart. Preserve clock/totals. |
| `_finish_session() -> void` | Idempotent expiry transition: only RUNNING can become FINISHED. Stop Snake and publish one stable summary. |
| `_now_msec() -> int` | Narrow internal time source; production returns `Time.get_ticks_msec()`. Tests override this method in a local fixture subclass. |

The time getters are read-only; expiry is enforced by `_sample_running_time_msec()`, reached from updates and action authorization. Stage 5 reuses that sampler for questions so authorization and elapsed time come from the same clock read. Do not authorize first and then sample a later getter for the same action. No message subsystem or unused cancellation signal is added now.

### Starting a new session

Validate session duration before discarding a previous summary. For a valid start, stop old Snake execution, clear results/status and all counters, set the score baseline to zero, capture start/deadline, enter RUNNING, and call `snake_game.start()`. Connections and the authorization callback must already be configured. On successful start set attempts started to one. Initial `score_changed(0)` updates presentation without awarding food.

If Snake validation fails, return to READY, clear the attempted clock/counters, leave Snake STOPPED and display the configuration error. This is a failed startup, not a completed session. After correcting configuration, rerun from the editor; no settings-recovery menu is needed. An unsuccessful attempt retry due to invalid Snake configuration retains Stage 3's error handling; the already running session clock continues to its deadline.

## 4. Authoritative clock and expiry ordering

Capture `start_msec` and `deadline_msec = start_msec + duration_seconds * 1000` at successful startup preparation. Read the monotonic source; do not decrement a Timer label, use system date/time or restart a countdown on attempt reset. Godot's [Time reference](https://docs.godotengine.org/en/4.4/classes/class_time.html) distinguishes monotonic tick methods from adjustable system time; verify the API against the installed 4.7 build during implementation.

The session `_process(delta)` calls `_sample_running_time_msec()` once. On -1 it returns; otherwise it updates the countdown from `duration_seconds - elapsed_msec / 1000.0`. All authoritative deadline comparisons stay in integer milliseconds; seconds getters are for presentation/measurements. The sampler expires the session at `now >= deadline_msec`. The clock continues during retry waiting and window focus loss. There is no user pause in this iteration. If execution stalls, the first resumed update/action sees the elapsed monotonic time and ends an expired session rather than extending it or simulating overdue gameplay. This is an experiment policy, not a final pause/resume design.

### Gate actions independently of callback order

Add `SnakeGame.set_action_authorizer(authorizer: Callable) -> void`. The callback takes no arguments and returns bool. The parent installs its bound `_authorize_snake_action` once before initial start. Store it as a private Callable and check validity; a missing/invalid callback denies actions and reports a setup error rather than silently allowing unlimited play. Test fixtures may install a named always-true callback when testing Snake alone.

Within SnakeGame, check authorization while PLAYING:

- Before accepting a recognized pressed/non-echo direction event.
- At the start of its physics callback and immediately before **each** due model step in the accumulator loop.

On denial return immediately without adding/consuming further timing debt, queuing a turn or calling `step()`. The parent may synchronously call `snake_game.stop()` from inside the authorizer: code must tolerate this state change and must not restore PLAYING afterwards. The authorizer never starts a new attempt or advances simulation. The parent's retry helper also calls it before restarting.

This preserves Snake's `_physics_process` accumulator without relying on parent/child callback order, process priorities or a Timer timeout arriving before keyboard input. At the exact deadline, a pending movement, food collection or retry is rejected. Expiry calls `stop()`, so Snake's model is not falsely marked dead or complete and no artificial `attempt_finished` event is emitted.

An individual model step admitted just before the deadline is atomic: its score/finish signals are accounted synchronously before the next time check. Do not reread the clock inside those accounting handlers and discard half of an already admitted step. At/after-deadline actions are never admitted; catching up after a stall does not replay historical steps past expiry.

### Finishing once

On expiry set FINISHED first, record elapsed as the configured duration (no displayed overrun), then call Snake's generic `stop()` to clear timing debt and prevent steering/retry. Freeze Snake counters and final attempt score. Set remaining time to zero, replace attempt status with `Session finished`, and publish the results panel exactly once. Stage 5 inserts synchronous question cancellation/accounting between Snake stop and the combined result snapshot; do not freeze the message totals before that cancellation. Repeated updates, queries, direction events and Space cannot recalculate totals or add terminal events. Do not pause the SceneTree; result input still works.

## 5. Aggregate accounting

All counters are integer fields owned by PrototypeSession. They are accumulated during RUNNING and reset only by `start_session()`.

| Field | Meaning / update |
| --- | --- |
| `total_food` | Sum of all food collected, including an unfinished last attempt. Add positive changes from `score_changed`. |
| `attempts_started` | One for the initial successful start, plus one per successful retry. Failed starts/rejected Space do not count. |
| `collisions` | Increment once for `wall_collision` or `self_collision` received through `attempt_finished`. |
| `boards_completed` | Increment once for `board_full`. |
| `last_attempt_score` | Previous score notification for the current attempt; used only to calculate deltas, not a second score authority. |

On `score_changed(score)`, add `score - last_attempt_score` to total food and update the baseline/HUD. Before an authorized initial start or retry, set the baseline to zero so the reset's zero notification neither subtracts prior food nor awards anything. An unexpected decrease outside this reset path is a contract error; report it instead of silently altering totals. Before an eligible retry, retain the previous baseline locally; if `restart_attempt()` returns false, restore it. A rejected input or failed retry must not change the baseline, totals or attempts-started count.

Do not add `attempt_finished.score` to total food: those points were already counted while playing. That payload can be checked against the current attempt score for consistency. The finish handler only increments the matching outcome counter and displays the retry prompt if the session is still RUNNING. Ignore late notifications once FINISHED; use synchronous connections, not deferred callbacks carried into a new session.

Example: collect three food, collide, retry, collect two and reach session expiry. Final result is five food, two attempts started, one collision and zero completed boards. The interrupted last attempt contributes its food but is not classified as a collision or completed board. At most one started attempt is unfinished; waiting at expiry adds no new outcome.

## 6. Results UI and restart input

Keep the current scene and visible board. Extend the HUD VBox with `TimeLabel`, `SessionFoodLabel` and a `ResultsPanel` containing a multiline Label, outside BoardArea. Hide the panel during play; show it after expiry. Containers continue to control layout and board resizing without resetting state. No focusable buttons are needed for this keyboard prototype.

Add these typed HUD methods:

| Method | Presentation only |
| --- | --- |
| `set_remaining_time(seconds: float) -> void` | Format nonnegative remaining time as `Time: MM:SS`, rounding up so any positive remainder displays at least 00:01. At finish display 00:00. |
| `set_total_food(total: int) -> void` | Display `Session food: N`, distinct from existing attempt `Score: N`. |
| `show_session_results(elapsed_seconds: float, total_food: int, attempts_started: int, collisions: int, boards_completed: int) -> void` | Show a labeled summary plus `Enter — new session.` No calculations or gameplay callbacks. |
| `hide_session_results() -> void` | Hide old summary on new startup. |

Add `session_restart` on Enter; do not overload Space. The parent handles it only when FINISHED, pressed and non-echo. Call `start_session()` once and consume that accepted event. Holding Enter must not restart a later session, and repeated presses while RUNNING must do nothing. Space remains attempt retry only and never becomes a new-session action.

Route an input using the session state at handler entry. For either recognized session-owned action (Space or Enter) received in RUNNING, call the authorizer before deciding whether the action is eligible. If it discovers expiry, finish and return; do not reinterpret that same key event as a FINISHED-state new-session request. This leaves results visible until a subsequent deliberate Enter press. Keep number keys 1–3 unclaimed for Stage 5.

## 7. Implementation sequence

### A. Session state and time authority

- [ ] Inspect accepted Stage 1–3 implementation, especially parent input, startup order, synchronous signal connections and generic stop behavior.
- [ ] Add controlled-clock deadline tests from Section 8 and confirm meaningful failures against the untimed session.
- [ ] Implement the session enum, snapshotted duration, monotonic time source, expiry transition and guarded startup/retry.
- [ ] Install the action authorizer and enforce it before Snake input/each step; preserve the existing accumulator and model rules.

### B. Results and new-session flow

- [ ] Implement event-based aggregate counters, reset baseline and successful-attempt counting.
- [ ] Extend HUD with time/total/results presentation and add Enter input. Ensure layout callbacks never reset clocks or totals.
- [ ] Adapt prior standalone controller fixtures and parent retry tests to explicit authorization/controlled time.
- [ ] Run the focused session tests and relevant controller regressions; perform the shortened editor scenario below.
- [ ] Record evidence and `NotRun` checks, restoring the normal 360-second preset after short manual testing.

## 8. Necessary verification

Create one bounded runner `tests/iteration01/test_timed_session.gd`, using the existing test reporting style. A test-local PrototypeSession subclass overrides `_now_msec()` with a controlled integer. Attach it to an instance of the real session PackedScene before entering the tree so layout, handlers and HUD remain real; initialize clock/settings before auto-start. No production clock setter, sleep-based test or full six-minute automated wait is needed.

Disable automatic processing only when manually driving a fixture. Advance fake monotonic time explicitly and call the relevant real session/controller callbacks; a test that only calls `_finish_session()` bypasses the behavior being verified. Bound layout/readiness waits. Use the following five groups:

1. **Retry preserves time and totals:** set duration to two seconds and start at fake time 1000 ms (deadline 3000). Reach score three through controlled valid collections or synchronize a scored model through the real score signal before collision. At 1500 collide, at 2000 send Space through the parent. Check deadline still 3000, remaining one second, total food three, attempts two, collisions one, attempt score zero and unchanged node instances. Advance while waiting in a separate subcase to prove time is not conditional on Snake PLAYING.
2. **Expiry precedes movement and retry:** at 3000 ms, call Snake's physics callback with a due step **before** calling the session update. No movement/food/score change is allowed; session becomes FINISHED and Snake STOPPED. Repeat with Snake waiting and Space routed before the update: no reset, no new attempt. Check a just-before-deadline action is allowed in a separate fixture, and a stalled jump beyond the deadline gives the same cutoff without catch-up steps. Within another single catch-up callback, script clock samples to admit callback entry and the first due step, then reach the deadline before the second due step. Only the first step and its food/score effects may survive; Snake must stop with zero timing debt and one summary. Also send a recognized direction event at the deadline before any session update and verify no turn is queued. Repeated callbacks do not republish/change results.
3. **Accounting includes the last attempt exactly once:** produce the three-food/collision/two-food example from Section 5, expire and expect totals 5/2/1/0. Verify reset-to-zero never subtracts food, terminal payload does not add it twice and expiry adds no collision. With the existing near-full fixture, route its initial score through the real signal path before the final collection; verify one board completion and one additional food, with no duplicate contribution from `attempt_finished`.
4. **New session resets once:** after results, advance the fake clock and send Enter (non-echo). Check a fresh deadline relative to the new start, cleared counters except attempts started = 1, zero score, fresh body/food, PLAYING, zero accumulator, hidden summary and unchanged node IDs. An Enter echo, release or another Enter during RUNNING must not reset time/counters. Repeat one finish/start cycle and count signals to detect duplicated connections; Space after finish must not start a session.
5. **Presentation and input boundary:** at 1 ms remaining the HUD shows 00:01, at expiry 00:00 and the summary has frozen metrics. An Enter event arriving while still logically RUNNING at the deadline finishes but does not immediately start again. Keep configuration range/failure behavior as startup guards and inspect their implementation; do not add a matrix of invalid settings or live Inspector edits to this gameplay suite.

Record explicit expected counters at each fixture setup; replacing a model alone does not notify the session/HUD. Use the real signal route and reset observation counters after setup where appropriate. Full-board fixtures must keep grid dimensions and score/body state consistent. Test both controller state and visible results so a stopped model cannot mask a running session.

Print `STAGE04_SESSION_PASS groups=5` only when all assertions/subcases complete. Exit nonzero on failure and treat unexpected engine errors as failure. Reuse existing validated reporting; do not add a testing framework. Resolve the actual Godot 4.7 console binary and verify flags before executing the equivalent of:

```powershell
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_timed_session.gd
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_collisions.gd
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_food.gd
```

Capture output and `$LASTEXITCODE` separately for each command. Stage 3's parent retry tests need a frozen unexpired clock; standalone controllers use an allow callback. The collision and food controller tests cover the modified authorization path. Pure movement rules are unchanged; rerun that runner only if implementation changes their code or new failures justify it. Follow project single-editor/import rules for scene tests.

### One shortened editor scenario

Use a 15-second session. Collect food, collide and verify the timer keeps counting while waiting; Space resets only attempt score/body. Let the session expire, confirm the board stops, Space is disabled and readable results replace retry feedback. Enter begins a fresh 15 seconds with cleared totals. In a second short run stay waiting until expiry to check the visible transition there. Restore the default 360 seconds and verify the next launch displays 06:00 initially. Inspect the debugger for relevant errors.

Do not run the six-minute divided-attention playtest yet: it belongs to the combined prototype after Stage 5. No packaging, device matrix, pause/save behavior or question simulation is required here.

## 9. Acceptance and Stage 5 handoff

- [ ] One session deadline survives all attempt failures and retries; time continues while waiting.
- [ ] Deadline checks prevent new movement/retry at expiry regardless of callback order; results freeze once.
- [ ] Food and attempt/outcome totals match the defined accounting, including an unfinished final attempt.
- [ ] Enter starts one fresh session, reusing scene instances and clearing clock, totals, attempt state and old summary.
- [ ] Focused tests, relevant controller regressions and the shortened editor scenario have recorded outcomes; normal duration is restored.
- [ ] Report actual changed files, commands/results and `NotRun` checks; do not claim final balance or messaging validation.

Stage 5 will attach its message lifecycle to session start/finish, reuse `_sample_running_time_msec()` for authorized updates/answers and cancel an active question before publishing session results. Attempt retry must never reset that message clock/state. No stub message manager or question-related metrics are required before that stage.
