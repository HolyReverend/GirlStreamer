# Documentation router

Choose a route based on the task. Read only the relevant files, not the whole folder.

## Game design

Use [GameDesign/](GameDesign/) for concepts, mechanics, gameplay rules, and player experience.

- [ConceptDesign.md](GameDesign/ConceptDesign.md): game concept.
- [Iteration02Scope.md](GameDesign/Iteration02Scope.md): agreed second-iteration scope: one complete stream with placeholder webcam, chat, choices, audience and donations.
- [Mechanics/](GameDesign/Mechanics/): individual gameplay systems; select files by topic.

Game design documentation is written in clear, simple Russian.

## Technical work

Use [Technical/](Technical/) for the roadmap, implementation stages, architecture, and technical implementation guidance. Select the document matching the task as these documents are added.

- [Iteration01ImplementationPlan.md](Technical/Iteration01ImplementationPlan.md): first-iteration roadmap for Snake and keyboard quick-message responses, shared architecture, stage boundaries and focused checks.
- [Iteration02ImplementationPlan.md](Technical/Iteration02ImplementationPlan.md): second-iteration staged implementation plan, ownership, proposed tuning and acceptance checks.
- [Architecture.md](Technical/Architecture.md): current file ownership, scene/data connections, implemented systems, and focused entry points. Read before Godot work; update affected entries after it.

Read [ImplementationRules.md](Technical/ImplementationRules.md) **only when working directly with the project engine**: engine code, assets, configuration, editor operations, builds, tests, or debugging. Do not load it for documentation-only tasks or game design discussions.

Technical documentation is written in English.

## Tasks spanning both areas

Read both areas only when the task depends on both gameplay intent and technical details. For example, implementing a mechanic requires its specific design document and the relevant technical documents. A technical task does not require unrelated game design documents.
