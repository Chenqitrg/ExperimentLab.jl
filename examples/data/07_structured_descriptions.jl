include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab
using AlgorithmConfigLab
using JSON

# 1. Create a small history with explicit configuration, run, and state identities.
@kwdef struct DescriptionSettings <: AbstractAlgorithmConfig
    iterations::Int = 2
end
struct DescriptionMeasurement <: AbstractMeasurement end
struct DescriptionResult <: AbstractMeasurementResult
    total::Float64
end
ExperimentLab.measure(::DescriptionMeasurement, vector) = DescriptionResult(sum(vector))

store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, DescriptionSettings(); label="demo")
run = ExperimentLab.record_execution!(store, algorithm; label="first run")
state = record_state!(store, run; step=1)
saved = save_snapshot!(store, capture(state, [1.0, 2.0]))
attempt = measure!(store, DescriptionMeasurement(), saved)
ExperimentLab.finish_execution!(store, run)

# 2. Human display and machine description describe the same ownership tree.
display(store)
description = ExperimentLab.describe(store)
@show description.kind # "data_store"
@show description.counts.measurements # 1
@show description.truncated # false: no nodes were omitted.
@show only(description.children).config # JSON-ready algorithm parameters.

# 3. Focus on one execution. The parent link remains present in this subtree.
run_description = ExperimentLab.describe(store, run)
@show run_description.status # "completed"
@show run_description.parent # Link to the AlgorithmRef.
state_description = only(run_description.children)
@show state_description.step # 1
measurement_description = only(filter(node -> node.kind == "measurement", state_description.children))
@show measurement_description.input_snapshot # A reference, not another expanded subtree.
@show measurement_description.result # Relative JSON file path; no result data is loaded.

# 4. Serialize the description for AI or frontend readers. No custom encoder needed.
json_text = JSON.json(run_description)
parsed = JSON.parse(json_text)
@show parsed["status"] # "completed"
description_path = joinpath(store.path, "description.json")
write(description_path, json_text)
@show description_path # A real file containing the structured description.
# This file is an inspection report, not a backup or a restorable DataStore.

# 5. Bound large histories. Truncation is explicit, never confused with no children.
summary = ExperimentLab.describe(store, run; maxdepth=0)
@show summary.children # Empty because the depth limit hides the state.
@show summary.child_count # 1
@show summary.omitted_children # 1
@show summary.truncated # true
@show ExperimentLab.describe(saved) # A bare Ref describes its identity only.
nothing
