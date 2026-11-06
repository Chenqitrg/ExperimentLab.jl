using Configurations: @option
using ExperimentLab: ConfigError
using ExperimentLab: configtree
using Test, ExperimentLab
using Accessors: @set
import ConstructionBase

struct TaggedConfig{Tag} <: AbstractAlgorithmConfig
    n::Int
end
TaggedConfig{Tag}(; n) where {Tag} = TaggedConfig{Tag}(n)
TaggedConfig(; n) = TaggedConfig{:default}(n)
ExperimentLab.config_constructor(::TaggedConfig{Tag}) where {Tag} = TaggedConfig{Tag}
# This tag is not inferable from stored fields. Its owner uses the standard protocol.
ConstructionBase.constructorof(::Type{TaggedConfig{Tag}}) where {Tag} = TaggedConfig{Tag}

@option struct ValueHolder{V} <: AbstractAlgorithmConfig
    value::V
end

@testset "export preserves types or reports unsupported values" begin
    original = TaggedConfig{:special}(; n=2)
    @test_throws ConfigError configtree(original)
    annotated = NamedTuple{(:x,),Tuple{Real}}((1,))
    config = ValueHolder(; value=annotated)
    @test_throws ConfigError configtree(config)

    for key in (Symbol("a b"), :if)
        config = ValueHolder(; value=NamedTuple{(key,)}((1,)))
        @test isequal(reconstruct_tree(configtree(config)), config)
    end
end

ExperimentLab.value_expression(x::Vector{Vector{Int}}) = repr(x)
ExperimentLab.value_expression(x::NamedTuple{(:x,),Tuple{Real}}) =
    "NamedTuple{(:x,),Tuple{Real}}((" * repr(x.x) * ",))"

@testset "explicit tree expressions override builtin encodings" begin
    for value in ([[1, 2]], NamedTuple{(:x,),Tuple{Real}}((1,)))
        config = ValueHolder(; value)
        restored = reconstruct_tree(configtree(config))
        @test typeof(restored) === typeof(config)
        @test isequal(restored, config)
    end
end

struct ExpressionLeaf
    text::String
end
ExperimentLab.value_expression(x::ExpressionLeaf) = x.text

@testset "expression codecs must emit one complete expression" begin
    for text in ("", "1; 2", "(", "1\n2")
        @test_throws ConfigError configtree(ValueHolder(; value=ExpressionLeaf(text)))
    end
end

@testset "standard reconstruction preserves tags and updates stored fields" begin
    tagged = TaggedConfig{:special}(; n=2)
    changed = @set tagged.n = 3
    @test changed isa TaggedConfig{:special}
    @test changed.n == 3
    @test tagged.n == 2

    # JSON/tree keywords may differ from stored fields. Accessors uses Julia fields.
    derived = TreeFixtures.Derived(; value=3)
    changed = @set derived.twice = 10
    @test changed.twice == 10
    @test ExperimentLab.config_fields(changed) == (; value=5)
    @test derived.twice == 6
    @test_throws ArgumentError (@set derived.twice = 9)
    @test isequal(reconstruct_tree(configtree(changed)), changed)
end
