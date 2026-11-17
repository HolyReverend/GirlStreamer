# Stage 3: Collisions and Retrying an Attempt — Detailed Implementation Plan

Date: 2026-11-12. Status: accepted on 2026-11-12.

**Goal:** End a Snake attempt on wall/self collision and let the player start a fresh attempt with Space without reloading the session scene.

**Architecture:** The existing `SnakeState` decides collisions before applying movement or food effects. `SnakeGame` owns attempt execution and emits one terminal notification. `PrototypeSession` owns retry authorization/input and reuses the existing Snake instance; the HUD only presents score and status.

**Tech stack:** Godot 4.7 Standard, typed GDScript, existing scenes and Input Map. Preserve the renderer, drawing layout, fixed-tick timing and plugin configuration.

**Specification:** [Iteration 1 roadmap](../Iteration01ImplementationPlan.md), Stage 3 and shared contracts; [Stage 1](Stage01SnakeMovement.md); [Stage 2](Stage02FoodAndGrowth.md); [Minigames](../../GameDesign/Mechanics/Minigames.md), attempt and Snake rules.

Stage 3 extends the accepted Stage 1–2 implementation.

## 1. Behavior and scope

| Event | Result |
| --- | --- |
| Next head lies outside the grid | End the attempt with reason `wall_collision`; no wrap or boundary sliding. |
| Next head enters a retained body cell | End the attempt with reason `self_collision`. |
| Next head enters the current tail cell on a nongrowing step | Allow movement because that tail cell is vacated in the same operation. |
| Collision | Freeze the last valid board and preserve food/score; show the reason and Space prompt. |
| Full board | Preserve Stage 2's successful completion and final score; now offer the same Space retry. |
| Fresh Space press while waiting | Start one fresh attempt in the same Snake/session instances. |
| Space during play, key release or keyboard echo | No retry; held Space must not automatically restart a later failed attempt. |
| New attempt | Centered three-cell body facing right, zero score, one valid food, empty turn buffer and zero timing debt. First movement follows one full interval. |

There are unlimited attempts at this stage. No lives, cooldown, automatic retry, death animation, extra score penalty, session totals or six-minute timer are introduced. The session timer and its expiry gate belong to Stage 4; only the ownership boundary needed to preserve them is established here. Questions and message clocks remain Stage 5 work.

This stage replaces the temporary wall guard and absent self-collision response from Stages 1–2. Earlier documents describe their own increments; their temporary behavior is no longer the acceptance target after Stage 3. The food, growth, score, steering and full-board rules otherwise remain intact.

## 2. Planned file changes

Paths below are relative to `GirlStreamer/` (`res://`). Extend existing files rather than reconstructing the scene tree.

| File | Change |
| --- | --- |
| `prototype/snake/snake_state.gd` | Terminal reason, collision-aware stepping, tail exception and terminal/reset queries. |
| `prototype/snake/snake_game.gd` | Explicit attempt lifecycle, one terminal notification, guarded restart and stopped input/processing. |
| `prototype/prototype_session.gd` | Own Space input and retry authorization; route outcome text and reset status. |
| `prototype/ui/prototype_hud.tscn` | Replace the temporary boundary note with final controls; reuse existing score/status labels. |
| `project.godot` | Add `attempt_retry` mapped to Space. |
| `tests/iteration01/test_snake_collisions.gd` (new) | Focused collision rules and lifecycle/retry integration checks. |
| `tests/iteration01/test_snake_movement.gd` | Remove the temporary wall case; retain the four movement/steering groups. |
| `tests/iteration01/test_snake_food.gd` | Adapt terminal/reset state and full-board controller fixtures; keep collision checks in the collision runner. |

No board renderer or HUD API change is required: reuse `set_snapshot(...)`, `set_score(score)` and `set_status(message)`. No physics bodies, collision shapes, Area2D signals, scene reloads, new gameplay scenes, global event bus or Autoload are needed for integer-grid collision.

## 3. SnakeState: terminal state and atomic step

Keep the existing model a `RefCounted` without scene access or signals. Use one authoritative `_finish_reason: StringName`, initially `&""`, with permitted terminal values `&"wall_collision"`, `&"self_collision"`, `&"board_full"`. Replace the Stage 2 completion flag with this reason; do not maintain independently writable `dead`, `complete` and `finished` flags.

| Interface | Stage 3 contract |
| --- | --- |
| `reset(grid_size: Vector2i, random_source: RandomNumberGenerator) -> void` | Preserve Stage 2 reset, additionally clear all terminal state. |
| `step() -> bool` | True for a successful move, including final collection; false for a collision or an already terminal model. The return value is still movement, not “attempt alive.” |
| `request_turn(candidate: Vector2i) -> bool` | Reject requests after any terminal outcome; otherwise keep existing turn-buffer rules. |
| `is_finished() -> bool` | Whether the finish reason is nonempty. |
| `get_finish_reason() -> StringName` | Empty while active; otherwise the terminal reason. |
| `is_complete() -> bool` | Preserve Stage 2 API: true only for `board_full`, not collision. |
| Existing body/food/score/direction getters | Preserve signatures and copied-body snapshots. |

### Step ordering

1. If finished, return false without changing anything.
2. Commit the pending direction and clear its buffer, as before. Compute `next_head` and whether it equals active food; this is a read-only growth decision.
3. If `next_head` is out of bounds, record `wall_collision` and return false.
4. Determine occupied body indices for this step: when growing, check the entire current body; otherwise check every segment except the last one, which will move away. If any checked coordinate equals `next_head`, record `self_collision` and return false.
5. Only after those checks pass, insert the new head. On a normal step remove the old tail. On collection retain it, increment score and replace food with Stage 2's finite free-cell selection.
6. If spawning finds no free cell, set the reason to `board_full`. Return true because the final collection did move/grow the body.

On collision the body, food, score and random-generator state remain unchanged. The committed direction may reflect the attempted turn, and the pending buffer is empty; these are reset on retry. Do not insert an invalid head even temporarily, consume food, award points, spawn replacement food or query the random generator before the collision decision.

Normal food placement never puts food on a body segment, including the tail. The growing-step occupancy rule is still defined explicitly for correct ordering and later extensions; do not add an invalid “food on tail” fixture as though it were normal gameplay. A valid active body now has unique coordinates. Earlier stages' temporary overlap tolerance must not become a production state loader or a supported movement mode.

## 4. SnakeGame: attempt execution

Replace the earlier writable `running` boolean with one typed enum state:

```gdscript
enum AttemptState { STOPPED, PLAYING, WAITING_FOR_RETRY }
```

`STOPPED` means not started or explicitly disabled by the owner. `WAITING_FOR_RETRY` means a real attempt ended; it is not equivalent to a generic stop. Model outcome and controller execution state have distinct roles: the model owns why an attempt ended, while the controller owns whether simulation/input may run.

| Method | Contract |
| --- | --- |
| `start() -> void` | Keep startup validation and fresh reset/seed behavior from Stage 2. On valid settings reset timing/model, enter PLAYING, publish initial board and emit `score_changed(0)` once. On invalid settings report an error and remain STOPPED. |
| `stop() -> void` | Enter STOPPED and clear accumulator; preserve the displayed board and emit no attempt-finished event. |
| `restart_attempt() -> bool` | Only allowed from WAITING_FOR_RETRY. Call the same reset/start path and return whether PLAYING was reached. Return false without changes from other states. |
| `is_playing() -> bool` | Read-only query derived from the enum. |
| `is_waiting_for_retry() -> bool` | Read-only query derived from the enum. |

Keep `score_changed(score: int)` and `attempt_finished(reason: StringName, score: int)` from Stage 2; do not introduce separate death/win/retry-result channels.

### Processing and notification order

Only PLAYING accepts steering or advances the accumulator. After **every** call to `step()`, query `is_finished()`, even if `step()` returned false. Otherwise wall/self collisions would never reach the controller.

For a terminal step:

1. Set WAITING_FOR_RETRY and zero accumulated time before invoking listeners.
2. Publish the last valid/final board snapshot. Emit score change first only if the step changed score (full-board collection); collision emits no extra score event.
3. Emit exactly one `attempt_finished` with model reason and current score.
4. Exit the physics callback immediately; no remaining catch-up steps may execute.

Later callbacks in WAITING_FOR_RETRY do nothing. State transition, not a repeated poll of terminal reason each frame, controls notification. Generic `stop()` must not be used for terminal transitions because it would suppress retry eligibility. Do not pause the SceneTree or change time scale: only Snake stops, leaving future session/message clocks operational.

Retry calls no signal-connection setup and never creates a new SnakeGame node. A fixed seed recreates the same initial food on each retry; normal mode creates a newly randomized generator, with no promise that a food coordinate differs by chance. Reset discards all old direction/timing/outcome state. Do not use held-key polling to repopulate a turn buffer immediately after restart.

## 5. Session-owned Space input and feedback

Add the Input Map action `attempt_retry` with Space, without altering movement actions or binding `ui_accept`. `PrototypeSession._unhandled_input(event: InputEvent) -> void` owns this action; SnakeGame continues to own only directions.

Accept only a fresh, pressed, non-echo retry event when `snake_game.is_waiting_for_retry()` is true. Mark that accepted event handled and call a local `_try_retry_attempt() -> bool` helper. Ignore unrelated keys, release/echo, and Space while PLAYING or STOPPED. The helper rechecks eligibility at the point of action and calls `snake_game.restart_attempt()`; clear HUD status only if it succeeds. If an eligible restart fails configuration validation and enters STOPPED, replace the retry prompt with `Cannot start — invalid Snake settings; correct them and run again.` Do not leave a Space prompt for an unavailable action. No input or HUD code calls `SnakeState.reset()` directly.

This helper is Stage 4's future authorization point: then it must additionally require a running session with time remaining, giving session expiry priority over retry. In Stage 3 it checks only the attempt state. Do not add a fake session timer or claim timer preservation has already been runtime-tested.

The first real Space press after an attempt ends may retry immediately; there is no mandatory delay. Holding Space from active play through a collision does not retry because later echo/release events are ignored. A second Space press after a successful restart sees PLAYING and cannot reset it again. Steering pressed while waiting is ignored; steering pressed after restart follows normal event order and turn buffering.

Connect signals once before initial start. Extend the existing parent handler to present these nonmodal status texts outside BoardArea:

| Reason | Status |
| --- | --- |
| `wall_collision` | `Wall collision — press Space to retry.` |
| `self_collision` | `Self collision — press Space to retry.` |
| `board_full` | `Board complete — press Space to play again.` |

Keep final score displayed until retry emits zero. Change the instruction label to `Arrow keys / WASD — steer. Space — retry after an attempt ends.` Remove the earlier nonlethal-boundary note. Status labels never request keyboard focus, delay retry or cover cells. Existing Container/layout notifications may resize drawing but must not restart gameplay.

## 6. Implementation sequence

### A. Collision rules

- [x] Inspect actual Stage 1–2 model, controller and tests; confirm their accepted behavior and reconcile interface differences.
- [x] Add the wall, self-collision and vacating-tail cases below; confirm meaningful failures before replacing temporary behavior.
- [x] Implement terminal reason/queries and collision checks before movement/food mutation. Preserve the existing seed, score and growth contracts.
- [x] Adapt obsolete earlier fixtures/expectations and run the focused model checks.

### B. Attempt lifecycle and retry

- [x] Replace the controller's writable running flag with the enum; update all users/tests and implement guarded restart/queries.
- [x] Handle all terminal reasons once, including collisions whose `step()` returns false. Preserve score-before-finish ordering for `board_full`.
- [x] Add Space action, parent authorization helper and status text changes. Reuse existing nodes/model reset path and connections.
- [x] Run the lifecycle/retry integration checks.
- [ ] Run the full editor scenario.
- [x] Record actual commands, outcomes and `NotRun` checks. No implementation checkboxes are complete merely because this document exists.

## 7. Necessary verification

Use the existing small engine-native runner pattern, without a new framework. The new `tests/iteration01/test_snake_collisions.gd` contains the following five case groups. Reuse test-local model fixture helpers; do not add production arbitrary-state setters. Use valid in-bounds, contiguous bodies with unique cells, consistent score (`length - 3`) and food outside the body.

1. **Wall collision:** on 8×8, body `[(7,3),(6,3),(5,3)]`, direction right, food `(0,0)`. `step()` returns false, reason is `wall_collision`, `is_finished()` true and `is_complete()` false. Body/food/score and RNG state remain unchanged. Further steps and turn requests cannot revive or mutate the attempt.
2. **Retained-body collision:** body `[(2,2),(2,3),(1,3),(1,2),(1,1)]`, committed direction up, score two, food `(6,6)`. Queue Left and step: `(1,2)` is a retained segment, so the result is `self_collision` without movement, growth, score/food/RNG mutation.
3. **Vacating-tail exception:** body `[(2,2),(2,3),(1,3),(1,2)]`, direction up, score one, food `(6,6)`. Queue Left and step: succeed with body `[(1,2),(2,2),(2,3),(1,3)]`, unchanged length/score/food and no finish reason. Together with case 2 this distinguishes tail from retained body rather than ignoring all body occupancy.
4. **One terminal notification and stopped processing:** run the real SnakeGame controller with the wall fixture from case 1. Disable automatic physics for deterministic driving, feed enough delta for several intervals, and check WAITING_FOR_RETRY, zero accumulator, one correct `attempt_finished` and no score change. Invoke another callback and send a direction press: no new terminal event/movement or buffered turn. Assert the controller enum/query, not merely the model refusing to step. Case 5 exercises self-collision through the real parent; do not repeat it here. Adapt Stage 2's existing full-board controller test to assert WAITING_FOR_RETRY and preserve its score-then-finish expectations.
5. **Parent-routed retry and repeat prevention:** instantiate the real session scene, await its initial positive-size layout/start with a bounded wait, then disable automatic physics for controlled stepping. Use fixed seed and matching controller/fixture grid dimensions. Arrange the scored case-2 fixture, synchronize the HUD through `score_changed(2)`, then begin counting events. Finish the attempt and retain its score/status; Space echo/release and steering while waiting must not retry or buffer a turn. Send a fresh Space through the actual parent handler. Verify unchanged node IDs, centered three-cell body/right direction, zero score, valid food, cleared reason/buffer, PLAYING and zero accumulator. Less than one interval must not move; completing the interval moves right once. Another Space during PLAYING must not reset it. Use the existing full-board fixture for one second finish/retry cycle, checking exactly one finish and zero-score reset per cycle; this covers successful completion and duplicate connections without repeating the whole input matrix. Generic `stop()` followed by Space must remain STOPPED.

For input fixtures use `InputEventKey` with explicit Space keycode, `pressed` and `echo` fields so the real action/echo filtering runs; do not bypass the parent handler by calling reset. Each controller fixture must use matching grid dimensions and normal node initialization. Free all test scenes and bound readiness waits. These are five case groups, not five individual assertions.

### Adapt earlier checks deliberately

- Remove Stage 1's temporary wall case entirely after introducing the canonical wall check above; keep its four movement/steering groups and change its marker to `STAGE01_MOVEMENT_PASS checks=4`. Do not duplicate collision assertions in the movement runner.
- Stage 2 retains its five food/reset/full-board groups. Full-board fixtures use the new finish reason instead of the removed completion flag, and controller assertions use the new queries. Collision behavior belongs in this stage's runner, not the food runner.
- If older tests were implemented before this audit, remove any overlapping-body or duplicate boundary cases rather than preserving obsolete behavior to satisfy them. Temporary stage rules are not permanent regression requirements.

The new runner prints `STAGE03_COLLISIONS_PASS groups=5` only after all cases/subcases pass, exits nonzero on failures, and treats unexpected engine errors as failure. Reuse validated runner reporting; only recheck intentional failure detection if that reporting mechanism changes.

At implementation time resolve the installed Godot 4.7 console executable and verify supported flags, then run each affected runner sequentially:

```powershell
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_collisions.gd
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_food.gd
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_movement.gd
```

`$godotExe` is a placeholder. Inspect output and capture `$LASTEXITCODE` separately after each command. Follow the project's single-editor and import rules for scene-based checks. The previous runners are relevant because collision/reset/controller changes directly affect their behavior; no unrelated suites are required.

### One editor scenario

Collect food, hit a wall and observe the frozen board, retained score and clear retry prompt. While waiting, press direction keys, then Space: verify a fresh three-cell body, zero score, valid food, cleared prompt and no stale turn. Continue collecting/growing and deliberately turn into the body; verify the self-collision prompt and retry again. Hold Space during active play through a later wall collision: it must wait for a new press. Repeated fresh Space presses during active play must not reset the attempt. Inspect the debugger for relevant errors.

This establishes actual key handling and readable feedback; deterministic fixtures establish difficult tail/full-board cases. Do not manually fill an entire board, repeat the FPS/resolution checks without evidence of regression, or test session timers/questions/packaging in this stage.

## 8. Acceptance and handoff

- [x] Walls and retained body cells end an attempt before invalid movement or reward effects.
- [x] Entering the vacating tail cell works on a nongrowing step.
- [x] Collision and full-board completion each notify once and leave Snake waiting without pausing the scene tree.
- [x] Space retries through the parent only while waiting, resetting attempt state without recreating session nodes or reconnecting signals.
- [x] Focused model/lifecycle checks and adapted earlier checks pass with recorded evidence.
- [ ] The full editor scenario passes with recorded evidence.
- [x] Report every changed file, actual checks and remaining `NotRun` items; distinguish planned future session behavior from tested behavior.

Stage 4 extends the parent's retry authorization with session state/deadline checks and keeps its clock/totals outside the attempt reset. Stage 5 keeps any active question and its deadline outside that reset too. Those integrations are future work, not hidden Stage 3 prerequisites.
