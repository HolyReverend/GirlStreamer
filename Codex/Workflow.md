# Project workflow

## Folder layout

- `GirlStreamer/`: the engine project, source code, configuration, and game assets.
- `Docs/`: game design and technical documentation.
- `Docs/GameDesign/`: game concepts, mechanics, gameplay rules, and intended player experience.
- `Docs/Technical/`: roadmap, implementation stages, technical architecture, and implementation guidance.
- `Codex/`: agent instructions and other Markdown files used by Codex in this project.

## Reading and writing

- Before working, read only the documents required for the task. Follow the routes in [Docs/README.md](../Docs/README.md).
- Keep documentation and agent rules concise, specific, and easy to understand.
- Split distinct topics into focused Markdown files. Prefer links over duplicated content.
- Keep indexes short so an agent can choose relevant files without reading unrelated topics.
- Update affected documentation when agreed rules or implementation decisions change.
- Write all game design documentation in clear, simple Russian.
- Write all other documentation and agent rules in English. Use professional terminology when it improves clarity.

## Git

Read [Git.md](Git.md) only when the task requires Git operations or repository configuration, including staging, commits, branches, remotes, merges and pushes.

## Godot skills

For Godot implementation, technical planning, review or debugging, use [GodotSkills.md](GodotSkills.md) to select only the needed specialists alongside `godot-gamedev`. Documentation wording and engine-neutral game design do not require Godot skills.
