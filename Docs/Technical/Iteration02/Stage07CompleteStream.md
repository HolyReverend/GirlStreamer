# Stage 7: Complete Stream and Iteration Acceptance — Detailed Implementation Plan

Plan date: 2026-11-13. Implemented and technically verified on 2026-11-16. Final playtest acceptance remains open.

> **For agentic workers:** Use `stage-orchestrator` for whole-stage execution and `executing-plans` for its tasks, subject to AGENTS.md. One writer owns session/HUD integration and one owner controls the editor and standalone test instance. No automatic commits or pushes.

**Goal:** Finish the stream's presentation, provide trustworthy readable results, add optional sound cues and verify the whole approved iteration as one playable experience.

**Architecture:** Reuse the Stage 1 closing lifecycle and Stage 3–6 authoritative state owners. Session builds one copied result snapshot after final accounting; HUD only renders it. A small scene-owned audio component reacts to accepted presentation events and never drives gameplay time or outcomes.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, native Control UI, local placeholder WAV assets and engine-native test runners. No external services, new framework or export pipeline.

**Specification:** [Iteration roadmap](../Iteration02ImplementationPlan.md), Stage 7; [approved scope and acceptance](../../GameDesign/Iteration02Scope.md); [Stage 1 closing](Stage01StreamShell.md); [Stage 3 replies](Stage03MeaningfulQuestions.md); [Stage 4 director](Stage04ReactionsAndDirector.md); [Stage 5 audience](Stage05AudienceConsequences.md); [Stage 6 donations](Stage06Donations.md). Read workflow/implementation rules before engine work; use `Codex/GodotSkills.md` for actual integration/UI/testing work.

## 1. Prerequisites and scope

The user accepted Stages 1–6 before this stage. The current implementation reuses their runtime owners and finish timing.

Include a short goodbye using the existing placeholder webcam, three distinct sound cues and mute, consolidated frozen results, up to three evidenced highlights, lifecycle stress checks, full six-minute manual playtests and a concise acceptance report.

Exclude new gameplay systems, another minigame, production art, voice, music, persistent settings/saves, analytics infrastructure, exported executable/package, performance benchmark suite and new devices/platforms. Standalone validation means launching the existing Godot project outside embedded editor play, not building an export. Use the existing default 360-second stream; shortened fixtures test boundaries only.

This is an integration and acceptance stage. Fix demonstrated defects in the owning subsystem and update its focused checks. Do not use “polish” as authorization for unrelated mechanics or a broad architecture rewrite. Separate completion of deterministic rules from subjective playability/balance acceptance.

## 2. Planned files and responsibility

Runtime paths are relative to `GirlStreamer/`.

| File | Planned change |
| --- | --- |
| `prototype/prototype_session.gd`, `.tscn` | Assemble final snapshot, closing presentation/audio wiring, retained in-memory mute preference and clean restart |
| `prototype/stream/stream_results.gd` (new) | Typed immutable-after-assembly result record and small per-kind/highlight records; no live node references |
| `prototype/stream/stream_audio.gd` (new) | Local sound playback, mute, stop and bounded simultaneous effects |
| `prototype/audio/question.wav`, `donation.wav`, `finish.wav` (new) | Three short original synthesized placeholder cues; no downloaded/third-party licensing dependency |
| `prototype/ui/prototype_hud.gd`, `.tscn` | Final results layout, closing copy, visible mute indicator/help |
| `prototype/ui/hero_webcam.gd` | Explicit static goodbye presentation compatible with stopped gameplay clock |
| `project.godot` | Add `stream_mute` on physical M, without changing current steering/answer/pause/start actions |
| `tests/iteration02/test_stream_integration.gd` (new) | Combined finish/reset/paused-boundary/summary/audio-trigger checks |
| Relevant Stage 1–6 owning tests | Update only for intended interface changes and discovered regressions |
| a new `Reports/Doc/Report_Doc_YYYY_MM_DD_HH_mm_JobName.md` (create during execution) | Actual settings, checks, manual findings, remaining issues and acceptance status |
| `Docs/Technical/Architecture.md`, `Iteration02ImplementationPlan.md` | Actual final ownership/status and evidence links after execution |

Do not create a report filled with invented results during this planning task. Preserve previous stage evidence and note which implementation/configuration the final checks cover.

## 3. One finish transaction

Reuse Stage 1 `_finish_session(now_msec)` and `_closing_started_msec`. No second end timer, no reload to show results and no completion callback that can reapply rewards. Triggered by expiry, the transaction is idempotent:

1. Deny new gameplay by entering CLOSING and capture the already sampled cutoff wall time. An input that discovers expiry cannot also skip closing or restart.
2. Stop Snake, donation sampling and director candidates. Do not treat pending-but-never-opened questions/reactions as player misses. Discard notification UI backlog without touching payment totals.
3. Flush Stage 5 passive audience boundaries through the completed duration exactly once, including the last second. Already-authorized synchronous game/answer accounting must have completed before this transaction; do not split a final score/completion pair.
4. Cancel the open StreamChoice once. Accept only its matching cancellation in CLOSING and record it before computing totals; cancellation has zero impression effect and no sound/selected reply.
5. Copy all final records into StreamResults. Stop chat and gameplay webcam transients. No mutations to the snapshot after assembly; no payment or impression recalculation when it is rendered.
6. Start a static goodbye and the finish cue once. After the existing two wall-clock seconds, or fresh Enter, transition to FINISHED and render that snapshot. All later updates leave gameplay/results unchanged.

The one-time final passive flush and cancellation accounting occur inside the finish transaction before the snapshot freezes. The phrase “no changes during closing” applies to the subsequent presentation interval, not to omitting these required terminal calculations. No donation sample or new choice occurs at cutoff, even if due then.

On invalid duplicate finish calls, late signals, resize, Enter echo or repeated `_process`, the transaction cannot run again. Fresh Enter in CLOSING only skips to results; a further fresh Enter is needed to restart. Escape is ignored in CLOSING/FINISHED. Mute remains available.

## 4. Final snapshot and UI

StreamResults stores values and copied records only:

- Stream elapsed active time and configured duration; Snake food/attempts/collisions/completed boards and per-stream best score.
- Initial/final/peak simultaneous viewer totals, final counts/impressions per group. Peak uses AudienceState's actual peak total, not summed group peaks.
- Authoritative donation count/total from DonationController, with no revenue recalculation from visible chat or notification queues.
- Per-kind shown/answered/expired/cancelled and summed active answered latency for ordinary question, donor question and reaction, plus all-kind totals. Keep question answer rate/mean separate from reactions; explicitly combine ordinary+donor questions for the overall question rate/mean, with per-kind counts visible. Cancelled choices are excluded from denominators; no data displays «нет данных».
- Copied list of answered reactions with style, source kind and source caption, bounded by the eight-choice cap. Display a compact «Выбранные реакции» list even when its effects were clipped/zero or its causal entry was evicted. This list is independent of positive highlights and includes every selected style/source, without implying a reward.
- Up to three copied highlights selected by the rule below. The existing 20-record causal history remains bounded; no new full event log or persistent history.

Expose `build_results_snapshot() -> StreamResults` on session as a finish-only assembly helper and `show_stream_results(results: StreamResults) -> void` on HUD as pure rendering. Snapshot arrays/records must be deep-copied at assembly; tests mutate a source collection afterward to prove isolation. UI can format counts/times but must not read live models to fill “missing” fields.

Combined question rate is `(ordinary_answered + donor_answered) / (ordinary_answered + donor_answered + ordinary_expired + donor_expired)`. Combined mean is the sum of both kinds' active answered latencies divided by their total answered count; never average per-kind percentages or means. A zero rate denominator displays «нет данных»; an expires-only run displays 0% rate and «нет данных» mean. Reaction latencies and cancelled questions contribute to neither formula.

Results may replace the main play area after gameplay stops. Use compact labelled sections «Игра», «Аудитория», «Донаты», «Общение», «Моменты эфира». Allow vertical scrolling for long results at 1024 × 768 without clipping the restart/mute hint. Do not force all data into the running HUD. Preserve the current stable layout while RUNNING/PAUSED and the board's last valid state behind/in closing presentation if retained.

Highlight selection is deterministic: from Stage 5's bounded causal history choose at most one largest positive actual impression change caused by a base achievement, one by an answered question, and one by a selected reaction. Rank within each category by the sum of actual positive clamped components; ties choose the earlier source ID/time. Then display selected records chronologically. Use existing source metadata or add the minimum typed category field to causal records if needed. No positive record in a category means no highlight for it; fewer than three is valid. State “Моменты, понравившиеся зрителям” rather than claiming these were the global best moments: the bounded history may have dropped earlier entries. Do not manufacture a donation cause, future popularity or a “perfect stream” rating.

## 5. Goodbye presentation

Add `HeroWebcam.show_goodbye(text: String) -> void` that clears active/pending gameplay expressions and shows a static friendly expression and «Спасибо за эфир! До встречи!» inside the existing slot. It must not use the frozen active-time clock to expire. Session alone owns the two-second wall-clock closing interval and exit; no webcam coroutine or timer waits after restart.

The view resets on a new stream. Display «Эфир завершён» and «Enter — перейти к итогам» during CLOSING, then «Enter — новый стрим» in FINISHED. The goodbye does not append a synthetic answer to chat, grant audience effects or count as a selected reaction.

## 6. Sound and mute contract

Create three short local mono WAV placeholders with gentle attack/release and no abrupt clicks: question ~0.15 seconds, donation ~0.3 seconds, finish ~0.5 seconds. They must be perceptually distinct at a moderate level. Record them as original synthesized project assets; no voice or music. Exact tone/pitch is an implementation choice verified by listening, not a game rule. Keep source-generation instructions concise in execution notes if a temporary script is used; no ongoing audio pipeline.

`StreamAudio extends Node` exposes `set_muted(value: bool)`, `play_question()`, `play_donation()`, `play_finish()`, `stop_all()`. Use one non-spatial player for question/donation cues and one for finish, with at most one gameplay cue audible at a time. A new gameplay cue replaces the previous cue rather than queuing it; finish stops gameplay audio before playing. No audio playback status can gate gameplay or state transitions.

Trigger rules:

| Cue | Trigger | Must not trigger |
| --- | --- | --- |
| Question | A successfully opened ordinary/donor question | Pending submission, rejected opening, expiration, hidden donor question, reaction choice |
| Donation | One accepted committed receipt after session routing deduplication | Toast display, aggregate summary, answer, repeated receipt signal |
| Finish | Successful first finish transaction | Repeated finish call, entering FINISHED again, restart, cancellation itself |

Multiple cues in one update are allowed as playback requests; only the last gameplay request is audible because it replaces prior playback. With Stage 6 update order a newly opened donor question can replace that receipt's donation sound. UI still shows both receipt and question, so meaning does not depend on hearing both. Do not add an audio queue to guarantee every cue plays.

Session owns a `muted: bool` preference and handles fresh non-echo M in READY/RUNNING/PAUSED/CLOSING/FINISHED, consuming only that action. Show «M — звук: вкл.» or «M — звук: выкл.». M has no overlap with WASD/arrows/1–3/Space/Enter/Escape. Keep the preference across fresh streams in the same process, default sound on at application launch; no file persistence/settings screen.

Muting immediately stops all players and suppresses new playback; unmuting does not replay missed events. On PAUSED stop active sounds and do not remember a playback offset; resume does not resume or replay them. CLOSING cannot be paused, but can be muted/skipped. Skipping closing stops the finish cue. New-stream start and scene teardown stop any remaining audio. Audio unavailable/headless does not block tests/gameplay; audible quality remains a manual NotRun check if not heard.

## 7. Integration validation scope

New runner `tests/iteration02/test_stream_integration.gd` uses controlled active/wall clocks, seeded existing content/RNG seams and a small injectable audio spy. Spy verifies requests and mute/stop calls, not speaker output. Do not build a new mocking framework or replace the underlying model tests with synthetic success.

| Case | Expected result |
| --- | --- |
| Crowded finish | Use a supported one-second shared-gap fixture: accept an answer at D−2500 ms and open another choice at D−1500 ms while the prior three-second reply is still active. With a one-second donation interval, force a donor question receipt at D−1000 ms and build the notification backlog with earlier forced receipts without questions, leaving the donor slot free. At D a due donation is rejected, open choice cancels once, final audience step is counted and complete snapshot freezes. Record the nondefault setting; do not claim this overlap occurs under the normal 25-second gap |
| Accepted terminal action | Reuse the Stage 2/5 terminal-action fixture if it changes, and assert its accepted effect is present in the final snapshot. |
| Freeze | Advance both clocks, call finish again, deliver stale signals and resize during CLOSING/FINISHED: snapshot values unchanged, no repeated credit/effect/cue |
| Closing controls | Keep wall-clock thresholds and Enter echo/release coverage in Stage 1. Verify that closing skip stops the finish cue and that mute changes neither state nor time. |
| Restart | Same scene instances begin with initial audience, zero money/records, clear IDs/candidates/high score/style counters and new schedules; mute preference retained; no duplicate callbacks |
| Pause with audio | Pause with a cue active and an upcoming donation opportunity. Verify cue stops and resume does not replay it. The Stage 1/6 runners own elapsed-time and sampling boundaries. |
| Results arithmetic | Shown equals answered+expired+cancelled per kind. Ordinary: two answers at 1 s/3 s and one expiry; donor: one answer at 5 s within a 6 s window and two expiries → overall rate 50%, mean 3 s, not an average of per-kind means. Empty/cancelled-only: no data; expires-only: rate 0%, mean no data |
| Snapshot copy | Mutating/resetting live source collections after assembly cannot change rendered result values/highlights |
| Highlights | At most one positive causal record per category, deterministic ties, no invented highlight for zero/clipped/suppressed changes; fewer than three allowed |
| Selected reactions | Every answered style/source remains in the separate chosen-reaction list, including zero/clipped effects, repeated styles and entries absent from positive highlights |
| Sound ownership | One donation request per routed receipt, question request only on actual question opening, finish once; pause/mute/skip/restart stop playback; no UI refresh replays cues |
| Empty results | Render zero-history/zero-donation results without reading live state. Verify readability and board layout in the standalone manual check. |

Resolve actual `$godotExe` from project configuration. Intended command from repository root:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_integration.gd
```

New marker `ITER02_STAGE07_INTEGRATION_PASS`; failures name the case and exit nonzero. Require exit zero, explicit PASS and no unexpected diagnostics. Label expected negative-case diagnostics separately. Load all touched scripts/scenes/assets using the installed engine's supported workflow.

For final acceptance run the existing Stage 1–6 owning runners once on the stable candidate, because this is the first final cross-system gate. Reuse recorded success afterward unless implementation/settings changes affect those contracts. If a defect requires edits, rerun its focused check and the integration cases it affects; do not repeat every suite without a reason. Include remaining iteration 01 Snake checks only if rules changed, prior evidence is missing or a regression points there. Record what actually ran; do not mark commands as passed from their presence in a plan.

## 8. Manual playtest protocol

Create a new `Reports/Doc/Report_Doc_YYYY_MM_DD_HH_mm_JobName.md` only when actual evaluation starts. Record engine version, tested source revision or exact changed-file state, settings/content version, seeds, window size, input method, tester and date. Do not require a new commit merely to identify the candidate. Record whether the run used normal or shortened settings and whether any events were forced.

1. **First-use check:** start from a fresh process, read Russian controls, start the stream without developer instructions, identify game/webcam/chat/choice regions, use pause and mute, then find the restart action. If the tester already knows the game, record that limitation rather than claiming a new-player study.
2. **Gameplay-focused full run:** six minutes at normal settings, prioritize Snake progress but interact when practical. Record mistakes, answered/missed questions, chosen reactions, audience trajectory, donations and observed causes.
3. **Communication-focused full run:** same initial settings and RNG seeds, six minutes prioritizing varied answers/reactions while keeping the game going. Same seeds do not guarantee equal donation results because audience and timing differ. Compare readable choices and consequences, not just final money.
4. **Short abuse/recovery run:** deliberately repeat quick losses and the same reaction style when actually available. Confirm no additional positive loss effects after the allowed two, style attenuation, continued ability to retry and recover. Preserve director gates; do not manufacture unlimited QTEs to make the test easier.
5. **Standalone lifecycle/audio check:** launch the project outside embedded editor play, inspect 1024 × 768 and one larger size, hear each cue using a deterministic fixture if needed, toggle mute, pause/resume, close/restart a stream and exit cleanly. This does not require an export/package or a second editor owner.

During the two full runs record plain-language observations: were three-second reaction labels readable, did attention demands feel recoverable, did chat distract or clarify, could the tester explain viewer changes, were donation questions distinguishable, did the finale/results explain the run, and would another style be worth trying? Record both strengths and concrete problem cases with approximate active time.

Do not impose a retroactive success-rate threshold or claim statistical balance from two runs. Deterministic tests establish rules; these runs supply exploratory experience evidence. If the same poor strategy is materially better or required interactions feel unfair, record the issue and adjust one relevant provisional parameter at a time. Repeat only affected automated checks and manual comparisons after a change; preserve prior settings/results so conclusions remain traceable.

## 9. Evidence and acceptance report

Keep a new `Reports/Doc/Report_Doc_YYYY_MM_DD_HH_mm_JobName.md` concise, with these sections:

- Candidate/settings and prerequisites: stage statuses and known limitations, exact normal overrides, independent seeds.
- Automated checks: command, PASS/Fail/NotRun, evidence path and pertinent diagnostics; no redundant log dump.
- Manual run table: intent, duration, results, tester observations and forced-event disclosure. Separate observed sound/UI from headless checks.
- Findings: created or updated OpenItems IDs for unresolved problems/decisions, plus completed fixes and relevant rechecks. Separate technical bugs, unchosen product requirements and balance hypotheses.
- Acceptance: each of the seven scope criteria mapped to evidence and Pass/Fail/NotRun; user acceptance separately recorded with actual date/statement if supplied.
- Remaining work: genuine limitations and deferred scope, without calling missing mandatory checks “optional polish.”

Do not mark the iteration accepted solely from automated success. If no human play/audio check is available, technical work can be recorded as verified while experiential/audio acceptance remains NotRun and user acceptance open. Do not fill that gap with synthetic measurements or agent opinion presented as a human playtest.

## 10. Ordered implementation tasks

- [ ] **A — Audit stable prerequisites.** Inspect implemented Stage 1–6 ownership/evidence and identify concrete integration gaps. Prepare the new failing integration checks and snapshot schema before adding presentation.
- [ ] **B — Consolidate finish/results.** Extend the existing finish transaction with copied full results and deterministic highlights; implement readable summary and frozen goodbye without a second timer.
- [ ] **C — Add local audio/mute.** Create three small original cues and one scene-owned audio component; wire only accepted event paths, M toggle and pause/skip/teardown behavior.
- [ ] **D — Run final technical gate.** Execute integration and stable-candidate owning checks, load touched scenes/assets and fix failures at their owners. Record actual evidence, not assumed pass status.
- [ ] **E — Run manual protocol.** Perform the paired full sessions, short abuse check and standalone/audio/lifecycle check. Record limitations; tune only evidence-backed provisional settings and recheck affected behavior.
- [ ] **F — Close documentation and handoff.** Update Architecture and roadmap to actual implemented state, record current acceptance status in the plan and write a local work report, list all changed files and distinguish technical completion from user/experiential acceptance. No commit/push/export unless separately authorized.

Current acceptance gaps: [audio](../../OpenItems/Items/OI-001-AudioAcceptance.md), [window/input](../../OpenItems/Items/OI-002-WindowAcceptance.md), [human playtest and tuning](../../OpenItems/Items/OI-003-StreamPlaytest.md). The protocols below define how to check them; maintain pending findings in the cards, not only in reports.
