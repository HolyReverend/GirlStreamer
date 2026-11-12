# Stage 2: Food Collection and Growth — Detailed Implementation Plan

Date: 2026-11-12. Status: planned; implementation and acceptance are not claimed.

**Goal:** Extend the movement prototype with one collectible food item, immediate body growth and a visible attempt score.

**Architecture:** Extend the existing `SnakeState` with food, score and board-completion state. `SnakeGame` advances the model and emits score/completion notifications; the existing board renderer and HUD present the result. There is still only one authoritative Snake model.

**Tech stack:** Godot 4.7 Standard, typed GDScript, existing native scenes and Node2D drawing; preserve the Compatibility renderer.

**Specification:** [Iteration 1 roadmap](../Iteration01ImplementationPlan.md), Stage 2 and shared contracts; [Stage 1 detailed plan](Stage01SnakeMovement.md); [Minigames](../../GameDesign/Mechanics/Minigames.md), Snake section.

This is a future implementation plan, not permission to begin engine work. Before execution, follow the project workflow, engine implementation rules and whole-stage workflow; inspect actual Stage 1 implementation and acceptance evidence. Stage 1's document alone does not establish that its code exists. If its implemented interfaces differ, reconcile them before editing rather than creating parallel systems. Checkboxes below are future work.

## 1. Scope and behavior

| Rule | Stage 2 behavior |
| --- | --- |
| Food count | Exactly one item while a running board has free cells; zero when the board is complete. |
| Initial food | Spawn immediately after resetting the centered three-cell body, before publishing the first frame. |
| Collection | Entering the food cell consumes it on that movement tick. |
| Growth | Insert the new head and retain the previous tail on a collection tick: exactly one new segment. |
| Score | Start at zero; add one per consumed item. This is attempt score, not session totals or currency. |
| Replacement | Spawn one replacement immediately from cells free after the growth operation. |
| Ordinary movement | Remove the old tail; no score change and no food relocation. |
| Full board | Stop Snake, remove food and display completion with the final score; no automatic restart. |
| Speed and steering | Keep Stage 1's interval, one-turn buffer, reverse rejection and keyboard bindings. Growth does not accelerate movement. |

Preserve Stage 1's temporary nonlethal boundary guard and absent self-collision response. Stage 3 owns lethal collisions and Space retry; Stage 4 owns session timing/totals. Do not add lives, menus, rewards, food variants, disappearing food, sound, particle effects, question UI or persistence.

Body cells may overlap until Stage 3. Therefore a board is full only when every grid coordinate is occupied, not when `body.size()` reaches the grid area. Body length and score still obey `length = 3 + score`; overlapping coordinates do not reduce segment count. This is temporary prototype behavior, not a final collision rule.

## 2. Planned file changes

Paths are relative to `GirlStreamer/` (`res://`). Extend the files introduced by Stage 1; do not rebuild its scene structure.

| File | Change |
| --- | --- |
| `prototype/snake/snake_state.gd` | Own food position/presence, score, completion and injected random generator; extend reset/step and free-cell selection. |
| `prototype/snake/snake_game.gd` | Configure randomness, publish richer snapshots, emit score/completion signals and stop after the final collection. |
| `prototype/snake/snake_board.gd` | Draw food from the supplied snapshot using the existing cell transform. |
| `prototype/ui/prototype_hud.tscn` | Add `ScoreLabel` and `StatusLabel` to the existing VBox, outside BoardArea. |
| `prototype/ui/prototype_hud.gd` | Expose typed score/status presentation methods; retain layout reporting. |
| `prototype/prototype_session.gd` | Connect notifications to HUD once, before starting Snake. |
| `tests/iteration01/test_snake_food.gd` (new) | Focused rule cases and one controller completion case using the existing runner style. |
| `tests/iteration01/test_snake_movement.gd` | Adapt reset calls/fixtures to the new model contract; retain movement/steering assertions. |

No new gameplay scene, food actor, Autoload, Resource schema, Input Map action or plugin is needed. The main scene remains the one registered by Stage 1. `snake_game.tscn` only needs editing if explicit Inspector defaults must be serialized; defaults may otherwise live in the controller script.

## 3. Model contracts and food placement

Keep `SnakeState` a typed `RefCounted` without signals, scene access, input or rendering. Add instance fields for the random generator, food presence/coordinate, integer score and completion flag. All mutable state remains local to this model.

| Interface | Contract |
| --- | --- |
| `reset(grid_size: Vector2i, random_source: RandomNumberGenerator) -> void` | Replaces Stage 1's signature. Reset body/direction/buffer, score to zero and completion to false; retain the supplied generator and spawn initial food. Requires validated dimensions and a non-null generator. |
| `step() -> bool` | Preserve its meaning: true when body positions change, including a collection/final collection; false when boundary-blocked or already complete. |
| `request_turn(candidate: Vector2i) -> bool` | Preserve Stage 1 rules; reject requests after completion. |
| `get_score() -> int` | Current attempt score. |
| `has_food() -> bool` | Whether the food coordinate is valid for use/drawing. |
| `get_food_cell() -> Vector2i` | Current cell if food exists; otherwise return `Vector2i(-1, -1)`. Callers must check presence. |
| `is_complete() -> bool` | True only after no unoccupied cells remain. |
| `get_body_cells()` / `get_direction()` | Keep Stage 1 signatures and snapshot-copy behavior. |

Do not add a public arbitrary-body loader or food teleport API for testing. A test-local subclass may arrange controlled model fields as fixtures; production callers continue using reset, turns and steps. GDScript underscore-prefixed state is an encapsulation convention: only that test helper may deliberately access it, with setup kept in one place.

### Finite free-cell selection

Implement `_spawn_food() -> void` inside the model:

1. Build an occupied-coordinate lookup from the current body, deduplicating repeated coordinates.
2. Enumerate grid cells in fixed row-major order (Y outer, X inner) into `Array[Vector2i] free_cells`, excluding occupied cells.
3. If the array is empty, set food absent, coordinate to `(-1, -1)` and completion true. Do not call the random generator with an empty range.
4. Otherwise choose one index with the injected generator's `randi_range(0, free_cells.size() - 1)`, assign that food cell and set presence true/completion false.

Call this only at reset and after collection. Do not repeatedly sample random coordinates until one happens to be free, rescan every rendered frame or introduce a cached occupancy service. A complete grid scan is bounded and adequate for the supported 8–64 dimensions; the fixed enumeration order also makes seed-based checks meaningful.

### Atomic movement/collection order

1. If complete, return false without modifying state.
2. Commit/clear the pending turn as in Stage 1, then compute the next head cell.
3. Apply the temporary boundary guard. A rejected move leaves body, food and score unchanged; turn-buffer semantics remain those of Stage 1.
4. Determine whether the next head equals the active food coordinate **before** changing body or food.
5. Insert the new head. On an ordinary step remove the last segment. On collection retain the tail, increment score once, invalidate consumed food and call `_spawn_food()` using the updated body.
6. Return true. The controller reads the final coherent state; model methods do not emit callbacks partway through the operation.

No overlap with the replacement food can occur immediately because the new head and retained tail are included in the occupied set. Completion on the last food still counts that collection and its added segment.

## 4. Randomness and reproducibility

`SnakeGame` creates a fresh `RandomNumberGenerator` for each `start()`. Export `use_fixed_seed: bool = false` and `food_seed: int = 12345` as prototype settings. Read these alongside the validated grid/tick settings at attempt start; later Inspector edits apply to the next attempt only. With fixed mode enabled, assign that seed before reset; otherwise call `randomize()` once. Supply this instance to the model and do not consume it from rendering or the HUD. The model must not reseed it during spawning.

Every test model gets its own generator. Two generators initialized with the same seed and the same sequence of board changes should produce identical food choices in the same engine build. Do not share one advancing generator between comparison models or require exact random coordinates across Godot versions. The official [RandomNumberGenerator reference](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html) describes seed reproducibility and explicitly treats the underlying algorithm as an implementation detail; verify APIs against the installed 4.7 build during execution.

## 5. Controller, drawing and HUD integration

### SnakeGame notifications and lifecycle

Add the roadmap's typed signals:

```gdscript
signal score_changed(score: int)
signal attempt_finished(reason: StringName, score: int)
```

`start()` retains Stage 1 validation, resets its accumulator and the model with a fresh configured generator, publishes the initial board snapshot, emits `score_changed(0)` once and enables movement/input. Connections must already exist; layout changes never call `start()` again.

For each simulation step, read score before/after `step()`. Emit `score_changed(new_score)` only when it changes. If multiple steps are due in one callback, process each step's score change, but publish only the final visual snapshot. Do not infer collection from body length in the renderer or increment a second counter in the HUD.

On the step that makes `is_complete()` true, stop further stepping/input and clear the accumulator **before** notifying listeners. Publish the completed snapshot, emit the final `score_changed` first if needed, then emit `attempt_finished(&"board_full", final_score)` once. Break the catch-up loop immediately, so remaining accumulated time cannot move the completed body. Further callbacks produce no duplicate notifications. `stop()` itself remains a generic stop command and must not emit `attempt_finished`.

This implements only full-board completion, which Stage 2 needs. It does not implement failure, retry input or the future session state machine. Stage 3 can use the same `attempt_finished` signal for collision reasons; it should not create a second completion channel.

### SnakeBoard snapshot

Replace the Stage 1 signature with:

```gdscript
func set_snapshot(grid_size: Vector2i, body_cells: Array[Vector2i],
        food_present: bool, food_cell: Vector2i) -> void:
```

This is an interface declaration for the plan, not a complete script. Update all controller call sites together. Store copied presentation data, then `queue_redraw()`. Draw food as a small contrasting circle centered in its cell, distinct in shape from the body/head. Use exactly the same cell size/origin as the grid. If food is absent, draw none; never draw the sentinel coordinate. Keep rule updates out of `_draw()`.

### HUD and session wiring

Add nonfocusable `ScoreLabel` and `StatusLabel` above `BoardArea` in the existing VBox. Score text starts at `Score: 0`; status starts empty. On completion show `Board complete — stop and run again to restart.` Preserve the existing instruction/boundary note until Stage 3 changes those rules.

HUD exposes `set_score(score: int) -> void` and `set_status(message: String) -> void`. The parent connects SnakeGame signals once with named handlers, clears status before initial start, and routes `board_full` to the completion text. It does not calculate score or start another attempt. Let Containers update BoardArea and the existing layout signal resize the drawing; no manual board offsets or model reset on label/layout changes.

## 6. Implementation sequence

### A. Extend and verify the model

- [ ] Inspect the implemented Stage 1 files and runner; confirm its required behavior exists before beginning Stage 2.
- [ ] Add the focused model cases in Section 7 and confirm meaningful failures against the old food-free behavior.
- [ ] Extend reset, food selection, atomic growth/score updates and completion getters. Keep `step()` returning a movement boolean.
- [ ] Adapt all reset call sites, including Stage 1 test fixtures. Make movement tests place food outside their exercised route so randomness cannot turn a fixed-length assertion into an accidental growth test.
- [ ] Run the food model cases and retained movement checks; fix failures before integration.

### B. Integrate collection feedback

- [ ] Add controller seed settings and signals; extend stepping to detect score changes and stop exactly once at completion.
- [ ] Update snapshot signature/call sites and food drawing in the existing renderer.
- [ ] Add score/status labels and parent-owned signal connections, preserving the established layout flow.
- [ ] Run the bounded controller completion check and one editor collection scenario below.
- [ ] Record actual results and any `NotRun` checks; do not describe this plan or a successful parse as gameplay acceptance.

## 7. Necessary verification

Use the existing engine-native runner pattern; do not introduce a framework. The new `test_snake_food.gd` contains four model cases and one controller case. Fixtures live in this test file: a local model subclass arranges body, direction, pending turn, food, score and completion consistently, and can call the real `_spawn_food()` helper. It must not reimplement spawning or growth. Fixture helpers may access internal fields solely to reach final-cell states quickly. Do not add a separate test for temporary body overlap or duplicate Stage 1's wall guard check; they are superseded by Stage 3.

1. **Initial state and seeded spawning:** reset two models on 24×18 with separate generators seeded 12345. Both have length three, score zero, one in-bounds food outside the body and matching food cells. Repeat spawning a few times on the same fixture board and compare sequences; every choice remains free and each injected generator advances from its initial state. Do not reconstruct the free-cell selection algorithm in a reference implementation, pin exact coordinates or test statistical randomness.
2. **Ordinary step, collection and next step:** start with the standard body and put food at `(13,9)`. One step yields `[(13,9),(12,9),(11,9),(10,9)]`, score one and exactly one replacement outside that updated body. For the next ordinary-step assertion, arrange food off its path; verify length remains four, score stays one and food stays put. Check `length = 3 + score` after each step.
3. **Last free cell and completion:** on 8×8 construct a contiguous serpentine body occupying 63 distinct cells, head `(1,0)`, direction left, only `(0,0)` free; score is 60. The body runs from `(1,0)` through `(7,0)`, then row 1 right-to-left, row 2 left-to-right, and so on through row 7. Call real spawning: food must be `(0,0)`. One step produces length 64, score 61, no food and completion true. Further steps/turns cannot alter the result. No random-index error or unbounded search is allowed.
4. **Fresh reset:** after a collected/completed fixture, reset with a freshly seeded generator: length three, score zero, completion false, exactly one valid food, no stale turn. Reuse the established Stage 1 movement assertions for steering details.
5. **Controller completion once:** instantiate the real SnakeGame scene in a bounded test, configure its grid to 8×8, initialize it normally and then replace its model with the test's matching last-free-cell fixture. Connect counters to both signals after initial startup. With automatic physics processing disabled for the fixture, invoke its normal physics callback with enough delta for several movement intervals. Expect exactly one score event (61), then exactly one finish event (`board_full`, 61), the controller's own running flag false, zero remaining accumulator and no food in the final snapshot. Assert the controller flag directly: the completed model rejecting further steps alone does not prove that the controller stopped. Invoke another callback: counters and body remain unchanged. Free the scene. Do not add a production model-replacement API for this fixture.

The new runner prints `STAGE02_FOOD_PASS checks=5` only after all cases complete and exits nonzero on failure. Unexpected engine errors invalidate a run. Reuse Stage 1's already validated runner structure; if its failure/reporting mechanism is changed, verify intentional failure detection in a temporary fixture and restore it. Bound any scene-readiness wait with a timeout rather than waiting indefinitely.

Resolve the real Godot 4.7 console executable at execution time, check supported CLI flags, then run the equivalent of these commands sequentially:

```powershell
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_food.gd
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_movement.gd
```

`$godotExe` is a placeholder, not a known executable path. Capture output and `$LASTEXITCODE` separately for each run. Follow the project's single-editor/import rules when loading scenes. The retained movement checks are justified because Stage 2 changes their shared reset/step methods; do not repeat unrelated test suites.

### One editor collection scenario

Run the main scene, collect two food items and observe one-segment growth plus one score increment per item. Between collections confirm that movement does not change score, food does not move spontaneously, steering still works and speed does not increase. Food must be readable and distinct from head/body; the score must stay outside the board. Stop/run once to confirm zero score and a fresh three-cell body. Check the debugger for relevant errors.

Full-board termination is covered by the short deterministic fixture; manually filling a 24×18 board is not a requirement. Do not repeat the Stage 1 frame-rate comparison unless controller timing changes beyond the planned per-step result handling or a regression is observed. Questions, retry, lethal collisions, session timers and packaging remain outside this stage's checks.

## 8. Acceptance and handoff

- [ ] Initial food and every replacement occupy an in-bounds unoccupied cell.
- [ ] Each consumed food adds exactly one segment and one point; ordinary/blocked steps do neither.
- [ ] The final free cell can be consumed, and completion stops movement with one final notification and readable status.
- [ ] Five focused checks and the adapted movement checks pass with completion markers, successful exits and no unexpected errors.
- [ ] The editor collection scenario confirms drawing, score updates and unchanged steering/speed.
- [ ] The implementation report lists changed files, actual validation evidence, `NotRun` checks and remaining prototype limitations.

Stage 3 inherits this score/growth model and completion signal. Its collision decision must occur before mutating body, awarding score or spawning food; it replaces the temporary wall guard and adds self-collision/retry. No Stage 2 record should claim those mechanics or final game balance are already validated.
