# OI-108: Validate day planning, fatigue and recovery

- **Type:** Validation
- **Status:** Open
- **Area:** Day cycle
- **Issue:** Decide initial values (8/8 is only an example), repeatability, activity prices, preparation duration, promotion returns, recovery, arcade fatigue penalties and question-time modifiers. Test variety without mandatory rest or skipped streams, dominant routines or ignoring penalties; check training cost and both styles. With iteration 03's 8/8 start, two lifetime training sessions and current sleep values, the lowest natural launch values are vigor 6 and concentration 3. Use fixtures for the lower tiers and revisit whether daytime recovery offers a meaningful choice after the full-day playtest. Consider an unused-AP reminder and normal-price quick rest before starting. In the Stage 6 playtest, confirm hardware keyboard navigation and held Enter when leaving preparation.
- **Return trigger:** When prototyping daily preparation and condition.
- **Current evidence:** Stage 6 verified both evening routes over multiple days. At 30 viewers the 6/6, 3/3 and 2/2 fixtures produced the expected two, one and zero warning cells and 6000, 5400 and 5000 ms answer windows. Unassisted player choices and the value of daytime recovery remain pending. [Stage 6 verification](../../Technical/Iteration03/Stage06FullDayPlaytest.md#current-verification-and-acceptance)
- **Close when:** Play a multi-day prototype, record tradeoffs and agree on values and preparation UI behavior.
- **Sources:** [ActionPointsAndCondition](../../GameDesign/Mechanics/ActionPointsAndCondition.md), [CoreGameplayLoop](../../GameDesign/Mechanics/CoreGameplayLoop.md), [ConceptDesign](../../GameDesign/ConceptDesign.md).
