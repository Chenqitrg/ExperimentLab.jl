# Incremental migration

## Step 1: data and event schemas (committed as 316b8f1)

The source is taken from the current working trees of AlgorithmDataLab and
AlgorithmLogLab, including the latter's uncommitted simplification to event schemas.
ExperimentLab owns the implementations directly and depends on neither package.
The original directories initially remained as migration checkpoints, not
compatibility layers in ExperimentLab. AlgorithmLogLab has since been retired
and its local directory removed: no other package depends on it, and its event
implementation, tests, and examples are owned here. AlgorithmDataLab was retained
until its domain callers migrated; the remaining retirement is recorded below.

| Original | Destination | Changes to review |
| --- | --- | --- |
| AlgorithmDataLab `src/*.jl` | `src/data/*.jl` | Package name in docstrings and one error message |
| AlgorithmLogLab `src/events.jl`, `src/show.jl` | `src/logging/` | Package name in documentation; `describe` joins the data methods |
| Both module entry points | `src/ExperimentLab.jl` | One module, existing exports/public functions, directory-qualified includes |
| Both test suites | `test/data/`, `test/logging/` | Import names and child-process project discovery |
| Log dependency-boundary tests | `test/boundary.jl` | Combined exports; JSON is now expected through the data area |
| Existing examples | `examples/data/`, `examples/logging/` | Import names and automatic example-environment setup |

There is no storage-format redesign in this step. The schema marker remains
`algorithm_data`; snapshot directories remain `tensors`. This preserves the moved
implementation, not an additional compatibility protocol. Native serialized Julia
objects still require the modules that define their types. This migration does not
promise interchangeability of types from the two old modules and ExperimentLab.

The event and result encoders remain separate because their contracts differ:
events preserve typed NamedTuples, while measurement results support dictionaries
and multidimensional arrays. Consolidating them is not required to move the code.

### Verification (2026-11-06, Julia 1.12.5)

- All 11 migrated implementation files match their source files after package-name
  substitution: 724 lines of data code and 139 lines of event code.
- 360 tests passed: 237 data tests, 109 event/integration tests and 14 boundary checks.
- All 16 examples passed in separate Julia processes launched from `/tmp`, including
  automatic environment setup and the three optional logging integrations.
- Tests and examples used one Julia thread and one BLAS thread. No tensor backend
  or domain algorithm was run. The old package working trees were not edited.

## Step 2a: explicit log binding (current)

- Execution and measurement records now contain relative `log_path` fields.
- Qualified `with_log(store, owner)` appends JSON Lines with automatic ownership
  and per-message flushing, reusing LoggingExtras and LoggingFormats.
- One small internal logger makes output failures propagate and synchronizes
  append positioning, writing and flushing across scopes sharing a store.
- Measurement calculation handling preserves direct and task-wrapped log failures.
- No execution lifecycle or automatic measurement log scope is introduced.

Review [the binding example](../examples/02_execution_logs.jl),
[the implementation](../src/logging/binding.jl) and [its contract](log-binding.md).
The new logging dependencies implement actual package functionality, not demo-only behavior.

Verification on Julia 1.12.5: all 408 package tests passed with one Julia/BLAS
thread; the 50 binding tests also passed with two Julia threads. All 17 examples
passed in separate processes launched from `/tmp`. The example setup now resolves
local checkout dependency changes before instantiation, including stale manifests
left from step 1. No domain algorithms were run and the version remains 0.1.0.

## Step 3: configuration consolidation

The configuration implementation now lives in `src/config/`, in the same module
as data and logging. `AbstractAlgorithmConfig`, `@config`, `readconfig`, and
`writeconfig` are exported from ExperimentLab. Author hooks remain qualified.
Configurations.jl still owns `@option`, defaults, and dictionary conversion;
Accessors remains the update interface. No compatibility module is retained.

JSON is already a runtime dependency, so configuration file reading/writing is
ordinary code; the old JSON extension and load-error fallbacks are removed.
MatrixAlgebraKit formatting/conversion remains an optional extension.
Configuration tests and examples moved into `test/config/` and `examples/config/`.

Domain callers now depend on ExperimentLab. This loads storage/logging libraries
alongside configuration, but creates no store, file, or task implicitly. The
legacy AlgorithmDataLab imports only configuration symbols from ExperimentLab;
ExperimentLab does not depend on it. Execution remains separate.

The old AlgorithmConfigLab checkout is retired after validating all callers.

`FormatLogger` now receives an ordinary formatting function, supported from
LoggingExtras 1.0.3 onward. This avoids imposing 1.2 on applications using other
logging consumers. No MPSKit dependency, version branch, or domain-specific logic
is added. Full ExperimentLab tests pass with both LoggingExtras 1.0.3 and 1.2.0.

Verification: 556 ExperimentLab tests, UpdateLab and legacy AlgorithmDataLab tests,
45 focused domain configuration checks, both MatrixAlgebraKit extension load
orders, and 34 examples passed. All checks used one Julia/BLAS thread; no
renormalization or MPS optimization was executed.

## Step 4: generator execution consolidation

The reviewed two-file ExecutionLab controller now lives in `src/execution/`.
ExperimentLab owns Session, its five lifecycle states, and the five control
exports. ResumableFunctions remains the only generator mechanism; macros are
imported directly by algorithm authors. No ExecutionLab dependency or alias module
is added. The three small examples and controller tests moved with the code.

Session and ExecutionRef still have separate lifetimes. Explicit callbacks can
record states, and starting a Session in `with_log` inherits that logger. Await it
before closing the scope; finish the stored execution explicitly. Automatic
lifecycle coordination remains a separate review step.

At this stage the old ExecutionLab checkout remained as a migration reference.
Domain callers still used its superseded run/observer/checkpoint protocol and
were already incompatible with the generator refactor. Their subsequent migration
is recorded below.

## Step 5: recorded Sessions

`start_run(store, algorithm_ref, generator)` creates a fresh execution and owns
its log scope through pauses and termination. Session exposes its store and
ExecutionRef. The driver closes the log and persists the terminal outcome before
publishing completion/cancellation; finalization failures produce FAILED and
retain the exceptions. Unrecorded execution remains available.

Progress is not automatically persisted. Callbacks can log values or explicitly
record/capture states. Measurement scoping and disk restart remain separate.
See [04_recorded_run.jl](../examples/execution/04_recorded_run.jl).

## Suggested next review steps

Each step should be reviewed before proceeding to the next:

1. Review the automatic measurement log scopes now used by `measure!`, including
   nested and awaited asynchronous ownership (see [record-bound logs](log-binding.md)).
2. Review shared vocabulary for computational and laboratory experiments.
   Keep tensor types in domain packages.
3. Review the recorded Session entry point and finalization contract.
4. Review the migrated domain generators and numerical snapshot storage described below.

These are planned boundaries, not features implemented by this migration.

## Step 6: retire duplicate packages and migrate domain callers

The AlgorithmDataLab and ExecutionLab directories have been removed from the
sibling workspace. Their Git histories remain in the local Trash. Active Lab
projects, sources and examples now use ExperimentLab; historical plans retain
their original names. No compatibility modules or old checkpoint readers remain.

- MPSSplitLab exposes `split_steps(state)`, which yields its existing SiteLog.
  The old SplitRun wrapper and execution extension are gone. Numerical snapshot
  validation and cache reconstruction now belong to `snapshot`/`restore_split`
  in MPSSplitLab, while ExperimentLab stores the resulting values.
- LoopTNRLab exposes `tnr_steps(run)` around its numerical RG stepper. Its active
  split is a SplitState, and its measurement interfaces come from ExperimentLab.
  Old observer dispatch and generic checkpoint registration have been removed.
- Both use ordinary `start_run(...; onstep=(session, value) -> ...)`, including
  recorded sessions. Pause/resume remains in memory. Restart from saved numerical
  data creates a new generator and Session; Task/generator serialization is absent.
- Domain examples use tiny inputs and leave variables available in the REPL.
  Dependency manifests are refreshed after removing the retired packages.

The fresh-process restart test also exposed an unstable type check: Julia's
ordinary type display changes when names are imported into Main. Stored algorithm,
measurement and result type labels now use fully qualified names, independent of
the caller's imports.

Package versions are unchanged.

Validation for this migration: ExperimentLab 822 assertions, MPSSplitLab 660,
and LoopTNRLab 514 pass. Both updated domain examples run independently. The
LoopTNR storage test restores a nested split boundary in a fresh Julia process.
MPSSplitLab source (including its former extension) shrank from 1,085 to 950
lines; LoopTNRLab source shrank from 1,595 to 1,414 lines.

## Step 7: remove split-owned diagnostic history

The domain migration now uses ExperimentLab beyond the Session wrapper:

- `SplitLog`, `SiteLog`, `SweepLog` and their history/replay machinery are removed.
  `SplitResult` contains `mps` and fixed-size `progress`; old tuple returns are gone.
- Split updates use a registered `mps.split.update.v1` event schema. The generator
  emits Julia log messages; recorded Sessions own the JSONL history and identity.
- Ordinary `split` uses the same ExperimentLab driver as controlled execution.
- `capture(ref, state)` dispatches to the domain `copy_state` method, producing a
  minimal numerical snapshot with one tensor copy. The separate public snapshot
  call is gone. `restore_split(saved, target)` uses the saved configuration.
- Convergence retains the previous selected error and a comparison counter, not
  all sweep errors. Restart rebuilds caches without replaying diagnostic history.
- LoopTNR now stores split summaries rather than nested site histories and uses
  direct capture as well. Its redundant MeasurementHistory wrapper is removed;
  outer RG measurements and RG history still remain in the domain package.

No compatibility aliases or package version changes are introduced.

Step 7 validation: MPSSplitLab 702 assertions and LoopTNRLab 497 assertions pass,
including fresh-process restoration. Updated numerical and recorded examples run.
MPSSplitLab now has 809 source lines; LoopTNRLab has 1,386. Across steps 6 and 7,
the two packages contain 485 fewer source lines than before migration.

## Step 8: compose LoopTNR directly from split and experiment services

LoopTNR now delegates site iteration through `@yieldfrom MPSSplitLab.split_steps`.
Its phase enum, manual stepping protocol, result container, log history and
measurement history are removed. The result is `(cell, completed_rg)`; measurements
use `ExperimentLab.measure!` in the application's callback. Normalization remains
a numerical LoopTNR setting.

`capture(ref, state)` stores a minimal TNRSnapshot containing the configuration,
committed cell, completed RG count and an optional MPSSplitLab snapshot. Restore
with `LoopTNRLab.restore_tnr(saved)`. No logs, measurement history, generators or
caches are included, and the split target is derived from the committed cell.

Recorded Sessions retain the execution and measurement history. Each site log is
written once by MPSSplitLab using its own fields; LoopTNR registers its own RG
boundary event. No outer logging context is passed into the split algorithm.
The numerical state contains no record refs.
See LoopTNRLab's `docs/execution-refactor.md` and its three focused examples.
