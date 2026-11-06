using Configurations: @option
using Test
using ExperimentLab
using AlgorithmConfigLab
import JSON
import Serialization
const AD = ExperimentLab

@option struct ExampleRun <: AbstractAlgorithmConfig
    chi::Int = 8
end

function test_state(store; step=1, label="")
    algorithm = AD.record_algorithm!(store, ExampleRun())
    execution = AD.record_execution!(store, algorithm)
    return record_state!(store, execution; step, label)
end

@testset "Data storage" begin
    include("tree.jl")
    include("store.jl")
    include("snapshots.jl")
    include("measurements.jl")
    include("show.jl")
    include("tree_show.jl")
    include("describe.jl")
end
