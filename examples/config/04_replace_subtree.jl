# Run from ExperimentLab: julia --project=examples examples/config/04_replace_subtree.jl
# Combine the macros: build a new subtree, then install it at a path.
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

new_solver = @config """
IterativeMethod
├─ tolerance: 1e-12
└─ maxiter: 80
"""
settings = original
@reset settings.solver = new_solver
@test settings.solver === new_solver
@test settings.sweep == original.sweep
@test original.solver.maxiter == 50

# An ordinary constructor is equally valid for a small replacement.
same_change = @set original.solver = IterativeMethod(; tolerance=1e-12, maxiter=80)
@test same_change == settings

# The whole solver can change type because the parent has a parametric solver field.
@reset settings.solver = DirectMethod()
@test settings.solver isa DirectMethod
@test original.solver isa IterativeMethod
@test typeof(settings) != typeof(original)
display(settings)
# settings.solver = ... replaces the subtree; settings.solver.maxiter = ... changes one field.
# Next: copy a displayed tree back into @config.
nothing
