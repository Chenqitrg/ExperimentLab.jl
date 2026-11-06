# Incremental migration

## Step 1: data and event schemas (committed as 316b8f1)

The source is taken from the current working trees of AlgorithmDataLab and
AlgorithmLogLab, including the latter's uncommitted simplification to event schemas.
ExperimentLab owns the implementations directly and depends on neither package.
The original directories initially remained as migration checkpoints, not
compatibility layers in ExperimentLab. AlgorithmLogLab has since been retired
and its local directory removed: no other package depends on it, and its event
implementation, tests, and examples are owned here. AlgorithmDataLab remains
while its domain callers await migration. Do not make parallel feature changes
in the remaining duplicate data implementations.

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

## Suggested next review steps

Each step should be reviewed before proceeding to the next:

1. Automatically establish measurement log scopes inside `measure!`, using the
   explicit binding introduced in step 2a. Review nested and asynchronous ownership.
2. Review shared vocabulary for computational and laboratory experiments.
   Keep tensor types in domain packages.
3. Consolidate execution lifecycle and review waiting, completion and failures.
   Decide separately which interactive session controls belong here.
4. Switch domain-package callers and retire the superseded package implementations.

These are planned boundaries, not features implemented by this migration.
