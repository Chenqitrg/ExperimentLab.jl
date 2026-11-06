include(joinpath(@__DIR__, "setup.jl"))

# Select modules with LoggingExtras, without a package-specific routing policy.
using ExperimentLab
using Logging, LoggingExtras
import LoggingFormats, JSON

# Only this simulated external library needs a module.
module ExampleForeignLibrary
using Logging
work() = @info "Library is working" ordinary_field=123
end
struct RoutingStep <: AbstractLogEvent
    cost::Float64
end
registry = EventRegistry("example.routing_step.v1" => RoutingStep)

buffer = IOBuffer()
our_module = @__MODULE__
json = FormatLogger(LoggingFormats.JSON(; recursive=true, nest_kwargs=false), buffer)
ours = EarlyFilteredLogger(log -> log._module === our_module, json)
foreign = EarlyFilteredLogger(log -> log._module !== our_module, ConsoleLogger(stderr))
logger = TeeLogger(ours, foreign)

with_logger(logger) do
    ExampleForeignLibrary.work()  # Printed to the terminal.
    @info "Our step" event_record(registry, RoutingStep(0.1))...  # Written to JSON.
end
seekstart(buffer)
records = JSON.parse.(readlines(buffer))
seekend(buffer)
@show length(records)        # 1
@show records[1]["event"]    # "example.routing_step.v1"
@show records[1]["module"]   # "Main" in the REPL.
# Filters should be pure predicates: the logging pipeline may evaluate them more than once.
nothing
