# Stage 1 — Day model implementation plan

**Status:** Implemented and technically verified on 2026-11-18.

**Goal:** Give the preparation screen one authoritative answer to three questions. What can the player do now? What will it cost and change? Which conditions will carry into tonight's stream?

**Specification:** [Iteration 03 scope](../../GameDesign/Iteration03Scope.md), [stage roadmap](../Iteration03ImplementationPlan.md), [action points and condition](../../GameDesign/Mechanics/ActionPointsAndCondition.md), [mastery progression](../../GameDesign/Mechanics/SkillsAndTraining.md). The iteration scope selects the five activities and the first mastery threshold. Numeric defaults are first-pass tuning.

## Deliverable and ownership

| File | Responsibility |
| --- | --- |
| [day_state.gd](../../../GirlStreamer/prototype/day/day_state.gd) | Instance-owned Godot 4.7 GDScript `RefCounted` model. Own preparation data, activity evaluation and the decision to stream or skip. |
| [test_day_state.gd](../../../GirlStreamer/tests/iteration03/test_day_state.gd) | Deterministic `SceneTree` runner. Construct model instances directly and check results without loading a scene. Follow the [existing runner pattern](../../../GirlStreamer/tests/iteration01/test_snake_movement.gd). |
| [Architecture.md](../Architecture.md) | Lists the model and runner for Stage 2. |

The model has no clock, random input or dependency on UI, Snake or stream nodes. One preparation phase covers the whole morning and day. Stage 2 supplies the room and owns navigation. Stages 3–4 interpret the launch data. Stage 5 owns settlement, sleep and next-day integration.

## 1. Establish the state and read contract

- [x] Start a fresh model in `PREPARING` with day 1, 0 coins, 6 AP, vigor 8, concentration 8, mastery progress 0, and both daily flags clear. Keep mutable fields on each instance. Derive mastery level 1 at progress 4 and level 0 below it.
- [x] Expose `get_snapshot() -> DaySnapshot`. Include phase, day number, coins, AP, vigor, concentration, mastery progress and level, post published and topic prepared. Return a detached value on each read. Keeping an old snapshot must preserve its original values.
- [x] Add a runner check for these defaults, two independent instances, and mutation of a returned snapshot. Compare snapshot fields by value. The model and the second instance must retain their own values.

## 2. Implement the five activities

Use stable activity IDs. Stage 2 maps these IDs and the `RejectionReason` enum to Russian UI labels. `ActivityResult` exposes `activity_id`, `ap_cost`, `available`, `rejection_reason` and `resulting_snapshot`. Unknown IDs report a cost of zero.

| Activity ID | AP | Vigor | Concentration | Other change and availability |
| --- | ---: | ---: | ---: | --- |
| `publish_post` | 1 | 0 | 0 | Set post published. Once per day. |
| `prepare_topic` | 1 | 0 | −1 | Set topic prepared. Once per day. |
| `train_snake` | 2 | −1 | −2 | Add 2 mastery progress up to 4. Available while below 4. |
| `watch_anime` | 1 | 0 | +2 | Repeatable, including at full concentration. |
| `take_nap` | 1 | +2 | 0 | Repeatable, including at full vigor. |

- [x] Define `preview_activity(id: StringName) -> ActivityResult`. Include the activity ID, listed AP cost for known activities, availability/rejection reason and a detached resulting day snapshot. For an available action, the snapshot shows the actual result after clamping each condition to 0–10. For a rejected action it shows current values. Reading a preview has no side effects.
- [x] Define `apply_activity(id: StringName) -> ActivityResult` using the same evaluator on the **current** state. Commit cost, condition, progress and flags together only when eligible. A previously displayed preview cannot authorize spending. Return detached data for the UI to inspect.
- [x] The evaluation order is `PREPARATION_CLOSED`, `UNKNOWN_ACTIVITY`, `ALREADY_USED`, `MASTERY_CAP`, `INSUFFICIENT_AP`. Eligible activities return `NONE`. Zero vigor or concentration is a legal starting value for any otherwise affordable activity. Rest costs its listed AP even when its displayed recovery is zero.
- [x] Cover all five actions with a preview followed by a commit. Check field equality between the predicted and committed result and verify the stored state independently. Use the boundary cases below for rejections and clamping.

## 3. Close preparation exactly once

| Request in `PREPARING` | Result | Data owned by the model |
| --- | --- | --- |
| `begin_stream() -> bool` | Commit PREPARING → STREAMING once after successful candidate startup. Return true on success. | Preserve balances and progress. Stream start costs 0 AP. |
| `skip_stream() -> bool` | Switch to `SKIPPED` and return true. | Preserve the prepared state for the skipped-day summary. Skip costs 0 AP. |

- [x] Expose `preview_launch() -> LaunchSnapshot` while PREPARING. It copies day number, vigor, concentration, mastery level and both flags without changing phase. It returns null outside preparation. Test repeated previews, mutation of a returned copy and day edits after preview. Accept either evening decision at any AP balance, including zero. Outside preparation reject another launch with false and another skip with false. Reject further activities. Check launch → launch, launch → skip, skip → skip and skip → launch.
Stage 2 should initialize its stream scene and confirm readiness before calling `begin_stream()`. Preparation stays usable when scene setup fails. Input retries inside a running stream reuse the original launch conditions.

For the [Stage 5 handoff](Stage05DayResultsAndNextMorning.md), a completed stream will move from `STREAMING` to results once, using frozen donations and the stream load. A skipped evening will enter results from `SKIPPED` with zero income and load. Continuing from results will apply sleep, increment the day, issue 6 AP, clear daily flags and return to `PREPARING`. Stage 1 stops at the two evening decisions.

## 4. Verify the model

The runner covers eight groups. A test-local fixture seeds valid condition boundaries that the initial day cannot reach.

| Case | Expected observation |
| --- | --- |
| Train → train → post → topic from a fresh day | After training twice: 2 AP, vigor 6, concentration 4, progress 4, level 1. Final state: 0 AP, vigor 6, concentration 3, both flags set, day 1 and coins 0. Launch carries those conditions. Repeat on a fresh instance and choose skip at 0 AP. |
| Duplicate or unknown action | Repeat post or topic while AP remains, attempt a third training with 2 AP available, or supply an unknown ID. Each yields its reason and exactly the prior state. |
| Preview becomes stale | At 2 AP and level 0 preview training, spend 1 AP on a different activity, then try training. The commit reports insufficient AP and preserves the latest state. |
| Condition boundaries | At vigor 9 a nap gains 1 for 1 AP. At 10 it gains 0 for 1 AP. At concentration 0 anime gains 2. From condition 0/0, affordable training still grants progress and leaves both condition values at 0. |
| Early evening | Start or skip on separate untouched models at 6 AP. Day, coins and condition stay unchanged at the transition. Repeated or conflicting evening commands have no effects. |
| Snapshot isolation | Edit the returned preview, committed result and launch snapshot in turn. Read back the model state after each edit. An earlier day snapshot also retains its values across later actions. |

From the repository root, run the runner with the installed Godot 4.7 executable:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration03/test_day_state.gd
```

Godot 4.7.2 headless verification returned exit code 0 and `STAGE01_DAY_MODEL_PASS checks=8`. Balance and player comprehension remain subjects for [day-cycle playtesting](../../OpenItems/Items/OI-108-ConditionAndDailyBalance.md).
