@testset "Inspect small metadata without loading tensors" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        captured = capture(source, [1.0, 2.0])
        saved = save_snapshot!(store, captured)
        write(joinpath(path, "tensors", "$(saved.id).jld2"), "not a valid binary payload")
        description = AD.describe(store)
        @test description.kind == "data_store"
        @test description.counts.snapshots == 1
        @test JSON.parse(JSON.json(description))["counts"]["states"] == 1
        @test occursin("DataStore", repr(store))
        @test occursin(path, repr(MIME"text/plain"(), store))
        @test !occursin('\n', repr(source))
        @test AD.describe(source).kind == "state"
        @test AD.describe(captured).state_id == string(source.id)
        @test !occursin("[1.0, 2.0]", repr(MIME"text/plain"(), captured))
        @test AD.info(store, saved)["stored"]
    end
end
