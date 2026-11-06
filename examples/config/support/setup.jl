include("../setup.jl")
# Reuse the same types when reading several examples in one Julia session.
if !isdefined(@__MODULE__, :ReviewExample)
    include("example_types.jl")
end
using .ReviewExample
