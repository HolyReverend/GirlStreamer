# Iteration 02 acceptance evidence

## Candidate and settings

2026-11-16, Godot 4.7.2, working tree based on `e2c63f0` with Stages 1–7 implemented locally. The user accepted Stages 1–6 individually. Final iteration acceptance remains open.

Normal settings remain 360 active seconds, a 1024 × 768 minimum window, director delays of 30 s and 25 s, up to eight choices, three-second reactions, audience-adjusted question windows and ten-second donation opportunities. Stage 7 retains the provisional balance coefficients. The automated crowded finish uses a 12-second stream, one-second director gap and donation interval, scripted draws and a controllable clock.

## Automated checks

The integration runner, six earlier stage runners and the timed-session regression ran in the Godot console. Use `--headless --path GirlStreamer --script res://tests/iteration02/test_stream_integration.gd` for the final integration runner. Local logs use the `stage7-final-` prefix under `.godot`. See [Stage 7](Stage07CompleteStream.md#11-execution-record) for markers and diagnostics.

The integration runner covers concurrent finish conditions, snapshot copies, highlight selection, mute/pause/restart requests and WAV loading. Two ordinary answers at 1 s and 3 s and one donor answer at 5 s yield a mean of 3 s. Three answered and three expired questions give a 50% answer rate. Reaction latency stays separate.

## Manual checks

| Scenario | Status | Evidence |
| --- | --- | --- |
| First-use check with a new player | NotRun | No new-player observation |
| Gameplay-focused full six-minute run | NotRun | [Stage 5 scripted comparison](Stage05AudienceEvaluation.md) is separate |
| Communication-focused full six-minute run with matching seeds | NotRun | No matched human comparison |
| Short abuse and recovery play | NotRun | Stage 5 scripted repeated-loss run exercises reward limits |
| Standalone presentation and restart | Partial Pass | Agent used a 35 s fixture at 1024 × 768, first question at 3 s and donation opportunities every second. Ready and play screens were legible. The results scrolled to highlights while Enter remained visible. Enter started a new stream with 30 viewers and zero coins |
| Goodbye, larger window and physical mute in standalone | NotRun / unconfirmed | Goodbye was covered by the engine fixture. Desktop M injection did not change the indicator. Physical-only M events passed in Godot, including persistence across restart |
| Audible question, donation and finish cues | NotRun | Headless WAV and request-routing checks. Standalone started during intermediate import metadata work. Missing imported-cache files were fixed by loading local WAVs directly when available |

## Scope acceptance

| Scope criterion | Evidence and status |
| --- | --- |
| 1. Discover controls and finish a first stream without help | NotRun with a new player |
| 2. Visible and explainable game, answer and reaction consequences | Technical Pass in audience and feedback suites. Stage 5 windowed audience strip checked |
| 3. Both donation types and one-time payment without refunds for missed questions | Technical Pass in donation and integration suites. Stage 6 accepted by the user |
| 4. No simultaneous choices, backlog burst, board overlap or choice-induced movement pause | Technical Pass in director, choice and feedback suites |
| 5. Correct pause, retry, frozen finish and reset | Technical Pass in lifetime and integration suites |
| 6. Repeated losses and styles respect reward limits | Technical Pass in the audience runner. Relative incentives remain open in human play |
| 7. Both styles feel worthwhile and mistakes are recoverable | NotRun for the paired full sessions |

Audible quality, player comfort and combined balance remain open.
