using Test, ExperimentLab
include("boundary.jl")
@testset "Configuration" begin
    include("config/runtests.jl")
end
include("data/runtests.jl")
include("logging/runtests.jl")
include("execution/runtests.jl")
