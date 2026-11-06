using Configurations: @option
using Test, ExperimentLab, AlgorithmConfigLab, Logging
import JSON

@option struct LogSettings <: AbstractAlgorithmConfig end
@option struct LoggedMeasurement <: AbstractMeasurement end
struct LoggedResult <: AbstractMeasurementResult end
ExperimentLab.measure(::LoggedMeasurement, input) = (@info "Measuring"; LoggedResult())

log_file(store, ref) = joinpath(store.path, ExperimentLab.info(store, ref)["log_path"])
log_lines(path) = JSON.parse.(readlines(path))

@testset "Persistent log ownership" begin
    mktempdir() do directory
        store = DataStore(directory)
        algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
        first = ExperimentLab.record_execution!(store, algorithm)
        second = ExperimentLab.record_execution!(store, algorithm)
        @test haskey(ExperimentLab.info(store, first), "log_path")
        @test isdefined(ExperimentLab, :with_log)
        # Keep missing-feature failures explicit before exercising the new interface.
        if isdefined(ExperimentLab, :with_log)
            first_path, second_path = log_file(store, first), log_file(store, second)
            @test first_path != second_path
            @test !isfile(first_path)
            parent_logger = current_logger()
            value = ExperimentLab.with_log(store, first) do
                @info "Started" store_id="wrong" owner=(kind="wrong", id="wrong")
                # Read while the writer is still open: every message must be flushed.
                @test only(log_lines(first_path))["msg"] == "Started"
                @debug "Hidden"
                :returned
            end
            @test value === :returned
            @test current_logger() === parent_logger
            ExperimentLab.with_log(store, first) do
                @info "Continued" step=2 cost=0.01
            end
            ExperimentLab.with_log(store, second) do
                @info "Other run"
            end
            rows = log_lines(first_path)
            @test getindex.(rows, "msg") == ["Started", "Continued"]
            @test rows[2]["step"] == 2 && rows[2]["cost"] == 0.01
            @test all(row["owner"] == Dict("kind"=>"execution", "id"=>string(first.id)) for row in rows)
            @test all(row["store_id"] == string(store.id) for row in rows)
            @test all(!isempty(row["timestamp"]) for row in rows)
            @test only(log_lines(second_path))["msg"] == "Other run"
            @test ExperimentLab.info(store, first)["status"] == "running"
            @test ExperimentLab.describe(store, first).log_path == relpath(first_path, store.path)

            state = record_state!(store, first; step=1)
            attempt = ExperimentLab.start_measurement!(store, LoggedMeasurement(), state)
            ExperimentLab.with_log(store, first) do
                ExperimentLab.with_log(store, attempt) do
                    @info "Measurement started"
                end
                @info "Back in execution"
            end
            measurement_row = only(log_lines(log_file(store, attempt)))
            @test measurement_row["owner"] == Dict("kind"=>"measurement", "id"=>string(attempt.id))
            @test last(log_lines(first_path))["owner"]["id"] == string(first.id)
            @test !occursin("Measurement started", read(first_path, String))

            # Relative paths survive moving the entire store and reopening it.
            moved = directory * "-moved"
            try
                mv(directory, moved)
                reopened = DataStore(moved)
                ExperimentLab.with_log(reopened, first) do
                    @info "After moving"
                end
                @test last(log_lines(log_file(reopened, first)))["msg"] == "After moving"
            finally
                isdir(moved) && mv(moved, directory)
            end
        end
    end
end
