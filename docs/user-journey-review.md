# User journey review — 2026-11-07

Reviewed ExperimentLab after reorganizing its API declarations into four area
entry points. The review exercised public user operations, not internal test
fixtures. No runtime behavior was changed during this review.

## Journey exercised

1. Define a configuration with `@option`, construct it with `@config`, update one
   field through Accessors, copy the displayed tree back into `@config`, and
   write/read its JSON representation.
2. Register the configuration and start a recorded generator Session.
3. In its callback, create each StateRef, save an independent snapshot, measure
   that snapshot and log its identity.
4. Pause after the first step. Read the flushed log, saved tensor and typed
   measurement result while the driver remains paused.
5. Resume, fetch the result and verify automatic execution completion. Mutate
   the returned array and confirm earlier snapshots remain unchanged.
6. Repeat the same configuration and verify separate execution identities/logs.
   Cancel another paused run and provoke an algorithm failure; inspect both
   terminal records without affecting earlier successful results.
7. Remeasure an existing snapshot under an explicit measurement log scope.
8. Reopen the store, inspect its Ref tree and JSON description, then exit the
   writer process and restore data in a new Julia process that loads only the
   defining types and the stored directory.
9. Read the index, result JSON and JSON Lines logs with Python's standard library;
   verify execution ownership and measurement/snapshot links without loading Julia.

## Results

| Check | Result |
| --- | --- |
| Full package suite | 773 assertions passed, including cooperative and threaded execution |
| Combined user journey | 36 assertions passed |
| Fresh-process typed restoration | 14 assertions passed |
| Independent JSON-only inspection | 8 record checks passed |
| Representative examples in fresh processes | 12 scripts passed |
| Configuration walkthrough in one REPL-like process | Files 01–06 passed sequentially; variables remained accessible |

The 12 independent scripts covered configuration definition, scattered updates,
JSON interchange, measurements, retention, reference trees, all four execution
examples, structured events, and explicit execution logs. They launched from
`/tmp` without preselecting the package environment, so their own setup had to
activate the required dependencies.

Examples and the combined journey used one Julia thread and one BLAS thread.
The package suite used two Julia threads and one BLAS thread. Inputs were tiny
arrays; no MPS optimization or LoopTNR workload was run. VS Code's actual UI and
selection-evaluation extension were not automated; file execution and shared
process behavior were tested directly in Julia.

## Usability findings

No functional blocker appeared in the original journey. Its two usability gaps
were subsequently addressed:

- `ExperimentLab.describe(session)` now returns JSON-ready live status, control
  request, result availability, error summary and optional store/execution identity.
  It does not wait, read disk or include numerical payloads. The persisted tree
  remains available through `describe(store, session.execution)`.
- `measure!` now automatically opens the attempt's own log and restores its caller's
  logger on exit. Ordinary calculation failures retain their logs; infrastructure
  failures propagate. The log closes before an outcome is published. Child tasks
  must be awaited inside the calculation.

Focused regression tests cover nested ownership, awaited child tasks, empty logs,
calculation and logging failures, and live Session descriptions. The updated
examples are `data/02_measurements.jl` and `execution/04_recorded_run.jl`.
After these changes, the full package suite passed 816 assertions (two Julia
threads, one BLAS thread), and both updated examples passed in fresh processes.

## Audit artifacts

Temporary scripts and captured output are in
`/tmp/experimentlab-journey-review/`: `types.jl`, `run.jl`, `reopen.jl`,
`verify.py`, and the corresponding logs. These are local audit artifacts, not
new package dependencies or a permanent second test framework.
