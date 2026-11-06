include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab

struct CostReported <: AbstractLogEvent
    cost::Float64
end
registry = EventRegistry("solver.cost.v1" => CostReported)
record = event_record(registry, CostReported(0.01))
@show record.data.cost

# Invalid field values fail during conversion. Catch here so the example keeps running.
invalid = CostReported(NaN)
validation_error = try
    event_record(registry, invalid)
catch error
    error
end
@assert validation_error isa ArgumentError
println(sprint(showerror, validation_error))  # Identifies the cost field.

# An event must be explicitly registered before conversion.
empty_registry = EventRegistry()
unregistered_error = try
    event_record(empty_registry, CostReported(0.01))
catch error
    error
end
@assert unregistered_error isa ArgumentError
println(sprint(showerror, unregistered_error))

# Registry names and event types must be unique.
# Try these manually to see the corresponding errors:
# EventRegistry("first" => CostReported, "second" => CostReported)
# EventRegistry(" " => CostReported)
# Registration also rejects mutable or abstract event types.
nothing
