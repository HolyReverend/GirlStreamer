# Stage 4 — Announcement and prepared topic

**Status:** Implemented and technically verified on 2026-11-18. **Goal:** Deliver two observable callbacks to preparation. The player sees who arrived because of the announcement as soon as the stream opens. At the first scheduled question, the player recognizes the rehearsed topic and can use a hint to choose a reply.

**Dependencies:** [Iteration scope](../../GameDesign/Iteration03Scope.md), [Stage 1 daily flags](Stage01DayModel.md), [Stage 2 launch and forecast](Stage02PreparationScreen.md), [Stage 3 question timing](Stage03MasteryAndConcentration.md), [iteration roadmap](../Iteration03ImplementationPlan.md).

## 1. Pass both preparation flags into stream startup

- [x] Under the day controller launch guard, read the published-post and prepared-topic flags already present on the Stage 1 launch snapshot passed through Stage 3. Supply both before session initialization under the existing transition guard. Daily activity costs have already been committed in the room.
- [x] In [prototype_session.gd](../../../GirlStreamer/prototype/prototype_session.gd), use the post flag when resetting the audience and pass the topic flag to director startup. Keep false defaults for direct/standalone starts. A rejected launch preserves the room flags for retry. A Snake retry within a stream calls neither initialization path.
- [x] Check the four combinations independently at equal seeds. These are the reference observations with the normal preset:

| Published post | Prepared topic | First displayed audience | First interactive opening |
| --- | --- | --- | --- |
| No | No | 30, ten per group | Existing director selection |
| Yes | No | 33, eleven per group; «От анонса: +3» | Existing director selection |
| No | Yes | 30, ten per group | Prepared question with one marked reply |
| Yes | Yes | 33, eleven per group; «От анонса: +3» | Same prepared question; window sampled from actual audience and concentration |

## 2. Establish the promoted audience as the opening balance

- [x] Extend [AudienceState.reset](../../../GirlStreamer/prototype/stream/audience_state.gd) with an optional opening bonus of one viewer per group for the post. Set counts before computing the initial peak. Preserve default reset behavior, initial impressions of 50, zero carries, empty style history and zero elapsed audience steps.
- [x] Capture the actual initial total in the session immediately after reset. Use it for the first HUD snapshot and for `StreamResults.initial_viewers`; the current results builder assigns the constant `Audience.INITIAL_TOTAL`. An announced stream ending at 36 must show 33 at start and a live increase of 3. Its first peak is 33. Promotion has no live effect ID, highlight or donation receipt.
- [x] In [prototype_hud.gd](../../../GirlStreamer/prototype/ui/prototype_hud.gd), show the attributed gain alongside the opening count, separately from the explanation for the latest live change. A compact persistent line such as «На старте: 33 · От анонса: +3» keeps the cause readable after the first audience tick. Clear it on reset; omit the promotional cue on an ordinary start. Use the same announced gain as the room forecast.
- [x] Let chat cadence, question windows and donation sampling observe the resulting live counts through their existing providers. Check initial state before advancing the clock. Subsequent donation amounts depend on simulation and RNG; they are not an acceptance target for the post.

## 3. Author one topic and its rehearsed reply

**Owner:** [stream_content.gd](../../../GirlStreamer/prototype/stream/stream_content.gd). Add one dedicated template, suggested ID `prepared_snake_record`, available only through the preparation reservation. Keep its choice kind `question` so it uses ordinary handling for names, timing, counters, question audio and effects.

Suggested copy for the first pass, valid even before the player scores a point:

| Question | «Как собираешься побить свой рекорд в Змейке?» |
| --- | --- |
| 1 — rehearsed | «Оставлю себе место для разворота». Hint: «Ты это репетировала · Понравится любителям игры». |
| 2 | «Чат, какую тактику попробуем?» |
| 3 | «Для начала постараюсь не врезаться на глазах у всех». |

- [x] Author three distinct valid option IDs, labels, heroine replies, emotions, chat responses and audience effect vectors using the existing catalog rules. Assign a positive effect for the gaming group to the rehearsed answer. Validate the hint against its actual authored effect. All three responses remain selectable through the existing 1–3 inputs.
- [x] Attach optional hint text to the rehearsed option using its stable identity. Preserve it when the choice definition and its options are copied. Extend content validation to require exactly one non-empty hint for this topic, a unique template ID and three valid options. Keep the existing twelve-template ordinary catalog intact. Validate the dedicated prepared template against those IDs before starting a prepared stream. A malformed template must reject startup and return the player to the room with both flags intact. Add a failing-content fixture so the first opening cannot get stuck retrying an invalid question.
- [x] In the choice HUD, render the hint beside the corresponding numbered reply. Treat it as explanatory text. Keep the existing response timer, input and scoring for each option. On resolution, expiry, cancellation or the next ordinary choice, clear the hint along with the option labels.

## 4. Reserve the first successful opening

**Owner:** [stream_director.gd](../../../GirlStreamer/prototype/stream/stream_director.gd). Reuse the current active clock, admission callback, choice owner and opening budget.

1. At startup set one per-stream reservation when the topic flag is present and messages are enabled. Reset or stop clears it. At zero active time no question is visible.
2. In `tick()`, prune stale candidates and apply existing guards for enabled scheduling, due time, budget and active choice. When reserved, try the topic before the donor/reaction/ordinary branches. It is eligible during play and while waiting for Snake retry. Use a session-level question with no attempt-specific source event.
3. Sample the Stage 3 question window at the attempted opening. Use the existing session admission path to assign the ordinary question nickname and opening ID. Consume the reservation **only on success**. On rejection keep it, consume no budget, and return without offering another candidate in that tick.
4. A successful opening advances the gap and counts once toward the cap. Preserve pending donor and reaction candidates under their existing TTL, attempt and eligibility rules. A waiting donor retains the original already-credited payment. The next eligible opening resumes donor → reaction → ordinary priority. An answer, timeout or Snake retry cannot rearm the topic.

**Controlled-clock example.** With the default preset, nothing opens at 19,999 ms. At 20,000 ms a fresh donor question is queued, a collision reaction is eligible and Snake is waiting for retry. The donor becomes eligible once Snake resumes. The topic opens alone. The player can answer while waiting. If Snake restarts and the donor is still fresh, the donor can open at 40,000 ms. If admission of the topic instead first succeeds at 22,000 ms, the next opening is due at 42,000 ms. A paused clock, disabled messages or the 180-second hard cutoff must never force an extra opening.

## 5. Verification and acceptance

| Check | Evidence required |
| --- | --- |
| Audience and results | Extend `test_stream_audience.gd` and `test_stream_integration.gd`. Verify the four launch combinations, actual opening counts and peak, clean cause history, correct frozen baseline and independent subsequent reset. Verify the first donation opportunity sees the promoted counts. |
| Director contention | Extend `test_stream_director.gd`. While Snake is playing, queue a fresh donor and an eligible nonterminal reaction together with the prepared topic. Assert the topic wins over both. In a separate waiting-for-retry case queue a recent qualifying terminal reaction and a donor who must wait for play to resume. Also exercise pending reaction invalidation after retry, expired donor, rejection then admission, delayed first opening, pause, messages disabled and cutoff. At most eight openings total, including the topic exactly once in a normal prepared stream. |
| Content, time and counters | Extend `test_stream_choices.gd` and integration checks. Confirm exactly one copied hint, three selectable answers and the Stage 3 window. In separate runs answer each option, let the topic expire, and cancel an open topic at cutoff using a shortened test fixture. Verify exactly one ordinary shown/outcome entry, the selected option's normal effect and correct hint cleanup. |
| Input and visual feedback | Play a posted/prepared stream and a control stream at 1024 × 768 and 1280 × 900. Read the gain on frame one and the hint while Snake is moving and while waiting for retry. Check all three labels and timer fit the choice panel. Verify regular questions and donor receipts remain legible afterward. |
| Launch lifecycle | Skip a prepared evening and verify no session is instantiated. On a fresh unprepared launch neither cue appears. Verify failed initialization followed by retry applies each effect once. Stage 5 adds the full skip → next morning → unprepared stream check. |

- [x] Run each affected existing runner from the repository root, for example `& $godotExe --headless --path GirlStreamer --script res://tests/iteration02/test_stream_director.gd`, plus the Stage 3 condition runner after integration. Require exit code 0 and each runner's pass marker. Record rendered-window observations separately.
- [x] Update the [architecture map](../Architecture.md) with verified owners and lifecycle behavior during implementation. Stage 4 is ready for acceptance when a player can identify the viewers brought by the post, recognize the prepared question under contention and freely choose a reply.

## Verification status

- Godot 4.7.2 passed 119 director checks, 16 choice groups, 6 audience groups and 7 integration groups. Donation, feedback, lifetime and iteration 03 Stages 1–3 also passed. Intentional negative fixtures logged invalid inputs. Existing stream runners emitted nonblocking ObjectDB exit warnings.
- At the same seed, starts with a post displayed 33 viewers and starts without one displayed 30. The first donation opportunity received the current opening balance. The promoted 33-to-36 fixture showed +3 live growth in the frozen summary.
- Controlled runtime renders at 1024 × 768 and 1280 × 900 verified the opening gain, the prepared prompt and its three numbered replies, a visible timer, and the cleared hint in subsequent regular questions. The prepared topic was checked both while playing and while waiting for retry. Donation receipts remained readable alongside the persistent gain.
- The failing-content fixture rejected startup, preserved preparation and succeeded after retry. Skipping creates no stream. The cross-day reset belongs to Stage 5. Player acceptance remains part of the [Stage 6 playtest](Stage06FullDayPlaytest.md) and [day balance validation](../../OpenItems/Items/OI-108-ConditionAndDailyBalance.md).
