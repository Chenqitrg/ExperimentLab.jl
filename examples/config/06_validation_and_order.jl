# Run from ExperimentLab: julia --project=examples examples/config/06_validation_and_order.jl
# Inner constructors validate both ordinary construction and Accessors reconstruction.
include("support/setup.jl")
using ExperimentLab: @config
using Accessors: @set, @reset
using Test: @test, @test_throws

original = OptimizationSettings()
settings = original

# SweepSettings requires 1 <= min_sweeps <= max_sweeps.
@test_throws ArgumentError SweepSettings(0, 10)
@test_throws ArgumentError (@set settings.sweep.min_sweeps = 0)
@test settings === original

# Raise the upper bound before raising the lower bound.
@test_throws ArgumentError (@set settings.sweep.min_sweeps = 20)
@reset settings.sweep.max_sweeps = 30
@reset settings.sweep.min_sweeps = 20
@test settings.sweep == SweepSettings(; min_sweeps=20, max_sweeps=30)

# Separate statements take effect separately; there is no transaction block.
@reset settings.verbosity = 0
# `let` keeps the binding local inside this exception check in scripts and the REPL.
let candidate = settings
    @test_throws ArgumentError (@reset candidate.sweep.min_sweeps = 0)
    @test candidate === settings
end
@test settings.verbosity == 0
@test original.verbosity == 1

# Replace a whole subtree when its fields should be validated together.
new_sweep = @config """
SweepSettings
├─ min_sweeps: 20
└─ max_sweeps: 30
"""
replaced = @set original.sweep = new_sweep
@test replaced.sweep == settings.sweep
@test original.sweep == SweepSettings()
display(settings)
nothing
