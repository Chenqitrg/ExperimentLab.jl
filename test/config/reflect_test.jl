using Configurations: @option, Reflect
using Accessors: @set, @reset

@option "test.ReflectedLeaf" struct ReflectedLeaf <: AbstractAlgorithmConfig
    type::Reflect
end

@option struct ReflectedSettings{V} <: AbstractAlgorithmConfig
    # The field's type, not its name, marks serialization metadata.
    identity::Reflect
    value::V = ReflectedLeaf()
    count::Int = 2
end

@option struct OrdinaryTypeField <: AbstractAlgorithmConfig
    type::String = "user parameter"
end

@testset "Reflect identity stays out of editable configuration trees" begin
    leaf = ReflectedLeaf()
    original = ReflectedSettings()
    @test ExperimentLab.config_fields(leaf) == NamedTuple()
    @test ExperimentLab.config_defaults(ReflectedLeaf) == NamedTuple()
    @test keys(ExperimentLab.config_fields(original)) == (:value, :count)
    @test !haskey(ExperimentLab.config_defaults(typeof(original)), :identity)
    @test sprint(show, leaf; context=:compact=>true) == "ReflectedLeaf()"
    for mode in (:full, :compact)
        tree = configtree(original; mode)
        @test !occursin("identity:", tree)
        @test !occursin("type:", tree)
        @test isequal(include_string(@__MODULE__, "@config " * repr(tree)), original)
    end
    @test isequal(include_string(@__MODULE__, sprint(show, original)), original)
    @test occursin("type: \"user parameter\"", configtree(OrdinaryTypeField()))

    changed = @set original.count = 5
    @test changed.count == 5
    @test original.count == 2
    @test changed.identity isa Reflect
    @reset changed.value = 3
    @test changed.value == 3
    @test changed.identity isa Reflect

    # Fallback display must also hide metadata when a leaf has no tree codec.
    fallback = sprint(show, MIME"text/plain"(), ReflectedSettings(value=stdout))
    @test occursin("Display only", fallback)
    @test occursin("value:", fallback)
    @test !occursin("identity:", fallback)

    io = IOBuffer()
    writeconfig(io, original)
    text = String(take!(io))
    data = JSON.parse(text)
    @test occursin("ReflectedSettings{", data["identity"])
    @test data["value"]["type"] == "test.ReflectedLeaf"
    @test readconfig(IOBuffer(text), typeof(original)) == original
end
