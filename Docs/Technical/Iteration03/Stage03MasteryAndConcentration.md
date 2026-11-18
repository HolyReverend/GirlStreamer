# Stage 3 — Snake mastery, vigor and concentration

**Status:** Implemented and technically verified on 2026-11-18. The numeric values below are the iteration's first playtest preset.

**Goal:** Let the player recognize two consequences of preparation during the same stream. Training unlocks a warning about an imminent Snake collision, and vigor determines how far ahead it reaches. Concentration determines how long the player has to answer a viewer or donor question.

**Dependencies:** [Iteration scope](../../GameDesign/Iteration03Scope.md), [Stage 1 model and launch snapshot](Stage01DayModel.md), [Stage 2 forecast and guarded launch](Stage02PreparationScreen.md), [stage roadmap](../Iteration03ImplementationPlan.md). Use the existing Godot 4.7 Standard project and typed GDScript.

## 1. Carry the room forecast into the stream

| Condition value | Warning range at mastery level 1, by vigor | Question window multiplier, by concentration |
| --- | ---: | ---: |
| 6–10 | 2 moves | 1.00 |
| 3–5 | 1 move | 0.90 |
| 0–2 | 0 moves | 0.80 |

Read each column using its own condition value. At mastery level 0 the range is always zero. Stage 1 owns training progress and the first unlock at 4 points. For example, two training sessions from the 8/8 starting state leave vigor 6 and concentration 4. The room should forecast a two-move warning and a 10% shorter question window. Anime then restores concentration to 6, removing the timing penalty while leaving the warning range at two.

- [x] Use one pure calculation in the shared forecast for warning range and one for question multiplier. Have the preparation screen and launch path consume the same results. Inputs are mastery level, vigor and concentration. Keep viewer-dependent timing in the stream director.
- [x] Under the Stage 2 transition guard, read `preview_launch()` once and use its detached values to configure [session startup](../../../GirlStreamer/prototype/prototype_session.gd) before Snake starts and before the director opens any choice. Keep the existing zero-argument start valid with defaults of zero warning range and multiplier 1.00. On successful startup finalize the day launch in the same callback. On failure discard the candidate and keep preparation available.
- [x] The session owns the captured values for the entire stream. Pausing, retrying Snake and editing a detached snapshot cannot change them. Each new stream captures fresh inputs. Verify both independent axes at the boundary values 0, 2, 3, 5, 6 and 10 and verify standalone restart after a managed session cannot inherit its settings.

## 2. Predict the first collision on the current path

**Owner:** [snake_state.gd](../../../GirlStreamer/prototype/snake/snake_state.gd). Add a read-only query such as `predict_danger(max_steps: int) -> DangerHint`. A hit reports the collision kind, move distance, last legal head position and attempted cell. Return null on a clear path, a zero range or a finished attempt.

- [x] Share the wall and retained-body collision check with `step()`. Start from the current body; use the accepted pending turn for the first projected step, then continue straight. Rejected reverse or second inputs do not change that path.
- [x] Advance a temporary body for each legal projected step. The tail vacates on ordinary movement and stays on growth. Test the second move against this **updated** body. Stop on the first collision or a completed board. At a range of two, after eating on move one, wall/body collision on move two can be determined from occupancy: any newly spawned food must be on a free cell. The query never needs to spawn food, consume RNG or call the live movement method.
- [x] In paired fixed-seed runs, query repeatedly in one run only. Feed both runs identical turns and compare body, food sequence, score, finish reason and pending-turn behavior through growth and collision. Include a legal move into the departing tail, a retained segment, a hazard exactly two moves away, a clear path and a last-food completion.

## 3. Show the warning at the moment it can help

**Owners:** [snake_game.gd](../../../GirlStreamer/prototype/snake/snake_game.gd) publishes the current hint with the board snapshot. [snake_board.gd](../../../GirlStreamer/prototype/snake/snake_board.gd) draws it using the existing board origin and cell size.

- [x] Display only the first predicted hazard within range. Proposed visual treatment: a hollow outline inside the threatened body cell; for a wall, highlight the edge of the last legal cell facing the collision. This keeps off-board predictions visible at all four boundaries. Keep the head, food and grid legible.
- [x] Refresh after an accepted buffered turn, before the next movement tick, so turning away clears a warning immediately. Refresh after the final simulated step of a physics frame and after clearing a pending turn on pause. On stop, expiry or terminal movement clear the displayed warning. Retry rebuilds it from the new body with the same stream range. Resizing uses current board geometry.
- [x] With a wall two moves straight ahead, verify the high-vigor warning appears now, the middle-tier warning appears after one move and mastery level 0 gives no warning at either distance. Turn away before impact and check the marker moves or disappears. Continuing straight must still produce the same collision on the same tick, with the same score and retry behavior.

## 4. Apply concentration when a question opens

**Owner:** [stream_director.gd](../../../GirlStreamer/prototype/stream/stream_director.gd), specifically `_sample_question_window_msec()`. For the normal preset compute the window in integer milliseconds:

```text
base_ms   = clamp(6000 - 10 × max(0, viewers_at_open - 30), 5000, 6000)
window_ms = max(5000, round(base_ms × captured_multiplier))
```

| Viewers when opened | Base | Concentration 6–10 | Concentration 3–5 | Concentration 0–2 |
| ---: | ---: | ---: | ---: | ---: |
| 30 | 6000 ms | 6000 ms | 5400 ms | 5000 ms |
| 60 | 5700 ms | 5700 ms | 5130 ms | 5000 ms |
| 130 | 5000 ms | 5000 ms | 5000 ms | 5000 ms |

- [x] Pass the captured multiplier into director startup with neutral default 1.00. Keep a non-default Inspector question window fixed, including custom values below 5000 ms. With the normal preset and no viewer provider use base 6000 ms. Reactions keep their independent 3000 ms window.
- [x] Ordinary questions and queued donor questions use the same sampler. Sample viewers when the choice actually opens, including after a delayed donor question. Store the resulting window on the opened definition once. Audience changes after opening affect subsequent questions. Stage 4 will route its prepared question through this same ordinary-question sampler.
- [x] Keep [the choice controller](../../../GirlStreamer/prototype/stream/stream_choice.gd) responsible for its active-time deadline. Verify pause freezes remaining time, an attempt retry preserves the open deadline, and expiry follows the existing exact-deadline rule. Preserve the director's opening cadence and eight-opening cap.

## 5. Verify the stage

- [x] Add a focused `GirlStreamer/tests/iteration03/test_stream_condition.gd` runner for the tier matrix, room-to-runtime parity, projected paths and session lifecycle. In `tests/iteration02/test_stream_director.gd` cover all timing-table rows, a donor queued at 30 viewers and opened at 60, and a custom 4000 ms window. Exercise a reaction at low concentration. Verify the values on admitted choices, including the deadline used to accept or expire a reply.
- [x] From the repository root run `& $godotExe --headless --path GirlStreamer --script res://tests/iteration03/test_stream_condition.gd` and repeat with the existing Snake movement, food and collision runners, director, choice and lifetime runners. Require exit code 0, the expected pass marker for each runner and no unexpected engine errors.
- [x] In the playable day path compare two trainings followed by immediate launch against two trainings plus anime. Compare windows at the same audience size. Inspect wall and body warnings at 1024 × 768 and 1280 × 900, including a queued turn, pause and retry. Use controlled fixtures for vigor 0–5 and concentration 0–2, which are unreachable at stream launch throughout this preset. Stage 6 records this balance limitation. Record rendered observations separately from automated assertions.
- [x] Accept when the room forecast matches the observed warning distance and sampled window, all boundary checks pass, and the seeded gameplay comparison agrees. Update [Architecture.md](../Architecture.md) with verified owners and tests during implementation. Player comfort and balance are evaluated in the [day-cycle playtest](../../OpenItems/Items/OI-108-ConditionAndDailyBalance.md).

## Verification status

- Godot 4.7.2 passed the condition runner (6 groups), director (79 checks), Snake movement, food and collision, preparation, choice, lifetime and stream integration runners. The seeded comparison preserved body, food, RNG state, score and terminal reason. Low-vigor and low-concentration tiers used controlled fixtures.
- The preparation scene launched both comparison runs at 30 viewers. Two trainings yielded a two-cell warning range and a 5400 ms ordinary question window. Adding anime preserved the range and restored the window to 6000 ms. The room forecasts the normal preset. Custom Inspector windows remain fixed.
- Rendered checks at 1024 × 768 and 1280 × 900 showed the wall marker inside the board and the hollow outline inside a threatened body cell. The wall marker disappeared on the queued turn, returned when pause cleared that turn, and cleared after collision and retry. Food and head remained visible in both layouts.
- Player comfort and balance remain open for the [Stage 6 playtest](Stage06FullDayPlaytest.md), including the controlled lower tiers tracked under [OI-108](../../OpenItems/Items/OI-108-ConditionAndDailyBalance.md).
