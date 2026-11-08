using Configurations: @option
using ExperimentLab: configtree
using Test, ExperimentLab


@option struct Leaf <: AbstractAlgorithmConfig
    count::Int = 2
end

@option struct Alternate <: AbstractAlgorithmConfig
    value::Float64 = 1.0
end
@option struct Nested{C<:AbstractAlgorithmConfig} <: AbstractAlgorithmConfig
    child::C = Leaf()
    enabled::Bool = true
end
@testset "configuration value semantics and display" begin
    @test Nested() == Nested()
    @test isequal(Nested(), Nested())
    @test hash(Nested()) == hash(Nested())
    @test Nested(child=Leaf(count=3)) != Nested()
    @test sprint(show, Leaf(); context=:compact=>true) == "Leaf(...)"
    shown = sprint(show, MIME"text/plain"(), Nested())
    @test occursin("child: Main.Leaf", shown)
    @test occursin("count: 2", shown)
end

include("accessors_test.jl")
include("tree_test.jl")
include("extensions_test.jl")
include("json_interface_test.jl")

include("output_contract_test.jl")

include("automatic_display_test.jl")
include("registry_test.jl")
