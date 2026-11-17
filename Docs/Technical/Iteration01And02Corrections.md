# Iterations 1 and 2 Corrections — Implementation Plan

> **For agentic workers:** Use `executing-plans` to implement this plan task by task; follow the project workflow and use `stage-orchestrator` for whole-plan execution. Steps below track implementation, not documentation preparation.

**Date:** 2026-11-17. **Status:** Implemented. Automated verification passed on Godot 4.7.2. Final manual acceptance is open.

**Goal:** Shorten the stream, increase interaction frequency, clear the chat area, align controls with the board and accelerate Snake after food.

**Architecture:** Modify the existing session clock, StreamDirector, SnakeGame controller and HUD. Keep SnakeState's grid/food rules and the shared interaction pipeline; do not recreate iteration 1's obsolete QuickMessages controller.

**Tech stack:** Godot 4.7 Standard, typed GDScript, native Control containers, existing SceneTree test runners.

**Spec:** [Iteration 02 scope](../GameDesign/Iteration02Scope.md), [Minigames](../GameDesign/Mechanics/Minigames.md), [Streaming gameplay](../GameDesign/Mechanics/StreamingGameplay.md).

## Global constraints and precedence

This correction contract supersedes conflicting duration, interaction cadence, constant-speed and HUD-placement instructions in both original roadmaps and their stage documents. Other rules remain applicable. Previous acceptance does not certify these corrections. [Architecture.md](Architecture.md) describes the implemented ownership and contracts.

- Stream duration: **180 active seconds**. Pause and READY/CLOSING/FINISHED time are excluded; expiry still stops gameplay immediately.
- Interpret the requested approximately **20-second** message cadence as time **between interactive openings**, not a 20-second wait after answering. Ambient chat and donation receipts retain their own schedules.
- First opening: 20 active seconds. Next opening: no earlier than 20 active seconds after the previous actual opening, with at most one active choice and the existing maximum of eight openings per stream. Ideal uninterrupted times: 20, 40, 60, 80, 100, 120, 140, 160 seconds. Eligibility can reduce the count.
- Preserve donor → reaction → ordinary priority, candidate freshness, response windows, reaction eligibility cooldown, pause and cutoff authorization. Do not introduce random jitter or accumulate missed openings.
- Each food adds **10% of base movement speed** within the current attempt. Planning interpretation: retry and new stream reset speed; pause and answering preserve it. No additional speed cap is introduced by this request.
- Russian UI copy, current renderer/stretch, keyboard bindings and supported minimum 1024 × 768 remain in force. Validate also at 1280 × 900.
- Follow the project workflow and engine implementation rules.

## Review focus

1. Deadline at 180 seconds must reject gameplay, choice openings and donations while including the final passive audience second — Task 1.
2. Delayed eligibility, pause and long updates must not cause a burst or overlapping choices — Task 1.
3. Food collected during a multi-step update must affect the next step without changing the elapsed cost of the completed step — Task 2.
4. Retry, pause and terminal food must preserve accounting, notification order and correct speed reset — Task 2.
5. Visible audience explanations, donor receipts and long choice text must not overlap chat/board or move their geometry — Task 3.

## Task 1 — Stream duration and interaction cadence

**Files:** `GirlStreamer/prototype/prototype_session.gd`, `prototype/prototype_session.tscn`, `prototype/stream/stream_director.gd` (all subsequent runtime paths relative to `GirlStreamer/`). Tests: `tests/iteration01/test_timed_session.gd`, `tests/iteration02/test_stream_lifetime.gd`, `test_stream_director.gd`, `test_stream_audience.gd`, `test_stream_donations.gd`, `test_stream_integration.gd`.

**Interfaces:** Preserve `StreamDirector.start(enabled: bool, question_window_msec: int)`, `tick(now_msec: int, snake_playing: bool)` and `on_choice_resolved(resolution: Content.ChoiceResolution)`. Session remains the authority for elapsed active time and cutoff.

- [x] Add controlled-clock checks for the 180-second default, initial HUD `03:00`, pause exclusion, retry preserving the deadline and fresh-stream reset. Check just before and exactly at 180000 ms; include 180 audience drift steps and donation opportunities 10…170 seconds, never at 180.
- [x] Add director checks: no opening at 19999 ms; first at 20000; answering at 21000 or expiring at 26000 still permits the next at 40000, never earlier. Check delayed second opening at 47000 moves the next deadline to 67000. Check active-choice exclusion, pause, retry eligibility, existing priority/freshness and eight-opening cap.
- [x] Verify that the new opening-cadence regression fails against the previous scheduler.
- [x] Set `session_duration_seconds` to 180, including any scene override. Set director `first_delay_seconds` and `gap_seconds` to 20; redefine/document the gap as opening-to-opening. After a successful opening, schedule from its actual timestamp. Resolution releases the active slot without adding another gap. Rejected openings consume neither budget nor a new deadline. A delayed eligible opening schedules from now, without catch-up.
- [x] Update normal-preset fixtures and balance comparisons to 180 seconds. Keep explicit custom-duration tests when they test configuration rather than the default; do not blindly replace every 360 literal. Remove obsolete resolution-plus-gap expectations.
- [x] Run owning tests again and verify cutoff, restart and combined results.
- [ ] Reassess balance with the three-minute manual protocol.

## Task 2 — Additive Snake acceleration

**Files:** `prototype/snake/snake_game.gd`; tests `tests/iteration01/test_snake_movement.gd`, `test_snake_food.gd`, `test_snake_collisions.gd` and pause/lifetime checks in `tests/iteration02/test_stream_lifetime.gd`.

**Interfaces:** Keep `start()`, `restart_attempt() -> bool`, `_physics_process(delta: float)`, `score_changed(score: int)` and `attempt_finished(reason: StringName, score: int)`. SnakeState's current attempt score supplies food count; session food totals must not control speed.

For base tick interval `T0` and food count `n` in the current attempt:

```text
base_speed = 1 / T0                  # cells per second
speed(n) = base_speed * (1 + 0.10*n)
tick_interval(n) = T0 / (1 + 0.10*n)
```

At the existing base `T0 = 0.20 s`: 0 food → 5 cells/s and 0.20 s; 1 → 5.5 and ~0.181818 s; 2 → 6 and ~0.166667 s; 10 → 10 and 0.10 s. Do not multiply the current speed by 1.1 or subtract 10% from the tick interval.

- [x] Add checks for these values with floating-point tolerance, no acceleration without food, attempt-local counting, retry/new-stream reset and pause preserving speed plus partial tick time. Include a high food count proving the base export's 0.05-second validation floor is not a hidden runtime speed cap.
- [x] Add a controlled multi-step food scenario: subtract the interval used by the completed step before recalculating speed; remaining accumulated seconds use the updated interval. Test full-board food accounting and terminal notification order, with no movement after terminal state or stream expiry.
- [x] Run the focused checks and confirm the constant-speed implementation fails the new behavioral assertions.
- [x] Snapshot the base interval at `start()`, separately from the current interval. Derive the current interval from the base and attempt food count after collection, before evaluating the next movement step. Preserve leftover elapsed seconds, authorization before every step and terminal early return. Reset base/current interval through the existing attempt start path. Keep growth and score at one segment/point per food.
- [x] Run movement, food, collision and lifetime checks.
- [ ] Check steering and answering at increased speed during the human playtest.

## Task 3 — HUD layout corrections

**Files:** `prototype/ui/prototype_hud.tscn`, `prototype/ui/prototype_hud.gd`; affected node-path references in `prototype/prototype_session.gd`, `tests/iteration02/test_stream_feedback.gd`, `test_stream_lifetime.gd`, `test_stream_donations.gd`, `test_stream_integration.gd`.

**Interfaces:** Preserve `board_rect_changed(rect)` and the HUD's public presentation methods. Update scene paths and inferred-parent lookups together, particularly `_donation_strip`, which currently derives its location from ChatHistory's parent.

The user's blue annotation identifies **AudienceStrip and DonationStrip**, including explanations and receipt notifications. Move both into a dedicated panel **below ChatSlot**, aligned with its left/right edges. Keep the webcam above chat and the chat feed inside ChatSlot. Do not move the interactive question into the statistics panel.

Target arrangement (proportions are illustrative, not screenshot pixels):

```text
Header across the window
Board                         Webcam
Board                         Chat feed
Choice area                   Audience / donations
Controls centred under board
```

- [x] Use container-owned columns or coordinated rows to reserve the left board/choice/controls regions and the right webcam/chat/statistics regions. Preserve a board area of at least 480 × 360 and a stable choice region; do not add offsets that a parent Container will overwrite.
- [x] Place `Instructions` in a left-width container and centre its text on the actual board's horizontal centre, rather than the full window. Keep both control lines readable, including movement, answers, retry and pause. Retain start/results instructions through lifecycle changes.
- [x] Update all affected node references and layout assertions. Check fixed reserved panel space with empty and populated audience/donation content so changing visibility does not move the board, chat or controls.
- [ ] Verify at 1024 × 768 and 1280 × 900: statistics panel top is below chat bottom; their horizontal edges align; controls centre matches board centre (within one logical pixel); chat, board and choice text remain disjoint and readable. Show a long question with all options, audience explanation and donor notification together; inspect scroll behavior, pause, closing, results and restart in a standalone window.
- [x] Run the affected lifetime, feedback, donation and integration runners.
- [ ] Capture visual acceptance evidence in a standalone window.

## Verification and handoff

Use the installed Godot executable resolved through project instructions; from the repository root, run each owning runner listed above once against the integrated result:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_director.gd
```

Replace the script path for each runner. Expected: explicit success, exit code 0, no new parser/runtime errors. Investigate diagnostics rather than inferring success from exit status alone.

- [ ] Perform the Stage 7 gameplay-focused and communication-focused sessions at **three active minutes each**, using matching settings/seeds, plus its short abuse/recovery and standalone/audio protocols. Record actual readability and high-speed control observations. Existing acceptance cards [OI-002](../OpenItems/Items/OI-002-WindowAcceptance.md) and [OI-003](../OpenItems/Items/OI-003-StreamPlaytest.md) remain open until their checks are satisfied.
- [x] Update Architecture.md to implemented timing, speed and scene ownership; reconcile affected stage expectations with this contract. Keep pending failures in the relevant OpenItems cards and historical run evidence in a new local report.
Automated coverage includes all 11 iteration runners, the 17 normal donation opportunities, the 180-second cutoff, and layout geometry and text bounds at both target sizes. The six-minute repeated-loss scenario is an explicit stress fixture with custom director timing to isolate loss bonus suppression. Graphical scene-load smoke passed at both target sizes. A standalone run requested at 1024 × 768 confirmed the initial 03:00, panel order and alignment, controls centred under the board, and Escape pause/resume. Populated layout in a rendered window, screenshots, and the larger-window visual check remain open. Final acceptance is tracked in [OI-001](../OpenItems/Items/OI-001-AudioAcceptance.md), [OI-002](../OpenItems/Items/OI-002-WindowAcceptance.md) and [OI-003](../OpenItems/Items/OI-003-StreamPlaytest.md).
