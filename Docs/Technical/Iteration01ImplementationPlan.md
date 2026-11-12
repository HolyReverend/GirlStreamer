# Iteration 1: Snake and Quick Messages — Implementation Plan

Date: 2026-11-12. Status: proposed technical roadmap; no implementation or playtest acceptance implied.

**Goal:** Build a playable Godot prototype to assess whether a player can read short questions and select one of three answers while controlling Snake.

**Architecture:** Compose a session scene from an independent Snake scene, a quick-message controller and a small HUD. Keep grid rules separate from presentation; the session owns lifecycle and connects local systems through typed commands and signals.

**Tech stack:** Existing Godot 4.7 Standard project, typed GDScript, 2D drawing and native Control UI. Preserve the current Compatibility renderer and stretch configuration.

**Sources:** [Minigames](../GameDesign/Mechanics/Minigames.md), [Streaming gameplay](../GameDesign/Mechanics/StreamingGameplay.md), and the session timing section of [Core gameplay loop](../GameDesign/Mechanics/CoreGameplayLoop.md). The user's first-iteration scope takes precedence over the broader mechanics.

This overview defines the completed iteration. The five linked stage plans define successive increments: implement only the current stage, then apply later stages' explicit interface/behavior migrations. Temporary Stage 1–2 boundary behavior is not the final collision rule. When resuming a later stage, use the latest applicable contract rather than reapplying an earlier signature or test expectation. Read the project workflow and engine implementation rules before engine work.

## Scope and prototype choices

Include Snake movement, food and growth, collisions and retries, a bounded session, conditional-free questions, keyboard answers and basic results for evaluation. Use geometric graphics and short placeholder text.

Exclude background chat, donation priorities, event-driven reactions, character animation, audience, economy, skills, condition, daily loop, saves, other minigames and production art. Answers have no correctness score, rewards or gameplay consequences. A missed answer simply expires in this experiment; this does not decide the final game's question penalties.

The following are proposed experiment settings, not previously approved game-design rules:

| Decision | Initial prototype behavior |
| --- | --- |
| Snake arena | One bounded rectangular grid, lethal walls and self-collision, no obstacles or wraparound. |
| Movement | Arrow keys or WASD; constant adjustable tick interval, initially 0.20 seconds. No automatic speed ramp. |
| Growth | One food item in a free cell; eating adds one segment and one point. |
| Attempts | Unlimited retries; Space starts a fresh attempt after collision or board completion while the session remains active. Reset body and attempt score, retain session time, totals and any open question. |
| Session | 360 seconds by default; immediate stop at expiry, with no overtime in this experiment. This deliberately simplifies the design's proposed round-boundary ending. |
| New session | A fresh Enter press on results resets the whole session; Space never serves this purpose. |
| Questions | Short, unrelated prompts, e.g. “Pick a color” with “Red / Green / Blue”; exactly three answers, numbered 1–3. |
| Message timing | Initially a 5-second response window and a 45-second gap after resolution; first question after 45 seconds. These are tuning values, not the reaction QTE's proposed 3-second rule. |
| Controls | Top-row 1, 2, 3 select answers; no typing, mouse selection or device expansion required. |

The staged-field/exit proposal for Snake remains a later experiment. First measure a simpler Snake baseline and its compatibility with messages. If continuous movement makes answering impractical, record that result and consider stages in the next iteration rather than silently adding them here.

## Scene structure and ownership

Planned files below are relative to `GirlStreamer/`; `res://` points to that directory. The initial planning inspection found configuration and the editor integration plugin, without gameplay scenes or a main scene. This is historical planning context, not proof of current engine state; inspect it before implementation. These paths describe the planned systems.

| Files | Responsibility |
| --- | --- |
| `prototype/prototype_session.tscn`, `prototype_session.gd` | Root composition, start/finish/restart, session clock, attempt totals and message-enabled test setting. |
| `prototype/snake/snake_game.tscn`, `snake_game.gd` | Snake lifecycle, movement input, fixed-step advancement and notifications. |
| `prototype/snake/snake_state.gd` | `RefCounted` grid model: `Array[Vector2i]` body, direction, food, collision and score rules; no UI or scene-tree access. |
| `prototype/snake/snake_board.gd` | Node2D child drawing the grid, body and food from model state; no authoritative rules. |
| `prototype/messages/quick_messages.gd` | Node owning question schedule, current question, response deadline, number-key input and resolution. Small typed placeholder content lives here initially. |
| `prototype/ui/prototype_hud.tscn`, `prototype_hud.gd` | Control layout for board space, time/score, message text/options/countdown, attempt prompt and final summary. |
| `project.godot` | Register the main scene and named Input Map actions when the relevant stage needs them. |

The root owns `SnakeGame`, `QuickMessages` and the HUD. Reserve separate board and message regions with Containers; place the board renderer in its reserved region and derive drawing scale from that region. Questions must never cover playable cells. HUD presentation does not own timers or gameplay state.

Use composition rather than an inheritance framework for hypothetical future minigames. No Autoload, global event bus, service locator or new test framework is needed. Editor-created scenes own their serialized children. Children do not search for siblings or access `/root` paths: the parent supplies dependencies and wires their notifications. This follows Godot's [scene organization guidance](https://github.com/godotengine/godot-docs/blob/master/tutorials/best_practices/scene_organization.rst).

## Shared contracts

- **Session lifetime:** `READY → RUNNING → FINISHED`. A new session resets every subsystem and all measurements. An attempt restart resets only Snake. Finishing stops movement and scheduling, closes the active question as cancelled, and shows results. Cancelled questions are excluded from the answered/expired denominator.
- **Snake lifetime:** `STOPPED → PLAYING → WAITING_FOR_RETRY`; retry returns to PLAYING, while session expiry uses generic stop to enter STOPPED without inventing an attempt outcome. A full board ends the attempt cleanly. The session alone authorizes retries while time remains.
- **Commands and events:** session commands start/stop/restart; Snake reports `score_changed(score: int)` and `attempt_finished(reason: StringName, score: int)`; messages report `question_opened(id: int, prompt: String, options: Array[String])` and `question_resolved(id: int, answer_index: int, elapsed_seconds: float, outcome: StringName)`. Indices are 0–2; use -1 for expired/cancelled. The HUD receives presentation updates, never changes the model directly.
- **Connections:** the root establishes cross-system connections once during setup, using typed references and named handlers. Restart reuses nodes and resets their state; it must not reconnect or leave delayed callbacks from the previous run.
- **Time:** advance Snake with a fixed-interval accumulator in `_physics_process(delta)`, independent of render FPS. The session owns elapsed session time; message deadlines use that clock. Check the deadline again when accepting an answer, so an answer at/after expiry cannot win a callback-order race. No message modifies `Engine.time_scale` or pauses the tree.
- **Input:** Snake owns four direction actions; QuickMessages owns three answer actions; PrototypeSession owns Space retry and Enter new session. All ignore key echo. Accept at most one legal direction change per movement tick, rejecting reversal against the committed direction. Do not let answer UI take keyboard focus. Consume only the owned event. Godot's [InputEvent guidance](https://github.com/godotengine/godot-docs/blob/master/tutorials/inputs/inputevent.rst) describes event propagation and echo handling.
- **Message lifetime:** `IDLE → OPEN → IDLE`, with one resolution per question. No queue or overlapping questions. Time and an already open question continue while Snake waits for retry; defer new questions until Snake is playable again, without accumulating overdue messages. Session finish has priority over answering or retrying.
- **GDScript and tuning:** typed fields, parameters, return values and signals; `snake_case` files/members and `PascalCase` named classes. Use enums for local states. Export only meaningful settings with ranges and units. Keep mutable state on its owner, separate from content/settings; avoid a shared mutable Resource for session state. No custom Resource schema is necessary for this small placeholder set.

### Integration boundaries

| Owner | Final responsibility / change point |
| --- | --- |
| SnakeState | Grid rules and terminal reason. Stage 2 extends reset with an injected RNG and adds food to snapshots; Stage 3 adds terminal queries while preserving `step() -> bool` as “body moved.” |
| SnakeGame | Attempt-local validated grid/tick settings, accumulator and typed notifications. Stage 3 replaces the initial running flag with an enum; Stage 4 adds session authorization before input/each step. |
| PrototypeSession | Session clock, retry/new-session authorization and all aggregate measurements. Stage 5 uses a single authorized time sample per message decision/update. |
| QuickMessages | Question schedule/input/outcome only. Attempt reset never touches it; full session finish cancels once before the results snapshot. |
| PrototypeHUD | Presentation only. Board rectangle is reported in canvas-global coordinates and converted once by Board; gameplay-time decisions never live here. |

The completed finish sequence is: mark session FINISHED, stop Snake, synchronously cancel any open question and account that cancellation, then publish frozen results. Earlier stages have only the relevant subset. Snapshot grid/tick tuning per attempt and session/message tuning per session; mid-run Inspector edits do not bypass validated values. Support one prototype window size of at least 1024×768; this is a layout constraint, not a device matrix.

## Implementation stages

Each stage delivers one mechanic and its directly required scene/UI wiring. Linked stage documents provide available details; other filenames are planned follow-ups.

### 1. Grid movement and steering

- [x] Create the Snake scene/model/renderer and minimal runnable session composition; configure main scene and movement actions. Implement fixed-tick movement, one buffered turn and reverse rejection.
- **Deliverable:** visibly controllable Snake on a readable grid, with no food or messages yet.
- **Focused check:** short model assertions for reverse rejection and two direction inputs within one tick; editor play verifies keys and consistent movement pacing at two render frame rates.
- **Detailed plan:** [Stage01SnakeMovement.md](Iteration01/Stage01SnakeMovement.md).

### 2. Food collection and growth

- [ ] Add food spawning, growth and attempt score; draw food and update the HUD from Snake notifications. Inject a controllable random seed for repeatable rule checks.
- **Deliverable:** a playable collection loop that grows the body.
- **Focused check:** eating grows exactly once and increments score once; food never occupies the body, including the final free cell. Handle a full board without an endless search.
- **Detailed plan:** [Stage02FoodAndGrowth.md](Iteration01/Stage02FoodAndGrowth.md).

### 3. Collisions and retrying an attempt

- [ ] Add wall/self collision, stopped-attempt feedback and Space retry. Reset all attempt state; distinguish moving into a tail cell that vacates this tick from colliding with a retained body cell.
- **Deliverable:** failure and quick recovery without reloading the whole session scene.
- **Focused check:** wall collision, body collision and the vacating-tail case; one manual retry verifies a fresh body/food/score and no stale buffered turn.
- **Detailed plan:** [Stage03CollisionsAndRetries.md](Iteration01/Stage03CollisionsAndRetries.md).

### 4. Timed session and session results

- [ ] Implement session states, 360-second countdown, aggregate food/attempt results, finish and new-session restart. Enforce time limits during both active play and retry waiting.
- **Deliverable:** multiple attempts within one bounded session; final screen with a restart action.
- **Focused check:** use a shortened duration to verify retry preserves the deadline, expiry prevents further movement/retry, and a new session resets clock and totals exactly once.
- **Detailed plan:** [Stage04TimedSession.md](Iteration01/Stage04TimedSession.md).

### 5. Quick questions and keyboard answers

- [ ] Add the message controller and reserved HUD area, placeholder prompts, three numbered options, scheduling, response deadline and brief answer/expiry feedback. Enable an Inspector switch for a message-free baseline.
- **Deliverable:** answers by 1/2/3 during uninterrupted Snake play, with neither rewards nor contextual links.
- **Focused check:** manually steer while answering each option and confirm the board stays visible and speed stays unchanged. A small controller check verifies single resolution under repeated input, expiration, no overlap and cancellation on session finish; retry must not reset an open question.
- **Detailed plan:** [Stage05QuickMessages.md](Iteration01/Stage05QuickMessages.md).

## Iteration evaluation

Evaluation is the acceptance activity for the combined prototype, not another feature stage. Add only local, in-memory measurements to the existing session/message owners: questions shown, answered, expired and cancelled; response time per answered question; collisions/attempts and food collected. Show a compact summary. Do not build analytics infrastructure, persistence or automatic difficulty adjustment.

Play one six-minute session without messages and one with messages using the same Snake settings; record settings and subjective reading/steering difficulty. Compare response times and misses alongside collisions and collection rate. This is exploratory evidence, not statistical proof; no arbitrary answer-rate threshold is imposed before observing the prototype.

Record whether prompts can be read, all three keys can be used while steering, and mistakes feel recoverable. If interaction is too demanding, vary one of message frequency, response window, text length or Snake speed at a time and repeat only the affected experiment. Stage-based Snake remains a separate possible response to the findings.

## Verification limits and completion

Use a minimal engine-native assertion script for the small deterministic rule checks above, or an existing runner if one is introduced before implementation. UI and divided-attention checks require actual editor play. Do not add tests for excluded systems, exhaustive resolutions/devices, generic infrastructure or packaging to this iteration.

Each rule has one owning check: movement/turns in Stage 1, food/growth/full-board in Stage 2, collision/retry in Stage 3, session time/totals in Stage 4, question lifecycle/metrics in Stage 5. Later integration tests exercise the new boundary, not every earlier rule again. Replace or remove temporary checks when their behavior is superseded. Run earlier runners only when their owning code/contracts changed; the stage command lists identify relevant candidates, not a mandate to rerun the entire iteration after every edit. Validate a new runner's failure reporting once, then reuse it.

For each implemented stage, parse/load the touched scripts and scenes with the project's actual Godot 4.7 binary, run that stage's focused checks, and record the outcome. Verify exact APIs against the installed version; the official documentation links above explain architecture, not proof of local 4.7 runtime behavior. Readability and game feel cannot be accepted from a successful headless run.

Iteration completion means the five mechanics work together, the focused checks pass, and the paired playtest findings are recorded with remaining tuning decisions. It does not mean the complete streaming mechanic or final game balance has been validated.
