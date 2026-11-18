# OI-106: Define stream endings, pause and resume

- **Type:** Question
- **Status:** Open
- **Area:** Stream lifecycle
- **Issue:** Test 6–10 minute short sessions and the proposed setup/main/farewell rhythm. Decide whether to allow bounded overtime at a per-arcade round boundary, how active choices resolve, how early exits affect load and practice, and how pause, save and resume work across a day and inside streams. The [corrected prototype preset](../../Technical/Iteration01And02Corrections.md) ends at 180 active seconds. Iteration 03 adds pre-stream skip, full-stream settlement and in-memory morning rollover. Overtime, mid-stream exit accounting and disk save/resume remain full-game questions.
- **Return trigger:** When extending stream or day lifecycle beyond iteration 2.
- **Close when:** Document finish boundaries, overtime cap if approved, active choice handling, early-exit accounting and save/resume policy.
- **Sources:** [CoreGameplayLoop](../../GameDesign/Mechanics/CoreGameplayLoop.md), [Minigames](../../GameDesign/Mechanics/Minigames.md), [StreamingGameplay](../../GameDesign/Mechanics/StreamingGameplay.md), [ActionPointsAndCondition](../../GameDesign/Mechanics/ActionPointsAndCondition.md), [SkillsAndTraining](../../GameDesign/Mechanics/SkillsAndTraining.md), [Iteration02Scope](../../GameDesign/Iteration02Scope.md).
