@testset "Inspection bounds human output without truncating machine data" begin
    entries = ["step.$i" => DiagnosticValue{Val{i}} for i in 1:20]
    registry = EventRegistry(entries...)
    output = IOBuffer()
    show(IOContext(output, :limit => true, :displaysize => (12, 80)), MIME"text/plain"(), registry)
    limited = String(take!(output))
    @test occursin("more", limited)
    @test length(split(limited, '\n')) <= 12
    @test length(ExperimentLab.describe(registry).events) == 20
    full = repr(MIME"text/plain"(), registry; context=:limit => false)
    @test occursin("\"step.20\"", full)
    @test !occursin("more", full)

    calls = Ref(0)
    encoder = x -> (calls[] += 1; x.name)
    registry = EventRegistry("label.v1" => DiagnosticValue{SolverLabel};
        codecs=(SolverLabel => encoder,))
    @test ExperimentLab.describe(registry).codecs[1].encoder == "anonymous function"
    repr(MIME"text/plain"(), registry)
    @test calls[] == 0
end

@testset "Registry descriptions are sorted data, not callable internals" begin
    registry = EventRegistry("z.step" => UpdateCompleted, "a.label" => DiagnosticValue{SolverLabel};
        codecs=(SolverLabel => LabelEncoder("do not display captured state"),))
    info = ExperimentLab.describe(registry)
    @test info.kind == "event_registry"
    @test [item.name for item in info.events] == ["a.label", "z.step"]
    @test occursin("UpdateCompleted", info.events[2].type)
    @test info.codecs[1].encoder == "Main.LabelEncoder"
    @test JSON.parse(JSON.json(info))["events"][1]["name"] == "a.label"
    detailed = repr(MIME"text/plain"(), registry)
    @test occursin("a.label", detailed)
    @test !occursin("do not display captured state", detailed)
    @test !occursin('\n', repr(registry))
    @test !occursin('\n', repr(MIME"text/plain"(), registry; context=:compact => true))
    @test isempty(ExperimentLab.describe(EventRegistry()).events)
end
