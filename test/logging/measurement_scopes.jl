@option struct ScopeMeasurement <: AbstractMeasurement
    fail::Bool = false
end
function ExperimentLab.measure(config::ScopeMeasurement, input)
    @info "Measurement started"
    @sync @async @info "Measurement child"
    config.fail && error("calculation failed")
    return LoggedResult()
end

@testset "measure! selects and restores log ownership" begin
    mktempdir() do directory
        store = DataStore(directory)
        algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
        run = ExperimentLab.record_execution!(store, algorithm)
        state = record_state!(store, run; step=1)
        ExperimentLab.with_log(store, run) do
            outer = current_logger()
            @info "Before measurement"
            for fail in (false, true)
                attempt = measure!(store, ScopeMeasurement(; fail), [1.0]; state)
                @test current_logger() === outer
                @test ExperimentLab.info(store, attempt)["status"] == (fail ? "failed" : "completed")
                path = log_file(store, attempt)
                @test isfile(path)
                if isfile(path)
                    rows = log_lines(path)
                    @test getindex.(rows, "msg") == ["Measurement started", "Measurement child"]
                    @test all(r["owner"] == Dict("kind" => "measurement", "id" => string(attempt.id)) for r in rows)
                end
            end
            @info "After measurement"
        end
        @test getindex.(log_lines(log_file(store, run)), "msg") == ["Before measurement", "After measurement"]
    end
end
