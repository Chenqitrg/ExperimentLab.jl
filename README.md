# ExperimentLab

Julia infrastructure for experiments: configuration, execution, data and logs
share one package. Numerical algorithms, tensor types and instrument drivers
belong in applications or domain packages above it.

**Current stage: configuration, generator execution, data storage and record-bound logs.**
Configurations.jl supplies `@option` and dictionary conversion. ResumableFunctions
supplies generator mechanics; ExperimentLab controls their background sessions.
Execution and measurement records own log paths; `ExperimentLab.with_log` binds
ordinary Julia messages to one record. `start_run(store, algorithm, generator)`
creates an execution record, owns its log scope, and writes its terminal outcome.
`start_run(generator)` remains available for execution without storage.

## Start reviewing

1. For configuration, start with [00_define_options.jl](examples/config/00_define_options.jl)
   and the [configuration walkthrough](examples/config/README.md).
   For execution, start with [01_run.jl](examples/execution/01_run.jl), then
   [pause](examples/execution/02_pause.jl) and [nest](examples/execution/03_nested.jl).
   [04_recorded_run.jl](examples/execution/04_recorded_run.jl) adds automatic logs and a stored run.
   For data and events, run [01_data_and_events.jl](examples/01_data_and_events.jl). It uses a short
   vector and leaves every variable available in the REPL.
   Then run [02_execution_logs.jl](examples/02_execution_logs.jl) for the new binding.
2. Read [src/ExperimentLab.jl](src/ExperimentLab.jl): a single module includes
   `config/`, `execution/`, `data/`, and `logging/`; these are internal directories in one module.
3. Read [the migration notes](docs/migration.md) to distinguish moved code from
   actual changes. The detailed [data](docs/data.md) and [event](docs/logging.md)
   reference guides preserve the existing behavior.

Run the complete example directly in VS Code, or:

```julia
include("examples/01_data_and_events.jl")
display(store)
restored
diagnostic
```

The first line activates and instantiates the examples environment. For selected
code execution, run setup and imports first. No variables are hidden in a module.
See [examples/README.md](examples/README.md) for the individual feature examples.

## Current responsibilities

| Area | Responsibilities |
| --- | --- |
| `src/config/` | Tree construction and display, defaults from Configurations, JSON files |
| `src/execution/` | One generator driver Task, controls, results, and optional record/log ownership |
| `src/data/` | Reference ownership, snapshots, measurements, retention, native and JSON storage, inspection |
| `src/logging/` | Event schemas, record-bound file scopes, identity, synchronization and error propagation |
| Julia Logging and external logging libraries | Message emission, filtering, formatting and output |

`ExperimentLab.describe` is one qualified function with methods for stores,
references, captures and event registries. Everyday exports are the existing
data operations, `AbstractLogEvent`, `EventRegistry`, `event_record`, and the four
configuration entries: `AbstractAlgorithmConfig`, `@config`, `readconfig`, `writeconfig`.
Execution exports are `start_run`, `pause!`, `resume!`, `cancel!`, and `run_status`.
`Session`, status constants, record coordination and inspection remain qualified.
See [execution controls](docs/execution.md) and [session lifecycle](docs/session_lifecycle.md).

There is no new experiment object, scheduler, compatibility wrapper or tensor
dependency. A small internal logger wraps the library sink to attach identity and
propagate output failures. The existing `AlgorithmRef`
and `ExecutionRef` vocabulary remains until its own review step. Storage operations
are synchronous; applications decide when to capture states and wait for Sessions.

## Verification

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project=. -e 'using Pkg; Pkg.test(; julia_args=["-O0", "--threads=2"])'
```

Configuration, execution, data, and logging tests live in separate directories. Package-boundary
tests additionally verify that ExperimentLab loads none of the retired configuration/data/log packages,
ExecutionLab nor TensorKit. LoggingExtras and LoggingFormats are now direct
dependencies used for bound log output. Tests use tiny inputs, including injected
write/flush failures and overlapping log scopes.

## Configuration definitions

Define stored algorithm and measurement configurations with `Configurations.@option`
(and the appropriate abstract supertype). Their readable metadata contains the
plain nested dictionary from Configurations.jl, without constructor registries.
`load_algorithm` and `load_measurement` still restore native Julia values.
