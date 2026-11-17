# Stage 5: Audience Consequences — Detailed Implementation Plan

Plan date: 2026-11-13. Implemented and headless-verified on 2026-11-16.

> **For agentic workers:** Use `stage-orchestrator` for whole-stage execution and `executing-plans` for its tasks, subject to AGENTS.md. Keep one writer for session/content/HUD integration and one owner of the editor. No automatic commits or pushes.

**Goal:** Make game results, authored answers and selected reactions produce visible, explainable changes in the three audience groups during one stream.

**Architecture:** AudienceState is a deterministic RefCounted model owning group counts, impressions, fractional population changes and style attenuation. Session owns event-to-effect routing, active-time advancement and source deduplication. HUD displays copied snapshots; the director samples current audience only when opening an ordinary question.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, native UI, engine-native assertion runners; no new framework or randomness in the audience model.

**Specification:** [Iteration roadmap](../Iteration02ImplementationPlan.md), Stage 5; [scope](../../GameDesign/Iteration02Scope.md); [audience design](../../GameDesign/Mechanics/AudienceAndDonations.md); [Stage 3 choice data](Stage03MeaningfulQuestions.md); [Stage 4 scheduling and source identity](Stage04ReactionsAndDirector.md). Read workflow/implementation rules before engine work and select specialists through `Codex/GodotSkills.md`.

## 1. Scope and dependencies

The user accepted Stages 1–4 before this stage. Their active clock, canonical event and copied resolution contracts provide the routing inputs.

Include group impressions/counts, fixed-second population changes, once-only effects, bounded causal explanations, current/peak counts, audience-dependent ordinary question time and ambient chat speed, plus deterministic scenario comparisons. This completes the previously authored effect data's first actual gameplay use.

Exclude donation generation/payment, cross-stream loyalty, permanent subscribers, subscriptions, clothes, career/day systems and financial sustainability. Donation-question effects can be checked through controlled fixtures only; Stage 6 creates actual in-game donations. Expose no fake donation totals or income promise now.

All numbers below are provisional first-pass tuning. Preserve the approved three-group model and distinct base-event/reaction effects. Coefficients, including the additional record-reward gate, are proposals to evaluate rather than validated balance or new user-approved canon.

## 2. Files and ownership

Runtime paths are relative to `GirlStreamer/`.

| File | Planned changes |
| --- | --- |
| `prototype/stream/audience_state.gd` (new) | Deterministic state, fixed-second updates, clamps, repeat scaling, immutable snapshots |
| `prototype/prototype_session.gd` | Own model, time advancement, source/effect identities, achievement/loss eligibility, causal history and final snapshot |
| `prototype/stream/stream_content.gd` | Validate existing effects/style/source metadata; centralize proposed audience tuning if a typed local settings record is needed |
| `prototype/stream/stream_director.gd` | Inject current audience snapshot access for ordinary-question window at opening; never owns audience mutations |
| `prototype/stream/chat_feed.gd` | Sample audience-dependent ambient interval without changing context/event eligibility |
| `prototype/ui/prototype_hud.gd`, `.tscn` | Compact three-group state, current/peak viewers, brief explanations, audience summary |
| `tests/iteration02/test_stream_audience.gd` (new) | Numerical rules, event routing, repeat protection and scripted scenarios |
| `tests/iteration02/test_stream_director.gd`, `test_stream_choices.gd`, `test_stream_feedback.gd`, `test_stream_lifetime.gd` | Adapt audience integration boundaries while preserving each owner's tests |
| `Docs/Technical/Architecture.md` | Update actual ownership after execution |

No Snake rules, input mapping, rendering backend or webcam state changes are expected. Keep immutable configuration separate from mutable per-stream state; no Resource/Autoload service is required.

## 3. Model contracts and initial state

Group order is fixed everywhere: gamer, social, image. Initial `counts = Vector3i(10,10,10)`, `impressions = Vector3(50,50,50)`, fractional carries zero. Clamp counts to 0–200 per group and impressions to 0–100. Total count is derived, not an independently mutable fourth population.

AudienceState owns style-use counts, last accepted effect ID, elapsed model-step count and peak simultaneous total. Peak starts at 30, updates after each population step and is never the sum of individual group peaks from different moments.

Use three-element typed `Array[float]` values for authoritative impressions/carries so repeated arithmetic uses scalar double precision, rather than repeatedly storing accumulators in Vector3 components. Vector3/Vector3i are boundary representations for effect inputs and display snapshots; copy arrays for diagnostic snapshots if full precision is needed. Validate all three-element lengths. Do not let rounded UI values feed back into the model.

| Interface | Contract |
| --- | --- |
| `reset() -> void` | Restore initial values, counters, carries and peak; no inherited history |
| `apply_effect(effect_id: int, effects: Vector3, repeat_key: StringName) -> void` | Apply one finite delta, optionally scale positive components by style usage, clamp impression; duplicate/out-of-order effect ID is a no-op before any counters mutate |
| `advance_second() -> void` | Perform one deterministic second in the order below; no clock sampling or scene access |
| `get_snapshot() -> Snapshot` | Return copied counts/impressions/carries/peak/step count; no live mutable arrays/dictionaries escape |

Define Snapshot as a typed local record. A caller may inspect but cannot alter owned state by modifying it. Model requires increasing positive effect IDs from the session; no per-source policy is inferred from the effect ID. Validate finite effects/configuration before use; invalid input yields a named diagnostic and no partial mutation. Validate the authored raw vectors before multipliers, so the legitimate donation-answer ×1.5 result is not incorrectly rejected for exceeding the raw +4 authoring limit.

`repeat_key` is empty for ordinary answers/base events; otherwise it is one of the three validated reaction style IDs. On an accepted reaction effect increment that style's usage n once; multiply each positive component by 1/n, leave zero/negative components unchanged, then clamp impression. No style count change for duplicates, cancelled/expired choices or hidden candidates. A chosen reaction consumes its style use even if impression was already capped; this is practice of the same style, not refunded reward.

## 4. Fixed-second numerical rule

At each model step, for each group:

1. Read impression at the start of the second's update.
2. Add `(impression - 40.0) / 200.0` to signed fractional carry.
3. Extract whole units by truncation toward zero (not floor for negative fractions). Add them to count and retain the signed remainder.
4. Clamp count. If at the upper bound, discard outward positive remainder; if at zero, discard outward negative remainder. Preserve inward carry so recovery is possible; never bank blocked future departures/arrivals beyond a bound.
5. Move impression toward 50 by 0.1, without overshooting; update peak from the resulting simultaneous counts.

The numerical model is intentionally deterministic. At impression 50 the drift is +0.05 viewers/second/group: the starting neutral state has slow organic growth, not equilibrium. Do not describe a no-action stream as guaranteed audience loss. Persistent collisions push impressions down and eventually reverse drift. This baseline growth and how noticeable social choices feel are tuning questions for scenario/manual evaluation, not grounds to silently alter coefficients.

Use tolerance for fractional whole-unit extraction to avoid delaying the expected +1 after twenty additions of 0.05 due to floating-point error (e.g. 1e-9 in scalar double calculations); do not introduce a one-viewer bias at every step. Test both positive and negative accumulation symmetrically.

## 5. Time advancement and event order

Session owns `_next_audience_step_msec`, initially 1000. Before applying an accepted event or resolution at active time t, advance all due model seconds with boundary ≤t, capped at the stream duration. Then apply that event's effect. Thus an effect exactly at a second boundary acts after that boundary's drift, not retroactively on the previous second. Ordering of two effects at the same timestamp follows the existing synchronous source delivery order.

Also advance to the authorized sample on each RUNNING process update before ticking choices/director. At cutoff first close gameplay authorization, then flush remaining passive model boundaries up to and including duration before freezing the audience summary. For a 360-second stream this means boundaries 1000…360000: the last step represents the completed final second, not permission for an action at cutoff. A one-second stream has exactly one passive step. No new choice/action or future donation sample runs at that instant. Large frame gaps process every bounded due second; this is numerical integration, not multiple chat lines or multiple choice openings. Do not skip drift to cap catch-up, and do not use render delta for audience evolution.

Use only already-authorized source timestamps for accepted gameplay and resolution accounting. The Stage 2/4 guarantee remains: no reentrant finishing sampler inside a score/outcome handler. A final accepted score/completion pair must remain fully counted even if later cosmetic time has reached cutoff. Reuse the producing step's authorized sample for canonical events (the Stage 2 session authorizer cache), rather than deriving a later timestamp from presentation. ChoiceResolution already carries its authorized resolution sample. Timestamps must be nondecreasing across routing; reject invalid past-time test inputs explicitly rather than retroactively rewriting population history.

Pause stops all model steps and effect routing for new actions; rejected input has no source outcome. Retry preserves audience/carry/style usage/peak/clock. New stream resets everything. After the one-time finish-boundary flush, closing/finished never advance drift, apply late effects or recompute a frozen summary.

## 6. Base events and record protection

The session maps accepted canonical game events to the following initial deltas; vector order remains gamer/social/image:

| Source | Impression delta | Eligibility |
| --- | --- | --- |
| FOOD | (0,0,0) | Game score still changes; no audience bonus per food |
| MILESTONE | (8,2,2) | First threshold 5/10/20 per stream, already canonicalized in Stage 2 |
| RECORD | (8,2,2) | Qualifying canonical record, subject to the separate base-record gate below |
| COLLISION | (−2,−1,−1) | Once per real wall/self collision, even when no reaction is offered |
| BOARD_COMPLETED | (10,3,3) | First board completion per stream only |

Preserve precedence BOARD_COMPLETED > first MILESTONE > RECORD > FOOD. No extra record reward is added to a milestone or completion from the same step. Stage 4 emits intermediate RECORD events on successive high scores, so numerical rewards require their own gate.

Proposed base-record gate: initialize next eligible record time to zero; after any rewarded milestone, record or first completion set it to that event's time +60000 active ms. A RECORD before this time has zero base audience delta; at equality it may reward. Milestones/first completion bypass the record gate but advance it after reward. Rejected records do not slide the gate forward. Keep this separate from cosmetic throttling and the director's reaction eligibility cooldown; suppressing a choice must not cancel an otherwise eligible base achievement.

The session additionally guards once-only milestone/completion application so duplicate delivery cannot reward again. Second/later board completions remain visible but have no new base reward. Record gate, milestone eligibility and completion reward reset only for a new stream. Expose the 60-second reward interval as clearly named validated tuning, separate from the director's identically valued initial cooldown.

## 7. Choice effects, source IDs and abuse limits

For every accepted resolution use the copied Stage 3/4 data, not whichever context is latest when the player answers.

| Resolution | Effect |
| --- | --- |
| Ordinary question answered | Apply selected authored vector once, without reaction-style attenuation |
| Ordinary question expired | Zero; missed opportunity only |
| Reaction answered | Apply selected extra vector with 1/n positive scaling for its style; retain base game effect independently |
| Reaction expired | Zero; never reverse or add a penalty to the original event |
| Any choice cancelled | Zero; not a player miss |
| Hidden/expired pending item | No audience application or denominator entry |
| Synthetic donation question answered | Raw answer vector ×1.5, no reaction-style scaling |
| Synthetic shown donation question expired | −2 to its validated source group only |

Only the first two answered loss reactions in a stream can provide positive extra effects. Recognize loss from immutable `source_event_kind == collision`. Consume one loss allowance for each of those selected loss reactions even when clipping prevents visible gain. For later answered loss reactions zero all positive components before calling the model; keep any authored negative components and still count the selected style use. Do not consume allowance for expiry, cancellation, hidden events or malformed/duplicate input. No donation or income hook is emitted in this stage.

Deduplicate at two levels: session rejects duplicate/out-of-order game source IDs and already-accounted choice resolution IDs in their separate namespaces; only then allocate a strictly increasing audience effect ID. Model independently rejects a repeated/stale effect ID before mutating impressions or style counts. Base-event and reaction source IDs can share the same underlying game event but receive distinct effect IDs. Accepted no-effect sources still advance their source watermark so a replay cannot become a reward after a cooldown. Source IDs are not reused across attempts; fresh stream resets all namespaces together.

Store no growing gameplay-event ledger just to deduplicate: use source watermarks under the ordered delivery contracts. The existing bounded choice-result collection remains available for summaries. Never replay historical outcome records on UI refresh, retry, scene resize or Stage 6 integration.

## 8. Presentation and dependent timing

HUD shows current total, peak total and three compact group entries with count and impression description. Labels: «Геймеры», «Любители общения», «Поклонники образа». Impression <40: «интерес снижается»; 40…60 inclusive: «спокойный интерес»; >60: «увлечены». Use text plus a small optional meter; colors alone are insufficient. Avoid claiming every low label immediately loses a whole viewer.

Fit the new information into the existing shell with a compact fixed-size strip in ChatSlot, leaving a scrollable feed below it. Keep the 480 × 360 minimum board and choice region intact; verify the 1024 × 768 layout. Show initial/final/peak total and per-group final values in the frozen summary. Detailed analytics graphs are not runtime UI requirements.

Maintain at most twenty causal records with source kind/time, short Russian reason and actual clamped impression delta. Capture before/after snapshots around effects; explanations must report the actual delta, not the raw authored value. Zero change caused by a clamp or eligibility gate must not claim a rise. No record for ordinary per-second drift; show neutral wording such as «Часть зрителей пришла или ушла со временем» when distinguishing drift in the summary. A brief latest-effect explanation can replace the prior one; do not add an independent popup queue or feedback RNG. Repeated suppressed records must not flood the history.

Examples: «Рубеж в игре заинтересовал геймеров», «Шутка понравилась любителям общения», «Повтор этого приёма действует слабее». Only show them when the associated measured effect supports the claim. Do not imply guaranteed donations or a changed career specialization.

At opening an ordinary question, director reads a copied snapshot and calculates `clamp(6.0 - max(0, total_viewers - 30) / 100.0, 5.0, 6.0)` seconds. Snapshot milliseconds once; never shorten a currently open choice. Reaction windows remain 3000 ms. For explicitly shortened test configurations retain the configured test window rather than applying the normal audience formula; make this an explicit test/Inspector override with no mid-stream mutation. Stage 6 will use the same normal formula for donation questions.

For ambient chat, proposed interval is `clamp(4000.0 * 30.0 / max(1, total_viewers), 1500.0, 6000.0)` milliseconds, rounded to an integer. This gives 4000 ms at initial audience. Apply it only when scheduling the next ambient line after an emission or accepted contextual append; changing population does not move a pending deadline or trigger catch-up. Event-context eligibility and the food/record cosmetic throttle remain unchanged. Inject a snapshot/interval provider explicitly into director/feed; neither may mutate the audience or use global lookups.

## 9. Implementation sequence

- [ ] **A — Inspect dependencies and add failing rule checks.** Confirm event/source metadata and authoritative clock paths exist. Add `test_stream_audience.gd` using native runner conventions with deterministic timestamps and explicit input vectors.
- [ ] **B — Implement the pure model.** Add reset, copied snapshots, finite validation, signed carries, step order, clamps, peak and style scaling. Verify exact numerical fixtures before session integration.
- [ ] **C — Wire canonical effects and time.** Add ordered source routing/effect IDs, model advancement, base-record gate and first-completion protection. Preserve accepted terminal-step accounting without lifecycle resampling.
- [ ] **D — Activate authored choice effects.** Consume copied resolution data once, implement loss allowances and synthetic donation-kind rules. Confirm no historical replay or coupling of base reward to reaction choice.
- [ ] **E — Add readable state and timing dependencies.** Implement HUD snapshots/causal strip/final summary, ordinary question window sampling and ambient interval provider. Verify stable layout and frozen active deadlines.
- [ ] **F — Compare scenarios and record evidence.** Run tests and the bounded comparisons below, load affected scenes and perform manual audience readability checks. Update actual Architecture/roadmap; record proposed tuning changes and user decisions separately from test results.

## 10. Numerical and integration checks

| Case | Required result |
| --- | --- |
| Initial/reset | Counts 10 each, impressions 50 each, zero carries/styles, peak 30; returned snapshot mutation cannot affect model |
| Signed fraction | Twenty increments of +0.05 yield +1, nineteen do not; symmetric −0.05 case yields −1, not −1 on its first step. Isolate accumulation or account for the specified decay in fixtures |
| Step order | At impression 60 first carry increment is 0.1, then impression becomes 59.9; repeated updates match a scalar reference calculation |
| Clamp recovery | At 200 with outward carry, discard blocked growth; at zero discard blocked departures; inward flow still recovers. Impression never leaves 0…100 |
| Peak | Peak is max of simultaneous total, not independent group maxima; decreases never reduce it |
| Style usage | Repeated (4,1,0) style gives positive deltas (4,1,0), (2,0.5,0), (4/3,1/3,0) before clipping; another style starts at full effect |
| Source identity | Duplicate game/choice source, duplicate effect ID and late out-of-order ID cannot apply again or consume a style/loss allowance |
| Independent effects | Milestone base (8,2,2) remains when reaction expires; selecting flirt adds its own scaled vector without replacing base |
| Record gate | Milestone at 10000 delays base record reward until 70000; intermediate records do not push it later; equality permits one reward, duplicate does not |
| Loss protection | Three answered loss reactions: only first two can gain positive extra impression; third still consumes its style count. Retry/newer source context cannot disguise the saved collision kind |
| Donation fixture | Answer ×1.5 applies once; expiry affects exactly the source group; unseen/cancelled question does nothing; no payment API invoked |
| Temporal partition | Same ordered events/timestamps produce identical state with frequent frames or batched advances; a boundary event acts after that boundary's drift |
| Finish | 360-second stream integrates boundaries 1…360, then freezes; a one-second stream has exactly one passive step. Already-authorized terminal pair is included once; new gameplay actions at cutoff are rejected. CLOSING adds no steps |
| Pause/retry | Reuse the Stage 1 controlled-clock fixture and assert the new audience invariants: no drift while paused, unchanged counts/carries/gates on retry and initial state on restart. |
| Sampled windows | Totals 30/80/130 give normal windows 6/5.5/5 seconds; higher totals never go below 5; open choice and reaction deadline unchanged |
| Chat intervals | Totals 30/60/0 give 4000/2000/6000 ms; pending deadline is unchanged by a mid-interval audience update |
| Bounded causes | After 25 significant changes only the newest 20 records remain; suppression/clamp does not falsely claim a positive change |

Use scalar high-precision reference arithmetic/tolerance in numerical tests; do not make assertions depend on platform-specific decimal formatting. New runner marker: `ITER02_STAGE05_AUDIENCE_PASS`, named failure and nonzero exit. Expected invalid-content/configuration diagnostics must be identified; reject unexpected errors.

Resolve `$godotExe` from actual project configuration. Intended commands from repository root:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_audience.gd
# Earlier runners below are regression candidates when this stage changes a contract they exercise.
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_director.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_choices.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_feedback.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd
```

## 11. Scenario comparison and manual acceptance

Run deterministic six-minute scenarios from identical initial state using valid event and choice sequences: model-only zero-input baseline, achievement-focused play, communication-focused play, and repeated-loss/style spam. The zero-input baseline isolates passive audience drift and is not an AFK game session: normal Snake moves without input and eventually generates a collision. If also testing session-level AFK behavior, include that real collision and label it separately. Keep scenario inputs versioned in the runner, not random play statistics. Gameplay scenarios obey actual director windows/cap/cooldowns; do not fabricate more answered reactions than gameplay permits. Use fixed seeds for content/Snake if those systems participate; AudienceState itself uses no RNG.

Record initial/final/peak counts, final impressions, rewarded milestones/records, accepted reaction styles and suppressed positive loss effects. Require replay determinism, bounds, duplicate protection and no unlimited reward from repeated failure. Compare trajectories and explain differences; do not assert both play styles are balanced simply because all tests pass. The no-action organic-growth baseline must be visible in the comparison. If one style is consistently dominated, record the evidence and tune provisional coefficients with a focused rerun rather than silently declaring balance.

During implementation create a concise `Reports/Doc/Report_Doc_YYYY_MM_DD_HH_mm_JobName.md` with actual scenario settings/results and manual checks, not fabricated results in this plan. Manually verify that a player can explain an impression change, see later count changes, distinguish group preferences, and read the display while steering at minimum window size. Full combined stream/donation balance remains Stage 7.

Current combined balance/readability follow-up: [OI-003](../../OpenItems/Items/OI-003-StreamPlaytest.md). Retain the verification protocol here; track unresolved findings in that card.
