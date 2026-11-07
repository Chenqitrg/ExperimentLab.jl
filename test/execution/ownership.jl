@testset "Execution is owned by ExperimentLab" begin
    @test isdefined(ExperimentLab, :start_run)
    if isdefined(ExperimentLab, :start_run)
        @test parentmodule(ExperimentLab.Session) === ExperimentLab
        @test parentmodule(ExperimentLab.start_run) === ExperimentLab
        @test !("ExecutionLab" in (id.name for id in keys(Base.loaded_modules)))
    end
end
