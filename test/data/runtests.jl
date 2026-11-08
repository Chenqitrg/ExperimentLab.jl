using Configurations: @option
using Test
using ExperimentLab
using ExperimentLab: AbstractAlgorithmConfig, @config, readconfig, writeconfig
import JSON
import JLD2
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
    include("jld2.jl")
    include("type_identity.jl")
    include("show.jl")
    include("tree_show.jl")
    include("describe.jl")
end
