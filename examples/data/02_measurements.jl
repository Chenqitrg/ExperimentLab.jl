include(joinpath(@__DIR__, "..", "setup.jl"))
using Configurations: @option
# An ordinary matrix spectrum illustrates storage; this is not a CFT calculation.
using ExperimentLab
using ExperimentLab: AbstractAlgorithmConfig, @config, readconfig, writeconfig
using LinearAlgebra

# 1. Define a measurement configuration, result, and calculation.
@option struct EigenvalueMeasurement <: AbstractMeasurement
    count::Int = 2
end
struct EigenvalueResult <: AbstractMeasurementResult
    levels::Vector{Float64}
end
function ExperimentLab.measure(config::EigenvalueMeasurement, matrix)
    @info "Computing eigenvalues" count=config.count
    config.count > 0 || throw(ArgumentError("count must be positive"))
    levels = eigvals(Hermitian(matrix))
    EigenvalueResult(levels[1:min(config.count, length(levels))])
end

# 2. Register the producing algorithm and state, then measure the current matrix without saving a snapshot.
@option struct MatrixSettings <: AbstractAlgorithmConfig end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, MatrixSettings())
run = ExperimentLab.record_execution!(store, algorithm)
matrix = [2.0 1.0; 1.0 2.0]
state = record_state!(store, run; step=1, label="two-level matrix")
attempt = measure!(store, EigenvalueMeasurement(), matrix; state)
# Default Julia loading restores the result struct and its typed fields.
result = load_result(store, attempt)
@show typeof(result) # EigenvalueResult
@show eltype(result.levels) # Float64
@show result.levels # Approximately [1.0, 3.0].
@show ExperimentLab.info(store, state)["availability"] # "never_persisted"
# measure! automatically owns a separate log for this attempt.
logpath = joinpath(store.path, ExperimentLab.info(store, attempt)["log_path"])
println(read(logpath, String)) # JSON Lines; owner.id identifies this measurement.

# 3. Different parameters create another attempt; the previous result remains.
second = measure!(store, EigenvalueMeasurement(count=1), matrix; state)
@show load_result(store, second).levels # Approximately [1.0].
@show length(ExperimentLab.records(store, :measurement)) # 2

# 4. Restore the original configuration without a constructor mapping.
definition = ExperimentLab.load_measurement(store, second)
@show typeof(definition) # EigenvalueMeasurement
@show definition.count # 1
nothing
