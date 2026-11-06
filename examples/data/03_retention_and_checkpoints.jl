include(joinpath(@__DIR__, "..", "setup.jl"))
using Configurations: @option
using ExperimentLab
using AlgorithmConfigLab

# 1. Save a state that will also be required by a checkpoint.
@option struct RestartSettings <: AbstractAlgorithmConfig end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, RestartSettings())
run = ExperimentLab.record_execution!(store, algorithm)
state = record_state!(store, run; step=1, label="state required for restart")
saved = save_snapshot!(store, capture(state, [1.0, 2.0]))

# 2. A checkpoint pin references the existing payload; it does not duplicate it.
pin = ExperimentLab.pin_snapshot!(store, saved; owner="checkpoint-001")
# An external checkpoint writer would now publish a checkpoint referencing saved.
@show length(readdir(joinpath(store.path, "tensors"))) # 1

# 3. Release analysis retention. The checkpoint still needs the tensor.
ExperimentLab.delete_snapshot!(store, saved)
@show ExperimentLab.info(store, saved)["retained"] # false
@show load_snapshot(store, saved) # [1.0, 2.0]

# 4. After removing the external checkpoint, release its pin too.
ExperimentLab.release_pin!(store, pin)
@show readdir(joinpath(store.path, "tensors")) # Empty.
@show ExperimentLab.info(store, state)["availability"] # "removed"
nothing
