include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab

# 1. Define the diagnostic fields produced by an algorithm.
struct StepFinished <: AbstractLogEvent
    step::Int
    cost::Float64
end
event = StepFinished(3, 1e-8)
@show event.step
@show event.cost

# 2. Assign a stable name. This name does not depend on the Julia type's spelling.
registry = EventRegistry("looptnr.step.v1" => StepFinished)

# 3. Validate and convert the event to ordinary structured Julia data.
record = event_record(registry, event)
@show record.event  # "looptnr.step.v1"
@show record.data   # (step = 3, cost = 1.0e-8)
@show typeof(record.data)
@assert record == (event="looptnr.step.v1", data=(step=3, cost=1e-8))

# This is a NamedTuple, not JSON text or a Dict. No logger or file is involved.
# Try another StepFinished value and call event_record again.
nothing
