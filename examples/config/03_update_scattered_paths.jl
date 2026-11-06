# Run from ExperimentLab: julia --project=examples examples/config/03_update_scattered_paths.jl
# The everyday workflow: modify parameters in several parts of the same tree.
include("support/setup.jl")
using ExperimentLab: @config
using Accessors: @set, @reset
using Test: @test

original = @config """
OptimizationSettings
├─ solver: IterativeMethod
│  └─ tolerance: 1e-8
├─ sweep: SweepSettings
│  └─ max_sweeps: 10
└─ verbosity: 1
"""

settings = original
println("Before:")
display(settings)

@reset settings.solver.tolerance = 1e-12
@reset settings.solver.maxiter = 80
@reset settings.sweep.max_sweeps = 20
@reset settings.verbosity = 0

# Each statement returns a new value and rebinds settings immediately.
# Paths start with the variable and can also traverse ordinary Julia containers.
@test settings.solver.tolerance == 1e-12
@test settings.solver.maxiter == 80
@test settings.sweep.max_sweeps == 20
@test settings.verbosity == 0
@test settings.sweep.min_sweeps == original.sweep.min_sweeps
@test original == OptimizationSettings()
println("After:")
display(settings)
# Next: replace an entire solver instead of editing its individual fields.
nothing
