# Start here: define a configuration type, then construct its values.
include("setup.jl")
using Configurations: @option, to_dict, from_dict
using ExperimentLab: AbstractAlgorithmConfig, @config
using Test: @test

# Configurations.jl defines the type, keyword constructor, and field defaults.
# AbstractAlgorithmConfig adds ExperimentLab's tree construction/display.
@option struct ExampleSettings <: AbstractAlgorithmConfig
    tolerance::Float64 = 1e-8
    maxiter::Int = 50
end

# Ordinary keyword construction uses the defaults declared above.
defaults = ExampleSettings()
settings = ExampleSettings(maxiter=80)
@test settings.tolerance == 1e-8
@test defaults.maxiter == 50
display(settings)

# ExperimentLab's @config constructs the same type from a tree.
from_tree = @config """
ExampleSettings
└─ maxiter: 80
"""
@test from_tree == settings

# Dictionary conversion belongs to Configurations.jl too.
# The JSON file interface writes this plain dictionary.
data = to_dict(settings)
@show data
restored = from_dict(ExampleSettings, data)
@test restored == settings

# Next: 01_create_config.jl builds a nested optimization configuration.
# Its shared type definitions use @option in support/example_types.jl.
nothing
