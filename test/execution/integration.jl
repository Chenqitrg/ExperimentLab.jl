using Logging
import JSON

@resumable function logged_steps()::Int
    @info "Algorithm started"
    @yield 1
    @info "Algorithm finished"
    return 2
end

@testset "Sessions compose with explicit records and log scopes" begin
    for threaded in (false, true)
        mktempdir() do path
            store = DataStore(path)
            algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
            run = ExperimentLab.record_execution!(store, algorithm)
            session = ExperimentLab.with_log(store, run) do
                active = start_run(logged_steps(); threaded, onstep=(_, step) -> begin
                    record_state!(store, run; step)
                    @info "Step recorded" step
                end)
                @test fetch(active) == 2 # Finish before closing the log file.
                active
            end
            @test run_status(session) == ExperimentLab.COMPLETED
            @test ExperimentLab.info(store, run)["status"] == "running"
            ExperimentLab.finish_execution!(store, run)
            @test ExperimentLab.info(store, run)["status"] == "completed"
            rows = log_lines(log_file(store, run))
            @test [row["msg"] for row in rows] ==
                ["Algorithm started", "Step recorded", "Algorithm finished"]
            @test all(row["owner"]["id"] == string(run.id) for row in rows)
            @test only(ExperimentLab.children(store, run)) isa ExperimentLab.StateRef
        end
    end
end

@option struct SessionLoggedMeasurement <: AbstractMeasurement
    threaded::Bool = false
end
function ExperimentLab.measure(config::SessionLoggedMeasurement, input)
    fetch(start_run(logged_steps(); threaded=config.threaded))
    return LoggedResult()
end

@testset "Session-wrapped log failures escape measurement handling" begin
    for threaded in (false, true)
        mktempdir() do path
            store = DataStore(path)
            algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
            run = ExperimentLab.record_execution!(store, algorithm)
            state = record_state!(store, run; step=0)
            logger = ExperimentLab.record_logger(FaultLogIO(:write, IOBuffer()), store, run)
            failure = try
                with_logger(logger) do
                    measure!(store, SessionLoggedMeasurement(; threaded), nothing; state)
                end
            catch err
                err
            end
            @test failure isa CapturedException
            if failure isa CapturedException
                @test failure.ex isa ExperimentLab.LogWriteError
            end
            attempt = only(ExperimentLab.records(store, :measurement))
            @test ExperimentLab.info(store, attempt)["status"] == "running"
        end
    end
end

@resumable function interrupted_steps()::Int
    @yield 1
    throw(InterruptException())
end

@option struct SessionInterruptedMeasurement <: AbstractMeasurement end
function ExperimentLab.measure(::SessionInterruptedMeasurement, input)
    fetch(start_run(interrupted_steps(); threaded=false))
    return LoggedResult()
end

@testset "Session-wrapped interrupts escape measurement handling" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
        run = ExperimentLab.record_execution!(store, algorithm)
        state = record_state!(store, run; step=0)
        failure = try
            measure!(store, SessionInterruptedMeasurement(), nothing; state)
        catch err
            err
        end
        @test failure isa CapturedException
        if failure isa CapturedException
            @test failure.ex isa InterruptException
        end
        attempt = only(ExperimentLab.records(store, :measurement))
        @test ExperimentLab.info(store, attempt)["status"] == "running"
    end
end
