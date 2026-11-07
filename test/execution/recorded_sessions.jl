using Test, ExperimentLab, ResumableFunctions, Logging
using Configurations: @option
import JSON

@option struct TrackedSettings <: AbstractAlgorithmConfig
    steps::Int = 2
end

@resumable function tracked_count(n::Int, entered)::Int
    entered[] = true
    @info "Started"
    for step in 1:n
        @yield step
    end
    @info "Finished"
    return n
end

@testset "Recorded session entry point" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = ExperimentLab.record_algorithm!(store, TrackedSettings())
        @test applicable(start_run, store, algorithm, tracked_count(2, Ref(false)))
    end
end

@testset "Recorded sessions (threaded=$threaded)" for threaded in (false, true)
    mktempdir() do path
        store = DataStore(path)
        algorithm = ExperimentLab.record_algorithm!(store, TrackedSettings())
        held_logger = Ref{Logging.AbstractLogger}()
        session = start_run(store, algorithm, tracked_count(2, Ref(false)); threaded,
            label="first run", provenance=(host="test",), onstep=(s, step) -> begin
                held_logger[] = current_logger()
                state = record_state!(s.store, s.execution; step)
                save_snapshot!(s.store, capture(state, [step]))
                @info "Step" step
                step == 1 && pause!(s)
            end)
        wait_for_status(session, ExperimentLab.PAUSED)
        execution = session.execution
        @test session.store === store
        @test ExperimentLab.parent_ref(store, execution) == algorithm
        record = ExperimentLab.info(store, execution)
        @test record["label"] == "first run"
        @test record["provenance"]["host"] == "test"
        @test record["status"] == "running"
        logfile = joinpath(path, record["log_path"])
        rows = JSON.parse.(readlines(logfile))
        @test [r["msg"] for r in rows] == ["Started", "Step"]
        @test isopen(held_logger[].sink.stream)
        resume!(session)
        @test fetch(session) == 2
        @test !isopen(held_logger[].sink.stream)
        @test ExperimentLab.info(DataStore(path), execution)["status"] == "completed"
        rows = JSON.parse.(readlines(logfile))
        @test [r["msg"] for r in rows] == ["Started", "Step", "Step", "Finished"]
        @test all(r["owner"]["id"] == string(execution.id) for r in rows)
        states = ExperimentLab.children(store, execution)
        @test length(states) == 2
        @test load_snapshot(store, only(ExperimentLab.children(store, last(states)))) == [2]

        second = start_run(store, algorithm, tracked_count(0, Ref(false)); threaded,
            initial_state=last(states))
        @test fetch(second) == 0
        @test second.execution != execution
        @test ExperimentLab.info(store, second.execution)["log_path"] != record["log_path"]
        @test ExperimentLab.info(store, second.execution)["initial_state"]["id"] == string(last(states).id)
        @test length(readlines(logfile)) == 4

        cancelled = start_run(store, algorithm, tracked_count(2, Ref(false)); threaded,
            onstep=(s, _) -> pause!(s))
        wait_for_status(cancelled, ExperimentLab.PAUSED)
        cancel!(cancelled)
        wait(cancelled)
        @test run_status(cancelled) == ExperimentLab.CANCELLED
        @test ExperimentLab.info(store, cancelled.execution)["status"] == "cancelled"
        @test_throws ArgumentError fetch(cancelled)

        for generator in (failing_steps(), tracked_count(2, Ref(false)))
            failed = start_run(store, algorithm, generator; threaded,
                onstep=(_, _) -> error("callback failed"))
            @test_throws CapturedException fetch(failed)
            @test run_status(failed) == ExperimentLab.FAILED
            failed_record = ExperimentLab.info(store, failed.execution)
            @test failed_record["status"] == "failed"
            @test occursin("callback failed", failed_record["error"]["message"])
        end
        failed = start_run(store, algorithm, failing_steps(); threaded)
        @test_throws CapturedException fetch(failed)
        @test occursin("algorithm failure", ExperimentLab.info(store, failed.execution)["error"]["message"])
    end
end

@testset "Recorded session infrastructure failures" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = ExperimentLab.record_algorithm!(store, TrackedSettings())
        # Block the log directory before the driver starts. No algorithm work runs.
        write(joinpath(path, "logs"), "blocked")
        entered = Ref(false)
        failed = start_run(store, algorithm, tracked_count(2, entered); threaded=false)
        @test_throws CapturedException fetch(failed)
        @test !entered[]
        @test ExperimentLab.info(store, failed.execution)["status"] == "failed"
        rm(joinpath(path, "logs"))

        # Closing the live stream forces a real logging error at the first callback.
        progress = Int[]
        failed = start_run(store, algorithm, tracked_count(2, Ref(false)); threaded=false,
            onstep=(_, step) -> begin
                push!(progress, step)
                close(current_logger().sink.stream)
                @info "Cannot write"
            end)
        @test_throws CapturedException fetch(failed)
        @test failed.failure.ex isa ExperimentLab.LogWriteError
        @test progress == [1]
        @test ExperimentLab.info(store, failed.execution)["status"] == "failed"

        # Block final record publication after a successful numerical step.
        failed = start_run(store, algorithm, tracked_count(1, Ref(false)); threaded=false,
            onstep=(_, _) -> begin
                mv(joinpath(path, "index.json"), joinpath(path, "held-index.json"))
                mkdir(joinpath(path, "index.json"))
            end)
        @test_throws CapturedException fetch(failed)
        @test run_status(failed) == ExperimentLab.FAILED
        @test failed.failure.ex isa CompositeException
        rm(joinpath(path, "index.json"))
        mv(joinpath(path, "held-index.json"), joinpath(path, "index.json"))
        @test ExperimentLab.info(store, failed.execution)["status"] == "running"

        # Failure recording must preserve the original callback error as well.
        failed = start_run(store, algorithm, tracked_count(1, Ref(false)); threaded=false,
            onstep=(_, _) -> begin
                mv(joinpath(path, "index.json"), joinpath(path, "held-index.json"))
                mkdir(joinpath(path, "index.json"))
                error("original callback error")
            end)
        @test_throws CapturedException fetch(failed)
        errors = failed.failure.ex.exceptions
        @test length(errors) == 2
        @test errors[1] isa CapturedException
        @test errors[1].ex isa ErrorException
        @test errors[1].ex.msg == "original callback error"
        @test errors[2] isa CapturedException
        rm(joinpath(path, "index.json"))
        mv(joinpath(path, "held-index.json"), joinpath(path, "index.json"))

        foreign = DataStore(mktempdir())
        entered = Ref(false)
        @test_throws ArgumentError start_run(foreign, algorithm, tracked_count(1, entered))
        @test !entered[]
        @test isempty(ExperimentLab.records(foreign, :execution))
        ordinary = start_run(sum_steps(1); threaded=false)
        @test fetch(ordinary) == 1
        @test ordinary.store === nothing && ordinary.execution === nothing
    end
end
