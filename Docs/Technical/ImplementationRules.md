# Engine implementation rules

## When to read

Read this file only when working directly with the project engine: code, assets, configuration, editor operations, builds, tests, or debugging. It is not required for documentation-only work or game design discussions.

## Engine

- Use Godot 4.7 Standard with GDScript. The installed editor is 4.7.2; do not switch to .NET or upgrade the engine as a side effect.
- For live editor access or MCP troubleshooting, read [GodotMCP.md](../../Codex/GodotMCP.md).

## Before changes

- Read [Architecture.md](Architecture.md) first to locate the relevant systems and their owning files, then inspect only the sources needed for the task.
- Work inside `GirlStreamer/` for engine files. Keep documentation in `Docs/` and agent workflow files in `Codex/`.
- Inspect the actual project, engine version, existing implementation, and relevant local instructions before choosing an approach.
- Read only the technical documents and specific gameplay rules needed for the task.
- Check existing changes and editor state before acting. Preserve unrelated user work.

## Implementation

- Follow the project's existing architecture and conventions. Keep changes focused on the requested behavior.
- Do not invent gameplay requirements. Ask about unresolved decisions that materially affect implementation; continue independent work where possible.
- Use tools and APIs compatible with the actual engine version.
- Keep code and comments clear and concise. Explain purpose and non-obvious constraints rather than restating code.

## Verification and handoff

- After every Godot task, review [Architecture.md](Architecture.md) and update it to reflect changed files, responsibilities, connections, contracts, tests, and implemented systems. Do not present planned systems as implemented. If no architecture update is needed, state that in the handoff.
- Run checks appropriate to the change: build, focused tests, or editor checks as needed.
- Distinguish verified results from assumptions and checks not run. Do not claim success without evidence.
- Update affected technical documentation and link to existing design rules instead of duplicating them.
- Report changed files, checks performed, remaining limitations, and any required user decisions.
