@kwdef struct TreeConfig <: AbstractAlgorithmConfig
    scales::Vector{Float64} = [1.0, 2.0]
end
struct TreeMeasurement <: AbstractMeasurement end
struct TreeResult <: AbstractMeasurementResult
    value::Float64
end
AD.measure(::TreeMeasurement, value) = TreeResult(sum(value))

@testset "Ref ownership tree and cross-branch inputs" begin
    mktempdir() do path
        store = DataStore(path)
        config = TreeConfig()
        algorithm = AD.record_algorithm!(store, config; label="A")
        equal_config = AD.record_algorithm!(store, TreeConfig(); label="B")
        @test algorithm isa AD.RecordRef{:algorithm}
        @test algorithm != equal_config
        config.scales[1] = 99
        @test AD.load_algorithm(store, algorithm).scales == [1.0, 2.0]
        copy_config = AD.load_algorithm(store, algorithm)
        copy_config.scales[2] = 88
        @test AD.load_algorithm(store, algorithm).scales == [1.0, 2.0]
        run = AD.record_execution!(store, algorithm; label="first", provenance=(revision="abc",))
        again = AD.record_execution!(store, algorithm; label="second")
        state = record_state!(store, run; step=1)
        later = record_state!(store, run; step=2)
        branch = AD.record_execution!(store, equal_config; initial_state=state, label="branch")
        @test AD.parent_ref(store, algorithm) === nothing
        @test AD.parent_ref(store, run) == algorithm
        @test AD.parent_ref(store, again) == algorithm
        @test AD.parent_ref(store, state) == run
        @test AD.parent_ref(store, branch) == equal_config
        @test Set(AD.children(store, algorithm)) == Set([run, again])
        @test Set(AD.children(store, run)) == Set([state, later])
        @test AD.info(store, branch)["initial_state"] == Dict("kind"=>"state", "id"=>string(state.id))
        @test !haskey(AD.info(store, run), "config")
        tensor = [3.0, 4.0]
        captured = capture(state, tensor)
        tensor .= 99
        attempt = measure!(store, TreeMeasurement(), captured)
        @test load_result(store, attempt).value == 7.0
        @test isempty(readdir(joinpath(path, "tensors")))
        @test AD.parent_ref(store, attempt) == state
        @test !haskey(AD.info(store, attempt), "execution")
        @test !haskey(AD.info(store, attempt), "step")
        saved = save_snapshot!(store, captured)
        @test AD.parent_ref(store, saved) == state
        @test Set(AD.children(store, state)) == Set([saved, attempt])
        remeasured = measure!(store, TreeMeasurement(), saved)
        @test AD.info(store, remeasured)["input_snapshot"] == Dict("kind"=>"snapshot", "id"=>string(saved.id))
        @test AD.parent_ref(store, remeasured) == state
        @test_throws ArgumentError AD.start_measurement!(store, TreeMeasurement(), later; input_snapshot=saved)
        AD.delete_snapshot!(store, saved)
        reopened = DataStore(path)
        @test AD.parent_ref(reopened, AD.parent_ref(reopened, attempt)) == run
        @test AD.parent_ref(reopened, run) == algorithm
        @test load_result(reopened, attempt).value == 7.0
        @test AD.info(reopened, state)["availability"] == "removed"
        @test AD.info(reopened, branch)["initial_state"]["id"] == string(state.id)
        @test_throws ArgumentError load_snapshot(reopened, saved)
        mktempdir() do other_path
            other = DataStore(other_path)
            local_algorithm = AD.record_algorithm!(other, TreeConfig())
            @test_throws ArgumentError AD.record_execution!(other, algorithm)
            @test_throws ArgumentError AD.record_execution!(other, local_algorithm; initial_state=state)
            @test_throws ArgumentError record_state!(other, run; step=1)
            @test_throws ArgumentError measure!(other, TreeMeasurement(), captured)
            @test_throws ArgumentError save_snapshot!(other, captured)
            @test isempty(AD.records(other, :execution))
            @test isempty(AD.records(other, :measurement))
        end
    end
end
