# Stage 1: Stream Shell and Pause-Aware Lifetime — Detailed Implementation Plan

Plan date: 2026-11-12. Implemented, headless-verified and manually accepted by the user on 2026-11-13.

> **For agentic workers:** Use `stage-orchestrator` when executing the whole stage and `executing-plans` for its steps, subject to AGENTS.md. One writer owns the session/HUD integration and one owner controls the editor. No automatic commit or push.

**Goal:** Turn the existing automatically started prototype into a manually started, pausable stream with stable screen regions and a complete start/finish/restart lifecycle.

**Architecture:** PrototypeSession remains the lifetime and time authority. Snake and QuickMessages retain their existing rules and consult the session before actions. Pause is implemented through explicit session gates and a frozen elapsed-time sample, not global tree pause or Engine.time_scale.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, native Containers, Input Map and GL Compatibility.

**Specification:** [Iteration 02 roadmap](../Iteration02ImplementationPlan.md), Stage 1; [agreed scope](../../GameDesign/Iteration02Scope.md); [current architecture](../Architecture.md). Read `Codex/Workflow.md`, `Codex/GodotSkills.md` and `Docs/Technical/ImplementationRules.md` before engine execution. Select Godot UI and scene specialists for the actual edits; use the testing specialist if changing runner behavior.

## 1. Scope and boundaries

Include explicit start/restart, pause/resume, pause-aware deadlines, a minimal closing state, Russian shell text and fixed regions for the existing board/questions plus future webcam/chat.

Keep existing Snake settings, food/collision rules, unlimited attempt retries, 360-second default duration, placeholder question content, 45-second first delay/gap, 5-second answer window and optional message-free baseline. Stage 3 replaces QuickMessages; this stage must not introduce a parallel choice controller. Future question timing from the iteration roadmap does not apply yet.

Do not implement audience, money, donations, contextual chat, character emotions, reactions, sound, new content schemas, saves, additional games, export packaging or the final expanded summary. Webcam/chat areas are labelled static placeholders only.

The roadmap includes CLOSING in Stage 1 but richer closing presentation in Stage 7. Resolve this now: Stage 1 implements the actual two-second lifecycle and plain “Эфир завершён” text, with Enter to skip to results. Stage 7 adds character/audio presentation and expanded statistics without introducing another closing timer.

## 2. Baseline source evidence

- `prototype_session.gd::_on_board_rect_changed()` currently calls `start_session()` after the first usable layout. Replace this with readiness only.
- `_start_msec` and `_deadline_msec` currently use wall-clock ticks. Both `_process()` and action-time checks use `_sample_running_time_msec()`; preserve that single authorization path while changing its clock basis.
- QuickMessages obtains time from the injected sampler before accepting a key. A negative result already rejects input without resolving the question. Its schedules, response latency and feedback deadlines are all expressed in stream elapsed milliseconds.
- SnakeGame checks authorization before accumulating physics delta and before each step. Do not call `stop()` when pausing: it changes the attempt to STOPPED and clears its accumulator.
- Pending direction belongs to SnakeState; no public clear method exists. A minimal new model command is necessary to discard buffered input without resetting the attempt.
- Timed-session, quick-message and parent-retry collision fixtures assume automatic start. Some assert English labels and old HUD paths; the first two also inspect old clock fields. Migrate those assertions deliberately.

These are planning observations from source, not results of running Godot.

## 3. Planned files and ownership

Runtime paths are relative to `GirlStreamer/`.

| File | Planned change |
| --- | --- |
| `prototype/prototype_session.gd` | Readiness, state machine, clock, pause/start input, closing and frozen result ownership |
| `prototype/prototype_session.tscn` | Only composition updates if required by the HUD change; retain SnakeGame, PrototypeHUD, QuickMessages |
| `prototype/ui/prototype_hud.tscn` | Stable header/main/choice/footer regions, webcam/chat slots, shell/status/results presentation |
| `prototype/ui/prototype_hud.gd` | Display methods and Russian strings; preserve board-rectangle reporting and question APIs |
| `prototype/snake/snake_game.gd` | Public `clear_pending_turn() -> void` delegating to its model; no new pause state |
| `prototype/snake/snake_state.gd` | `clear_pending_turn() -> void` clears only `_has_pending_turn` and `_pending_direction` |
| `project.godot` | Add `session_pause` on Escape; reuse `session_restart` on Enter for start/restart/closing skip |
| `tests/iteration02/test_stream_lifetime.gd` (new) | Deterministic readiness, pause, boundary, closing and reset checks |
| `tests/iteration01/test_timed_session.gd` | Explicit start fixture, elapsed-time expectations, CLOSING-aware result/restart checks, Russian text and HUD paths |
| `tests/iteration01/test_quick_messages.gd` | Explicit start, frozen cancellation/results boundary, HUD paths and localized summary assertions |
| `tests/iteration01/test_snake_collisions.gd` | Explicit start in parent retry fixture, localized labels and HUD paths |
| `Docs/Technical/Architecture.md` | Update implemented ownership/contracts after execution, not during this planning task |

QuickMessages source should not need behavioral changes: the session sampler and call gating suffice. If inspection during execution proves otherwise, keep changes limited to the pause contract and record the reason. Do not delete old rule checks merely because their fixtures need migration.

## 4. State and input contract

Use `SessionState { READY, RUNNING, PAUSED, CLOSING, FINISHED }` with explicit comparisons, not hard-coded enum integers.

| State | Behavior | Accepted controls |
| --- | --- | --- |
| READY | No active attempt, clock/metrics zero, controls shown; positive board layout enables start | Fresh Enter starts after readiness and successful validation |
| RUNNING | Existing Snake and questions advance; retry waiting still consumes stream time | Movement, 1–3, Space when waiting, Escape pauses |
| PAUSED | All gameplay and message time frozen; attempt and open question retained | Fresh Escape resumes; other gameplay/start inputs ignored |
| CLOSING | Gameplay ended, active question cancelled once, summary already frozen, no new outcomes | Fresh Enter skips to FINISHED; otherwise automatic after 2 seconds |
| FINISHED | Stable existing results and last board | Fresh Enter starts a clean session |

Handle only pressed non-echo events; releases do nothing. A single event can cause at most one transition. Enter that discovers expiry in RUNNING must not also skip closing or restart. Enter used to skip closing must not also restart. Escape at/after the stream deadline finishes rather than pausing.

Keep session controls in one handler. Consume recognized session actions before returning, including ignored Enter/Escape in other states. Passive HUD Controls must not gain keyboard focus. Snake and QuickMessages continue to own their respective actions; do not introduce buttons or duplicate key polling.

No automatic pause on focus loss is added in this stage. Window-close retains ordinary application behavior. Pause is not a settings menu and does not allow changing active tuning values.

## 5. Clock and method contracts

Use the existing overridable `_now_msec() -> int` as the wall-clock seam for deterministic tests. Replace `_deadline_msec` as gameplay authority; do not keep two competing deadline implementations.

Session-local fields:

- `_layout_ready: bool`: first positive board rectangle observed; later resize never starts/restarts anything.
- `_elapsed_before_run_msec: int`: completed active RUNNING spans, initially zero.
- `_run_started_msec: int`: wall-clock start of the current active span.
- `_duration_msec: int`: validated snapshotted duration; Inspector edits cannot change an active stream.
- `_closing_started_msec: int`: separate wall-clock presentation start, set only at finish.

Clock calculation while RUNNING: `min(_duration_msec, _elapsed_before_run_msec + max(0, now - _run_started_msec))`. PAUSED returns the saved elapsed value. READY returns zero. CLOSING/FINISHED return the captured final duration. Sample wall time once per decision and pass the sample through private helpers; avoid nested helpers consuming multiple controlled-clock samples.

| Method | Contract |
| --- | --- |
| `is_layout_ready() -> bool` | Exposes start readiness for fixtures without relying on private HUD layout |
| `start_session() -> bool` | Only READY/FINISHED and ready layout; validate before mutations, reset state once, set RUNNING before Snake emits initial score; return success |
| `get_stream_time_msec() -> int` | Read-only clamped gameplay elapsed sample; does not authorize actions or trigger a state transition |
| `get_elapsed_seconds() -> float` | Compatibility wrapper over stream elapsed milliseconds |
| `get_remaining_seconds() -> float` | Remaining duration in RUNNING/PAUSED; zero before start and after finish |
| `is_stream_active() -> bool` | True only in RUNNING; no gameplay updates during PAUSED, even though the stream is resumable |
| `_sample_running_time_msec() -> int` | Return -1 outside RUNNING; in RUNNING use one wall sample, finish if elapsed ≥ duration, otherwise return elapsed |
| `_authorize_snake_action() -> bool` | Existing wrapper: authorized sample ≥0 |
| `pause_session() -> bool` | Only RUNNING; first check expiry with one sample, otherwise save elapsed, clear buffered turn and set PAUSED |
| `resume_session() -> bool` | Only PAUSED; set new wall-clock span start, clear buffered turn again, set RUNNING without resetting other systems |
| `_finish_session(now_msec: int) -> void` | Idempotent RUNNING-only transition to CLOSING; cancel and freeze once, start presentation clock from the caller's already sampled wall time |
| `_complete_closing() -> void` | CLOSING-only transition to FINISHED and display the frozen results |

Pause must leave the Snake body, committed direction, food, score, PLAYING/WAITING_FOR_RETRY state and partial movement accumulator unchanged. Only pending direction is cleared. Paused physics callbacks return at authorization before adding delta. On resume the partial active tick continues; paused wall time is never injected into physics delta or accumulated in a catch-up loop.

Do not use `SceneTree.paused` or change process modes globally. The existing owner-level gates provide the necessary freeze and keep Escape, resizing and shell presentation responsive. Future Stage 2+ systems must use the same RUNNING gate and stream clock. For synchronous Snake notifications, preserve the authorized timestamp for the producing step as specified in Stage 2. The generic lifetime runner owns clock, input and closing boundaries. Legacy runners retain their attempt, aggregation and question-specific checks without adding a second shell matrix.

## 6. Questions, retry and finish ordering

During PAUSED the session does not call QuickMessages.tick. Its input sampler returns -1. Preserve current question ID/options/deadline, feedback deadline, next due time and metrics. Resume changes none of these because their timestamps already use active elapsed time. Answer latency excludes paused duration.

Space remains a fresh attempt command only in RUNNING while Snake waits. Retry changes neither clock nor question. Pausing during WAITING_FOR_RETRY preserves that state; resume must not start a new attempt automatically. A new question is still deferred until Snake is playing.

At stream expiry:

1. Enter CLOSING first, denying gameplay/retry/answer authorization.
2. Stop Snake once and capture final elapsed duration.
3. Cancel QuickMessages synchronously with final stream elapsed milliseconds.
4. Accept only the matching `cancelled` resolution in CLOSING; reject other late outcomes. Update `_on_question_resolved`, which currently permits this exception only in FINISHED.
5. Capture existing session and question summary values after cancellation. Clear the question display and show closing text; no expanded audience/donation results yet.
6. After two wall-clock seconds, or a fresh closing-skip Enter, show that same frozen summary in FINISHED. No second cancellation or metrics recalculation.

Preserve `shown = answered + expired + cancelled` and exclude cancelled questions from answer-rate denominators. Keep individual answer times owned by the session; copy them if retaining them in a snapshot. Do not delay the actual freeze until the closing animation finishes.

Startup failure: invalid duration/message settings must leave READY or FINISHED unchanged and show a readable Russian error. If Snake fails after start initialization, clean up to READY with zero clock/counters, no question and no active attempt. A subsequent valid start must succeed without duplicated connections. Start/restart from PAUSED or CLOSING must return false without side effects.

## 7. HUD layout and copy

Preserve 1024 × 768 minimum size and current stretch settings. Use existing Containers rather than absolute child offsets. Proposed shell hierarchy under `MarginContainer/VBoxContainer`:

```text
Header                         # two compact rows: time, scores, session status
MainArea (HBoxContainer)
  BoardArea                    # expanding, minimum usable area 480 × 360
  SideColumn (VBoxContainer)   # 280 px starting width
    WebcamSlot                 # 160 px height, static “Вебка” placeholder
    ChatSlot                   # fills remaining space, static “Чат” placeholder
ChoiceArea                     # fixed 180 px minimum height, full available width
Instructions                   # compact two-line control text
```

Use 16 px outer margins and approximately 8 px separations. Keep header ≤56 px and instructions ≤40 px at minimum size; MainArea receives remaining height. ChoiceArea uses compact prompt, countdown, three options and feedback rows. Limit current short content to the reserved area; do not let Label minimum widths force a larger window. Validate actual font metrics visually, adjusting spacing rather than shrinking the board below its stated minimum.

READY/PAUSED/CLOSING banners use a reserved header/status slot, not a transient row that moves the board. Pause leaves the question visible with its frozen countdown. Results may replace the main content after gameplay ends; board geometry must stay identical across RUNNING question/idle/feedback/PAUSED states at the same window size. Preserve the existing board rectangle → session → renderer flow with canvas-global coordinates.

HUD remains presentation-only. Add `show_ready()`, `set_paused(paused: bool)` and `show_closing()` as display methods; keep existing score/time/question/result methods. `set_paused(false)` restores presentation without resetting messages or overwriting the attempt's retry status. Update all onready paths after moving Controls. Keep keyboard focus disabled on passive content.

Minimum shell copy:

| Situation | Russian text |
| --- | --- |
| Ready | «Готова к эфиру»; «Enter — начать стрим» |
| Running controls | «Стрелки / WASD — движение. 1–3 — ответ.» / «Пробел — новая попытка. Esc — пауза.» |
| Paused | «Пауза — Esc, чтобы продолжить» |
| Closing | «Эфир завершён»; «Enter — перейти к итогам» |
| Finished | «Итоги эфира»; «Enter — новый стрим» |
| Wall / self collision | «Столкновение со стеной — пробел для новой попытки» / «Столкновение с собой — пробел для новой попытки» |
| Full board | «Поле заполнено — пробел для новой попытки» |
| Bad settings | «Не удалось начать: проверьте настройки длительности / вопросов / Змейки» (select the actual failing category) |

Localize existing time, score, food and summary captions too; use «нет данных» for undefined answer rate/mean, preserving zero-denominator semantics. No localization framework is needed for these fixed strings.

## 8. Ordered implementation tasks

- [x] **A — Prepare focused failing checks.** Confirm that the lifetime runner rejects automatic start on the baseline.
- [x] **B — Implement state and clock.** Add explicit readiness, active-time calculation, pause/resume, synchronous question cancellation and frozen results.
- [x] **C — Implement pause input boundary.** Add Escape mapping, state-based Enter handling and buffered-turn clearing.
- [x] **D — Build the shell layout.** Reserve the board, question and static placeholder regions. Localize the presentation and preserve resize propagation.
- [x] **E — Migrate affected regression fixtures.** Start explicitly after readiness, update the clock and HUD assertions and preserve accounting checks through CLOSING.
- [ ] **F — Verify and document.** Run the bounded checks below, inspect loaded scenes and visually exercise the minimum layout/pause cases. Record evidence and remaining issues, then update Architecture and roadmap checkboxes only for completed work. Leave manual acceptance open if not performed.

## 9. Required checks and acceptance scenarios

| Case | Assertions / expected behavior |
| --- | --- |
| Ready and layout | Multiple layout frames/resizes do not start Snake or show questions; Enter before readiness does nothing; fresh Enter after readiness starts exactly one attempt |
| Active-time arithmetic | With duration 10 s: start at wall 1000 ms, pause at 3000, resume at 63000, sample at 64000 → elapsed 3000 ms, remaining 7000 ms |
| Repeat pause | Two separate pause spans are both excluded; direct start while paused is rejected; counters and body unchanged |
| Turn buffer | Queue a perpendicular turn, pause/resume, then step: committed direction continues. New fresh direction after resume is accepted; partial movement accumulator is preserved |
| Frozen gameplay | While paused, force process/physics callbacks and send movement/1–3/Space/Enter; body, food, attempts, question state and response metrics do not change |
| Open question | Open at elapsed 1000 with a 2000 ms window; pause at 1500 for 60 wall seconds; resume and answer at active 2000: one answer, latency 1.0 s, original deadline 3000 |
| Scheduled question/feedback | Pause before a scheduled open and during feedback; both retain their remaining active time; resume does not produce multiple overdue callbacks |
| Retry waiting | Collision→pause→resume remains waiting; fresh Space restarts only Snake. The open question and session deadline are retained |
| Deadline precedence | Escape, Space or Enter at exact expiry cause CLOSING without a gameplay action. Movement while PLAYING and answer with an open enabled question also sample expiry and cause CLOSING. Otherwise-ineligible movement/answer input may return without sampling; the session process tick owns cutoff in that case. No action may mutate gameplay at/after cutoff; Enter that detects expiry does not skip closing |
| Closing and cancellation | One open question cancels once; totals freeze immediately; 1999 ms closing stays CLOSING, 2000 ms enters FINISHED. Fresh Enter skips only to FINISHED |
| Clean restart | Fresh Enter from FINISHED resets all current fields, question scheduling and pause/closing spans; repeated input/layout events do not reconnect or reset twice |
| Bad configuration | Invalid settings do not start a partial session; correcting settings allows one clean start |
| Layout | At 1024 × 768 and one larger size, board/question/slots are readable and non-overlapping; question open/feedback/paused states preserve the board rectangle |

New runner success marker: `ITER02_STAGE01_LIFETIME_PASS`; failure prints the failed case and exits nonzero. Follow the existing project runner convention and validate its failure reporting once. Headless geometry checks do not replace visual inspection.

Resolve `$godotExe` from the project's actual installed Godot configuration before execution; do not guess a binary path. From repository root, intended focused commands are:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_timed_session.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_quick_messages.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_snake_collisions.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_snake_movement.gd
```

Require exit code 0, explicit PASS and no unexpected parser/runtime diagnostics. Negative configuration cases intentionally exercise existing validation errors. Also load touched scripts and scenes through the installed engine's supported validation workflow.

Manual scenario: start using Enter; steer and answer; pause with a question; wait and resize; press ignored controls; resume and answer; collide, pause while waiting, resume and retry; finish a shortened test session, skip closing, restart. Check normal 360-second default remains configured. A full paired six-minute balance playtest belongs to Stage 7, not this shell stage.
