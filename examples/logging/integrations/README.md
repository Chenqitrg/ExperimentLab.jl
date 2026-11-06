# Optional logging integrations

These demonstrate application wiring, not ExperimentLab's own implementation.
Read the [main examples](../README.md) first. This directory has its own project
with Logging, LoggingExtras, LoggingFormats and JSON. Every script activates and
instantiates that environment via its first setup line; the main examples do not
install these dependencies.

| Example | External responsibility |
| --- | --- |
| [01_logging.jl](01_logging.jl) | Sample LoopTNR-style costs and elapsed times: terminal summaries and JSON Lines |
| [02_execution_context.jl](02_execution_context.jl) | TransformerLogger adds execution IDs around a shared sink |
| [03_module_routing.jl](03_module_routing.jl) | EarlyFilteredLogger and TeeLogger route exact modules |

Run a whole file, or first execute its setup/import lines before selecting sections
in VS Code. Variables remain available in the REPL. Returning to a main example
activates the main examples environment again.

ExperimentLab contributes only `event_record(registry, event)`. Its result is a
NamedTuple with `event` and `data`; splatting it into `@info` supplies those keywords.
Formatting, filtering, routing and writing belong to the other libraries.

The examples select `LoggingFormats.JSON(recursive=true, nest_kwargs=false)`:
numbers and containers remain structured, and extra fields appear at the top level.
LoggingFormats supplies `level`, `msg`, `module`, `file`, `line`, `group` and `id`.
The `id` identifies a log call site, not a unique event occurrence. Execution IDs
are supplied by the application. ExperimentLab generates no record UUID,
timestamp or log-envelope version; `.v1` in an event name is the author's schema
version. Ordinary metadata is formatted according to LoggingFormats' rules.

Files are opened with Julia's `open(path, "a") do ... end`, so they append and
close on exit. FormatLogger flushes by default. There is no ExperimentLab
recovery protocol for partial writes or damaged files. Error handling follows the
selected logger; validate with `event_record` outside `@info` when rejection must
propagate directly to the caller. Filters should be pure predicates.

Finish writing tasks before closing the file. Share a file IOStream for concurrent
writers; the IOBuffer in the context example is for sequential REPL exploration.
These examples run no actual LoopTNR calculation and create no execution controller.
