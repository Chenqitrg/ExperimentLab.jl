# Examples

Read these short files in order:

1. [Run](01_run.jl): define a calculation and fetch its final answer.
2. [Pause](02_pause.jl): pause at a step boundary and continue.
3. [Nest](03_nested.jl): compose calculations and print their progress.
4. [Record](04_recorded_run.jl): bind a session to an execution record and its log.

Each file activates the shared ExperimentLab examples environment and can run
independently in VS Code or with `include`. Variables remain available in the
REPL. ResumableFunctions macros are imported directly from their owning package.

Cancellation, failures, and concurrency edge cases belong to the test suite.
Generator checkpoint integration is deferred to a separate review.
