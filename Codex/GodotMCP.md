# Godot MCP

Read this file only when connecting to or troubleshooting the Godot editor.

## Setup

- Engine: Godot 4.7.2 Standard, GDScript, GL Compatibility.
- Editor: `C:/Program Files (x86)/Godot/Godot_v4.7.2-stable_win64.exe`.
- Project: [project.godot](../GirlStreamer/project.godot).
- Server: [Funplay MCP 0.10.1](https://github.com/FunplayAI/funplay-godot-mcp), MIT, pinned commit `ec595d2d9b3e664bf7d15064f140f121c07e7d97`.
- Addon: [plugin.cfg](../GirlStreamer/addons/funplay_mcp/plugin.cfg), enabled in the project.
- Codex server: `godot_girlstreamer`, configured only for this project in [.codex/config.toml](../.codex/config.toml).
- Launcher: [launch.mjs](Tools/FunplayMCP/launch.mjs), using `C:/Program Files/nodejs/node.exe` and the pinned upstream stdio wrapper.

## Use

1. Open this project in Godot and keep its editor running. The addon starts automatically.
2. Restart Codex after the initial configuration so it loads the new MCP tools.
3. Call `get_project_info` and confirm the project root before making changes.

Use MCP for live editor inspection and changes. File-only tasks can use normal filesystem tools. Keep normal task authorization and project rules in force.

The core profile exposes 78 tools, including scene inspection, scripts, play controls, and `execute_code`. Discover schemas before use. Do not generate replacement agent instructions through the plugin.

The runtime bridge is not installed as an autoload. Live game inspection/input tools may require it; enable and validate it when a gameplay task needs it. Do not assume editor connectivity proves game runtime behavior.

## Connection and troubleshooting

The addon listens on loopback only, initially `127.0.0.1:8765`, and requires authentication. The launcher reads its current port and token from `%APPDATA%/Godot/app_userdata/GirlStreamer/funplay_mcp_settings.cfg`. Credentials are not stored in the repository. Restart the MCP connection after rotating the token or changing the port.

If unavailable, check that the correct project is open and Funplay MCP is enabled under Project Settings → Plugins. Only one editor instance for this project should own the connection. Do not start a second editor against the same project for testing.

The launcher depends on the project user-data name `GirlStreamer`; update it if that name or the user-data location changes. Do not update the vendored addon independently of its wrapper without validation.

References: [upstream](https://github.com/FunplayAI/funplay-godot-mcp), [Codex MCP configuration](https://developers.openai.com/codex/mcp/).

Conditional runtime-access follow-up: [OI-005](../Docs/OpenItems/Items/OI-005-McpRuntime.md); check when a task actually needs live gameplay tools.
