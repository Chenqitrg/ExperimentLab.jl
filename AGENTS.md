# Repository instructions

- Do not change package versions unless explicitly requested; bump patch only.
- Code, documentation and examples are in English.
- Migrate in small reviewable stages. Do not add compatibility wrappers.
- This package owns experiment infrastructure; tensor and domain algorithms belong above it.
- Reuse Julia Logging and maintained logging libraries for generic logging mechanics.
- Keep examples at top level and runnable from VS Code and the REPL.
- Current stage: data storage and event schemas only. Configuration and execution consolidation are later stages.
