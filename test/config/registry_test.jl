using ExperimentLab: ConfigRegistry, config_record
using Accessors: @set, @reset

@option struct RegisteredLeaf <: AbstractAlgorithmConfig end
@option struct RegisteredSettings{V} <: AbstractAlgorithmConfig
    value::V = RegisteredLeaf()
    type::String = "ordinary parameter"
    count::Int = 2
end
@option struct RegisteredVector <: AbstractAlgorithmConfig
    values::Vector{RegisteredLeaf} = [RegisteredLeaf()]
end
@option struct RegisteredContainers <: AbstractAlgorithmConfig
    mapping::Dict{String,RegisteredLeaf} = Dict("child" => RegisteredLeaf())
    pair::Tuple{RegisteredLeaf,Int} = (RegisteredLeaf(), 2)
    labelled::NamedTuple{(:child,),Tuple{RegisteredLeaf}} = (; child=RegisteredLeaf())
end
@option struct RegisteredChoice <: AbstractAlgorithmConfig
    method::Union{RegisteredLeaf,RegisteredSettings{Int}} = RegisteredLeaf()
    optional::Union{Nothing,RegisteredLeaf} = nothing
    methods::Vector{Union{RegisteredLeaf,RegisteredSettings{Int}}} = [RegisteredLeaf()]
end
const TEST_CONFIGS = ConfigRegistry("test.leaf" => RegisteredLeaf,
    "test.settings" => RegisteredSettings, "test.vector" => RegisteredVector,
    "test.containers" => RegisteredContainers, "test.choice" => RegisteredChoice)
ExperimentLab.config_registry(::Type{RegisteredLeaf}) = TEST_CONFIGS
ExperimentLab.config_registry(::Type{<:RegisteredSettings}) = TEST_CONFIGS
ExperimentLab.config_registry(::Type{RegisteredVector}) = TEST_CONFIGS
ExperimentLab.config_registry(::Type{RegisteredContainers}) = TEST_CONFIGS
ExperimentLab.config_registry(::Type{RegisteredChoice}) = TEST_CONFIGS

@option "plain.a" struct PlainAliasA <: AbstractAlgorithmConfig end
@option "plain.b" struct PlainAliasB <: AbstractAlgorithmConfig end
@option struct PlainAliasChoice <: AbstractAlgorithmConfig
    method::Union{PlainAliasA,PlainAliasB} = PlainAliasA()
end

@testset "Unregistered Union fields retain upstream aliases" begin
    for method in (PlainAliasA(), PlainAliasB())
        config = PlainAliasChoice(; method)
        io = IOBuffer()
        writeconfig(io, config)
        text = String(take!(io))
        @test JSON.parse(text)["method"] == Configurations.to_dict(config)["method"]
        @test readconfig(IOBuffer(text), PlainAliasChoice) == config
    end
end

@testset "Configuration identities live outside structs" begin
    @test fieldnames(RegisteredLeaf) == ()
    @test fieldnames(RegisteredSettings) == (:value, :type, :count)
    leaf = config_record(TEST_CONFIGS, RegisteredLeaf())
    @test leaf == Dict("type" => "test.leaf", "parameters" => Dict())
    original = RegisteredSettings()
    record = config_record(TEST_CONFIGS, original)
    @test record["type"] == "test.settings"
    @test record["parameters"]["type"] == "ordinary parameter"
    @test record["parameters"]["value"] == leaf
    @test config_record(TEST_CONFIGS, RegisteredSettings(value=:fast))["parameters"]["value"] == "fast"
    @test sprint(show, RegisteredLeaf(); context=:compact=>true) == "RegisteredLeaf()"
    @test isequal(include_string(@__MODULE__, "@config " * repr(configtree(original))), original)
    changed = @set original.count = 3
    @reset changed.value = 4
    @test changed.count == 3 && changed.value == 4
    @test original == RegisteredSettings()

    for config in (RegisteredLeaf(), original, changed, RegisteredVector(), RegisteredContainers(),
                   RegisteredChoice(), RegisteredChoice(method=changed, optional=RegisteredLeaf(),
                       methods=[RegisteredLeaf(), changed])), defaults in (true, false)
        io = IOBuffer()
        writeconfig(io, config; include_defaults=defaults)
        text = String(take!(io))
        @test haskey(JSON.parse(text), "type")
        @test readconfig(IOBuffer(text), typeof(config)) == config
        @test readconfig(IOBuffer(text), TEST_CONFIGS) == config
    end
    mktempdir() do path
        filename = joinpath(path, "config.json")
        writeconfig(filename, original)
        @test readconfig(filename, TEST_CONFIGS) == original
    end
end

@testset "Configuration registries compose without global registration" begin
    first = ConfigRegistry("test.leaf" => RegisteredLeaf)
    second = ConfigRegistry("test.settings" => RegisteredSettings)
    @test length(ConfigRegistry(first, second).names) == 2
    @test length(ConfigRegistry(first, first).names) == 1
    @test ExperimentLab.describe(TEST_CONFIGS).kind == "config_registry"
    @test_throws ArgumentError ConfigRegistry("" => RegisteredLeaf)
    @test_throws ArgumentError ConfigRegistry("abstract" => AbstractAlgorithmConfig)
    @test_throws ArgumentError ConfigRegistry("number" => Int)
    @test_throws ArgumentError ConfigRegistry("same" => RegisteredLeaf, "same" => RegisteredSettings)
    @test_throws ArgumentError ConfigRegistry("a" => RegisteredLeaf, "b" => RegisteredLeaf)
    @test_throws ArgumentError ConfigRegistry(first, ConfigRegistry("test.leaf" => RegisteredSettings))
    @test_throws ArgumentError ConfigRegistry(first, ConfigRegistry("another" => RegisteredLeaf))
    @test_throws ArgumentError config_record(TEST_CONFIGS, Leaf())
    @test_throws ArgumentError readconfig(IOBuffer("{\"type\":\"unknown\",\"parameters\":{}}"), TEST_CONFIGS)
    @test_throws ArgumentError readconfig(IOBuffer("{\"type\":\"test.settings\",\"parameters\":{}}"), RegisteredLeaf)
    @test_throws ArgumentError readconfig(IOBuffer("{\"type\":\"test.leaf\",\"parameters\":1}"), TEST_CONFIGS)
end

@testset "Untagged generic objects cannot silently become strategy dictionaries" begin
    # A generic field does not distinguish a real Dict from an encoded external
    # object. A concrete type removes that ambiguity; a registry alone cannot.
    config = RegisteredSettings(Dict("threshold" => 0.1), "data", 2)
    io = IOBuffer()
    writeconfig(io, config)
    text = String(take!(io))
    @test readconfig(IOBuffer(text), typeof(config)) == config
    @test_throws ArgumentError readconfig(IOBuffer(text), TEST_CONFIGS)
end
