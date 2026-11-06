include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab
using AlgorithmConfigLab
using LinearAlgebra

# 1. Register fixed parameters, then an execution and one produced state.
@kwdef struct ScanSettings <: AbstractAlgorithmConfig
    chi::Int = 16
end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, ScanSettings(); label="chi-16")
run = ExperimentLab.record_execution!(store, algorithm;
    label="first run", provenance=(revision="example-revision",))
state = record_state!(store, run; step=3)
saved = save_snapshot!(store, capture(state, [3.0, 4.0]))
ExperimentLab.finish_execution!(store, run)

# 2. Later analysis belongs to the original state, even after the run finishes.
struct NormMeasurement <: AbstractMeasurement end
struct NormResult <: AbstractMeasurementResult
    value::Float64
end
ExperimentLab.measure(::NormMeasurement, vector) = NormResult(norm(vector))
attempt = measure!(store, NormMeasurement(), saved)
@show load_result(store, attempt).value # 5.0

# 3. Each node stores only its direct parent. Walk up to find the algorithm.
@show ExperimentLab.parent_ref(store, attempt) == state # true
@show ExperimentLab.parent_ref(store, state) == run # true
@show ExperimentLab.parent_ref(store, run) == algorithm # true
@show ExperimentLab.parent_ref(store, algorithm) # nothing: a root.
@show ExperimentLab.children(store, state) # Snapshot and measurement references.
settings = ExperimentLab.load_algorithm(store, algorithm)
@show settings.chi # 16

# 4. Reopening preserves identities; no in-memory registry is required.
reopened = DataStore(store.path)
@show ExperimentLab.parent_ref(reopened, attempt) == state # true
@show ExperimentLab.info(reopened, attempt)["input_snapshot"]
display(reopened) # Read only metadata; do not load tensor payloads.
nothing
