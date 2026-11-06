include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab

struct InspectionStep <: AbstractLogEvent
    step::Int
    cost::Float64
end
registry = EventRegistry("solver.step.v1" => InspectionStep)

# Human-readable views of the same registry.
@show registry
display(registry)

# Structured schema information for Julia callers, frontends or AI consumers.
description = ExperimentLab.describe(registry)
@show description.kind            # "event_registry"
@show description.events[1].name  # "solver.step.v1"
@show description.events[1].type  # The Julia type name, for inspection.
@show description.codecs         # Empty: this event needs no special codecs.
@assert description.events[1].name == "solver.step.v1"

# A description explains registered types. A record contains one event's values.
record = event_record(registry, InspectionStep(3, 1e-8))
@show record.data
# Both are plain Julia data. Serializing or displaying them elsewhere is the caller's job.
nothing
