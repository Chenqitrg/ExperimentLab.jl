# Run from ExperimentLab: julia --project=examples examples/config/01_create_config.jl
# Create the optimization configuration that all six examples use.
include("support/setup.jl")
using ExperimentLab: @config
using Test: @test

# A real algorithm package supplies types defined with Configurations.@option.
# See 00_define_options.jl for a direct definition, and support/example_types.jl
# for the @option definitions used here. @config constructs their values.
original = @config """
OptimizationSettings
├─ solver: IterativeMethod
│  └─ tolerance: 1e-8
├─ sweep: SweepSettings
│  └─ max_sweeps: 10
└─ verbosity: 1
"""

# Omitted fields use constructor defaults: maxiter=50 and min_sweeps=1.
@test original.solver.maxiter == 50
@test original.sweep.min_sweeps == 1
@test original == OptimizationSettings(;
    solver=IterativeMethod(; tolerance=1e-8),
    sweep=SweepSettings(; max_sweeps=10),
    verbosity=1,
)
display(original)

# The same tree can be written with two spaces per level.
indented = @config """
OptimizationSettings
  solver: IterativeMethod
    tolerance: 1e-8
  sweep: SweepSettings
    max_sweeps: 10
  verbosity: 1
"""
@test isequal(indented, original)
# Next: use a path to change one field of this configuration.
nothing
