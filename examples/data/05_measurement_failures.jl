include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab
using AlgorithmConfigLab

# 1. Define a measurement that can fail for a particular parameter choice.
@kwdef struct RatioMeasurement <: AbstractMeasurement
    divisor::Float64 = 1.0
end
struct RatioResult <: AbstractMeasurementResult
    value::Float64
end
function ExperimentLab.measure(config::RatioMeasurement, values)
    config.divisor != 0 || throw(ArgumentError("divisor must be nonzero"))
    RatioResult(sum(values) / config.divisor)
end

# 2. A calculation error creates a failed attempt.
struct VectorSettings <: AbstractAlgorithmConfig end
store = DataStore(mktempdir())
algorithm = ExperimentLab.record_algorithm!(store, VectorSettings())
run = ExperimentLab.record_execution!(store, algorithm)
state = record_state!(store, run; step=1, label="produced vector")
failed = measure!(store, RatioMeasurement(divisor=0.0), [1.0, 2.0]; state)
@show ExperimentLab.info(store, failed)["status"] # "failed"
@show ExperimentLab.info(store, failed)["error"]["message"]

# 3. Retry with a new measurement configuration; the failed attempt remains.
retried = measure!(store, RatioMeasurement(divisor=2.0), [1.0, 2.0]; state)
@show failed == retried # false
@show load_result(store, retried).value # 1.5
@show ExperimentLab.info(store, failed)["status"] # Still "failed".
# Encoding and storage failures instead propagate to the caller.
nothing
