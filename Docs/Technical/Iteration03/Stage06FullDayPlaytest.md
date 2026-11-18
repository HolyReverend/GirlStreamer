# Stage 6 — Full-day playtest and iteration acceptance

**Status:** Accepted on 2026-11-18 after technical verification and the user's manual checklist.  
**Question:** Can the player make a deliberate choice in the room, recognize its consequence while streaming, and use the evening results to decide what to do tomorrow?

**Contract:** [Iteration 03 scope](../../GameDesign/Iteration03Scope.md) and [implementation roadmap](../Iteration03ImplementationPlan.md). Use the [corrected stream preset](../Iteration01And02Corrections.md): 180 active seconds, first scheduled opening at 20 active seconds, at least 20 seconds between successful openings, up to eight openings. Preparation, pause, goodbye and results are outside the active clock.

## 1. Select the candidate and establish the technical baseline

- [x] Identify the build by revision and relevant local changes. Record Godot version, language, window size, input, audio state, tuning, and available Snake/chat/donation seed settings. State which randomness the build can reproduce. Fix the exposed seed settings for the scripted pair. For a time-seeded subsystem without an override, record that limitation and use its deterministic runner for exact comparisons. Use the same preset and a fresh day 1 for each arm. Keep the same participant, window size and play instructions across that pair.
- [x] Start through the normal game entry point into the preparation room. Verify that both evening routes return to a playable morning on this candidate. If a route fails, record the exact transition and stop that scenario. Independent readability or model checks can still be completed.
- [x] Run the Stage 1–5 focused checks and the affected prior suites using the installed Godot executable. From the project root, for example: `& $godotExe --headless --path GirlStreamer --script res://tests/iteration03/test_day_cycle.gd`. Record each runner name, exit status, expected pass marker and unexpected diagnostics.

| Area | Planned or existing runners under `GirlStreamer/tests/` |
| --- | --- |
| Day rules, room, effects, settlement | `iteration03/test_day_state.gd`, `test_preparation_screen.gd`, `test_stream_condition.gd`, `test_day_cycle.gd` in the same directory |
| Snake, clock and retry | Iteration 01 movement, food, collisions and timed-session runners |
| Stream regressions | Iteration 02 lifetime, choices, director, feedback, audience, donations and integration runners, including the Stage 4 extensions |

## 2. Observe a full day without coaching

Run this first, before showing expected numbers or prescribing activities. Prefer a player who has not seen the day plans. Record their familiarity with Snake and prior iterations; if the designer alone plays, identify which discoverability observations still need a fresh player. Allow as much time as needed in the room.

1. Give one task in Russian: «Проведи день стримерши так, как тебе хочется. Когда наступит следующее утро, реши, чем займёшься дальше». Let the player choose activities, finish early, go live or skip. Avoid pointing at a control or explaining an effect. If help is needed, record the obstacle and the help given.
2. Before the evening decision, ask «Чего ты ожидаешь от этого вечера?» Record the prediction in the player's words. Observe whether they use prices, capped gains and tonight's forecast while choosing. During the stream let them steer and answer without interview interruptions.
3. In results ask «Что сегодня изменилось и почему?» At the next morning ask «Что ты выберешь сегодня и почему?» Record which on-screen event or value the player cites, one concrete tradeoff, and whether they act on it. A decision to repeat a routine is informative when the player can explain the alternatives.
4. If the player skipped, keep that observation and cover the streamed evening in the comparison below. For whichever evening route they have yet to see, ask the same results and next-morning questions before explaining the expected values. Record whether the player can reconcile both outcomes. Record what they discovered unaided separately from what they recognized after a scripted run.

## 3. Compare preparation under controlled conditions

Play both streams for the full 180 active seconds. The pair tests whether the combined preparation effects are visible; use the individual stage checks to isolate a cause. Record actual run order, audience at opening, collisions and chosen answers. Even equal seeds can produce different donation totals when player inputs and audiences differ.

| Checkpoint | A — start immediately | B — train twice, publish post, prepare topic |
| --- | --- | --- |
| Room before launch | 6 AP; vigor/concentration 8/8; mastery 0; neither flag | 0 AP; 6/3; mastery 1; both flags |
| First stream frame | 30 viewers; no promotion credit | 33 viewers, 11 per group; +3 attributed to post |
| During Snake | Baseline play without warning | Two-move danger warning. Approach a wall, turn away, then deliberately lose before the first scheduled opening. Remain waiting for retry through that opening. |
| First interactive choice | Usual director selection and eligibility | Prepared topic opens once at the first eligible scheduled time even while waiting for retry. One reply has the rehearsal hint; all three are available. Retry and check for duplicates. |
| Question timing | Ordinary viewer-dependent window | At concentration 3, ordinary, donor and prepared questions use 90% of the sampled base, with a 5-second floor. Compare at matched viewer counts using the timing fixture. Reactions retain their 3-second window. |
| Results → next morning | 5/6 after stream → 8/9 after sleep | 3/1 after stream → 6/4 after sleep |

For each arm, sum the prior wallet and the **actual frozen donation total**. Match this to the resulting wallet. Check 6 fresh AP, retained mastery and clear post/topic flags the next morning. In B, first ask «Что ты заметил в начале эфира?» and record the unprompted answer. If needed, ask specifically about the opening audience and question. Mark those answers as prompted.

## 4. Cover recovery, fatigue and repeat play

- [x] **Skip, then stream.** From fresh day 1 repeat B's preparation but skip at 0 AP. Evening condition is 6/3 with zero income and zero load. Day 2 opens directly in the room at 9/6 with mastery 1, 6 AP and zero coins. Launch unprepared and check 30 opening viewers and ordinary first-choice rules. Complete the stream and reconcile the day 3 wallet with day 2 donations only.
- [x] **Stream, then skip.** Continue arm B from its morning at 6/4. Skip day 2 without spending AP. Expect day 3 at 9/7, 6 AP, mastery 1 and the same wallet. Repeated continue input, including Enter used to shorten goodbye, must advance only one transition per deliberate press.
- [x] **Rested versus strongly fatigued.** Use the [condition fixtures](Stage03MasteryAndConcentration.md) with mastery 1, identical board/direction and 30 viewers. Compare vigor/concentration 6/6 against 2/2: two-cell versus absent warning and 6000 versus 5000 ms for an ordinary question. Inspect the middle band separately (one cell and 5400 ms at 3/3). Check that retry keeps the captured condition and pause preserves the remaining answer time. The minimum attainable launch vigor in this preset is 6: two lifetime trainings cost 1 each, and sleep offsets the full stream's vigor load. The minimum launch concentration is 3 after two trainings and a topic. On later days sleep offsets one topic and the stream load. Verify the remaining tiers in fixtures and record the balance limitation: ordinary play cannot demonstrate a nap changing warning range or the strongest question penalty. Revisit tuning after observing actual day choices.
- [x] **Window, input and sound.** Inspect the populated room, topic hint under movement, long results, compact skip result and next morning at 1024 × 768 and 1280 × 900. Physically test mouse/keyboard activation, scroll, steer, 1–3, Space, Escape, Enter and M. Listen for question, donation and finish cues; verify mute persists into the next managed stream. If no donation occurs naturally, use a disclosed repeatable donation scenario to hear it. Direct-launch the stream scene separately to check standalone restart.

## 5. Record evidence and decide

Use one row per run or focused fixture. Record actual observations after execution in the local work report per [project workflow](../../../Codex/Workflow.md). Keep the current acceptance decision in the roadmap and actionable findings in their owning open items.

| Record | Minimum useful detail |
| --- | --- |
| Context | Candidate, scenario, settings/seeds, participant familiarity, observation method, window size |
| Preparation and stream | Activity order, AP and condition at launch, mastery/flags, predicted consequence, opening viewers, topic time/count, sampled question window and viewers, collision/retry, help or missed cue |
| Settlement | Route, wallet before, actual income, wallet after, condition before/load/sleep, next day number/AP/mastery/flags |
| Interpretation | Observed action, player's own explanation or difficulty, next-day choice, expected versus actual, status, smallest follow-up and retest scenario |

| Acceptance criterion | Evidence for a pass |
| --- | --- |
| Day is playable end to end | Normal entry reaches one preparation room. Spending all AP and finishing early both allow a streamed or skipped evening. Both routes lead to a playable next morning. |
| Preparation changes the stream as advertised | The paired runs and boundary fixtures agree with the forecast for audience, topic, warning distance and answer window. No duplicated topic, credit, load or recovery. |
| Results support the next decision | Both evening routes reconcile to the displayed wallet and morning condition. The player can explain what carried forward and identify a choice they would change or deliberately repeat. |
| Feedback is legible during play | The player can point to a concrete preparation consequence observed in the stream and explain its cause. Timed choices, state changes and the continue action are readable and operable in both target windows. Record any intervention that made a task possible. |
| Technical and human evidence is traceable | Affected suites pass on the identified candidate. Actual rendered, physical-input, listening and player observations are recorded with any limitations. |

Mark each criterion **Pass**, **Fail** or **NotRun**. An unobserved cue or coached explanation leaves unaided comprehension unverified. A reproducible state, accounting or lifecycle error requires a fix and a rerun of its scenario and dependent checks. For a readability or balance concern, record the moment, the player's explanation and the proposed retest. A small playtest supports a prototype decision; report individual observations without inventing a population success rate.

Present the evidence and remaining tuning decisions to the user for iteration acceptance. Keep acceptance pending while a required criterion is failed or unverified. Record any explicit user decision to defer an issue with its scope and return trigger. Reuse overlapping evidence for [audio](../../OpenItems/Items/OI-001-AudioAcceptance.md), [window/input](../../OpenItems/Items/OI-002-WindowAcceptance.md) and [stream playtesting](../../OpenItems/Items/OI-003-StreamPlaytest.md) only for the conditions actually observed. Track day-specific findings under [daily balance](../../OpenItems/Items/OI-108-ConditionAndDailyBalance.md), [mastery](../../OpenItems/Items/OI-115-SkillProgression.md) and [results](../../OpenItems/Items/OI-116-ExpandedResults.md).

## Current verification and acceptance

Candidate is the working tree with Stages 1–5 on revision `1e27c5946f1b22294c7d7933c0ccd565ab7ad071`. The normal project entry booted. All 15 runners passed on Godot 4.7.2. The full-day fixture drove six 180-active-second streams in the production day scene, three per target size. It verified both evening routes, the prepared question once at 20 active seconds while waiting for retry, wallet reconciliation and a clean next morning. Screens included initial audience, prepared reply, scrolled results, skip and next morning. The fixture confirmed that all three sound cues were requested. The user reported that the manual checklist passed and accepted iteration 03 on 2026-11-18. The manual result was reported as an overall pass, with no individual measurements or player comments supplied.

| Acceptance criterion | Status | Current evidence |
| --- | --- | --- |
| Day is playable end to end | Pass | Normal boot and both evening routes reached a playable next morning. |
| Preparation changes the stream as advertised | Pass | Controlled pair and boundary fixtures verified opening audience, topic, warning range, answer windows and single settlement. |
| Results support the next decision | Pass | Both automated routes reconciled wallet and condition. The user confirmed the manual checklist. |
| Feedback is legible during play | Pass | Both target layouts rendered and scrolled. The user confirmed the manual checklist. |
| Technical and human evidence is traceable | Pass | Technical evidence and the user's overall manual pass are recorded above. |

### Manual checklist for retests

1. Start the project normally. Play one day freely before reading the expected values or asking for hints. At the next morning, explain what changed, why it changed, and what you would do differently today.
2. Compare two fresh starts, each for a full three-minute stream. Start immediately in one. In the other, train twice, post the announcement and prepare the topic. See whether you notice the opening audience and warning. After seeing the warning, lose before the first question and wait for it before pressing Space. Answer, retry and check whether the topic returns.
3. Try a skipped evening as well. In both results views, compare the shown income, wallet and sleep preview to the next morning. Check that holding Enter or double-clicking continue advances one day and leaves the room idle.
4. Check the room, question and long results at 1024 × 768 and 1280 × 900. Try mouse, Tab, Enter and scroll, then arrows or WASD, 1–3, Space, Escape and M in the stream. Listen for the question, donation and finish sounds. Confirm M carries to the next managed stream, and Enter restarts the stand-alone stream scene.
