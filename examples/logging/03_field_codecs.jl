include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab

# Suppose a numerical library represents a residual with its own type.
struct ResidualNorm
    value::Float64
end
struct ResidualMeasured <: AbstractLogEvent
    residual::ResidualNorm
end
event = ResidualMeasured(ResidualNorm(1e-8))

# The package does not guess how an opaque object should be represented.
plain_registry = EventRegistry("solver.residual.v1" => ResidualMeasured)
unsupported_error = try
    event_record(plain_registry, event)
catch error
    error
end
@assert unsupported_error isa ArgumentError
println(sprint(showerror, unsupported_error))

# A codec is an ordinary function that explicitly chooses the plain value.
encode_residual(residual::ResidualNorm) = residual.value
registry = EventRegistry("solver.residual.v1" => ResidualMeasured;
    codecs=(ResidualNorm => encode_residual,))
record = event_record(registry, event)
@show record.data.residual        # 1.0e-8
@show typeof(record.data.residual) # Float64
@assert record.data == (residual=1e-8,)

# Codec output is validated too. Try this manually:
# event_record(registry, ResidualMeasured(ResidualNorm(Inf)))
nothing
