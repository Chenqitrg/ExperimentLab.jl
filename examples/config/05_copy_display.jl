# Run from ExperimentLab: julia --project=examples examples/config/05_copy_display.jl
# Display and reconstruct the same configuration using only the normal user API.
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

display(original)
# Entering `original` in the REPL displays the same editable tree.
# @show prints an @config expression. The semicolon suppresses REPL redisplay.
@show original;

# Copy the displayed tree into @config. The module prefixes identify our shared types.
copy = @config """
Main.ReviewExample.OptimizationSettings
├─ solver: Main.ReviewExample.IterativeMethod
│  ├─ tolerance: 1.0e-8
│  └─ maxiter: 50
├─ sweep: Main.ReviewExample.SweepSettings
│  ├─ min_sweeps: 1
│  └─ max_sweeps: 10
└─ verbosity: 1
"""
@test isequal(copy, original)

# For a small change, a path saves copying the entire tree.
@reset copy.solver.tolerance = 1e-12
@test copy.solver.tolerance == 1e-12
@test original.solver.tolerance == 1e-8
# Next: see how constructors validate construction and updates and why update order matters.
nothing
