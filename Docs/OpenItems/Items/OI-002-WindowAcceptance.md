# OI-002: Complete standalone window and input checks

- **Type:** Validation
- **Status:** Open
- **Area:** UI, Input, Iteration02
- **Issue:** The iteration 02 roadmap still requires larger-window and physical-mute checks. The Stage 7 protocol also requires standalone lifecycle/closing inspection; do not infer human coverage from headless tests.
- **Return trigger:** Before final iteration 02 acceptance, or when changing stream layout/input.
- **Close when:** Run the Stage 7 standalone protocol at 1024×768 and a larger window using physical input; inspect goodbye, results, mute, pause/resume and restart. Update the owning plan with actual acceptance or concrete remaining failures.
- **Source:** [Owning document](../../Technical/Iteration02/Stage07CompleteStream.md).
