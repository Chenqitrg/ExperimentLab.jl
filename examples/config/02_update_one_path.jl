# Run from ExperimentLab: julia --project=examples examples/config/02_update_one_path.jl
# Start with the same tree, then change one parameter through its path.
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

# Update the current variable; aliases still refer to the original value.
settings = original
returned = @reset settings.solver.maxiter = 80
@test returned === settings
@test settings.solver.maxiter == 80
@test original.solver.maxiter == 50
@test settings.solver.tolerance == original.solver.tolerance
@test settings.sweep == original.sweep

# A top-level field is a path with one component.
@reset settings.verbosity = 0
@test settings.verbosity == 0
@test original.verbosity == 1

# Use @set when you want a separate candidate for comparison.
candidate = @set settings.solver.maxiter = 120
@test candidate.solver.maxiter == 120
@test settings.solver.maxiter == 80
display(settings)
# Dot paths are ordinary Julia property paths.
# Next: change several scattered parameters with ordinary Julia statements.
nothing
