include(joinpath(@__DIR__, "setup.jl"))

# Two execution IDs, one output. This example starts no tasks or algorithms.
using ExperimentLab
using Logging, LoggingExtras
import LoggingFormats, JSON

struct ContextStep <: AbstractLogEvent
    cost::Float64
end
registry = EventRegistry("example.context_step.v1" => ContextStep)
buffer = IOBuffer()
sink = FormatLogger((io, event) -> LoggingFormats.JSON(; recursive=true, nest_kwargs=false)(io, event), buffer)

# TransformerLogger adds context using ordinary log keywords.
parent = TransformerLogger(sink) do log
    (; log..., kwargs=(; log.kwargs..., execution_id="parent"))
end
child = TransformerLogger(sink) do log
    (; log..., kwargs=(; log.kwargs..., execution_id="child"))
end
# Both wrap the same sink. Wrapping parent would apply its context again.
with_logger(parent) do
    @info "Parent step" event_record(registry, ContextStep(0.1))...
end
with_logger(child) do
    @info "Child step" event_record(registry, ContextStep(0.01))...
end

seekstart(buffer)
records = JSON.parse.(readlines(buffer))
seekend(buffer)
@show records[1]["execution_id"]  # "parent"
@show records[2]["execution_id"]  # "child"
@show records[2]["data"]["cost"]  # 0.01
# Use a shared file IOStream for concurrent writers, not an unsynchronized IOBuffer.
nothing
