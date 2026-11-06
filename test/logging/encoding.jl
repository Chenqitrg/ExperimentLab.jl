struct MixedEvent <: AbstractLogEvent
    step::Int
    cost::Float64
    label::String
end
struct OptionalEvent <: AbstractLogEvent
    cost::Union{Nothing,Float64}
end
struct OptionalTupleEvent <: AbstractLogEvent
    values::Tuple{Union{Nothing,Float64}}
end
struct UntypedEvent <: AbstractLogEvent
    value::Any
end
struct AbstractFieldEvent <: AbstractLogEvent
    value::Real
end

encode_solver_label(label::SolverLabel) = (; name=label.name)
encode_complex_value(value::ComplexF64) = (; real=real(value), imag=imag(value))

struct LabelEncoder
    prefix::String
end
(encoder::LabelEncoder)(label::SolverLabel) = (; name=encoder.prefix * label.name)

@testset "Mixed event fields remain typed until JSON serialization" begin
    registry = EventRegistry("mixed.v1" => MixedEvent)
    record = ExperimentLab.event_record(registry, MixedEvent(12, 1e-8, "sample"))
    @test record.data === (step=12, cost=1e-8, label="sample")
    parsed = JSON.parse(JSON.json(record))
    @test parsed["data"]["step"] == 12
    @test parsed["data"]["cost"] == 1e-8
    @test parsed["data"]["label"] == "sample"
end

@testset "Callable encoders and plain output boundaries" begin
    registry = EventRegistry("solver.v1" => DiagnosticValue{SolverLabel};
        codecs=(SolverLabel => LabelEncoder("solver:"),))
    record = ExperimentLab.event_record(registry, DiagnosticValue(SolverLabel("direct")))
    @test record.data.value.name == "solver:direct"
    chained = EventRegistry("solver.v1" => DiagnosticValue{SolverLabel};
        codecs=(SolverLabel => (_ -> (value=1.0 + 2.0im,)), ComplexF64 => encode_complex_value))
    @test_throws ArgumentError ExperimentLab.event_record(chained, DiagnosticValue(SolverLabel("direct")))

    empty_value = (items=Float64[], pair=())
    empty_registry = EventRegistry("empty.v1" => typeof(DiagnosticValue(empty_value)))
    empty_record = ExperimentLab.event_record(empty_registry, DiagnosticValue(empty_value))
    @test empty_record.data.value == empty_value
    @test empty_record.data.value.items !== empty_value.items
end

@testset "Several explicit codecs encode their registered types" begin
    registry = EventRegistry("solver.v1" => DiagnosticValue{SolverLabel},
        "complex.v1" => DiagnosticValue{ComplexF64};
        codecs=(ComplexF64 => encode_complex_value, SolverLabel => encode_solver_label))
    label = ExperimentLab.event_record(registry, DiagnosticValue(SolverLabel("direct")))
    number = ExperimentLab.event_record(registry, DiagnosticValue(1.0 + 2.0im))
    @test label.data.value === (name="direct",)
    @test number.data.value === (real=1.0, imag=2.0)

end

@testset "Nested typed fields and vectors keep their shape and detach storage" begin
    value = (pair=(1, "first"), items=[1.0, 2.0], solver=SolverLabel("direct"))
    registry = EventRegistry("nested.v1" => typeof(DiagnosticValue(value));
        codecs=(SolverLabel => encode_solver_label,))
    record = ExperimentLab.event_record(registry, DiagnosticValue(value))
    value.items[1] = 99.0
    @test record.data.value.pair == (1, "first")
    @test record.data.value.items == [1.0, 2.0]
    @test record.data.value.solver == (name="direct",)
    parsed = JSON.parse(JSON.json(record))
    @test parsed["data"]["value"]["pair"] == [1, "first"]
end

@testset "Actual values determine whether broadly declared fields can be encoded" begin
    events = (UntypedEvent(1.0), AbstractFieldEvent(2.0),
        DiagnosticValue(Any[1, "sample", nothing]), DiagnosticValue(Real[1, 2.0]),
        DiagnosticValue{Tuple{Int,Any}}((1, "sample")),
        DiagnosticValue{NamedTuple{(:value,),Tuple{Any}}}((value=1.0,)),
        DiagnosticValue{Tuple{Vararg{Float64}}}((1.0, 2.0)))
    for event in events
        registry = EventRegistry("value.v1" => typeof(event))
        record = ExperimentLab.event_record(registry, event)
        @test JSON.parse(JSON.json(record))["data"]["value"] ==
              JSON.parse(JSON.json(event.value))
    end
    registry = EventRegistry("untyped.v1" => UntypedEvent)
    for value in (NaN, Inf, SolverLabel("unsupported"), Any[1, Inf], Any[SolverLabel("nested")])
        @test_throws ArgumentError ExperimentLab.event_record(registry, UntypedEvent(value))
    end
    cyclic = Any[]
    push!(cyclic, cyclic)
    @test_throws ArgumentError ExperimentLab.event_record(registry, UntypedEvent(cyclic))
    adapted = EventRegistry("untyped.v1" => UntypedEvent;
        codecs=(SolverLabel => encode_solver_label,))
    @test ExperimentLab.event_record(adapted, UntypedEvent(SolverLabel("direct"))).data.value == (name="direct",)
end

@testset "Optional fields retain their explicit alternatives" begin
    registry = EventRegistry("optional.v1" => OptionalEvent)
    # Union-valued fields deliberately retain their explicit alternatives.
    @test ExperimentLab.event_record(registry, OptionalEvent(nothing)).data.cost === nothing
    @test ExperimentLab.event_record(registry, OptionalEvent(1e-8)).data.cost === 1e-8
    @test JSON.parse(JSON.json(ExperimentLab.event_record(registry, OptionalEvent(nothing))))["data"]["cost"] === nothing
    tuple_registry = EventRegistry("optional_tuple.v1" => OptionalTupleEvent)
    @test ExperimentLab.event_record(tuple_registry, OptionalTupleEvent((nothing,))).data.values === (nothing,)
    @test ExperimentLab.event_record(tuple_registry, OptionalTupleEvent((1e-8,))).data.values === (1e-8,)
end
