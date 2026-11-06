include(joinpath(@__DIR__, "setup.jl"))
using ExperimentLab
using AlgorithmConfigLab

# 1. Register settings and one execution. These calls do not run an algorithm.
@kwdef struct ReadingSettings <: AbstractAlgorithmConfig
    count::Int = 3
end
settings = ReadingSettings()
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, settings; label="readings")
run = ExperimentLab.record_execution!(store, algorithm; label="first run")

# 2. Associate a state with the execution, then explicitly copy and save it.
values = [1.0, 2.0, 3.0]
state = record_state!(store, run; step=1, label="sample readings")
captured = capture(state, values)
saved = save_snapshot!(store, captured)
values[1] = 99.0
restored = load_snapshot(store, saved)
@assert restored == [1.0, 2.0, 3.0]
@show store.path
@show restored

# 3. Define a diagnostic and convert it to validated, ordinary Julia data.
struct ReadingsSaved <: AbstractLogEvent
    count::Int
end
registry = EventRegistry("readings.saved.v1" => ReadingsSaved)
diagnostic = event_record(registry, ReadingsSaved(length(restored)))
@show diagnostic
@assert diagnostic == (event="readings.saved.v1", data=(count=3,))

# Julia Logging prints this message. It is not automatically saved in the store.
# See 02_execution_logs.jl for explicitly binding messages with with_log.
@info "Readings saved" diagnostic...

# 4. Complete the execution and inspect both areas through the same package.
ExperimentLab.finish_execution!(store, run)
display(store)
display(registry)
store_description = ExperimentLab.describe(store)
event_description = ExperimentLab.describe(registry)
nothing
