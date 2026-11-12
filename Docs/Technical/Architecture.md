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
| Session composition and startup | [prototype_session.tscn](../../GirlStreamer/prototype/prototype_session.tscn), [prototype_session.gd](../../GirlStreamer/prototype/prototype_session.gd) | Instantiates `SnakeGame` and `PrototypeHUD`, sets minimum window size, forwards board geometry, starts the game once layout has a nonempty area. |
| Snake controller and tuning | [snake_game.tscn](../../GirlStreamer/prototype/snake/snake_game.tscn), [snake_game.gd](../../GirlStreamer/prototype/snake/snake_game.gd) | Owns `SnakeState` and child `Board`; handles input, start/stop, physics-time accumulation, and visual snapshot updates. Exported defaults: 24 × 18 cells, 0.20 seconds per tick. |
| Snake movement rules and data | [snake_state.gd](../../GirlStreamer/prototype/snake/snake_state.gd) | `RefCounted` model: body cells, direction, one pending turn, reset and discrete step. Returns copied body snapshots. No UI or input dependency. |
| Board drawing | [snake_board.gd](../../GirlStreamer/prototype/snake/snake_board.gd) | `Node2D` draws the grid and body from a snapshot; centers square cells within the supplied rectangle. Owns drawing colors, not movement rules. |
| Layout and instructions | [prototype_hud.tscn](../../GirlStreamer/prototype/ui/prototype_hud.tscn), [prototype_hud.gd](../../GirlStreamer/prototype/ui/prototype_hud.gd) | Full-window layout with `MarginContainer/VBoxContainer/BoardArea` and instructions label. Emits `board_rect_changed(rect)` after board-area resizing. |
| Controls | [project.godot](../../GirlStreamer/project.godot) | `snake_up/down/left/right`: arrow keys and physical WASD. Consumed by `SnakeGame._unhandled_input()`. |
| Movement regression checks | [test_snake_movement.gd](../../GirlStreamer/tests/iteration01/test_snake_movement.gd) | Standalone `SceneTree` runner: reset/step, copied snapshots, reverse rejection, one-turn buffering, invalid directions, and boundary behavior. |

## Connections and contracts

- Scene tree: `PrototypeSession` → `SnakeGame` → `Board`; `PrototypeHUD` is a sibling of `SnakeGame`.
- Layout flow: HUD resize signal → session → `SnakeGame.set_board_rect()` → `SnakeBoard`. Initial layout is applied deferred before the session starts movement.
- Gameplay flow: Input Map → controller → `SnakeState.request_turn()`; physics accumulator → `SnakeState.step()` → copied snapshot → board redraw.
- The model starts with three cells facing right. It accepts at most one perpendicular turn per tick; reverse, repeated direction, and non-cardinal requests are rejected.
- Current boundary behavior holds the body at the edge until a valid turn moves it away. Self-overlap is currently allowed. These are Stage 1 behaviors, not a completed collision system.
- Controller tuning is validated and captured at `start()`: dimensions 8–64, tick interval 0.05–1.00 seconds. Editing exports during a run does not update the active values until another start.

## Scope and tooling

- Implemented gameplay: Stage 1 snake movement and responsive board layout. Food/growth, collision loss/retries, timed sessions, quick messages, and broader game systems have no implementation yet. See the [iteration plan](Iteration01ImplementationPlan.md) only when planning or implementing those tasks.
- `addons/funplay_mcp/` is vendored editor integration, not gameplay code. The enabled entry is [plugin.cfg](../../GirlStreamer/addons/funplay_mcp/plugin.cfg). Its runtime bridge source exists, but no runtime bridge autoload is configured.
- MCP connection: project `.codex/config.toml` → `Codex/Tools/FunplayMCP/launch.mjs` → pinned stdio wrapper → plugin in the running editor. Read [GodotMCP.md](../../Codex/GodotMCP.md) only for connection details or troubleshooting.
- `.godot/` is generated editor/import data. Keep script `.gd.uid` companions and scene/resource references intact; do not use caches as implementation sources.

## Working requirements

- Follow [ImplementationRules.md](ImplementationRules.md). Read the specific design or stage document only when the task depends on it.
- Keep movement rules in the model, input/timing in the controller, drawing in the board, layout in the HUD, and cross-component coordination in the session.
- Preserve or update both sides of signal, node-path, and scene-resource references when changing composition. Verify the current source before relying on this map.
- For movement changes, the existing focused runner is `Godot --headless --path GirlStreamer --script res://tests/iteration01/test_snake_movement.gd` from the repository root; substitute the installed Godot executable. UI/layout/input changes also need editor or play checks. This document does not certify test results.
- After every Godot task, check this map against the result and update affected ownership, paths, connections, contracts, tests, and implementation status before handoff. If nothing architectural changed, leave it unchanged and state that in the handoff. Keep it short; link to focused documents instead of adding implementation history.
