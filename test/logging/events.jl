struct UpdateCompleted <: AbstractLogEvent
    step::Int
    cost::Float64
    duration::Float64
end
struct DiagnosticValue{T} <: AbstractLogEvent
    value::T
end
mutable struct MutableEvent <: AbstractLogEvent
    value::Int
end
struct SolverLabel
    name::String
end

@testset "Registered event fields survive JSON without implicit conversion" begin
    registry = EventRegistry("example.update.v1" => UpdateCompleted)
    record = ExperimentLab.event_record(registry, UpdateCompleted(12, 1e-8, 0.4))
    parsed = JSON.parse(JSON.json(record))
    @test parsed["event"] == "example.update.v1"
    @test parsed["data"]["step"] == 12
    @test parsed["data"]["cost"] == 1e-8
    @test parsed["data"]["duration"] == 0.4
    @test Set(keys(parsed["data"])) == Set(["step", "cost", "duration"])
    @test_throws ArgumentError ExperimentLab.event_record(registry, DiagnosticValue(2))
    @test_throws ArgumentError EventRegistry("same" => UpdateCompleted, "same" => DiagnosticValue{Int})
    @test_throws ArgumentError EventRegistry("one" => UpdateCompleted, "two" => UpdateCompleted)
    @test_throws ArgumentError EventRegistry(" " => UpdateCompleted)
    @test_throws ArgumentError EventRegistry("mutable" => MutableEvent)
    @test_throws ArgumentError EventRegistry("abstract" => AbstractLogEvent)
    @test_throws ArgumentError EventRegistry("unbound" => DiagnosticValue)
end

@testset "Unsupported values fail, explicit codecs are checked" begin
    values = Any[NaN, Inf, -Inf, 1 + 2im, big"1.2", big(2), 2^53,
                 typemax(UInt64), SolverLabel("direct"), Dict("arbitrary" => 1), [1 2]]
    for value in values
        registry = EventRegistry("value" => typeof(DiagnosticValue(value)))
        @test_throws ArgumentError ExperimentLab.event_record(registry, DiagnosticValue(value))
    end
    registry = EventRegistry("solver" => DiagnosticValue{SolverLabel};
                             codecs=(SolverLabel => (x -> (; name=x.name)),))
    record = ExperimentLab.event_record(registry, DiagnosticValue(SolverLabel("direct")))
    @test JSON.parse(JSON.json(record))["data"]["value"]["name"] == "direct"
    invalid = EventRegistry("solver" => DiagnosticValue{SolverLabel};
                            codecs=(SolverLabel => (_ -> Inf),))
    @test_throws ArgumentError ExperimentLab.event_record(invalid, DiagnosticValue(SolverLabel("direct")))
    @test_throws ArgumentError EventRegistry("solver" => DiagnosticValue{SolverLabel};
        codecs=(SolverLabel => identity, SolverLabel => identity))
end

@testset "Basic collections are copied and nested failures are rejected" begin
    value = (label="sample", valid=true, optional=nothing, values=[1.0, 2.0])
    registry = EventRegistry("sample" => typeof(DiagnosticValue(value)))
    record = ExperimentLab.event_record(registry, DiagnosticValue(value))
    value.values[1] = 99.0
    parsed = JSON.parse(JSON.json(record))
    @test parsed["data"]["value"]["values"] == [1.0, 2.0]
    @test parsed["data"]["value"]["optional"] === nothing
    @test parsed["data"]["value"]["valid"] === true
    bad = (values=[SolverLabel("hidden")],)
    registry = EventRegistry("sample" => typeof(DiagnosticValue(bad)))
    @test_throws ArgumentError ExperimentLab.event_record(registry, DiagnosticValue(bad))
end
