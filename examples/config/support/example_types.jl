# These types stand in for configuration types provided by an algorithm package.
# Read this file when reviewing type definitions; the numbered examples focus on usage.
module ReviewExample
using Configurations: @option
using ExperimentLab: AbstractAlgorithmConfig
export OptimizationSettings, IterativeMethod, DirectMethod, SweepSettings

@option struct DirectMethod <: AbstractAlgorithmConfig end

@option struct IterativeMethod <: AbstractAlgorithmConfig
    tolerance::Float64 = 1e-8
    maxiter::Int = 50
end

@option struct SweepSettings <: AbstractAlgorithmConfig
    min_sweeps::Int = 1
    max_sweeps::Int = 10
    function SweepSettings(min_sweeps::Integer, max_sweeps::Integer)
        1 <= min_sweeps <= max_sweeps ||
            throw(ArgumentError("require 1 <= min_sweeps <= max_sweeps"))
        new(min_sweeps, max_sweeps)
    end
end

@option struct OptimizationSettings{S<:AbstractAlgorithmConfig} <: AbstractAlgorithmConfig
    solver::S = IterativeMethod()
    sweep::SweepSettings = SweepSettings()
    verbosity::Int = 1
end
end
