include("ownership.jl")
include("algorithm_protocol.jl")
include("generator_sessions.jl")
include("describe.jl")
include("integration.jl")
include("recorded_sessions.jl")
@testset "execution method ambiguities" begin
    @test isempty(detect_ambiguities(ExperimentLab; recursive=true))
end
