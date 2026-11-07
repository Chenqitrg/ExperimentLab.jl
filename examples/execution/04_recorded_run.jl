include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab, ResumableFunctions
using Configurations: @option

@option struct CountingSettings <: AbstractAlgorithmConfig
    steps::Int = 3
end

@resumable function counted_sum(settings::CountingSettings)::Int
    @info "Algorithm started"
    total = 0
    for i in 1:settings.steps
        total += i
        @yield total
    end
    return total
end

settings = CountingSettings()
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, settings)
session = start_run(store, algorithm, counted_sum(settings);
    label="first sum", onstep=(_, value) -> @info "Step completed" value)

@show fetch(session) # 6; the log is closed and the record is finalized.
@show session.execution
record = ExperimentLab.info(store, session.execution)
@show record["status"] # "completed"
@show joinpath(store.path, record["log_path"])
# No with_log scope or finish_execution! call is required.
nothing
