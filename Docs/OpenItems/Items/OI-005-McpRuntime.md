# OI-005: Validate MCP runtime access only when needed

- **Type:** Validation
- **Status:** Deferred
- **Area:** Codex, Godot, MCP
- **Issue:** The runtime bridge is not installed as an autoload. Editor connectivity does not establish game inspection/input capability; native connection must be checked against the actual project when used. No bridge installation is authorized by this card alone.
- **Return trigger:** When an authorized task requires MCP gameplay inspection/input, or after MCP configuration changes.
- **Close when:** Verify native project identity and the required capabilities. Enable and validate a runtime bridge only if needed within the task scope; document the supported route or a concrete limitation.
- **Source:** [Owning document](../../../Codex/GodotMCP.md).
