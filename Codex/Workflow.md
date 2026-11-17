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

## Local work reports

- For every task, create a brief Markdown report in each affected category: `Reports/Project/` for engine/source/assets/configuration, `Reports/Doc/` for documentation, and `Reports/Codex/` for agent rules/tooling and repository workflow. Do not create empty reports for untouched categories. For work without file changes, use the task's category and state that no files changed.
- Name reports `Report_WorkType_YYYY_MM_DD_HH_mm_JobName.md`, with WorkType `Project`, `Doc` or `Codex`, local Europe/Moscow time in 24-hour format, and a short English PascalCase job name. Use zero-padded date/time fields. Add a distinguishing word to JobName on collision; never overwrite another report.
- Keep reports extremely brief and factual: changed files/areas and purpose, checks actually run, and material unresolved issues or NotRun checks. Do not copy plans, tool transcripts or full diffs. Use English, as for other technical documentation.
- Reports are write-only by default. Never open, read, search, index or use their contents as context without an explicit user request. Exclude `Reports/` and `Report_*.md` from broad searches. The sole routine exception is reading unmarked reports when preparing an authorized commit, as specified in Git.md.
- Never read or otherwise consult reports ending in `_commited.md`, including during commit preparation. Git commits are the primary project change history.
- Keep current contracts and implementation/acceptance status in their owning documents; track unresolved questions, proposals and validation gaps in OpenItems cards with links from those documents. Historical execution/change records belong only in reports. Do not link reports from documentation or direct future agents to read them.
- All report files are Git-ignored. Historical records migrated on 2026-11-17 are created with `_commited` at the user's direction; their filename timestamp records migration time. Reports of the migration and rule changes themselves remain unmarked until committed.

## Open questions and proposals

- `Docs/OpenItems/Index.md` is the short active register; `Docs/OpenItems/Items/OI-NNN-ShortName.md` holds one focused issue or related decision. These documents are version-controlled, unlike reports. The index has only ID/title link, area tags and a concrete return trigger; no discussion or completed-item history.
- For routine tasks, select only index rows matching the affected area (for example `rg -n 'Audio|Iteration02' Docs/OpenItems/Index.md`). Do not read every card. At iteration/stage planning and before stage completion, review the entire short index for due items and acceptance blockers. For an explicit user inquiry, select the requested rows/cards.
- Open a card only if it is relevant to the current task, its return trigger has occurred, or the user directly asks. Exclude `Docs/OpenItems/Items/` from broad searches unless that search is explicitly about unresolved items. Keep a pointer to the register in the documentation router; do not preload card contents into every task.
- A card contains Type (Problem, Question, Proposal or Validation), Status (Open, Deferred or Needs user decision), Area, Issue, Return trigger, Close when, and links to owning source documents. Keep it concise but preserve important alternatives and scope. Use a specific event/stage for return; use next-iteration planning for ideas with no narrower trigger. Deferred items still need a trigger.
- When discovering an unresolved item, check matching index rows to avoid duplicates, then create a card and row or update the existing card. Maintain one authoritative description in the card; keep a short status/link in the owning document. Do not turn ordinary implementation steps, every provisional number or already-accepted prototype choices into new issues.
- A proposal is not approved scope. A due trigger requires reassessment and, where needed, a user decision; it does not authorize implementation. Keep full-game questions separate from accepted iteration-specific contracts. Surface relevant blockers at handoff without listing unrelated items.
- To close an item, satisfy its close condition or record an explicit rejection/superseding decision. Transfer lasting decisions and current acceptance state to owning documents, remove incoming card links, then remove the card and its index row in the same change. Git holds history. Deferral alone does not close an item. Allocate new IDs from the index counter and advance it; never reuse closed IDs.
- Every work report may note created/updated/closed IDs, but never leave an actionable unresolved item only in a write-only report. Keep reports under the existing access restrictions.
