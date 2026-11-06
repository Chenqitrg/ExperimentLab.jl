include(joinpath(@__DIR__, "..", "setup.jl"))
using Configurations: @option
# 1. Create a real on-disk store. Variables remain available in the REPL.
using ExperimentLab
using AlgorithmConfigLab
@option struct MatrixPreparation <: AbstractAlgorithmConfig end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, MatrixPreparation())
run = ExperimentLab.record_execution!(store, algorithm)
@show store.path
state = record_state!(store, run; step=1, label="initial matrix")
tensor = [1.0 2.0; 3.0 4.0]

# 2. Capture makes an independent copy, but does not yet write a tensor file.
captured = capture(state, tensor)
tensor[1, 1] = 99.0
@show captured.value[1, 1] # 1.0
@show readdir(joinpath(store.path, "tensors")) # Empty.

# 3. Save that copy. Saving the same capture again reuses the same identity/file.
saved = save_snapshot!(store, captured)
same = save_snapshot!(store, captured)
@show saved == same # true
@show ExperimentLab.info(store, saved)

# 4. Reopen the store and load the state into a new Julia object.
reopened = DataStore(store.path)
restored = load_snapshot(reopened, saved)
@show restored # [1.0 2.0; 3.0 4.0]
@show ExperimentLab.info(store, state)["availability"] # "available"
nothing
