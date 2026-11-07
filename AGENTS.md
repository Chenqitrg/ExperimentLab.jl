# Repository instructions

- Do not change package versions unless explicitly requested; bump patch only.
- Code, documentation and examples are in English.
- Migrate in small reviewable stages. Do not add compatibility wrappers.
- This package owns experiment infrastructure; tensor and domain algorithms belong above it.
- Reuse Julia Logging and maintained logging libraries for generic logging mechanics.
- Keep examples at top level and runnable from VS Code and the REPL.
- Current stage: configuration, generator execution, data storage, event schemas and explicit log scopes. Recorded sessions bind execution logs and terminal records automatically; automatic measurement scoping remains a later stage.
- Bound logs append and flush every message; output errors must propagate through Julia Logging and measurement dispatch.
