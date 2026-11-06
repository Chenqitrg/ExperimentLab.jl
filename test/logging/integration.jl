read_records(io::IOBuffer) = JSON.parse.(split(String(take!(io)), '\n'; keepempty=false))

@testset "LoopTNR-style event survives standard JSON and terminal routing" begin
    registry = EventRegistry("looptnr.sweep.v1" => UpdateCompleted)
    output, terminal_output = IOBuffer(), IOBuffer()
    disk = MinLevelLogger(FormatLogger(
        (io, event) -> LoggingFormats.JSON(; recursive=true, nest_kwargs=false)(io, event), output), Logging.Info)
    terminal = MinLevelLogger(FormatLogger(terminal_output) do io, log
        println(io, log.message, " cost=", log.kwargs[:data].cost)
    end, Logging.Warn)
    with_logger(TeeLogger(disk, terminal)) do
        @info "Sweep completed" event_record(registry, UpdateCompleted(1, 1e-8, 0.4))...
        @warn "Slow convergence" event_record(registry, UpdateCompleted(2, 1e-7, 0.5))...
        @debug "Hidden" event_record(registry, UpdateCompleted(3, 0.0, 0.0))...
    end
    records = read_records(output)
    @test length(records) == 2
    @test records[1]["event"] == "looptnr.sweep.v1"
    @test records[1]["data"]["step"] == 1
    @test records[1]["data"]["cost"] == 1e-8
    @test records[1]["data"]["duration"] == 0.4
    @test records[1]["level"] == "info"
    @test records[1]["module"] == "Main"
    @test records[1]["line"] isa Integer
    terminal_text = String(take!(terminal_output))
    @test !occursin("Sweep completed", terminal_text)
    @test occursin("Slow convergence cost=1.0e-7", terminal_text)
end

@testset "Encoded nested values stay structured with recursive JSON" begin
    value = (; history=[1.0, 0.1], label="trial", optional=nothing,
              solver=SolverLabel("direct"), pair=(1, true))
    registry = EventRegistry("diagnostic.v1" => typeof(DiagnosticValue(value));
                             codecs=(SolverLabel => encode_solver_label,))
    output = IOBuffer()
    logger = FormatLogger((io, event) -> LoggingFormats.JSON(; recursive=true, nest_kwargs=false)(io, event), output)
    with_logger(logger) do
        @info "Diagnostic" event_record(registry, DiagnosticValue(value))...
    end
    data = only(read_records(output))["data"]["value"]
    @test data["history"] == [1.0, 0.1]
    @test data["optional"] === nothing
    @test data["solver"]["name"] == "direct"
    @test data["pair"] == [1, true]
    @test data["label"] == "trial"
end

@testset "Standard file scope appends, flushes and closes on failure" begin
    registry = EventRegistry("step.v1" => UpdateCompleted)
    mktempdir() do directory
        path = joinpath(directory, "events.jsonl")
        for step in 1:2
            open(path, "a") do io
                logger = FormatLogger((io, event) -> LoggingFormats.JSON(; recursive=true, nest_kwargs=false)(io, event), io)
                with_logger(logger) do
                    @info "Step" event_record(registry, UpdateCompleted(step, 0.1, 0.4))...
                    @test length(readlines(path)) == step
                end
                # Validate outside @info when rejection must throw to the caller.
                before = filesize(path)
                @test_throws ArgumentError event_record(registry, UpdateCompleted(step, NaN, 0.0))
                @test filesize(path) == before
            end
        end
        @test [JSON.parse(line)["data"]["step"] for line in readlines(path)] == [1, 2]
        stream = Ref{IOStream}()
        @test_throws ErrorException open(path, "a") do io
            stream[] = io
            error("algorithm failed")
        end
        @test !isopen(stream[])
    end
end

module ForeignLogSource
using Logging
emit() = @info "Foreign message" value=42
end

@testset "Module selection uses the library filter" begin
    registry = EventRegistry("step.v1" => UpdateCompleted)
    output, foreign_output = IOBuffer(), IOBuffer()
    ours = EarlyFilteredLogger(log -> log._module === Main,
        FormatLogger((io, event) -> LoggingFormats.JSON(; recursive=true, nest_kwargs=false)(io, event), output))
    foreign = EarlyFilteredLogger(log -> log._module !== Main, SimpleLogger(foreign_output))
    with_logger(TeeLogger(ours, foreign)) do
        ForeignLogSource.emit()
        @info "Our step" event_record(registry, UpdateCompleted(1, 0.1, 0.4))...
    end
    @test only(read_records(output))["event"] == "step.v1"
    @test occursin("Foreign message", String(take!(foreign_output)))
end

@testset "Context transformers share one file stream" begin
    registry = EventRegistry("step.v1" => UpdateCompleted)
    mktempdir() do directory
        path = joinpath(directory, "contexts.jsonl")
        open(path, "a") do io
            sink = FormatLogger((io, event) -> LoggingFormats.JSON(; recursive=true, nest_kwargs=false)(io, event), io)
            @sync for step in 1:8
                Threads.@spawn begin
                    context = TransformerLogger(sink) do log
                        (; log..., kwargs=(; log.kwargs..., execution_id="run-$step"))
                    end
                    with_logger(context) do
                        @info "Step" event_record(registry, UpdateCompleted(step, 0.1, 0.4))...
                    end
                end
            end
        end
        records = JSON.parse.(readlines(path))
        @test length(records) == 8
        @test Set(record["data"]["step"] for record in records) == Set(1:8)
        @test all(record["execution_id"] == "run-$(record["data"]["step"])" for record in records)
    end
end
