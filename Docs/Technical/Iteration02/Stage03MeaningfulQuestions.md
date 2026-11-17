# Stage 3: Meaningful Questions and Shared Choice Input — Detailed Implementation Plan

> **Current corrections (2026-11-17):** [Iterations 1–2 correction plan](../Iteration01And02Corrections.md) supersedes this document where duration, interaction cadence, Snake speed or HUD placement conflicts. Apply its 180-second preset to future acceptance runs. See the correction plan for current implementation and acceptance status.

Plan date: 2026-11-13. Implemented and headless-verified.

> **For agentic workers:** Use `stage-orchestrator` for whole-stage execution and `executing-plans` for its tasks, subject to AGENTS.md. Keep one writer for shared session/content/HUD files and one owner of the editor. No automatic commits or pushes.

**Goal:** Replace placeholder questions with authored contextual conversations, visible selected replies and one authoritative timed-choice controller, ready for later reactions and audience effects.

**Architecture:** StreamChoice owns only the currently open choice, its deadline and 1–3 input. The session temporarily schedules ordinary questions, retains outcome records and routes presentation; Stage 4 transfers scheduling to StreamDirector. StreamContent holds immutable authored content; webcam/chat display outcomes without modifying gameplay.

**Tech stack:** Existing Godot 4.7 Standard, typed GDScript, native Control UI and Input Map; no new dependencies.

**Specification:** [Iteration roadmap](../Iteration02ImplementationPlan.md), Stage 3; [iteration scope](../../GameDesign/Iteration02Scope.md); [Stage 1](Stage01StreamShell.md); [Stage 2](Stage02ChatAndWebcam.md); [current architecture](../Architecture.md). Before implementation read the project workflow/implementation rules and select Godot specialists through `Codex/GodotSkills.md`.

## 1. Dependencies and boundaries

Stage 1 supplies lifetime and active time. Stage 2 supplies content, feed and webcam. The user accepted both before Stage 3. This stage replaces the baseline QuickMessages controller.

Include twelve ordinary questions, three distinct answers each, contextual eligibility, six-second answer windows, selected heroine replies, corresponding chat responses, retained outcomes and intended three-group effect vectors. Effects are authored data only until Stage 5. No viewer changes, donation payments, correctness score, reward popup or claimed popularity gain now.

Exclude reaction QTEs, donation questions, director queues/priorities, audience simulation, adaptive question time, new keyboard mappings, sound and external text generation. Keep the optional messages-disabled baseline: it disables timed questions only, not the Stage 2 ambient chat/webcam. Snake keeps moving during choices; only explicit user pause freezes it.

Stage 4 will replace this stage's temporary 45-second scheduling with the shared interaction cadence. Do not apply Stage 4's 25-second gap/eight-opening cap or build its scheduler early.

## 2. Files and migration ownership

Paths below are relative to `GirlStreamer/`.

| File | Planned change |
| --- | --- |
| `prototype/stream/stream_choice.gd` (new) | Single active choice lifecycle, input, injected authorized time sampler and immutable resolution snapshot |
| `prototype/stream/stream_content.gd` | Extend Stage 2 types with QuestionTemplate, ChoiceDefinition, ChoiceOption and ChoiceResolution; twelve questions and reply-specific chat text |
| `prototype/prototype_session.gd`, `.tscn` | Replace QuickMessages with StreamChoice, temporary scheduling/eligibility, resolution accounting and presentation routing |
| `prototype/ui/prototype_hud.gd`, `.tscn` | Reuse reserved choice area for question/nickname/options/countdown and short feedback; existing results metrics retained |
| `prototype/ui/hero_webcam.gd` | Add selected-reply priority and one coalesced automatic-state slot |
| `prototype/stream/chat_feed.gd` | Add contextual response append contract using the existing bounded history and independent RNG |
| `prototype/messages/quick_messages.gd` and its `.uid` | Retire after all references and coverage are migrated; no inactive duplicate input owner |
| `tests/iteration02/test_stream_choices.gd` (new) | Choice lifecycle, catalog, scheduling, integration and presentation tests |
| `tests/iteration01/test_quick_messages.gd` | Retire after its meaningful cases move to the new runner |
| `tests/iteration02/test_stream_lifetime.gd`, `test_stream_feedback.gd` | Adapt old node/signal access and update answer presentation expectations |
| `tests/iteration01/test_timed_session.gd` | Adapt message-disabled fixture dependencies or references where present |
| `Docs/Technical/Architecture.md` | Update actual runtime/test ownership after implementation |

Retain action names `message_answer_1/2/3`; their owner changes, their physical top-row bindings do not. No project.godot edit is expected. Search all non-generated runtime/test references before deleting QuickMessages and update live consumers. Historical iteration 01 plans remain historical; do not rewrite their acceptance records.

## 3. Typed content and instance identity

Keep Stage 2 content types and validation. Add:

- `QuestionTemplate`: `id: StringName`, `prompt: String`, `context: StringName`, `options: Array[ChoiceOption]`. Context is general, achievement or loss. IDs are catalog identities, not runtime choice IDs.
- `ChoiceOption`: `id: StringName` (globally unique, e.g. q01_record), `label: String`, `reply: String`, `emotion: StringName`, `effects: Vector3`, `chat_responses: Array[String]`. Vector order is gamer/social/image. Supply two short, mutually compatible chat responses per option, so later feed selection can avoid an immediate repeated line.
- `ChoiceDefinition`: `id: int` (session-local opening ID), `template_id: StringName`, `kind: StringName`, `prompt: String`, `nick: String`, `options: Array[ChoiceOption]`, `window_msec: int`, `source_event_id: int`, `source_group_index: int`. This stage uses kind `question`, group -1, source event ID 0 for general questions and the actual game event ID for contextual ones.
- `ChoiceResolution`: choice/template/kind/source IDs, `outcome: StringName`, `option_index: int`, `opened_at_msec: int`, `resolved_at_msec: int`, `elapsed_msec: int`, and a copied chosen option for answered outcomes; no chosen option for expired/cancelled.

Definitions are per-opening snapshots. Copy option records and nested response arrays when opening; later catalog/Inspector changes cannot mutate the current question. The session allocates increasing IDs starting at 1, commits an ID only after successful opening, and never resets IDs on attempt retry. Full stream restart clears IDs and records.

Validate before a new stream: twelve unique templates, exactly three nonempty distinct option labels each, nonempty prompt/reply, supported emotion, two nonempty distinct response texts per option, finite effects within −2…+4 per component, legal context, positive finite configured timing. Require distinct effect vectors per question. Reject malformed content before gameplay starts with a readable Russian error; preserve Stage 1 failed-start behavior.

## 4. Content brief

The following twelve entries define the initial authoring scope, not new story canon. At implementation, write complete short Russian replies and two compatible chat responses for each of the 36 options. Labels convey intention; replies express the heroine's voice. No insult, fabricated donation or future feature promise is needed.

| ID / context | Prompt | Three answer intentions, in displayed order |
| --- | --- | --- |
| q01 / general | «Что сегодня важнее: рекорд или уют?» | «Побить рекорд» / «Посмеяться вместе» / «Очаровать чат» |
| q02 / general | «Давно играешь в Змейку?» | «Люблю тренироваться» / «Учусь на ходу» / «Главное — подача» |
| q03 / general | «Почему выбрала именно эту игру?» | «Люблю испытания» / «Хочу отдохнуть с вами» / «Хотела вас удивить» |
| q04 / general | «Будешь рисковать ради очков?» | «Если есть шанс» / «Поберегу наши нервы» / «Ради ваших взглядов» |
| q05 / general | «Как справляешься с волнением?» | «Слежу за маршрутом» / «Шучу над собой» / «Улыбаюсь в камеру» |
| q06 / general | «Что тебе нравится в стримах?» | «Делиться прогрессом» / «Болтать с вами» / «Ловить комплименты» |
| q07 / achievement | «Как удалось так далеко зайти?» | «Продумала повороты» / «Сама удивилась» / «Вы вдохновляете» |
| q08 / achievement | «Дальше будет ещё лучше?» | «Попробую превзойти» / «Не будем загадывать» / «Смотрите внимательно» |
| q09 / achievement | «Гордишься этой попыткой?» | «Тренировка помогла» / «Празднуем вместе» / «Жду комплиментов» |
| q10 / loss | «Обидно было проиграть прошлую попытку?» | «Поняла свою ошибку» / «Смешно получилось» / «Засмотрелась на чат» |
| q11 / loss | «Что изменишь после прошлой ошибки?» | «Выберу другой маршрут» / «Выдохну и продолжу» / «Нужна ваша поддержка» |
| q12 / loss | «Этот заход будет реваншем?» | «Обязательно попробую» / «Ещё одна попытка!» / «Если поболеете за меня» |

All are questions about the stream/game, not factual quizzes. Avoid repeating identical reply text under different labels. No permanent mapping of keys to audience groups is promised for ordinary questions: permute option order in the authored catalog where it helps avoid automatic “always press 1.” Reaction-style positions become fixed only in Stage 4.

Initial effect proposals may use (4,1,0), (1,4,1), (0,1,4) as authoring seeds, but contextual edits must reflect the actual wording. At least some questions must vary the relative tradeoff so the whole catalog is not the same three effects with different text. Values remain provisional and have no runtime audience effect in this stage. Do not make any option component-wise greater than or equal to both alternatives; avoid an obviously dominant option. In the six-second choice UI show short intent labels, not numeric vectors or large descriptive paragraphs.

## 5. Controller contracts and event ordering

`StreamChoice extends Node` uses IDLE/OPEN, contains no question catalog iterator, schedule, viewer model or queue.

| Interface | Contract |
| --- | --- |
| `set_time_sampler(sampler: Callable) -> void` | Inject the session's action-authorizing active-time sampler; it may synchronously cancel on stream expiry |
| `reset() -> void` | Clear current/last choice snapshots; called only after prior lifecycle ended, without synthesizing outcomes |
| `try_open(definition: StreamContent.ChoiceDefinition, now_msec: int) -> bool` | Only IDLE, valid definition and a session-authorized opening sample; copy definition, set deadline, emit opened once. No internal resampling or gameplay policy |
| `tick(now_msec: int) -> void` | Session calls only with authorized active time; expire OPEN at now ≥ deadline |
| `cancel(now_msec: int) -> void` | Resolve OPEN once as cancelled; IDLE is a no-op; allowed during CLOSING |
| `is_open() -> bool` | Current lifecycle state |
| `get_remaining_seconds(now_msec: int) -> float` | Nonnegative deadline difference or zero when idle |
| `get_last_resolution() -> StreamContent.ChoiceResolution` | Defensive copy of the last complete record, available before resolved signal is emitted |
| `opened(definition: StreamContent.ChoiceDefinition)` | Copied active definition for presentation/accounting |
| `resolved(choice_id: int, option_index: int, outcome: StringName)` | Preserve roadmap signature; outcome is answered/expired/cancelled, index 0–2 or -1 |

On key input, ignore releases/echo and unrelated actions. For owned 1–3 while OPEN, retain current ID, sample authorization once, then recheck that the same ID is still OPEN. The sampler can synchronously finish/cancel, in which case return without a second result. At the choice deadline expire rather than answer. At stream deadline session cancellation wins. Once a key resolves a choice, consume it and return; never open the next question from a resolution callback.

For any resolution, capture immutable outcome data using the already authorized sample, switch IDLE and populate the last-resolution record before emitting the signal. Answer latency is clamped active elapsed time from opening; cancelled/expired use no selected option and a zero applied-effect intention. The session copies the resolution immediately, keyed by choice ID, and rejects duplicate/stale IDs. No handler invokes the finishing time sampler again while accounting for an accepted answer.

## 6. Temporary scheduling and context freshness

Session owns this stage's temporary fields: next-question due time, used template IDs, latest eligible achievement/loss source event and its active-time timestamp. No queue or new scheduling service.

- Default first question at 45000 active ms; next due is resolution time +45000 ms after answered/expired. Cancelled at finish schedules nothing. Default window is 6000 ms, snapshotted at open.
- Preserve meaningful Inspector timing controls for shortened tests, validate/snapshot them per stream, and keep `messages_enabled`. Supported bounds remain 1–120 seconds for first delay/gap and 1–15 seconds for the question window. Use the configured gap in every next-due calculation; 45000 ms is only the default. Viewer-based shortening is deferred to Stage 5.
- Open only in RUNNING while Snake is playing, no choice is open, and due time has arrived. Waiting for retry defers a single opportunity; no backlog. An already-open question keeps running while waiting/retrying.
- At opening, prefer an unused question matching the latest achievement/loss event if it is at most 15000 active ms old; otherwise select an unused general question. Retry clears achievement context from the previous attempt, but retains the latest factual loss within its original TTL: loss questions explicitly refer to the previous attempt/current revenge attempt. Do not refresh its timestamp on retry. A newer achievement/loss replaces the old candidate; ordinary food does not. Already-open questions are snapshots and are not withdrawn on retry/new events.
- Within the eligible pool, use stable catalog order for deterministic first-pass behavior; remove shown templates from eligibility for the rest of the stream. If all eligible general questions have been used and no fresh unused contextual question exists, skip this opportunity and set the next due to now + the snapshotted configured gap. Do not invent context or replay a stale prompt to fill a quota.
- Select the questioner's nickname through a dedicated seeded question RNG, separate from chat and Snake, or use a stable authored nickname sequence. Pick one at implementation and record it; no use of the global RNG.

Context freshness and the six general questions may produce fewer openings than a purely periodic schedule; twelve templates are a catalog, not a requirement to show twelve questions in six minutes. Stage 4 takes ownership of scheduling but retains these factual context/duplicate protections. Run context/short-timing tests to exercise all twelve entries without pretending one ordinary stream displays them all.

## 7. Selected replies, chat and stored consequences

On answered resolution: record it once, update existing metrics, clear the choice area, show brief “Ответ отправлен” feedback for 1000 active ms, display the selected heroine reply for 3000 ms and append one compatible viewer response. Remove the Stage 2 generic answer-line/shy-emotion call for this same event; do not show both feedback paths.

Add `ChatFeed.append_answer_response(option: StreamContent.ChoiceOption, now_msec: int) -> void`: choose one of that option's two responses with the chat RNG, assign stable template identity from the globally unique option ID plus response index, append through the existing bounded history path and reschedule ambient cadence. A response must match the selected reply; a random generic line from another answer is invalid. No duplicate fake viewer question is inserted into the background feed when the dedicated choice panel opens.

Add `HeroWebcam.show_reply(text: String, emotion: StringName, now_msec: int) -> void`. Selected reply has priority over all automatic states and uses one immutable three-second deadline. If short test settings produce another answered choice during that interval, the new selected reply replaces the old one with its own three-second deadline, without a reply queue. Preserve any pending automatic state only with its original expiry, discarding it if already stale. Automatic events during a reply do not interrupt it: retain only the latest eligible automatic emotion with its original event time and two-second expiry. On reply expiry show that automatic state only for its remaining original lifetime; otherwise return to the current playing/waiting baseline. Never restart an expired automatic emotion for a fresh two seconds. Clear active/pending presentation on stop/reset. Pause freezes both deadlines.

Use existing five emotions; keep text short enough for the 160 px webcam region, with a reserved two-line caption. Longer authored reply text must fail a visual/content review rather than expanding the board layout. The answer options remain in the fixed choice region with no focus/input capture by decorative Controls.

Store one copied resolution per shown choice in a session-local typed array; no disk persistence/export or generic analytics service. At 360 seconds with default timing there are only a few records; retain validated positive minimum spacing so no unbounded per-frame creation occurs. Stage 5 will consume selected effects at resolution time, not replay stored records as a second reward source. Current summaries still report shown/answered/expired/cancelled, answer rate and mean active response time; no speculative audience result is displayed.

Expired questions show “Время вышло” for 1000 active ms, with no selected reply, response line or effect. Cancelled questions clear silently and never enter answer-rate denominators. The Stage 2 accounting-first boundary remains: an already-authorized answer is recorded even if a subsequent read-only cosmetic clock sample reaches stream cutoff; suppress late presentation without undoing the accepted outcome.

## 8. Lifecycle and legacy coverage migration

At successful new-stream initialization reset controller, schedule, IDs, used catalog set, contextual source, resolution records and feedback deadlines before opening is possible. Content validation runs before session mutation. Retry resets none of the choice state or records; it clears prior achievement eligibility but retains fresh retrospective loss context as above. Pause blocks session scheduler/controller ticks and rejects input via the sampler. Resume preserves open deadlines, feedback/reply time and pending automatic expiry.

At finish, enter CLOSING, cancel the open choice synchronously, record matching cancellation, then freeze summary and stop presentation. Accept no late non-cancelled callback during CLOSING. Connect signals once during setup and remove all old QuickMessages connections, preload constants, node paths and obsolete message-reset methods. Replace message-specific mechanics with the new owner while retaining player-visible metrics.

Before retiring `test_quick_messages.gd`, transfer choice-specific coverage to the new runner: disabled scheduling, answer keys/repeat, exact expiration, no overlap, retry preservation and active response latency. Keep one finish-cancellation case for the new controller and reuse the lifetime runner for the surrounding shell transition. Keep existing question denominator coverage until Stage 7 replaces it with the combined results cases. Stage 4 transfers scheduler tests out of this runner. Adapt Stage 1/2 fixtures that mention QuickMessages or rely on generic shy response. Preserve the Stage 2 accepted final-score/outcome boundary case.

## 9. Ordered implementation tasks

- [x] **A — Inspect prerequisites and map old coverage.** Confirm Stage 1/2 are implemented; inventory QuickMessages consumers and map each old test group to a new case. Prepare the new runner and confirm intended missing-feature failures without editor changes beyond authorized implementation scope.
- [x] **B — Author and validate content.** Add the typed records and twelve prompts, 36 replies/effects and 72 response alternatives. Check context, emotion, uniqueness, length/readability and lack of mechanically dominant choices. Keep all coefficients marked provisional.
- [x] **C — Implement StreamChoice lifecycle.** Add injected sampler, typed copied definitions/resolutions, single input owner, boundary/reentrant cancellation handling and opening/resolution signals. Verify controller cases in isolation with controlled active time.
- [x] **D — Replace QuickMessages and add temporary scheduling.** Update composition/session/HUD, migrate timing defaults to six seconds, add context filtering/no-repeat selection and copied outcome records. Confirm retries and disabled questions preserve the rest of the broadcast.
- [x] **E — Integrate selected presentation.** Add reply priority and response append; replace generic Stage 2 answer presentation. Verify no stale automatic queue, duplicate response or layout shift.
- [ ] **F — Retire obsolete owner and verify.** Remove old runtime/test files only after coverage and references are migrated. Run relevant suites, load affected scenes, manually play the interaction scenario, then update actual architecture/roadmap status and record remaining checks.

## 10. Required verification

| Case | Expected result |
| --- | --- |
| Catalog validation | Twelve templates, exactly three options each; malformed IDs/options/effects/emotions reject before start; all authored entries can be selected under an eligible fixture |
| Open snapshot | Opening while OPEN fails without replacing anything; mutating original content does not change prompt/options/deadline |
| Boundaries | Open at 1000 ms with window 6000: answer at 6999 succeeds, at 7000 expires; if stream also ends at 7000, cancelled wins |
| Reentrant sampler | Sampling triggers session finish and cancel; the input handler emits no second resolution and does not access cleared active data |
| Single input | Each of 1/2/3 works while steering; release/echo/unrelated key ignored; repeated presses cannot answer twice or open the next question |
| Time and retry | Pause 60 wall seconds preserves remaining time and active latency; retry preserves current choice/ID/deadline; new questions remain deferred while waiting |
| Context freshness | Eligible loss/achievement prompt at age 15000 ms; age 15001 falls back to general. Real collision→retry→due opening can select a retrospective loss prompt; no prompt opens while waiting. Retry does not refresh loss age, a newer significant event replaces it, and prior achievement context clears on retry; shown template not repeated |
| Scheduling | First opening at 45000; resolve at 47000 gives next due 92000; long wait for retry creates one opening only, never catch-up |
| Configured gap | With a 1000 ms gap and exhausted general pool, a skipped opening sets next due to now +1000, not +45000; fresh contextual content can open at that next opportunity |
| Metrics and effects | One resolution record per ID; correct selected vector copied only for answered; no audience/money mutation; shown equals answered + expired + cancelled after finish |
| Presentation | One selected reply and one compatible chat response; no generic duplicate; automatic event at reply time +2500 survives only until +4500, not a fresh two seconds after reply ends |
| Stale automatic state | Automatic event at reply time +500 expires before reply ends; return to baseline rather than replaying it |
| Overlapping replies | A second accepted answer at first-reply time +1500 replaces its text/emotion until +4500; keep an unexpired automatic candidate's original deadline, never queue either reply or refresh the automatic lifetime |
| End/reset | Finish cancels once before summary; stops response updates; restart resets catalog/history references/choice state without duplicate subscriptions |
| Disabled baseline | No questions or resolution records; Snake, ambient chat and automatic webcam still work |
| Layout | All authored question/option/reply texts readable at 1024 × 768; controls and board remain usable without overlap or resize |

Use existing SceneTree runner conventions. New marker: `ITER02_STAGE03_CHOICES_PASS`; named failed case and nonzero exit on failure. Resolve `$godotExe` from actual project configuration, then intended commands from repository root:

```powershell
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_choices.gd
# Earlier runners below are regression candidates when this stage changes a contract they exercise.
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_lifetime.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_feedback.gd
& $godotExe --headless --path GirlStreamer --script res://tests/iteration01/test_timed_session.gd
```

Require explicit PASS, exit code zero and no unexpected diagnostics. Label expected invalid-content errors separately. Load touched scripts/scenes with the installed engine's supported workflow. Do not run the retired quick-message runner or unrelated pure Snake suites without a relevant change/failure.

Manual scenario: open a contextual question using shortened timing; steer while answering each key across several questions; pause during an open question and a selected reply; collide/retry during a question; observe expiry; finish with an open question; restart and run with questions disabled. Inspect a catalog fixture for all long text cases rather than waiting for twelve prompts in one stream. Full experience/balance acceptance remains Stage 7.
