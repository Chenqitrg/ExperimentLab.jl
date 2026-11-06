using Test, ExperimentLab

using Logging, LoggingExtras
import LoggingFormats, JSON

@testset "Event schemas and logging integrations" begin
    include("events.jl")
    include("encoding.jl")
    include("integration.jl")
    include("show.jl")
end
