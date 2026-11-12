# Current project architecture

Read before Godot work, then open only the files relevant to the task. This is a map of existing code, not a roadmap. Last checked against source: 2026-11-12.

## Runtime and entry point

- Godot 4.7 Standard, GDScript, GL Compatibility; configured viewport and minimum window size: 1024 × 768.
- Engine root: `GirlStreamer/`; all `res://` paths below are relative to it.
- [project.godot](../../GirlStreamer/project.godot) owns the startup scene, display settings, Input Map, renderer, and enabled editor plugins.
- Startup scene: `res://prototype/prototype_session.tscn`. No autoloads are currently configured.

## Find the owning file

| Concern | Files | Responsibility |
| --- | --- | --- |
| Session lifecycle and timing | [prototype_session.tscn](../../GirlStreamer/prototype/prototype_session.tscn), [prototype_session.gd](../../GirlStreamer/prototype/prototype_session.gd) | Instantiates `SnakeGame` and `PrototypeHUD`, sets minimum window size, owns the 360-second monotonic deadline, session totals, action authorization, Space retry, Enter restart and question metrics. Owns QuickMessages and supplies its authorized elapsed-time sample. Initial usable layout starts the first session. |
| Snake controller and tuning | [snake_game.tscn](../../GirlStreamer/prototype/snake/snake_game.tscn), [snake_game.gd](../../GirlStreamer/prototype/snake/snake_game.gd) | Owns `SnakeState` and child `Board`; handles steering, attempt lifecycle, physics-time accumulation, board snapshots, and score/outcome signals. Consults the parent before steering and each model step. Exported defaults: 24 × 18 cells, 0.20 seconds per tick and randomized food seed. |
| Snake rules and data | [snake_state.gd](../../GirlStreamer/prototype/snake/snake_state.gd) | `RefCounted` model: body cells, direction, one pending turn, food, score, collision rules and terminal reason. Reset injects an RNG; discrete steps return a movement flag. Body snapshots are copied. No UI or input dependency. |
| Board drawing | [snake_board.gd](../../GirlStreamer/prototype/snake/snake_board.gd) | `Node2D` draws the grid, body and food from a snapshot; centers square cells within the supplied rectangle. Owns drawing colors, not movement rules. |
| Layout, HUD and results | [prototype_hud.tscn](../../GirlStreamer/prototype/ui/prototype_hud.tscn), [prototype_hud.gd](../../GirlStreamer/prototype/ui/prototype_hud.gd) | Full-window layout with `MarginContainer/VBoxContainer/PlayArea/BoardArea` plus attempt score, session food, countdown, attempt status, a fixed message column, results and instructions. Emits `board_rect_changed(rect)` after board-area resizing. |
| Controls | [project.godot](../../GirlStreamer/project.godot) | `snake_up/down/left/right`: arrow keys and physical WASD. Consumed by `SnakeGame._unhandled_input()`. Space maps to `attempt_retry` and Enter to `session_restart`. Both are handled by `PrototypeSession._unhandled_input()`. Physical top-row 1–3 map to `message_answer_1/2/3` and are handled by QuickMessages. |
| Quick questions | [quick_messages.gd](../../GirlStreamer/prototype/messages/quick_messages.gd) | Holds question content, scheduling, deadline, keyboard answers and feedback. Uses the session sampler and reports opening/resolution. |
| Movement regression checks | [test_snake_movement.gd](../../GirlStreamer/tests/iteration01/test_snake_movement.gd) | Standalone `SceneTree` runner: reset/step, copied snapshots, reverse rejection, one-turn buffering, and invalid directions. |
| Food and completion checks | [test_snake_food.gd](../../GirlStreamer/tests/iteration01/test_snake_food.gd) | Seeded spawning, collection, growth, reset, final-cell completion and controller notification order. |
| Collision and retry checks | [test_snake_collisions.gd](../../GirlStreamer/tests/iteration01/test_snake_collisions.gd) | Wall, retained body, vacating tail, single notification and session-routed retry. |
| Timed-session checks | [test_timed_session.gd](../../GirlStreamer/tests/iteration01/test_timed_session.gd) | Controlled-clock deadline, retry accounting, results and new-session reset. |
| Quick-message checks | [test_quick_messages.gd](../../GirlStreamer/tests/iteration01/test_quick_messages.gd) | Scheduling, physical keys, retry independence, cancellation and metrics. |

## Connections and contracts

- Scene tree: `PrototypeSession` → `SnakeGame` → `Board`; `PrototypeHUD` and `QuickMessages` are siblings of `SnakeGame`.
- Layout flow: HUD resize signal → session → `SnakeGame.set_board_rect()` → `SnakeBoard`. Initial layout is applied deferred before starting the first session.
- Gameplay flow: Input Map → controller → `SnakeState.request_turn()`; physics accumulator → `SnakeState.step()` → copied snapshot → board redraw.
- Feedback flow: `SnakeGame.score_changed` and `SnakeGame.attempt_finished` → session → HUD. Terminal steps publish the final board and enter WAITING_FOR_RETRY before notifying listeners.
- The model starts with three cells facing right. It accepts at most one perpendicular turn per tick; reverse, repeated direction, and non-cardinal requests are rejected.
- Walls and retained body cells end the attempt before movement or reward changes. A nongrowing step may enter the tail cell vacated in that same step.
- Session state is READY, RUNNING or FINISHED. The parent samples the monotonic deadline before gameplay actions and stops Snake at expiry, including while waiting for a retry.
- Space requires RUNNING with time remaining and an attempt in WAITING_FOR_RETRY. Enter requires FINISHED. Attempts reset only Snake state; a new session also resets time and aggregate counters.
- The parent advances QuickMessages with its existing time sample and only opens new choices while Snake is playing. Active choices survive retries and are cancelled synchronously at session expiry before results are shown.
- The parent snapshots question settings per session (enabled, 45 s first delay, 45 s gap, 5 s window), tracks outcome counts and stores response samples in memory.
- Controller tuning is validated and captured at `start()`: dimensions 8–64, tick interval 0.05–1.00 seconds. A fresh RNG per start uses randomized or fixed seed settings. Editing exports during a run does not update the active values until another start.

## Scope and tooling

- Implemented gameplay: Snake movement, responsive board layout, food, growth, attempt score, full-board completion, wall/self collisions, Space retry, timed sessions, quick questions and combined results. The paired human playtest is tracked in the Stage 5 plan. See the [iteration plan](Iteration01ImplementationPlan.md) only when planning or implementing those tasks.
- `addons/funplay_mcp/` is vendored editor integration, not gameplay code. The enabled entry is [plugin.cfg](../../GirlStreamer/addons/funplay_mcp/plugin.cfg). Its runtime bridge source exists, but no runtime bridge autoload is configured.
- MCP connection: project `.codex/config.toml` → `Codex/Tools/FunplayMCP/launch.mjs` → pinned stdio wrapper → plugin in the running editor. Read [GodotMCP.md](../../Codex/GodotMCP.md) only for connection details or troubleshooting.
- `.godot/` is generated editor/import data. Keep script `.gd.uid` companions and scene/resource references intact; do not use caches as implementation sources.

## Working requirements

- Follow [ImplementationRules.md](ImplementationRules.md). Read the specific design or stage document only when the task depends on it.
- Keep movement rules in the model, input/timing in the controller, drawing in the board, layout in the HUD, and cross-component coordination in the session.
- Preserve or update both sides of signal, node-path, and scene-resource references when changing composition. Verify the current source before relying on this map.
- For movement changes, the existing focused runner is `Godot --headless --path GirlStreamer --script res://tests/iteration01/test_snake_movement.gd` from the repository root; substitute the installed Godot executable. Use `test_snake_food.gd` for collection/completion and `test_snake_collisions.gd` for collisions/retry, and `test_timed_session.gd` for the session lifecycle and `test_quick_messages.gd` for questions with the same command. UI/layout/input changes also need editor or play checks. This document does not certify test results.
- After every Godot task, check this map against the result and update affected ownership, paths, connections, contracts, tests, and implementation status before handoff. If nothing architectural changed, leave it unchanged and state that in the handoff. Keep it short; link to focused documents instead of adding implementation history.
