using Configurations: @option
@testset "Create and reopen a self-contained data store" begin
    mktempdir() do path
        store = DataStore(path)
        @test isfile(joinpath(path, "index.json"))
        reopened = DataStore(path)
        @test reopened.id == store.id
        @test isempty(AD.records(store, :state))
        document = JSON.parsefile(joinpath(path, "index.json"))
        @test document["schema"] == 1
        @test document["kind"] == "algorithm_data"
        document["schema"] = true
        write(joinpath(path, "index.json"), JSON.json(document))
        @test_throws ArgumentError DataStore(path)
        document["schema"] = 900
        write(joinpath(path, "index.json"), JSON.json(document))
        @test_throws ArgumentError DataStore(path)
    end
    mktempdir() do path
        write(joinpath(path, "unrelated.txt"), "keep me")
        @test_throws ArgumentError DataStore(path)
        @test read(joinpath(path, "unrelated.txt"), String) == "keep me"
    end
end

@testset "Registered algorithms, executions, and mandatory state provenance" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = AD.record_algorithm!(store, ExampleRun(); label="scan")
        run = AD.record_execution!(store, algorithm; provenance=(revision="abc123",))
        @test AD.parent_ref(store, run) == algorithm
        @test AD.info(store, algorithm)["config"]["chi"] == 8
        @test AD.load_algorithm(DataStore(path), algorithm).chi == 8
        @test AD.info(store, run)["provenance"]["revision"] == "abc123"
        produced = record_state!(store, run; step=3, metadata=(temperature=0.5,))
        @test AD.info(store, produced)["availability"] == "never_persisted"
        @test AD.info(store, produced)["step"] == 3
        @test AD.info(store, produced)["metadata"]["temperature"] == 0.5
        for step in (-1, true, 2^53)
            @test_throws ArgumentError record_state!(store, run; step)
        end
        count = length(AD.records(store, :state))
        @test_throws ArgumentError record_state!(store, run; step=4, metadata=(value=NaN,))
        @test_throws ArgumentError record_state!(store, run; step=4, metadata=(value=2^53,))
        @test_throws ArgumentError record_state!(store, run; step=4, metadata=Dict{Any,Any}(:same => 1, "same" => 2))
        @test length(AD.records(store, :state)) == count
        AD.finish_execution!(store, run; status="completed")
        @test AD.info(store, run)["status"] == "completed"
        @test_throws ArgumentError AD.finish_execution!(store, run; status="failed")
        @test_throws ArgumentError AD.finish_execution!(store, run; status="unknown")
        @test_throws ArgumentError record_state!(store, run; step=4)
        mktempdir() do other_path
            other = DataStore(other_path)
            @test_throws ArgumentError record_state!(other, run; step=4)
            @test_throws ArgumentError AD.info(other, produced)
            @test isempty(AD.records(other, :state))
        end
    end
end

@option struct UnserializableAlgorithm <: AbstractAlgorithmConfig end
Serialization.serialize(::Serialization.AbstractSerializer, ::UnserializableAlgorithm) =
    error("algorithm serialization failed")
mutable struct MutableAlgorithm <: AbstractAlgorithmConfig
    value::Int
end
@testset "Invalid algorithm registration publishes nothing" begin
    mktempdir() do path
        store = DataStore(path)
        @test_throws ErrorException AD.record_algorithm!(store, UnserializableAlgorithm())
        @test_throws ArgumentError AD.record_algorithm!(store, MutableAlgorithm(1))
        @test isempty(AD.records(store, :algorithm))
        @test isempty(readdir(joinpath(path, "algorithms")))
    end
end
