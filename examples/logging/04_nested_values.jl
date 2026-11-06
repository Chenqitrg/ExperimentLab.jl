include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab

# Supported containers are encoded recursively; vectors get independent storage.
struct ConvergenceTrace{D} <: AbstractLogEvent
    costs::Vector{Float64}
    details::D
end
event = ConvergenceTrace([0.1, 0.01],
    (label="trial", converged=false, optional=nothing, interval=(1, 2)))
registry = EventRegistry("solver.trace.v1" => typeof(event))
record = event_record(registry, event)
@show record.data.details
@show record.data.costs
@show record.data.costs === event.costs  # false

# A later change to the original vector does not change the encoded record.
event.costs[1] = 99.0
@show event.costs        # [99.0, 0.01]
@show record.data.costs  # [0.1, 0.01]
@assert record.data.costs == [0.1, 0.01]
@assert record.data.details.optional === nothing

# The event struct is immutable, but a vector stored in it can still be modified.
# Copying during conversion is distinct from writing the resulting data to disk.
nothing
