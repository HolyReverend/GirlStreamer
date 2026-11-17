# Godot skill routing

Read this file only for Godot implementation, technical planning, review or debugging.

Use `godot-gamedev` once as the common workflow. It owns project context, version selection, scope, validation and handoff. Add only the specialist whose topic the task actually needs; being a GDScript project is not sufficient to load every skill.

| Task | Specialist |
| --- | --- |
| Typing, annotations, parser errors, coroutine semantics | `godot-gdscript` |
| Scene composition, instancing, ownership, paths, transitions | `godot-nodes-scenes` |
| Signal contracts, connections, groups, duplicate callbacks | `godot-signals-groups` |
| Resource schemas, loading, shared and per-instance data | `godot-resources` |
| Control layout, themes, focus, mouse filtering | `godot-ui-control` |
| Save/load, version migration, slots, corruption recovery | `save-systems` |
| Headless test implementation, runner failures, CI | `godot-gdscript-headless-testing` |

A task may need multiple specialists when it crosses their actual responsibilities. Load optional references only for the specific API or pattern being used. Running an existing check does not require reading the entire testing skill. Ordinary documentation wording and engine-neutral game design need no Godot skill. Use the existing documentation router for task documents and GodotMCP.md only for editor access.

Project rules remain authoritative. Preserve Godot 4.7 Standard / GDScript and existing architecture; skills do not authorize upgrades, new Autoloads, test frameworks, device support or cloud saves. Choose verification proportional to the changed behavior. Inspect live editor state before engine operations and follow the single-editor rule.

## Installation and maintenance

Seven adapted skills are installed under `C:/Users/DrDre/.codex/skills/`, each in its named directory. The existing `godot-gamedev` was not changed. The new skills should be discoverable on the next turn; if a chat still has a stale catalog, reopen it and confirm the catalog before use.

Source: https://github.com/gamedev-skills/awesome-gamedev-agent-skills, commit `25eec57919aec2cfd87d4ef9ae5661832302585e`, Apache-2.0. Each installed directory includes SOURCE.md, LICENSE and NOTICE. Preserve local adaptations when updating; do not overwrite them from upstream automatically.

Local adaptations: narrow discovery triggers, common workflow delegated to godot-gamedev, on-demand technical references, conditional verification, corrections to lifecycle/typing/resource examples. Unsafe save/test templates and both bundled executable checkers were omitted. These skills provide guidance, not a runtime integration.

Installed file inventory and hashes: [GodotSkillsInstallation.json](GodotSkillsInstallation.json).

Discovery follow-up: [OI-004](../Docs/OpenItems/Items/OI-004-SkillDiscovery.md); check only when the relevant skills are needed.
