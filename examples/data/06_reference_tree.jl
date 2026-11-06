include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab
using AlgorithmConfigLab

# 1. Register one configuration and explicitly reuse it for two executions.
@kwdef struct IterationSettings <: AbstractAlgorithmConfig
    iterations::Int = 2
end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, IterationSettings(); label="original settings")
first_run = ExperimentLab.record_execution!(store, algorithm; label="first run")
first_state = record_state!(store, first_run; step=1)
final_state = record_state!(store, first_run; step=2)
saved = save_snapshot!(store, capture(final_state, [3.0, 4.0]))
ExperimentLab.finish_execution!(store, first_run)
second_run = ExperimentLab.record_execution!(store, algorithm; label="repeat run")
second_state = record_state!(store, second_run; step=1)

# 2. Another registration always gets its own identity, even for equal parameters.
other_algorithm = ExperimentLab.record_algorithm!(store, IterationSettings(); label="new registration")
@show other_algorithm == algorithm # false

# 3. A branch belongs to its algorithm. Its input is a separate link to an old state.
branch = ExperimentLab.record_execution!(store, other_algorithm;
    initial_state=final_state, label="continue from old state")
branch_state = record_state!(store, branch; step=1)
@show ExperimentLab.parent_ref(store, branch) == other_algorithm # true
@show ExperimentLab.info(store, branch)["initial_state"]
# This records provenance only. The caller loads the tensor and runs the algorithm.

# 4. Measurements belong to the state they inspect; no second tensor copy on disk.
struct SquaredNorm <: AbstractMeasurement end
struct SquaredNormResult <: AbstractMeasurementResult
    value::Float64
end
ExperimentLab.measure(::SquaredNorm, vector) = SquaredNormResult(sum(abs2, vector))
attempt = measure!(store, SquaredNorm(), saved)
@show load_result(store, attempt).value # 25.0
@show length(readdir(joinpath(store.path, "tensors"))) # 1

# 5. Display the whole tree, or focus on one run. Arrows are not expanded.
display(store)
ExperimentLab.showtree(stdout, store, first_run)
println()
# Bound a larger history when reviewing in the REPL.
ExperimentLab.showtree(stdout, store; maxdepth=2, maxnodes=20)
println()
nothing
