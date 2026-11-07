@testset "Unified package boundary" begin
    expected = Set((:AbstractAlgorithmConfig, Symbol("@config"), :readconfig, :writeconfig, :DataStore, :record_state!, :capture, :save_snapshot!, :load_snapshot,
        :AbstractMeasurement, :AbstractMeasurementResult, :measure, :measure!, :load_result,
        :AbstractLogEvent, :EventRegistry, :event_record,
        :start_run, :pause!, :resume!, :cancel!, :run_status))
    exported = Set(filter(n -> n !== :ExperimentLab && Base.isexported(ExperimentLab, n),
                          names(ExperimentLab)))
    @test exported == expected
    @test !Base.isexported(ExperimentLab, :describe)
    loaded = Set(id.name for id in keys(Base.loaded_modules))
    for name in ("AlgorithmConfigLab", "MatrixAlgebraKit", "AlgorithmDataLab", "AlgorithmLogLab", "ExecutionLab", "TensorKit")
        @test !(name in loaded)
    end
    @test !isdefined(ExperimentLab, :AlgorithmLogger)
    @test !isdefined(ExperimentLab, :with_logfile)
    @test parentmodule(AbstractAlgorithmConfig) === ExperimentLab
    @test parentmodule(DataStore) === ExperimentLab
    @test parentmodule(EventRegistry) === ExperimentLab
    @test ExperimentLab.describe(EventRegistry()).kind == "event_registry"
    mktempdir() do path
        @test ExperimentLab.describe(DataStore(path)).kind == "data_store"
    end
end
