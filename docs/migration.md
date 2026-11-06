# Incremental migration

## Step 1: data and event schemas (current)

The source is taken from the current working trees of AlgorithmDataLab and
AlgorithmLogLab, including the latter's uncommitted simplification to event schemas.
ExperimentLab owns the implementations directly and depends on neither package.
The original directories remain untouched while their callers await migration;
they are migration checkpoints, not compatibility layers in ExperimentLab.
Do not make parallel feature changes in both implementations.

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

## Suggested next review steps

Each step should be reviewed before proceeding to the next:

1. Bind logs to the store and to an execution or measurement. Establish execution
   context before the first message; ordinary `@info "Experiment started"` must
   work before a state exists. Nested and asynchronous measurements must retain
   their own context. Use Julia Logging and existing output libraries.
2. Consolidate configuration and review vocabulary for both computational and
   laboratory experiments. Do not require tensor types in the infrastructure.
3. Consolidate execution lifecycle and review waiting, completion and failures.
   Decide separately which interactive session controls belong here.
4. Switch domain-package callers and retire the superseded package implementations.

These are planned boundaries, not features implemented by this migration.
