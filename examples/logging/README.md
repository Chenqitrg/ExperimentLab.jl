# Review ExperimentLab itself

The main examples use only ExperimentLab. Follow one event from its Julia
struct to a registered, validated NamedTuple. There is no logging pipeline,
JSON formatting or file output to understand along the way.

| Example | What this package does |
| --- | --- |
| [01_structured_events.jl](01_structured_events.jl) | Define an event, register its stable name, and inspect `event_record` |
| [02_validation.jl](02_validation.jl) | Reject invalid field values and unregistered types |
| [03_field_codecs.jl](03_field_codecs.jl) | Explicitly convert a custom field to supported plain data |
| [04_nested_values.jl](04_nested_values.jl) | Encode nested containers and detach vector storage |
| [05_inspecting_registry.jl](05_inspecting_registry.jl) | Compare human registry display, `describe`, and one event record |

Start with 01. Variables such as `event`, `registry`, `record` and `description`
remain available at top level. Each file is independent. Event type names differ,
so all five can run in one REPL. Restart Julia after changing a struct definition.
Expected errors are caught for inspection or left as commented manual experiments.

## VS Code and the REPL

Run a complete file directly. Each starts with:

```julia
include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab
```

Setup activates the examples environment and instantiates its declared dependencies
without automatic bulk precompilation. It uses the file location, not the current
working directory. No packages are added to the core environment. The local,
Git-ignored VS Code settings may also select `examples`; they are not required.

For selected-code execution, run setup and imports first, then the desired
sections. Send each struct or try/catch definition as a complete block.

From the package root, either of these also works:

```sh
julia examples/logging/01_structured_events.jl
```

```julia
include("examples/logging/01_structured_events.jl")
record
record.event
record.data
```

## Optional application integrations

Only after reviewing the core, see [integrations](integrations/README.md) for
LoggingExtras/LoggingFormats composition. That directory has a separate project
and setup. Its dependencies are not required by any main example.
