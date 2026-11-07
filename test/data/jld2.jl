import JLD2

@testset "Native payloads can be read directly with JLD2" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = AD.record_algorithm!(store, ExampleRun(chi=12))
        run = AD.record_execution!(store, algorithm)
        state = record_state!(store, run; step=1)
        captured = capture(state, ComplexF64[1+2im 3; 4 5-6im])
        saved = save_snapshot!(store, captured)
        attempt = AD.start_measurement!(store, SmallestValues(count=1), state;
            input_snapshot=saved)
        AD.finish_measurement!(store, attempt, TypedResult(Float32[2, 4]))

        algorithm_file = joinpath(path, AD.info(store, algorithm)["julia_config"])
        snapshot_file = joinpath(path, AD.info(store, saved)["payload"])
        config_file = joinpath(path, AD.info(store, attempt)["julia_config"])
        result_file = joinpath(path, AD.info(store, attempt)["julia_result"])
        @test all(endswith(".jld2"), (algorithm_file, snapshot_file, config_file, result_file))
        @test JLD2.load(algorithm_file, "value").value isa ExampleRun
        @test JLD2.load(algorithm_file, "value").value.chi == 12
        @test JLD2.load(snapshot_file, "value") == ComplexF64[1+2im 3; 4 5-6im]
        @test JLD2.load(config_file, "value").value isa SmallestValues
        @test JLD2.load(config_file, "value").value.count == 1
        native = JLD2.load(result_file, "value").value
        @test native isa TypedResult{Float32}
        @test native.values == Float32[2, 4]
        reopened = DataStore(path)
        @test load_snapshot(reopened, saved) == captured.value
        @test AD.info(reopened, attempt)["input_snapshot"]["id"] == string(saved.id)
        @test AD.load_result_data(reopened, attempt)["values"] == [2, 4]
    end
end

@testset "Failed native writes preserve the published file" begin
    mktempdir() do path
        destination = joinpath(path, "snapshot.jld2")
        AD.write_native(destination, [1.0, 2.0])
        original = read(destination)
        @test_throws ErrorException AD.write_native(destination, BrokenPayload())
        @test read(destination) == original
        @test AD.read_native(destination) == [1.0, 2.0]
        @test readdir(path) == ["snapshot.jld2"]
    end
end
