# Event schemas

Event schemas for algorithm diagnostics. This package owns stable event names,
field validation, explicit codecs and registry inspection. For binding messages
to execution or measurement files, see [record-bound logs](log-binding.md).
Julia and existing logging libraries provide message emission and formatting.

## Start here

```julia
using ExperimentLab

struct SweepCompleted <: AbstractLogEvent
    step::Int
    cost::Float64
    elapsed_seconds::Float64
end
registry = EventRegistry("looptnr.sweep.v1" => SweepCompleted)
event = SweepCompleted(3, 1e-8, 0.4)
record = event_record(registry, event)

record.event  # "looptnr.sweep.v1"
record.data   # (step = 3, cost = 1.0e-8, elapsed_seconds = 0.4)
```

The result is ordinary Julia data: a NamedTuple, not a Dict or JSON text.
Conversion validates values and copies nested collections; it does not emit a
log message, open a file or run an algorithm. The [main examples](../examples/logging/README.md)
focus on these responsibilities and use only this package.

## Three entry points

| Export | Responsibility |
| --- | --- |
| `AbstractLogEvent` | Base type for immutable diagnostic events |
| `EventRegistry` | Map concrete event types to stable names and special field types to codecs |
| `event_record(registry, event)` | Validate and return detached, JSON-ready `event` and `data` fields |

`describe` remains qualified: `ExperimentLab.describe(registry)` returns a
JSON-ready NamedTuple with sorted event/codec mappings. `display(registry)` is
for people. Neither executes codecs or exposes captured callable state.
External loggers use their own interfaces. The internal record-bound wrapper is
not another exported logger API or logger-inspection protocol.

## Event fields

Event types must be concrete, immutable and explicitly registered. Names and
types must be unique. Register concrete parameterized types separately. Treat
registries as read-only after construction; reuse them across log calls.

Supported values are `nothing`, booleans, strings, machine integers within the
exact frontend range `-(2^53-1):(2^53-1)`, finite Float16/32/64, and nested tuples,
named tuples and vectors of these values. Collections are copied. Encoding
rejects unsupported values, cycles and excessive nesting. It checks actual
values even when a field is declared `Any` or another broad type.

Custom objects are not traversed or stringified automatically. Supply an
explicit codec for complex numbers, custom numerical types or other special values:

```julia
registry = EventRegistry("solver.started.v1" => SolverStarted;
    codecs=(SolverName => (solver -> (; name=String(solver.value))),))
```

A codec must return supported plain values; opaque codecs are not chained.
The codec dictionary deliberately uses `Any` for heterogeneous callables at this
I/O boundary. Event fields remain typed NamedTuples before JSON serialization.

These guarantees apply to `event_record`'s output. Ordinary `@info` messages and
extra metadata need not use the event schema. Their formatting, including any
string fallback for unsupported metadata, belongs to LoggingFormats.

## Optional application integrations

The caller chooses what to do with the encoded record. For logging, Julia's
`@info` accepts its named fields; LoggingExtras and LoggingFormats handle output.
See the separate [integration examples](../examples/logging/integrations/README.md) for
terminal/JSON output, execution context and module routing. These illustrate
application-controlled composition separately from the event walkthrough.

## Review and tests

Start with [the five core examples](../examples/logging/README.md), then read `src/logging/events.jl`
and `src/logging/show.jl`. The binding implementation is in `src/logging/binding.jl`.
The main examples import ExperimentLab; LoggingExtras and LoggingFormats are
core dependencies used by the binding. JSON is also used by the data area.

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project=. -e 'using Pkg; Pkg.test(; julia_args=["--compile=min", "-O0", "--threads=1"])'
```

Tests cover schema validation, nested JSON values, terminal/file routing,
append/close behavior and shared-file context writes. They use small records,
not numerical calculations or tensor packages.
