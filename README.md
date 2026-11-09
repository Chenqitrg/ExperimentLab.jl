# ExperimentLab

ExperimentLab connects an algorithm's **configuration, execution, saved data and
logs** in Julia. It helps you answer: *What settings produced this result? Which
run and step did it come from? Where are its data and logs?*

You supply the numerical algorithm and measurement definitions. ExperimentLab
provides the surrounding workflow, with no dependency on tensor or MPS packages.
It is under active development; the API and storage format may change.

## Quick start

Requires Julia 1.12 or later. From this checkout, instantiate the environment:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=.
```

Paste the following into that Julia REPL. This small calculation adds the numbers
1 through 3, saves each partial sum, and writes a log associated with the run.

```julia
using ExperimentLab, ResumableFunctions
using Configurations: @option

@option struct SumSettings <: AbstractAlgorithmConfig
    steps::Int = 3
end

@resumable function partial_sums(settings::SumSettings)
    total = 0
    @info "Calculation started" steps=settings.steps
    for step in 1:settings.steps
        total += step
        @yield (step=step, total=total)
    end
    return total
end

settings = SumSettings()
store = DataStore(mktempdir()) # Temporary demo directory; use a lasting path for real data.
algorithm = ExperimentLab.record_algorithm!(store, settings; label="partial sums")

session = start_run(store, algorithm, partial_sums(settings);
    onstep=(session, progress) -> begin
        state = record_state!(store, session.execution; step=progress.step)
        save_snapshot!(store, capture(state, progress.total))
        @info "Step completed" step=progress.step total=progress.total
    end)

fetch(session) # 6; waits for completion, including log closure and record updates.
ExperimentLab.showtree(store)

record = ExperimentLab.info(store, session.execution)
println(read(joinpath(store.path, record["log_path"]), String))
```

`@option` defines the configuration type. `@resumable` and `@yield` turn your
calculation into a generator that reports progress at points you choose.
ExperimentLab advances it in a Julia Task and calls `onstep` for each yielded value.
The final `return` value is obtained with `fetch(session)`.

Saving is explicit: `record_state!` creates metadata, `capture` makes an independent
copy, and `save_snapshot!` writes it to disk. Yielding a value alone does not save it.
To run without records or files, use `start_run(partial_sums(settings))`.

Stateful algorithms can subtype `AbstractAlgorithmState` and extend
`ExperimentLab.algorithm_steps(state)` with a resumable generator. Both PMPSLab
and LoopTNRLab use this interface, so their states run through
`start_run(algorithm_steps(state); onstep=...)`. State fields, progress values and
snapshot restoration remain algorithm-owned; ordinary generators such as the
example above still work. See [the algorithm state protocol](docs/execution.md#algorithm-state-protocol).

## How the pieces fit

A **Session** is a live, in-memory controller for one running generator. A **Ref**
identifies a stored record. A **DataStore** is the directory containing those
records, payloads and logs. A Session started with a store exposes its run as
`session.execution`.

Stored records form an ownership tree:

```text
DataStore
└─ AlgorithmRef                 configuration registered once
   ├─ ExecutionRef              one run using that configuration
   │  ├─ StateRef               state produced at a particular step
   │  │  ├─ SnapshotRef         saved copy of that state
   │  │  └─ MeasurementRef      measurement configuration, outcome and result
   │  └─ StateRef               another step
   └─ ExecutionRef              another run using the same configuration
```

Each execution and measurement has its own log path. Logs belong to those records;
they are not additional tree nodes. A run can also refer to an earlier state as
its input, and a measurement can refer to a saved snapshot. These are cross-links,
so the ownership tree remains unambiguous.

| Part | What you use it for | Start here |
| --- | --- | --- |
| Configuration | Define typed settings, construct nested values with `@config`, read/write JSON | [Configuration walkthrough](examples/config/README.md) |
| Execution | Start a generator, pause/resume/cancel at its boundaries, obtain its final result | [Minimal run](examples/execution/01_run.jl) |
| Data | Save selected states, run measurements, restore typed Julia results, inspect their origin | [Snapshots](examples/data/01_snapshots.jl), [measurements](examples/data/02_measurements.jl) |
| Logging | Associate ordinary `@info` messages with a run or measurement; optionally validate structured events | [Recorded run](examples/execution/04_recorded_run.jl), [event schemas](examples/logging/01_structured_events.jl) |

### Configuration and measurements

Define settings with `Configurations.@option`. Ordinary constructors work, and
`@config` provides a tree-shaped alternative. For the type above:

```julia
settings = @config """
SumSettings
└─ steps: 5
"""
```

A measurement supplies a configuration subtype of `AbstractMeasurement`, a result
subtype of `AbstractMeasurementResult`, and a `measure(definition, input)` method.
`measure!` records the attempt, opens its log, runs that method, and saves the
outcome. It accepts a current state or an existing snapshot. `load_result` restores
the Julia result type; `ExperimentLab.load_result_data` reads its JSON representation.
See the [complete measurement example](examples/data/02_measurements.jl).

### Control, storage and inspection

- `pause!`, `resume!` and `cancel!` control a Session at generator boundaries.
  Pausing keeps the Julia process and Task alive. Saved snapshots do not serialize
  the generator's execution position. See [session lifecycle](docs/session_lifecycle.md).
- Configuration objects, snapshots and typed results use **JLD2**. The index and
  portable measurement results use **JSON**; logs use **JSON Lines**. Native loading
  requires the defining Julia types in a compatible environment.
- `start_run(store, algorithm, generator)` owns the execution log automatically.
  `measure!` temporarily selects its own measurement log, then restores the caller's
  logger. Every message is flushed; output failures propagate. See [log ownership](docs/log-binding.md).
- Storage and measurement calls are synchronous. Applications choose when to save
  and how to schedule background work. Use one coordinated `DataStore` writer per
  directory, and await child tasks before leaving their log scope.
- `ExperimentLab.showtree(store)` displays the stored relationships.
  `ExperimentLab.describe(store)` returns JSON-ready metadata without loading
  numerical payloads. `ExperimentLab.describe(session)` reports live status and
  storage identity without waiting for completion.

## Review and explore

Start with [execution/01_run.jl](examples/execution/01_run.jl), then
[execution/04_recorded_run.jl](examples/execution/04_recorded_run.jl) to see what
adding storage changes. Continue with [data/01_snapshots.jl](examples/data/01_snapshots.jl)
and [data/02_measurements.jl](examples/data/02_measurements.jl). Review nested
configuration and structured events independently when you need them.

Examples can be run as whole files in VS Code or with `include`. Their setup
activates the examples environment. For selected execution, run setup and imports
first; the main walkthroughs leave variables available for REPL inspection.
The [example index](examples/README.md) lists the remaining features.

For source review, [src/ExperimentLab.jl](src/ExperimentLab.jl) includes four areas
in one module. Each area's entry file lists its API and implementation files:
[config](src/config/config.jl), [data](src/data/data.jl),
[logging](src/logging/logging.jl), [execution](src/execution/execution.jl).
Names marked `export` are imported by `using ExperimentLab`; names marked `public`
are supported APIs accessed with the `ExperimentLab.` prefix.

ExperimentLab builds on Configurations for defaults and dictionary conversion,
ResumableFunctions for generator mechanics, Julia Tasks for scheduling, JLD2 for
native storage, and Julia Logging with LoggingExtras/LoggingFormats for log output.
The package connects these facilities through record ownership and lifecycle rules.
[Migration notes](docs/migration.md) document the earlier package consolidation.

## Tests

From the repository root:

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project=. -e 'using Pkg; Pkg.test(; julia_args=["-O0", "--threads=2"])'
```

Tests cover configuration, storage, log ownership and failures, cooperative and
threaded execution, and package boundaries. They use small inputs and do not run
MPS or LoopTNR calculations.

## Acknowledgements

ExperimentLab grew out of the experiment-management needs of PMPSLab and
LoopTNRLab. We are grateful to the authors and contributors of
[TNRKit.jl](https://github.com/QuantumKitHub/TNRKit.jl) for the work that helped
inspire this effort.

The idea of separating algorithm configuration from the iterator that drives
execution comes from Zhengyuan Yue's [TRG implementation](https://github.com/Yue-Zhengyuan/TNRKit.jl/blob/9cc5088bcca55ff9c5a72403764acfe8e9ceeb21/src/schemes/trg.jl)
and its [Renormalizer iterator](https://github.com/Yue-Zhengyuan/TNRKit.jl/blob/9cc5088bcca55ff9c5a72403764acfe8e9ceeb21/src/schemes/renormalizer.jl)
in his TNRKit fork. We are grateful to him for sharing this design and for the
helpful discussions that informed this work.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
