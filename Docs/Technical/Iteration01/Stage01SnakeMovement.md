# Stage 1: Snake Movement — Detailed Implementation Plan

Date: 2026-11-12. Status: planned; implementation has not started.

**Goal:** Run the existing Godot project and control a visible, fixed-length Snake on a grid with predictable discrete movement and one buffered turn per tick.

**Architecture:** A `RefCounted` model owns cell positions and steering rules. A scene controller owns input and simulation timing; a Node2D renderer displays snapshots. The session composes the gameplay scene and a minimal Control layout without owning Snake rules.

**Tech stack:** Godot 4.7 Standard, typed GDScript, native scenes and 2D custom drawing; existing Compatibility renderer.

**Specification:** [Iteration 1 roadmap](../Iteration01ImplementationPlan.md), Stage 1 and shared contracts; [Minigames](../../GameDesign/Mechanics/Minigames.md), Snake and input compatibility sections.

This document authorizes no engine changes by itself. When implementation is requested, follow the project workflow and engine implementation rules, inspect the actual project/editor state, and use the project stage-orchestration workflow for the whole stage. Checkboxes below track future work, not completed work.

## 1. Scope and completion target

Deliver a main scene that starts moving Snake automatically after its layout is ready. Arrow keys and WASD steer it. The head is distinguishable from the body; all cells remain visible and square. Movement uses a 0.20-second simulation interval, independent of rendering frequency under normal execution.

Include only movement, drawing, input, minimal layout and the checks needed to establish those behaviors. Do not implement food, growth, score, lethal collision, attempts, retry input, session countdown, question UI, sounds, animations, persistence or menus. Do not add their signals or placeholder services before their owning stages need them.

### Stage-local choices

These settings complete details left open by the roadmap; they are initial technical choices, not final balance decisions.

| Setting | Initial value / behavior |
| --- | --- |
| Grid | 24 columns × 18 rows; X increases right, Y increases down. |
| Body | Three cells, head first: `(12, 9)`, `(11, 9)`, `(10, 9)`. |
| Initial direction | `Vector2i.RIGHT`. |
| Tick interval | 0.20 seconds; controller Inspector range 0.05–1.00 seconds, increment 0.01. |
| Grid tuning | Controller owns exported columns/rows, each 8–64; default start is centered with two cells extending left. Initial length stays a constant of three. |
| Visuals | Dark board, subdued grid, bright body, distinct head; one Node2D draws the entire board. No imported art. |
| Boundary before Stage 3 | Reject a step whose next head lies outside the board; keep the body unchanged. Continue ticking and accepting legal turns. No wrap, death or automatic reset. |
| Body overlap before Stage 3 | No self-collision response. Occupied cells do not end movement. Stage 3 replaces this omission and the nonlethal boundary guard with its collision rules. |
| Recovery | Stop/run the scene again in the editor; no in-game restart action in this stage. |
| Supported window | Use a prototype window of at least 1024×768; set that initial/minimum size during implementation without changing the existing stretch mode. Later HUD additions must fit this same supported size. |

The temporary boundary guard keeps the movement prototype on screen without introducing the failure/retry mechanic early. A direction committed on a blocked tick remains committed; the next tick can accept another turn. This is not the final wall behavior.

## 2. Planned files and scene composition

All runtime paths below are relative to `GirlStreamer/` (`res://`). Create only the following when implementation begins; preserve editor plugins, unrelated settings and existing files.

| File | Responsibility |
| --- | --- |
| `prototype/prototype_session.tscn` | Main composition: Snake scene instance and HUD scene instance. |
| `prototype/prototype_session.gd` | Connect layout notification, supply board rectangle, start Snake once layout is usable. |
| `prototype/snake/snake_game.tscn` | Node controller plus Node2D board child. |
| `prototype/snake/snake_game.gd` | Input Map routing, model ownership, accumulator, start/stop and rendering updates. |
| `prototype/snake/snake_state.gd` | Typed cell data, turn buffer and one-step movement. |
| `prototype/snake/snake_board.gd` | Draw grid and copied body snapshot within the supplied rectangle. |
| `prototype/ui/prototype_hud.tscn` | Container-based board region and a short instruction label. |
| `prototype/ui/prototype_hud.gd` | Expose board layout through a typed rectangle getter/signal. |
| `tests/iteration01/test_snake_movement.gd` | Small engine-native runner for deterministic movement/turn checks; no framework. Reuse an appropriate runner if one exists at implementation time. |
| `project.godot` (modify) | Set main scene, initial supported window size and four movement actions; enforce the supported minimum window size in session setup if required by the installed Godot API. No other gameplay actions yet. |

```text
PrototypeSession (Node; prototype_session.gd)
├── SnakeGame (Node; snake_game.tscn instance)
│   └── Board (Node2D; snake_board.gd)
└── PrototypeHUD (Control; prototype_hud.tscn instance, full rect)
    └── MarginContainer (full rect; 16 px margins)
        └── VBoxContainer
            ├── BoardArea (Control; expand/fill in both axes)
            └── Instructions (Label)
```

Use `Arrow keys / WASD — steer` and a short Stage 1 boundary note in the instruction label. `BoardArea` is transparent; the HUD must not paint a background over the separately rendered board. No focusable widgets or message panel are needed yet. Stage 5 can extend the layout without moving rule ownership into the HUD.

Keep these nodes on the same canvas, without Camera2D, CanvasLayer, rotation or scaling of ancestors. The HUD reports `BoardArea.get_global_rect()`; the session forwards it through `SnakeGame` to `Board`, which converts the rectangle origin with `to_local()`. This keeps the renderer independent of HUD node paths. If these transform assumptions change later, update the coordinate conversion deliberately.

Containers own Control sizes. Do not manually set BoardArea offsets every frame. Connect layout changes once, recompute after container layout has settled, and read the current rectangle explicitly at startup so an earlier `resized` signal cannot be missed. A zero-size area delays startup/drawing instead of producing invalid cell dimensions. Resizing updates presentation only, never resets the model.

## 3. Ownership and typed interfaces

Use `class_name` for the script types referenced in typed interfaces. Keep instance references explicit and use `@onready` only for children owned by that scene. Internal field names may vary; public contracts below should remain consistent across files.

### SnakeState (`RefCounted`)

Own private `Array[Vector2i]` body, grid size, committed direction and pending direction/flag. No nodes, input access, timers, signals or drawing calls.

| Method | Contract |
| --- | --- |
| `reset(grid_size: Vector2i) -> void` | Center the three-cell body, face right and clear the pending turn. Requires dimensions within the supported range. |
| `request_turn(candidate: Vector2i) -> bool` | Accept one perpendicular cardinal direction if no turn is pending. Return true only when a new turn is queued. |
| `step() -> bool` | Commit the pending turn, clear the buffer, attempt one cell of movement. Return true if body positions changed, false for the temporary boundary guard. |
| `get_body_cells() -> Array[Vector2i]` | Return a copy; presentation/test consumers must not mutate the authoritative array. |
| `get_direction() -> Vector2i` | Return the committed direction, not the pending one. |

**Turn acceptance order:** reject zero/diagonal/non-unit directions; reject an occupied turn buffer; reject the committed direction and its opposite; otherwise queue the candidate. Rejected or same-direction input never consumes an empty buffer slot. Later input cannot replace an already accepted turn.

**Step order:** commit pending direction if present; clear the pending flag; compute next head; apply the temporary bounds guard; if allowed, insert the new head and remove the last segment. Preserve exactly three cells and their head-to-tail order. A blocked step still clears the turn buffer, allowing a fresh turn next tick. Stage 2 changes tail removal only when growth is introduced.

Example: while heading right, Up then Left before the next tick queues only Up. The next step goes up; Left requires a fresh press after that step. Right then Up still queues Up because pressing the current direction does not occupy the buffer. A rejected Left followed by Up also queues Up.

### SnakeGame (`Node`)

Own the only `SnakeState` instance, exported grid/tick settings, `running: bool` and `accumulator_seconds: float`. On successful start, capture validated grid dimensions and tick interval in attempt-local fields; simulation and drawing use those snapshots. Inspector changes take effect on the next start, never inside an already running accumulator loop. The model owns pending turns; do not keep a second input queue in the controller.

| Method | Contract |
| --- | --- |
| `start() -> void` | Reset model and accumulator, publish the initial snapshot, enable movement/input. Initial movement occurs after a full interval, not immediately. |
| `stop() -> void` | Disable movement/input and discard elapsed debt; do not emit failure or session results. A later `start()` resets the model. |
| `set_board_rect(rect: Rect2) -> void` | Forward layout to Board; no model changes. |
| `_physics_process(delta: float) -> void` | While running, add delta; for each complete interval subtract that interval and call `step()`. Redraw once with the final snapshot if positions changed. |
| `_unhandled_input(event: InputEvent) -> void` | Map only pressed, non-echo movement actions to cardinal candidates while running. |

Keep fractional accumulator remainder. Do not set it to zero after each movement, multiply displacement by render delta, or move once per rendered frame. If multiple steps are due, only the first consumes the single pending turn; later steps keep the committed direction. Do not add a custom real-time catch-up service or change Godot's physics timing settings. Severe stalls are outside the frame-rate acceptance claim.

### SnakeBoard (`Node2D`)

- `set_board_rect(rect: Rect2) -> void`: receive the canvas-global rectangle forwarded unchanged by session/controller, convert its origin with Board's `to_local()` exactly once, store the local rectangle and request redraw. Under the stated unscaled/unrotated canvas contract, size is unchanged.
- `set_snapshot(grid_size: Vector2i, body_cells: Array[Vector2i]) -> void`: copy/store presentation data and request redraw.
- `_draw() -> void`: calculate cell size as the smaller of available width/columns and height/rows, center the resulting board, draw background/grid/body/head. Use floating-point cell size so the board fits without distorting cells; slight segment insets distinguish adjacent cells.

Draw only from snapshots. No gameplay tick in `_draw()`, no node per segment and no rigid/character bodies for grid motion. Custom drawing uses cached draw commands and `queue_redraw()` to refresh them, as described in the [official drawing guide](https://docs.godotengine.org/en/4.4/tutorials/2d/custom_drawing_in_2d.html). The guide illustrates the pattern; verify APIs against the project's installed 4.7 build during implementation.

### PrototypeHUD and PrototypeSession

HUD exposes `get_board_rect() -> Rect2` and `signal board_rect_changed(rect: Rect2)`. It reports settled layout changes, not gameplay events. Session wires this signal to SnakeGame with a named handler and calls `start()` exactly once after the initial positive-size rectangle is supplied. Later layout notifications only update that rectangle.

Use one connection path, not both an editor connection and a code connection for the same handler. Cross-system references belong to the parent. Do not add a global event bus, Autoload or paths into unrelated scenes.

## 4. Keyboard input contract

| Input Map action | Bindings | Candidate |
| --- | --- | --- |
| `snake_up` | Up arrow, physical W | `Vector2i.UP` |
| `snake_down` | Down arrow, physical S | `Vector2i.DOWN` |
| `snake_left` | Left arrow, physical A | `Vector2i.LEFT` |
| `snake_right` | Right arrow, physical D | `Vector2i.RIGHT` |

Use physical WASD positions to keep steering usable with a Russian keyboard layout. Avoid reusing `ui_*` actions or polling all held directions every frame. A key-down requests a turn once; holding a key must not queue a new turn later via operating-system repeat. Two presses between ticks follow event arrival order, with the first legal turn winning.

Mark only recognized movement presses handled, including recognized turns rejected by the model. Do not handle unrelated keys, key releases or echo events. Keys 1–3 and Space remain available for later stages. UI labels/containers must not capture keyboard focus.

## 5. Implementation sequence

### A. Establish the movement model

- [ ] Recheck current files and project instructions; confirm the engine version without opening/importing with another version.
- [ ] Create the focused movement checks listed in Section 6 and run them against the initial model interface; confirm a meaningful failure before implementing the rules.
- [ ] Implement `SnakeState` and its five methods from Section 3.
- [ ] Run the checks and resolve failures before wiring rendering or input.

### B. Build the grid view and simulation controller

- [ ] Create `snake_game.tscn` with its Board child and attach the typed scripts.
- [ ] Implement rectangle-based drawing and snapshot refresh; keep rendering independent of model mutation.
- [ ] Implement `start()`, `stop()` and fixed-interval accumulation. Expose grid dimensions and tick interval with the stated defaults/ranges. Before resetting or starting, reject dimensions outside 8–64 and a nonfinite or out-of-range tick interval: report a clear configuration error and leave simulation/input stopped. Do not silently clamp loaded settings or enter the accumulator loop with them.
- [ ] Add the four Input Map actions and event-based steering. Verify the scene/scripts load before composing the session.

### C. Compose the runnable stage

- [ ] Create the minimal HUD scene and layout getter/notification; no future message or score widgets.
- [ ] Create the session scene, connect layout once and start Snake after the first usable layout. Register it as the project main scene.
- [ ] Run the focused editor scenario in Section 6. Fix errors in the owning model, controller or layout rather than adding duplicate state to the session.
- [ ] Record changed files and actual check results; leave unperformed checks explicitly `NotRun`. Do not mark implementation accepted solely because scripts parse.

## 6. Necessary verification

### Deterministic model check group

Use `tests/iteration01/test_snake_movement.gd` as one small `SceneTree` runner if no existing runner fits. Preload the model directly, run synchronous checks and exit with a nonzero code on failure. Print `STAGE01_MOVEMENT_PASS checks=5` only after all five cases pass. No scene fixture, plugin dependency or testing framework is required for these rules.

1. **Reset and one step:** after reset to 24×18, body equals `[(12,9), (11,9), (10,9)]` and direction is right. One step produces `[(13,9), (12,9), (11,9)]`, retaining length three.
2. **Reverse rejection:** Left returns false while heading right; next step still goes right. A rejected Left followed by Up accepts Up.
3. **One buffered turn:** Up returns true, then Left returns false before a step. Direction stays right until the step; afterwards head is `(12,8)` and direction is up. A fresh Left after that step succeeds and the next head is `(11,8)`.
4. **Non-turn input and reset:** Right, zero and diagonal requests return false without using the buffer; Up then succeeds. Reset clears that pending Up; the next step goes right from the initial body.
5. **Temporary boundary guard:** advance right to column 23, then step again; it returns false and body is unchanged. Up is accepted and the next step moves to `(23,8)` without wrapping or resetting.

For a newly created runner, temporarily force one expectation to fail, confirm a nonzero exit and no success marker, then restore it and run the real checks. This validates the small runner, not an additional game subsystem. Unexpected script/engine errors invalidate the run even if its process exits successfully.

At implementation time resolve the actual console executable, confirm `--version` / `--help`, and invoke the equivalent of:

```powershell
& $godotExe --headless --path 'E:\Projects\VibeCoding\GirlStreamerProject\GirlStreamer' --script res://tests/iteration01/test_snake_movement.gd
```

`$godotExe` is a placeholder for the verified installed 4.7 executable, not an assumed PATH command. Inspect output and `$LASTEXITCODE`. Follow project editor/plugin rules for any import or scene load; the model runner does not replace verifying the main scene in the editor.

### One focused editor scenario

- Start the project: initial body/head are visible; first movement follows one full interval. Use arrows and physical WASD, including a Russian keyboard layout if available. Verify reverse rejection and rapid Up/Left presses. To verify echo rejection, hold Up through its committed turn, then press Right while still holding Up: after turning right, Snake must keep heading right through keyboard repeat until Up is released and pressed again.
- Reach a boundary, turn away and confirm the temporary guard behaves as documented. Resize the window once: square cells remain inside the reserved board area, the label stays readable, and resizing does not restart Snake. No broad resolution matrix is required.
- Repeat a straight, interior movement sample at render limits of 30 and 60 FPS with the same physics settings and 0.20-second tick interval. Measure from the first observed step across five subsequent moves: elapsed time should be approximately one second at both caps (allow one displayed-frame observation error per endpoint). Confirm the machine reaches those rates; a stalled run is inconclusive. Restore temporary frame-cap settings afterwards.
- Check the debugger for script/runtime errors in this scenario. Do not run a six-minute session or test questions, growth, collisions, packaging or unrelated engine features in Stage 1.

Godot distinguishes rendering updates from fixed physics callbacks in its [processing documentation](https://docs.godotengine.org/en/latest/tutorials/scripting/idle_and_physics_processing.html). The accumulator controls the slower grid interval; a fixed callback alone is not a substitute for that interval. Headless checks establish movement rules, not input feel or visual clarity.

## 7. Acceptance and handoff

- [ ] Main scene starts successfully in the intended Godot version with no relevant debugger errors.
- [ ] Grid, fixed-length body and distinct head are visible; steering and turn buffering meet Sections 3–4.
- [ ] Five model checks pass with the expected completion marker and successful exit.
- [ ] Editor input/layout/frame-rate scenario is completed and its observations recorded.
- [ ] No mechanics from Stages 2–5 have been implemented as hidden prerequisites.

The implementation report must list actual added/modified files, test commands/results and any `NotRun` checks. Carry forward the temporary boundary guard and absent self-collision explicitly so Stage 3 replaces them. Stage 2 should extend the same model with food/growth and the same renderer with food drawing; it should not create a second Snake state or replace the scene architecture.
