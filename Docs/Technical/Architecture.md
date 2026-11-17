# Current project architecture

Read before Godot work, then open only the files relevant to the task. This is a map of existing code, not a roadmap. Last checked against source: 2026-11-13.

## Runtime and entry point

- Godot 4.7 Standard, GDScript, GL Compatibility; configured viewport and minimum window size: 1024 × 768.
- Engine root: `GirlStreamer/`; all `res://` paths below are relative to it.
- [project.godot](../../GirlStreamer/project.godot) owns the startup scene, display settings, Input Map, renderer, and enabled editor plugins.
- Startup scene: `res://prototype/prototype_session.tscn`. No autoloads are currently configured.

## Find the owning file

| Concern | Files | Responsibility |
| --- | --- | --- |
| Session lifecycle and timing | [prototype_session.tscn](../../GirlStreamer/prototype/prototype_session.tscn), [prototype_session.gd](../../GirlStreamer/prototype/prototype_session.gd) | Owns readiness, active time, authorization, canonical event and attempt identity, per-kind accounting, frozen results and presentation routing. |
| Snake controller and tuning | [snake_game.tscn](../../GirlStreamer/prototype/snake/snake_game.tscn), [snake_game.gd](../../GirlStreamer/prototype/snake/snake_game.gd) | Owns `SnakeState` and child `Board`; handles steering, attempt lifecycle, physics-time accumulation, board snapshots, and score/outcome signals. Consults the parent before steering and each model step. Exported defaults: 24 × 18 cells, 0.20 seconds per tick and randomized food seed. |
| Snake rules and data | [snake_state.gd](../../GirlStreamer/prototype/snake/snake_state.gd) | `RefCounted` model: body cells, direction, one pending turn, food, score, collision rules and terminal reason. Reset injects an RNG; discrete steps return a movement flag. Body snapshots are copied. No UI or input dependency. |
| Board drawing | [snake_board.gd](../../GirlStreamer/prototype/snake/snake_board.gd) | `Node2D` draws the grid, body and food from a snapshot; centers square cells within the supplied rectangle. Owns drawing colors, not movement rules. |
| Layout, HUD and results | [prototype_hud.tscn](../../GirlStreamer/prototype/ui/prototype_hud.tscn), [prototype_hud.gd](../../GirlStreamer/prototype/ui/prototype_hud.gd) | Russian stream shell with board at `MarginContainer/VBoxContainer/MainArea/BoardArea`, a fixed choice area, side column, instructions and results. Renders chat snapshots and emits `board_rect_changed(rect)` on resize. |
| Stream events | [stream_event.gd](../../GirlStreamer/prototype/stream/stream_event.gd) | Typed records with attempt identity and precedence for completion, milestone, record and food. IDs increase across retries and reset with a new stream. |
| Chat | [chat_feed.gd](../../GirlStreamer/prototype/stream/chat_feed.gd), [stream_content.gd](../../GirlStreamer/prototype/stream/stream_content.gd) | Seeded local selection from Russian contextual pools, four-second ambient cadence and 60 retained lines. Emits copied snapshots to the HUD. |
| Webcam | [hero_webcam.gd](../../GirlStreamer/prototype/ui/hero_webcam.gd), [hero_webcam.tscn](../../GirlStreamer/prototype/ui/hero_webcam.tscn) | Geometric portrait with two-second automatic emotions and priority for three-second selected replies. Coalesces automatic updates during a reply and preserves their original deadlines. |
| Controls | [project.godot](../../GirlStreamer/project.godot) | Snake owns arrows/physical WASD. The session owns Space (`attempt_retry`), Enter (`session_restart`) and Escape (`session_pause`). StreamChoice owns physical top-row 1–3. |
| Timed choices | [stream_choice.gd](../../GirlStreamer/prototype/stream/stream_choice.gd), [stream_content.gd](../../GirlStreamer/prototype/stream/stream_content.gd) | One active choice with copied definition, source metadata and outcome. Content supplies twelve ordinary questions and four reaction variants with replies and provisional effects. |
| Interaction scheduling | [stream_director.gd](../../GirlStreamer/prototype/stream/stream_director.gd) | Shared opening budget, delay and cooldown. Owns ordinary context and one pending candidate each for reactions and donation questions. Requests openings through the session. |
| Audience | [audience_state.gd](../../GirlStreamer/prototype/stream/audience_state.gd), [prototype_session.gd](../../GirlStreamer/prototype/prototype_session.gd) | Deterministic group counts, impressions, signed carries and style attenuation. Session advances whole active seconds, routes each source once, applies record/loss gates and owns the latest 20 measured causes. |
| Donations | [donation_controller.gd](../../GirlStreamer/prototype/stream/donation_controller.gd) | Samples active-time opportunities from audience weights with an independent RNG and commits fictional coins before emitting a receipt. Session routes one copied receipt to chat, HUD and the donor-priority slot. |
| Frozen results | [stream_results.gd](../../GirlStreamer/prototype/stream/stream_results.gd), [prototype_session.gd](../../GirlStreamer/prototype/prototype_session.gd) | Session assembles one snapshot after final passive drift and choice cancellation. Includes per-kind counters and answer latency, selected reactions and up to three measured highlights. HUD renders the snapshot in a scrollable panel. |
| Audio | [stream_audio.gd](../../GirlStreamer/prototype/stream/stream_audio.gd) | Scene-owned players for question, donation and finish WAVs. Session owns the process-local M preference and stops audio on pause, close skip and restart. |
| Movement regression checks | [test_snake_movement.gd](../../GirlStreamer/tests/iteration01/test_snake_movement.gd) | Standalone `SceneTree` runner: reset/step, copied snapshots, reverse rejection, one-turn buffering, and invalid directions. |
| Food and completion checks | [test_snake_food.gd](../../GirlStreamer/tests/iteration01/test_snake_food.gd) | Seeded spawning, collection, growth, reset, final-cell completion and controller notification order. |
| Collision and retry checks | [test_snake_collisions.gd](../../GirlStreamer/tests/iteration01/test_snake_collisions.gd) | Wall, retained body, vacating tail, single notification and session-routed retry. |
| Timed-session checks | [test_timed_session.gd](../../GirlStreamer/tests/iteration01/test_timed_session.gd) | Controlled-clock deadline, retry accounting, results and new-session reset. |
| Stream choice checks | [test_stream_choices.gd](../../GirlStreamer/tests/iteration02/test_stream_choices.gd) | Catalog, single input ownership, deadlines, outcomes and selected presentation. |
| Director checks | [test_stream_director.gd](../../GirlStreamer/tests/iteration02/test_stream_director.gd) | Shared scheduling, candidate priority, freshness, caps and retry relevance. |
| Audience checks | [test_stream_audience.gd](../../GirlStreamer/tests/iteration02/test_stream_audience.gd) | Numerical model rules and deterministic six-minute comparisons. The feedback runner covers routing, timing and snapshots. |
| Donation checks | [test_stream_donations.gd](../../GirlStreamer/tests/iteration02/test_stream_donations.gd) | Sampling boundaries, deterministic receipts, routing, notification capacity and lifecycle. |
| Final integration checks | [test_stream_integration.gd](../../GirlStreamer/tests/iteration02/test_stream_integration.gd) | Crowded finish, copied results and highlights, combined question arithmetic, mute, WAV loading and restart. |
| Stream lifetime checks | [test_stream_lifetime.gd](../../GirlStreamer/tests/iteration02/test_stream_lifetime.gd) | Controlled-clock readiness, pause gates, expiry, closing and clean restart. |
| Stream feedback checks | [test_stream_feedback.gd](../../GirlStreamer/tests/iteration02/test_stream_feedback.gd) | Chat cadence and retention, seeded independence, event ordering, webcam priority, lifecycle and fixed layout. |

## Connections and contracts

- Scene tree: `PrototypeSession` owns SnakeGame, PrototypeHUD, StreamChoice, StreamDirector, ChatFeed, DonationController and StreamAudio. SnakeGame owns Board. HeroWebcam lives in the HUD's WebcamSlot.
- Layout flow: HUD resize signal → session → `SnakeGame.set_board_rect()` → `SnakeBoard`. The first positive layout rectangle enables explicit start.
- Gameplay flow: Input Map → controller → `SnakeState.request_turn()`; physics accumulator → `SnakeState.step()` → copied snapshot → board redraw.
- Feedback flow: Snake notifications → session accounting → canonical event → chat and webcam. Terminal steps enter WAITING_FOR_RETRY before notifying listeners. Final food counts toward the total and the board completion owns the only feedback event. Accepted Snake events carry the authorized step timestamp. Cosmetic cutoff checks use a read-only sample so they cannot split a terminal notification pair.
- The model starts with three cells facing right. It accepts at most one perpendicular turn per tick; reverse, repeated direction, and non-cardinal requests are rejected.
- Walls and retained body cells end the attempt before movement or reward changes. A nongrowing step may enter the tail cell vacated in that same step.
- Session state is READY, RUNNING, PAUSED, CLOSING or FINISHED. Only RUNNING spans contribute to gameplay elapsed time. Expiry takes precedence over gameplay actions. Pausing gates gameplay and clears only the buffered Snake turn, preserving the partial physics tick and retry state.
- Space retries while RUNNING and waiting for an attempt. Enter starts from READY/FINISHED or skips CLOSING. Escape toggles RUNNING/PAUSED. A new session resets time, attempts and aggregate counters.
- StreamChoice uses authorized active time for input deadlines and latency. Open choices survive retries and pause. Stream expiry stops the director and cancels the active choice before the results snapshot. Accepted choices route one authored reply and one compatible chat line.
- StreamDirector snapshots tuning at start. Defaults are 30 s to first opening, 25 s between a resolution and the next opening, and at most eight choices. Loss and completion reactions can open while waiting for retry. Ordinary and donation questions require a playing attempt. The donor's identity, amount, source group and text are copied at receipt. The window is sampled when the donor question opens.
- The session retains copied outcomes and provisional effects. Ordinary question answer rate and mean exclude reactions. Reaction options have fixed style order and a 3 s window, while ordinary questions default to 6 s.
- The session advances audience drift through the authorized event timestamp before applying an effect. Closing flushes the final passive step and freezes the snapshot. The HUD renders group counts, impressions and measured causes. The director and chat sample current viewers only when assigning a new ordinary question window or ambient deadline.
- During RUNNING the session advances drift, resolves due choices, samples at most one donation and then ticks the director. Donor answers and expiry affect audience only. The HUD keeps one visible receipt, three queued records and an overflow aggregate. Closing stops sampling and freezes controller totals before the summary.
- The two-second wall-clock closing interval presents a static webcam goodbye and one finish cue. Ordinary and donor question opens share an audio cue. Each committed routed payment requests one donation cue. A newer gameplay cue replaces the prior one. Rendering results has no model or audio side effects.
- Feed cadence, food feedback cooldown and webcam transients advance only with active stream time. Retry preserves chat history and milestone eligibility. Closing retains chat and replaces gameplay expressions with a static goodbye. Restart resets both views.
- Controller tuning is validated and captured at `start()`: dimensions 8–64, tick interval 0.05–1.00 seconds. A fresh RNG per start uses randomized or fixed seed settings. Editing exports during a run does not update the active values until another start.

## Scope and tooling

- Implemented gameplay includes Snake, retries, pausable streams, contextual choices, combined results, contextual chat and webcam replies. See the [iteration 02 plan](Iteration02ImplementationPlan.md) for implementation and acceptance boundaries.
- `addons/funplay_mcp/` is vendored editor integration, not gameplay code. The enabled entry is [plugin.cfg](../../GirlStreamer/addons/funplay_mcp/plugin.cfg). Its runtime bridge source exists, but no runtime bridge autoload is configured.
- MCP connection: project `.codex/config.toml` → `Codex/Tools/FunplayMCP/launch.mjs` → pinned stdio wrapper → plugin in the running editor. Read [GodotMCP.md](../../Codex/GodotMCP.md) only for connection details or troubleshooting.
- `.godot/` is generated editor/import data. Keep script `.gd.uid` companions and scene/resource references intact; do not use caches as implementation sources.

## Working requirements

- Follow [ImplementationRules.md](ImplementationRules.md). Read the specific design or stage document only when the task depends on it.
- Keep movement rules in the model, input/timing in the controller, drawing in the board, layout in the HUD, and cross-component coordination in the session.
- Preserve or update both sides of signal, node-path, and scene-resource references when changing composition. Verify the current source before relying on this map.
- Run the focused script for the affected owner with the installed Godot executable, for example `Godot --headless --path GirlStreamer --script res://tests/iteration02/test_stream_choices.gd`. UI/layout/input changes also need editor or play checks. This document does not certify test results.
- After every Godot task, check this map against the result and update affected ownership, paths, connections, contracts, tests, and implementation status before handoff. If nothing architectural changed, leave it unchanged and state that in the handoff. Keep it short; link to focused documents instead of adding implementation history.
