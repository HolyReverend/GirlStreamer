# Stage 5 audience evaluation

Run on 2026-11-16 with Godot 4.7.2. The [audience runner](../../../GirlStreamer/tests/iteration02/test_stream_audience.gd) uses the shipped interaction timing and an active clock advanced in 200 ms increments. The session cases use a 64 × 8 board, seed 1729, scripted steering and controlled food placement. Each case completed 360 passive steps and produced the same summary on replay.

All cases start at 30 viewers, ten per group, with impressions of 50 each. Vectors list gamers, social viewers and image fans in that order.

| Scenario | Final counts | Final total / peak | Final impressions | Accepted effects |
| --- | --- | --- | --- | --- |
| Passive model baseline | 28 / 28 / 28 | 84 / 84 | 50 / 50 / 50 | No inputs or Snake collision |
| Achievement focus | 63 / 29 / 29 | 121 / 121 | 69 / 50 / 50 | Milestones 5, 10, 20. Rewarded records 6, 11, 21. One competitive reaction |
| Communication focus | 28 / 34 / 28 | 90 / 90 | 50 / 50 / 50 | Six ordinary answers selected for their social effect |
| Repeated loss and style | 28 / 27 / 27 | 82 / 82 | 46 / 50 / 50 | Eleven collisions, milestone 5, three competitive loss reactions. Two grant positive effects and the third is suppressed |

The model-only baseline shows organic growth at neutral impression. Achievement play ended with 31 more viewers than communication play, while communication retained five more social viewers. These scripted strategies exercise different event patterns. The comparison measures model behavior and repeat protection. Player comfort, social-choice salience and combined balance remain open for the later playtest. No provisional coefficient was changed.

In the configured minimum-size game window, the three group rows, total and peak were visible alongside the board and scrollable chat. A collision displayed its measured impression changes of −2, −1 and −1. After 32 seconds the live total and peak reached 33. The audience strip uses small text. Readability while actively steering and interpretation by a player remain open. The frozen audience summary was verified by the feedback runner. An initial Windows security prompt from launching through Start-Process may remain. Direct console invocation successfully launched and closed the test game window.
