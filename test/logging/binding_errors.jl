using Configurations: @option
# Deterministic failures exercise the real FormatLogger write/flush path without
# filling a disk or relying on filesystem permission behavior under privileged users.
struct FaultLogIO <: IO
    mode::Symbol
    buffer::IOBuffer
end
Base.isopen(::FaultLogIO) = true
Base.seekend(io::FaultLogIO) = (seekend(io.buffer); io)
Base.write(io::FaultLogIO, bytes::Vector{UInt8}) =
    io.mode === :write ? error("forced write failure") : write(io.buffer, bytes)
Base.flush(io::FaultLogIO) = io.mode === :flush ? error("forced flush failure") : nothing

@option struct BrokenLogMeasurement <: AbstractMeasurement
    asynchronous::Bool = false
end
function ExperimentLab.measure(config::BrokenLogMeasurement, input)
    close(current_logger().sink.stream)
    if config.asynchronous
        @sync @async @info "Cannot write"
    else
        @info "Cannot write"
    end
    return LoggedResult()
end

@testset "Log failures escape macros, tasks and measurements" begin
    mktempdir() do directory
        store = DataStore(directory)
        algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
        run = ExperimentLab.record_execution!(store, algorithm)
        state = record_state!(store, run; step=1)
        for mode in (:write, :flush)
            io = FaultLogIO(mode, IOBuffer())
            logger = ExperimentLab.record_logger(io, store, run)
            @test !Logging.catch_exceptions(logger)
            reached = Ref(false)
            failure = try
                with_logger(logger) do
                    @info "Must fail"
                    reached[] = true
                end
            catch error
                error
            end
            @test failure isa ExperimentLab.LogWriteError
            @test occursin("forced $mode failure", sprint(showerror, failure))
            @test !reached[]
            # A flush failure can happen after bytes reached a buffer; it must still throw.
            @test (position(io.buffer) > 0) == (mode === :flush)
            @test_throws CompositeException with_logger(logger) do
                @sync @async @info "Background failure"
            end
        end
        # measure! owns its logger now; fail that stream, not the outer logger.
        outer = current_logger()
        @test_throws ExperimentLab.LogWriteError measure!(store, BrokenLogMeasurement(), [1.0]; state)
        @test_throws CompositeException measure!(store, BrokenLogMeasurement(asynchronous=true), [1.0]; state)
        @test current_logger() === outer
        # An open failure must escape before calling the scientific calculation.
        rm(joinpath(directory, "logs"); recursive=true)
        write(joinpath(directory, "logs"), "blocked")
        @test_throws Base.IOError measure!(store, LoggedMeasurement(), [1.0]; state)
        rm(joinpath(directory, "logs"))
        @test all(ExperimentLab.info(store, ref)["status"] == "running"
                  for ref in ExperimentLab.records(store, :measurement))

        # Caller errors escape, the previous logger is restored, and the file closes.
        outer = current_logger()
        captured_logger = Ref{Logging.AbstractLogger}()
        @test_throws ErrorException ExperimentLab.with_log(store, run) do
            captured_logger[] = current_logger()
            @info "Before calculation failure"
            error("calculation failed")
        end
        @test current_logger() === outer
        @test only(log_lines(log_file(store, run)))["msg"] == "Before calculation failure"
        @test_throws ExperimentLab.LogWriteError with_logger(captured_logger[]) do
            @info "After closing"
        end
        @test_throws ErrorException ExperimentLab.with_log(store, run) do
            @info "Invalid argument" value=error("message construction failed")
        end
        @test length(log_lines(log_file(store, run))) == 1

        other = ExperimentLab.record_execution!(store, algorithm)
        path = log_file(store, other)
        mkpath(path) # A directory blocks opening the logfile.
        called = Ref(false)
        @test_throws SystemError ExperimentLab.with_log(store, other) do
            called[] = true
        end
        @test !called[]
        @test_throws MethodError ExperimentLab.with_log(() -> nothing, store, state)
        foreign = DataStore(mktempdir())
        @test_throws ArgumentError ExperimentLab.with_log(() -> nothing, foreign, run)
    end
end

@testset "Shared writers and explicitly awaited tasks" begin
    mktempdir() do directory
        store = DataStore(directory)
        algorithm = ExperimentLab.record_algorithm!(store, LogSettings())
        run = ExperimentLab.record_execution!(store, algorithm)
        # Independent scopes share the store's lock, even with separate file handles.
        @sync for task_id in 1:4
            Threads.@spawn ExperimentLab.with_log(store, run) do
                for step in 1:5
                    @info "Concurrent message" task_id step payload=repeat("x", 4096)
                    yield()
                end
            end
        end
        rows = log_lines(log_file(store, run))
        @test length(rows) == 20
        @test Set((row["task_id"], row["step"]) for row in rows) ==
              Set((task_id, step) for task_id in 1:4 for step in 1:5)
        ExperimentLab.with_log(store, run) do
            @sync @async @info "Inherited context"
        end
        @test last(log_lines(log_file(store, run)))["owner"]["id"] == string(run.id)

        empty_run = ExperimentLab.record_execution!(store, algorithm)
        ExperimentLab.with_log(() -> nothing, store, empty_run)
        @test isempty(read(log_file(store, empty_run), String))
    end
end
