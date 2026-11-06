@testset "Unified package boundary" begin
    expected = Set((:DataStore, :record_state!, :capture, :save_snapshot!, :load_snapshot,
        :AbstractMeasurement, :AbstractMeasurementResult, :measure, :measure!, :load_result,
        :AbstractLogEvent, :EventRegistry, :event_record))
    exported = Set(filter(n -> n !== :ExperimentLab && Base.isexported(ExperimentLab, n),
                          names(ExperimentLab)))
    @test exported == expected
    @test !Base.isexported(ExperimentLab, :describe)
    loaded = Set(id.name for id in keys(Base.loaded_modules))
    for name in ("AlgorithmDataLab", "AlgorithmLogLab", "ExecutionLab", "TensorKit",
                 "LoggingExtras", "LoggingFormats")
        @test !(name in loaded)
    end
    @test !isdefined(ExperimentLab, :AlgorithmLogger)
    @test !isdefined(ExperimentLab, :with_logfile)
    @test parentmodule(DataStore) === ExperimentLab
    @test parentmodule(EventRegistry) === ExperimentLab
    @test ExperimentLab.describe(EventRegistry()).kind == "event_registry"
    mktempdir() do path
        @test ExperimentLab.describe(DataStore(path)).kind == "data_store"
    end
end
