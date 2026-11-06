using Configurations: @option
@option struct SmallestValues <: AbstractMeasurement
    count::Int = 2
    scale::Float64 = 1.0
end
struct Spectrum <: AbstractMeasurementResult
    levels::Vector{Float64}
end
const seen_input = Ref{Any}()
function AD.measure(config::SmallestValues, input)
    seen_input[] = input
    config.count > 0 || error("count must be positive")
    Spectrum(sort(input)[1:min(config.count, length(input))] .* config.scale)
end
struct InvalidResult <: AbstractMeasurementResult
    value::ComplexF64
end
@option struct InvalidMeasurement <: AbstractMeasurement end
AD.measure(::InvalidMeasurement, input) = InvalidResult(1 + 2im)
struct MatrixResult <: AbstractMeasurementResult
    matrix::Matrix{Float64}
end
struct AdaptedComplexResult <: AbstractMeasurementResult
    value::ComplexF64
end
AD.result_data(result::AdaptedComplexResult) = (real=real(result.value), imag=imag(result.value))

@testset "Measure in memory without a snapshot; retain every attempt" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store; label="produced tensor")
        input = [3.0, 1.0, 2.0]
        first_attempt = measure!(store, SmallestValues(), input; state=source)
        @test seen_input[] === input
        @test input == [3.0, 1.0, 2.0]
        @test AD.info(store, source)["availability"] == "never_persisted"
        @test isempty(readdir(joinpath(path, "tensors")))
        @test load_result(store, first_attempt).levels == [1.0, 2.0]
        second = measure!(store, SmallestValues(scale=2.0), input; state=source)
        @test second != first_attempt
        @test load_result(DataStore(path), second).levels == [2.0, 4.0]
        @test AD.info(store, first_attempt)["parent"] == AD.ref_data(source)
        @test AD.info(store, second)["status"] == "completed"
        config = AD.load_measurement(store, second)
        @test config isa SmallestValues
        @test config.scale == 2.0
        @test config.count == 2
        @test length(AD.records(store, :measurement)) == 2
        @test_throws ArgumentError AD.finish_measurement!(store, second, Spectrum([99.0]))
        @test load_result(store, second).levels == [2.0, 4.0]
    end
end

@testset "Failures are records; encoding/storage errors propagate" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        failed = measure!(store, SmallestValues(count=0), [1.0]; state=source)
        failure = AD.info(store, failed)
        @test failure["status"] == "failed"
        @test AD.load_measurement(DataStore(path), failed).count == 0
        @test occursin("count must be positive", failure["error"]["message"])
        @test_throws ArgumentError load_result(store, failed)
        @test_throws ArgumentError AD.finish_measurement!(store, failed, Spectrum([1.0]))
        retried = measure!(store, SmallestValues(), [1.0]; state=source)
        @test retried != failed
        @test AD.info(store, failed)["status"] == "failed"
        @test AD.info(store, retried)["status"] == "completed"

        @test_throws ArgumentError measure!(store, InvalidMeasurement(), [1.0]; state=source)
        running = filter(ref -> AD.info(store, ref)["status"] == "running", AD.records(store, :measurement))
        @test length(running) == 1
        @test AD.info(store, only(running))["result"] === nothing
        @test_throws ArgumentError load_result(store, only(running))
        AD.fail_measurement!(store, only(running), ErrorException("encoding rejected by caller"))

        pending = AD.start_measurement!(store, SmallestValues(), source)
        result_path = joinpath(path, "measurements", "$(pending.id).json")
        mkdir(result_path) # A real filesystem failure at the publication destination.
        @test_throws Exception AD.finish_measurement!(store, pending, Spectrum([1.0]))
        @test AD.info(DataStore(path), pending)["status"] == "running"
        @test AD.info(store, pending)["result"] === nothing
    end
end

@testset "Remeasure a saved state and prune tensors without deleting results" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = AD.record_algorithm!(store, ExampleRun())
        original_run = AD.record_execution!(store, algorithm)
        source = record_state!(store, original_run; step=5)
        saved = save_snapshot!(store, capture(source, [3.0, 1.0, 2.0]))
        attempt = measure!(DataStore(path), SmallestValues(count=1), saved)
        record = AD.info(store, attempt)
        @test AD.parent_ref(store, source) == original_run
        @test record["parent"] == AD.ref_data(source)
        @test record["input_snapshot"] == AD.ref_data(saved)
        @test AD.parent_ref(store, original_run) == algorithm
        @test load_result(store, attempt).levels == [1.0]
        AD.delete_snapshot!(store, saved)
        @test isempty(readdir(joinpath(path, "tensors")))
        @test load_result(store, attempt).levels == [1.0]
        @test AD.info(store, source)["availability"] == "removed"
        @test_throws ArgumentError measure!(store, SmallestValues(), saved)
    end
end

@testset "Numerical arrays have an explicit frontend representation" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        attempt = AD.start_measurement!(store, SmallestValues(), source)
        AD.finish_measurement!(store, attempt, MatrixResult([1.0 2.0; 3.0 4.0]))
        restored = load_result(store, attempt)
        @test restored isa MatrixResult
        @test restored.matrix == [1.0 2.0; 3.0 4.0]
        matrix = AD.load_result_data(store, attempt)["matrix"]
        @test matrix["shape"] == [2, 2]
        @test matrix["layout"] == "column-major"
        @test matrix["values"] == [1.0, 3.0, 2.0, 4.0]
        complex_attempt = AD.start_measurement!(store, SmallestValues(), source)
        AD.finish_measurement!(store, complex_attempt, AdaptedComplexResult(1 + 2im))
        @test load_result(store, complex_attempt) isa AdaptedComplexResult
        @test load_result(store, complex_attempt).value === ComplexF64(1 + 2im)
        @test AD.load_result_data(store, complex_attempt) == Dict("real" => 1.0, "imag" => 2.0)
    end
end


struct TypedResult{T} <: AbstractMeasurementResult
    values::Vector{T}
end
struct UnserializableResult <: AbstractMeasurementResult end
Serialization.serialize(::Serialization.AbstractSerializer, ::UnserializableResult) =
    error("result serialization failed")

@testset "Default result loading restores Julia types and detached values" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        attempt = AD.start_measurement!(store, SmallestValues(), source)
        original = TypedResult(Float32[1, 2])
        AD.finish_measurement!(store, attempt, original)
        original.values[1] = 99
        restored = load_result(DataStore(path), attempt)
        @test restored isa TypedResult{Float32}
        if restored isa TypedResult{Float32}
            @test restored.values == Float32[1, 2]
            restored.values[1] = -1
            @test load_result(store, attempt).values == Float32[1, 2]
        end
        @test AD.load_result_data(store, attempt) == Dict("values" => [1, 2])

        # A separate Julia process has no writer-side type registry or cached result.
        script = """
        using Configurations: @option
        using ExperimentLab, UUIDs
        struct TypedResult{T} <: AbstractMeasurementResult
            values::Vector{T}
        end
        @option struct SmallestValues <: AbstractMeasurement
            count::Int = 2
            scale::Float64 = 1.0
        end
        store = DataStore(ARGS[1])
        attempt = ExperimentLab.MeasurementRef(store.id, UUID(ARGS[2]))
        result = load_result(store, attempt)
        @assert result isa TypedResult{Float32}
        @assert result.values == Float32[1, 2]
        definition = ExperimentLab.load_measurement(store, attempt)
        @assert definition isa SmallestValues
        @assert definition.count == 2 && definition.scale == 1.0
        """
        project = dirname(Base.active_project())
        @test success(`$(Base.julia_cmd()) --startup-file=no --compile=min -O0 --threads=1 --project=$project -e $script $path $(string(attempt.id))`)

        # Frontend data remains readable without the Julia payload.
        rm(joinpath(path, "measurements", "$(attempt.id).bin"))
        @test AD.load_result_data(store, attempt)["values"] == [1, 2]
        @test_throws SystemError load_result(store, attempt)
    end
end

@testset "Native result failure cannot publish completion" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        attempt = AD.start_measurement!(store, SmallestValues(), source)
        @test_throws ErrorException AD.finish_measurement!(store, attempt, UnserializableResult())
        @test AD.info(store, attempt)["status"] == "running"
        @test AD.info(store, attempt)["result"] === nothing
        @test_throws ArgumentError load_result(store, attempt)

        blocked = AD.start_measurement!(store, SmallestValues(), source)
        mkdir(joinpath(path, "measurements", "$(blocked.id).bin"))
        @test_throws Exception AD.finish_measurement!(store, blocked, Spectrum([1.0]))
        @test AD.info(store, blocked)["status"] == "running"
        @test AD.info(store, blocked)["result"] === nothing
    end
end


@option struct UnserializableMeasurement <: AbstractMeasurement end
Serialization.serialize(::Serialization.AbstractSerializer, ::UnserializableMeasurement) =
    error("measurement serialization failed")

@testset "Configurations are readable before completion without constructor mappings" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        attempt = AD.start_measurement!(store, SmallestValues(count=1, scale=3.0), source)
        @test AD.info(store, attempt)["status"] == "running"
        definition = AD.load_measurement(DataStore(path), attempt)
        @test definition isa SmallestValues
        @test definition.count == 1
        @test definition.scale == 3.0
        @test AD.info(store, attempt)["config"]["count"] == 1
        mktempdir() do other_path
            @test_throws ArgumentError AD.load_measurement(DataStore(other_path), attempt)
        end
        rm(joinpath(path, "measurements", "$(attempt.id).config.bin"))
        @test_throws SystemError AD.load_measurement(store, attempt)
        @test AD.info(store, attempt)["config"]["scale"] == 3.0
    end
end

@testset "Configuration serialization failure does not publish an attempt" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        @test_throws ErrorException AD.start_measurement!(store, UnserializableMeasurement(), source)
        @test isempty(AD.records(DataStore(path), :measurement))
        @test isempty(readdir(joinpath(path, "measurements")))
    end
end
