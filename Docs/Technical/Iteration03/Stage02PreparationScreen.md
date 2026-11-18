# Stage 2 — Unified preparation screen

**Status:** Implemented and technically verified on 2026-11-18. The room uses the [Stage 1 day model](Stage01DayModel.md).  
**Goal:** From the first frame of a new day, the player can see the heroine’s condition, weigh five activities, spend AP and choose whether to stream. Reviewing the morning and planning the day happen in the same room, at the player's pace.

**Sources:** [Iteration scope](../../GameDesign/Iteration03Scope.md), [implementation roadmap](../Iteration03ImplementationPlan.md), [current architecture](../Architecture.md). Use the existing Godot 4.7 Standard project, native Controls, typed GDScript and Russian player-facing text.

## 1. Compose the day scene

| Path under `GirlStreamer/` | Responsibility |
| --- | --- |
| `prototype/day/day_cycle.tscn`, `day_cycle.gd` | Own one DayState for the run, the preparation view and a host for one stream instance. Route player requests, manage input ownership and recover from launch failures. |
| `prototype/day/preparation_screen.tscn`, `preparation_screen.gd` | Lay out the room, render model snapshots and activity previews, and emit activity/start/skip requests. Own focus, Russian labels and heroine feedback. |
| `prototype/day/stream_forecast.gd` | Shared forecast values and pure calculations for danger range, question timing, announcement and prepared topic. |
| `project.godot` | Set the normal startup scene to the day cycle after the room and evening routes work. |
| `tests/iteration03/test_preparation_screen.gd` | Exercise the real preparation scene and model, including startup, refresh, navigation and recoverable launch failures. |

- [x] Instantiate the preparation view on entry and render the first snapshot immediately. Apply the existing minimum window size at day startup: today the stream sets it in its own ready callback, which will run later. Keep existing stretch settings.
- [x] Keep stream instantiation on the launch path. Directly running [prototype_session.tscn](../../../GirlStreamer/prototype/prototype_session.tscn) must still provide its existing READY screen and controls.

## 2. Arrange the room around the player's decisions

The first playable pass uses the following layout.

| Region | Visible content and behavior |
| --- | --- |
| Day header | Day number, coin balance and remaining AP, for example «День 1», «Монеты: 0», «ОД: 6 из 6». |
| State and tonight’s conditions | Vigor and concentration as numbers out of 10, general arcade mastery progress toward the first threshold or its unlocked level. Name the relevant consequences in Russian: Snake warning range, normal or shortened question window, post and topic status. |
| Activity list | Five stable rows. Each has an action button, price and actual projected changes. Keep the order stable when an activity becomes unavailable and show its reason beside the button. |
| Heroine feedback | One short line following a successful activity, for example «Про рекорд точно спросят. Я готова!». Replace the previous line in place. Reserve room for wrapped text. |
| Evening actions | «Начать стрим» and «Пропустить стрим». Keep both visible when AP reaches zero. Remaining AP is visible when the player decides to finish early. |

- [x] Use a full-rect Control with margins and containers. Give the activities the main column and state/forecast the adjacent column. Keep the evening actions outside any scrolling list. At the minimum size allow text to wrap and activity rows to scroll vertically if necessary.
- [x] Support mouse and keyboard. Tab and Shift+Tab traverse available actions in reading order, activation uses the focused button, and the focus indicator remains visible. After refresh, keep focus on the same action if available, otherwise move to the next available activity or the start button. Reasons remain readable without hovering over a disabled control.

## 3. Bind actions to Stage 1

- [x] Connect the view's `activity_requested(id: StringName)`, `stream_requested()` and `skip_requested()` once in the day controller. On initial display and after each request, obtain `get_snapshot()` and `preview_activity(id)` for all five IDs. Derive displayed changes by comparing current and projected values. Keep eligibility, costs, limits and flag changes in DayState.

| Model ID | Button | Example of player-visible feedback |
| --- | --- | --- |
| `publish_post` | «Опубликовать анонс» | A successful post marks the announcement as published. The disabled row reads «Анонс уже опубликован». |
| `prepare_topic` | «Подготовить тему» | Name «Мой рекорд в Змейке», the concentration cost and the prepared question. Show the prepared flag after use. |
| `train_snake` | «Потренироваться в Змейке» | Show AP, vigor and concentration costs plus actual mastery gain. At the threshold, show the unlocked assistance and why training is unavailable. |
| `watch_anime` | «Посмотреть аниме» | Show actual concentration gain, including +0 at 10/10, alongside the AP cost. |
| `take_nap` | «Вздремнуть» | At vigor 9/10, preview «Бодрость +1». On success show 10/10 and deduct the listed AP. |

- [x] Call `apply_activity(id)` once per deliberate activation. A stale or rejected request refreshes the view and shows the current model reason without playing a success response. Merely focusing, inspecting, resizing or waiting changes no state.
- [x] Show the evening forecast from current values. Below mastery level 1 there is no danger outline; after unlock show 2, 1 or 0 cells for vigor 6–10, 3–5 or 0–2. For the same concentration bands show normal timing, −10% or −20%, subject to the 5-second floor. An announcement forecasts +3 starting viewers; a prepared topic forecasts the first question. The room displays the roadmap tuning. Stages 3 and 4 will use the same definitions to apply the effects during play.

## 4. Hand off the evening decision

**Launch.** The existing [stream controller](../../../GirlStreamer/prototype/prototype_session.gd) exposes `is_layout_ready()` and `start_session() -> bool`. Positive board geometry establishes readiness. The start call can still fail on settings, content or Snake initialization.

1. Accept the request only while preparing. Set a transition guard immediately, disable room actions and consume the initiating input. Defer child creation until that input dispatch finishes.
2. Mount one candidate session with a full-size layout. Keep the room covering it and block input on the session and child input owners during setup, including the READY-state Enter shortcut. Ensure the candidate HUD can still measure the board while the room covers it. Give its deferred layout a chance to produce a positive board rectangle. Check readiness for up to 12 process frames. Dispose of the candidate on timeout or invalid scene. Removing the day scene also removes its stream host and candidate.
3. Once ready, call `preview_launch()` under the guard, then start the candidate with those values. Keep the zero-argument `start_session()` entry for standalone play. In the same callback, call `begin_stream()` only after successful startup. Reveal the stream and enable input only after both operations succeed. Discard any failed candidate and its snapshot before retry.
4. On success release preparation focus, hide the room and transfer input to the running stream. This single button press starts the evening. Gate the managed FINISHED restart action so one day cannot launch a second stream. Keep closing-skip and standalone restart intact. If either startup or day commit fails, dispose of the candidate, show the current authoritative day state, and, if still preparing, restore focus and offer retry with «Не удалось начать стрим. Попробовать ещё раз».

**Skip.** Call `skip_stream()` once. On success lock activities, create no stream and show a brief «Сегодня без эфира» state. Stage 5 expands this state into the day summary and next morning. In Stage 2 neither evening route awards coins, applies sleep nor creates another day.

## 5. Acceptance checks for implementation

| Check | Expected evidence |
| --- | --- |
| Fresh launch and idle | Room opens directly at day 1, 0 coins, 6 AP, 8/8 condition and 0/4 mastery. All five activities are reachable. Waiting and moving focus leave the snapshot unchanged. |
| Refresh after spending | Two trainings → post → topic leaves 0 AP, vigor 6, concentration 3, unlocked mastery and both flags. Forecast shows two-cell assistance and a shortened question window. All activities explain their unavailability. Both evening actions remain usable. |
| Capped rest and rejected input | At full concentration, anime displays +0, costs 1 AP and gives one response. A repeated post request changes neither AP nor flags. Rapid refresh preserves usable focus. |
| Start and skip | On separate fresh instances, exercise both routes with 6 AP and with 0 AP. Double activation or Start immediately followed by Skip commits one decision. Start produces one running stream; skip produces none. Held Enter cannot restart or skip the new scene. |
| Failed setup and retry | Exercise missing layout readiness and a start rejection after valid layout. Compare the entire day snapshot before and after. Verify one readable error, restored controls and no orphan session. A corrected retry starts once. |
| Standalone compatibility | Launch the stream scene directly. Check READY → start, pause/resume, closing skip and restart. In a day-managed stream, finish remains terminal until the Stage 5 handoff. |
| Rendered room | At **1024 × 768** and **1280 × 900**, inspect initial state, longest row reason, full mastery, zero AP and launch failure. Read all costs, status text and buttons; activate by mouse and physical keyboard, scroll with focus where needed, and resize without losing the current day. |

- [x] During implementation, run the new runner from the repository root with `& $godotExe --headless --path GirlStreamer --script res://tests/iteration03/test_preparation_screen.gd`. Require exit code 0 and an explicit pass marker. Rerun the Stage 1 day-model runner and relevant existing stream lifetime/integration runners when changing input or startup routing.
- [x] Record the two rendered-window checks separately from automated results. Update [Architecture.md](../Architecture.md) with the actual startup scene, owners and checks once implemented. Stage 2 is ready for acceptance when the player can predict a preparation action, see its effect immediately and make either evening decision from the same room.

## Verification status

The Godot 4.7.2 headless runner returned exit code 0 and `STAGE02_PREPARATION_SCREEN_PASS checks=9`. It covers both evening routes at 6 and 0 AP, rejection and retry, guarded input, and the managed and standalone finish behavior. The day model, stream lifetime and stream integration runners also passed.

| Rendered size | Observed result |
| --- | --- |
| 1024 × 768 | All activity details, wrapped mastery reason, forecast and evening controls remained readable at 0 AP. The launch error and capped anime +0 were visible. |
| 1280 × 900 | All initial previews and capped recovery were visible. Resizing from 1024 × 768 preserved 0 AP, mastery and preparation flags. The longest reason and the prepared first question wrapped without clipping. |

Native Windows mouse and key events exercised activities, Tab and Shift+Tab navigation, Enter activation, failed launch, skip and managed and standalone stream controls. The headless runner covered repeated Enter events. Hardware key checks, including held Enter, and player acceptance remain part of the [Stage 6 playtest](Stage06FullDayPlaytest.md) and [day preparation validation](../../OpenItems/Items/OI-108-ConditionAndDailyBalance.md).
