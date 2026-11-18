# Stage 5 — Day results and the next morning

**Status:** Implemented and technically verified on 2026-11-18. **Goal:** After a stream or a skipped evening, the player can explain the wallet balance and the heroine’s condition, then enter the next day's preparation room with one action.

**Dependencies:** [Iteration scope](../../GameDesign/Iteration03Scope.md), [Stage 1 day model](Stage01DayModel.md), [Stage 2 evening routes](Stage02PreparationScreen.md), [Stage 3 condition snapshot](Stage03MasteryAndConcentration.md), [Stage 4 audience baseline and topic](Stage04PostAndPreparedTopic.md). The working preset follows the [condition rules](../../GameDesign/Mechanics/ActionPointsAndCondition.md). Progress lasts for the current game run.

## 1. Add settlement to the day model

The [day model](../../../GirlStreamer/prototype/day/day_state.gd) stores the settlement and morning preview. The model owns wallet, condition and phase transitions. The day controller owns the stream child and its frozen results. Keep these responsibilities separate so opening or scrolling a summary can never award money or change condition.

| From → to | Command on the model (proposed API) | Accepted effect |
| --- | --- | --- |
| STREAMING → RESULTS | `settle_stream(day: int, donation_total: int) -> DayResult` | Add the frozen nonnegative donation total to coins. Apply −3 vigor and −2 concentration to the state at launch. |
| SKIPPED → RESULTS | `settle_skip(day: int) -> DayResult` | Record zero income and zero stream load. Keep the effects of activities already performed. |
| RESULTS → PREPARING | `advance_morning(completed_day: int) -> DaySnapshot` | Apply sleep to settled condition, increment the day, set AP to 6, clear daily flags and return the new preparation snapshot. |

- [x] Validate the source phase, expected day and income before mutation. Apply each transition atomically. Return null for a stale day, wrong phase, repeated command or negative income, preserving all fields. A completed stream with zero donations still applies its full load.
- [x] Store a detached evening result with day number, outcome, balance before, income, balance after, and vigor/concentration before and after stream load. For skipped evenings the “before” value is the state when the player chose skip. Supply a read-only-by-contract snapshot for redisplay; mutations to a caller's copy cannot change the model.
- [x] Clamp each condition value to 0–10 **after load**, then clamp again **after sleep**. Display the actual changes. Both branches receive +3 vigor and +3 concentration on continuing. Unspent AP expires. Mastery progress, unlocked level, wallet and restored condition carry forward. Clear post/topic flags even if preparation was followed by a skip.

**Reference fixture.** Start day 1 at 8/8 and 0 coins. Train twice, publish the announcement and prepare the topic. Both branches now have 0 AP, vigor 6, concentration 3 and mastery level 1.

| End of day 1 | Wallet in results | Evening condition | Day 2 in the room |
| --- | --- | --- | --- |
| Full stream, 12 coins donated | 0 → 12 | 6/3 → 3/1 | 12 coins, 6/4 condition, 6 AP, mastery 1, both daily flags clear |
| Skip | 0 → 0 | 6/3 → 6/3 | 0 coins, 9/6 condition, 6 AP, mastery 1, both daily flags clear |

Also test 1/1 before a full stream: evening 0/0, morning 3/3. From 9/10 before a skip, morning is 10/10, an actual gain of 1/0. These fixtures expose an incorrect combined load-and-sleep calculation.

## 2. Deliver one terminal outcome to the controller

- [x] Preserve the ordering in [prototype_session.gd](../../../GirlStreamer/prototype/prototype_session.gd). At the 180-active-second cutoff, the session stops donation sampling, accounts for the final audience step, cancels the open choice, and freezes [StreamResults](../../../GirlStreamer/prototype/stream/stream_results.gd). The goodbye interval then finishes naturally or through Enter. Both paths already reach `_complete_closing()`.
- [x] Add a managed completion signal carrying the frozen result at the CLOSING → FINISHED transition. Connect the day controller before starting the child, binding the launching day number and session instance. Handle only a signal from the active child for that day. Pay the model from `StreamResults.donation_total` once. A receipt, replayed signal, final HUD draw, question cancellation or Snake retry cannot credit the wallet.
- [x] For a room skip, accept `skip_stream()` first, then settle from SKIPPED in the same controller action. Skip never creates a stream child or a synthetic StreamResults. A failed launch keeps the room usable under the Stage 2 contract. Enter during the stream's goodbye shortens only the presentation of a fully completed stream.
- [x] Keep the current frozen stream result available while the day summary is visible. Downstream views only read it. A completed session with missing results is an integration error: reject settlement and keep the day available for diagnosis instead of silently recording a skipped evening or a zero payout.

## 3. Present the evening and the morning decision

The day controller owns a results view with a common settlement header and a scrollable stream report for played evenings. The continue button stays outside the report.

| Region | Completed stream | Skipped evening |
| --- | --- | --- |
| Outcome | «Итоги дня 1 · Эфир завершён» | «Итоги дня 1 · Сегодня без эфира» |
| Wallet | «Донаты за эфир: +12» and «Баланс: 0 → 12» | «Доход за вечер: 0» and the current balance |
| Evening condition | Show actual changes, e.g. «Бодрость: 6 → 3», «Концентрация: 3 → 1» | Show current values and «Нагрузка от эфира: 0» |
| Stream detail | Retain existing Snake, audience, interaction, donation and highlight rows using the frozen result, including the actual opening audience from Stage 4 | Omit stream-only rows |
| Next action | «К следующему утру» with a sleep preview, e.g. «После сна: бодрость 6, концентрация 4» | Same control, with the skip branch's projected values |

- [x] Create the day-results Control and presenter under `prototype/day/`. Reuse the existing [stream HUD](../../../GirlStreamer/prototype/ui/prototype_hud.gd) result formatting, extracting its row builder for both views if needed. Standalone stream results keep their restart prompt. Managed sessions present the day view once and offer one continue action.
- [x] Show the actual capped recovery and projected morning values on both routes. Compute the sleep preview with the same pure clamped recovery calculation as the morning transition. Rendering, scrolling, resizing and time spent reading have no model side effects. Show the income before the new wallet balance so a returning player can reconcile both.

## 4. Return directly to preparation

- [x] Route the continue button and a fresh Enter press to one controller handler. Consume the event that skipped the goodbye or activated the room skip. A held key, key echo, double click or simultaneous GUI and session callbacks must not pass through to the next screen.
- [x] On the first valid continue, call `advance_morning` with the day shown. Disconnect the completed child, release its input and audio, then remove it; ignore late signals by source and day. Retain the same DayState instance. Refresh the Stage 2 room from its new snapshot, rebuild previews, clear yesterday's feedback and restore focus to an available room action.
- [x] Verify the second stream starts from fresh stream-local counters, donation totals, choices and audience. Without another announcement the opening audience is 30. Without preparing the topic again the director uses its ordinary first-opening rules. Keep the run's mute preference on the day controller. Capture the outgoing child's latest setting before disposal and apply it to the next child's audio controller and HUD before playback. Check mute across day 1 stream → skipped day → day 3 stream, then verify standalone restart separately.

## 5. Acceptance checks for implementation

| Check and owner | Expected evidence |
| --- | --- |
| Model arithmetic — extend `tests/iteration03/test_day_state.gd` | Verify both reference branches, zero-donation completion, pre-existing wallet balance, low and capped condition, and unused AP. Invalid or repeated settlement/continue commands make no changes. |
| Managed completion — add `tests/iteration03/test_day_cycle.gd` | With a controlled clock, finish normally and by shortening goodbye. Include multiple donation receipts and an active question at cutoff. Compare frozen totals to the day result, confirm cancellation counted once, and verify exactly one wallet credit and one stream load. |
| Skip and input | Skip an untouched day with 6 AP and a prepared day with 0 AP. Neither creates a child. The evening screen remains readable until a distinct continue action. Repeated inputs cannot trigger another night's recovery or an activity in the new room. |
| Sequential days | Starting from the 12-coin fixture, skip day 2 without activities. Day 3 must show 12 coins, 9/7 condition, 6 AP and mastery 1. Run the reverse route too: skip a prepared day, then complete an unprepared stream. Check fresh audience, topic, donation counters and one credit from day 2 only. Deliver a stale completion from day 1 and verify it has no effect. |
| Compatibility and readability | Run the existing iteration 01 timed-session and iteration 02 lifetime/integration suites. In a rendered window at 1024 × 768 and 1280 × 900, check scrolling long stream details, the compact skip summary, visible continue button, keyboard/mouse focus, and standalone Enter restart. |

- [x] From the repository root, run `& $godotExe --headless --path GirlStreamer --script res://tests/iteration03/test_day_cycle.gd` and the affected runners above. Require a pass marker, zero exit code and no unexpected errors. Record human checks separately.
- [x] After implementation, update the [architecture map](../Architecture.md) and the [day-summary validation item](../../OpenItems/Items/OI-116-ExpandedResults.md) with actual evidence. Stage 5 is ready for acceptance when a player can reconcile evening and morning values on both routes and play another day in the same run.

## Verification status

- Godot 4.7.2 passed 13 day model checks and 5 day-cycle groups. The preparation, condition, timed session, lifetime, integration, feedback, choices and donation runners also passed. Intentional invalid fixtures emitted validation diagnostics. Existing stream runners emitted nonblocking ObjectDB warnings during exit.
- The prepared 12-coin fixture finished at condition 3/1, then opened day 2 at 6/4 with 6 AP. Skipping day 2 led to day 3 with 12 coins, condition 9/7 and mastery 1. The reverse route opened the next stream with 30 viewers and no prepared question. Mute carried through a skipped day.
- At 1024 × 768 and 1280 × 900, controlled rendered checks verified the streamed and skipped summaries, scrolling while keeping continue visible, mouse and keyboard transitions, focus in the room and standalone Enter restart. The control fixtures also covered held Enter and the second click across a screen change.
- The user accepted the manual checks in [Stage 6](Stage06FullDayPlaytest.md). Further summary extensions are tracked in [OI-116](../../OpenItems/Items/OI-116-ExpandedResults.md).
