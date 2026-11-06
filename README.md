# ExperimentLab

Julia infrastructure for experiments: configuration, execution, data and logs
will share one package. Numerical algorithms, tensor types and instrument drivers
belong in applications or domain packages above it.

**Current stage: data storage, structured diagnostic events and explicit log binding.**
Configuration still comes from AlgorithmConfigLab. Execution control has not
moved. Execution and measurement records own log paths; `ExperimentLab.with_log`
binds ordinary Julia log messages to one record. Automatic measurement scoping is
the next review step.

## Start reviewing

1. Run [01_data_and_events.jl](examples/01_data_and_events.jl). It uses a short
   vector and leaves every variable available in the REPL.
   Then run [02_execution_logs.jl](examples/02_execution_logs.jl) for the new binding.
2. Read [src/ExperimentLab.jl](src/ExperimentLab.jl): a single module includes
   `data/` and `logging/`; these are directories, not another pair of packages.
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
| `src/data/` | Reference ownership, snapshots, measurements, retention, native and JSON storage, inspection |
| `src/logging/` | Event schemas, record-bound file scopes, identity, synchronization and error propagation |
| Julia Logging and external logging libraries | Message emission, filtering, formatting and output |

`ExperimentLab.describe` is one qualified function with methods for stores,
references, captures and event registries. Everyday exports are the existing
data operations plus `AbstractLogEvent`, `EventRegistry` and `event_record`.
Coordination and inspection functions remain qualified.

There is no new experiment object, scheduler, compatibility wrapper or tensor
dependency. A small internal logger wraps the library sink to attach identity and
propagate output failures. The existing `AlgorithmRef`
and `ExecutionRef` vocabulary remains until its own review step. Storage operations
are synchronous; applications still decide when to copy, run tasks and wait.

## Verification

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project=. -e 'using Pkg; Pkg.test(; julia_args=["--compile=min", "-O0", "--threads=1"])'
```

The original data and logging tests live in separate directories. Package-boundary
tests additionally verify that ExperimentLab loads neither predecessor package,
ExecutionLab nor TensorKit. LoggingExtras and LoggingFormats are now direct
dependencies used for bound log output. Tests use tiny inputs, including injected
write/flush failures and overlapping log scopes.
