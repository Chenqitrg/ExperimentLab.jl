include(joinpath(@__DIR__, "setup.jl"))
using Configurations: @option
using ExperimentLab
using ExperimentLab: AbstractAlgorithmConfig, @config, readconfig, writeconfig
import JSON

# 1. The same configuration can have separate executions and separate log files.
@option struct LoggedExperimentSettings <: AbstractAlgorithmConfig end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, LoggedExperimentSettings())
first_run = ExperimentLab.record_execution!(store, algorithm; label="first run")
second_run = ExperimentLab.record_execution!(store, algorithm; label="repeat run")
first_path = joinpath(store.path, ExperimentLab.info(store, first_run)["log_path"])
second_path = joinpath(store.path, ExperimentLab.info(store, second_run)["log_path"])
@assert first_path != second_path
@assert !isfile(first_path) # Registering a run records the path, without opening it.

# 2. No StateRef, event struct or event registry is required for ordinary messages.
ExperimentLab.with_log(store, first_run) do
    @info "Algorithm started"
    @info "Step completed" step=1 cost=0.001
    # A frontend could read these complete lines while the algorithm continues.
    @assert length(readlines(first_path)) == 2
end
first_messages = JSON.parse.(readlines(first_path))
@show first_messages[1]["owner"]
@show first_messages[2]["cost"]

# 3. Re-entering a scope appends. A new run writes to a different file.
ExperimentLab.with_log(store, first_run) do
    @info "Step completed" step=2 cost=0.0001
end
ExperimentLab.with_log(store, second_run) do
    @info "Algorithm started again"
end
@assert length(readlines(first_path)) == 3
@assert length(readlines(second_path)) == 1
@show first_path
@show second_path

# Logging does not control execution status. Complete the records explicitly.
ExperimentLab.finish_execution!(store, first_run)
ExperimentLab.finish_execution!(store, second_run)
description = ExperimentLab.describe(store, first_run)
@show description.log_path
# Messages inside with_log go to the file. The prior logger is restored on exit.
# If you spawn tasks inside a scope, await them inside it before the file closes.
nothing
