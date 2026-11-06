include("../setup.jl")
using Configurations: @option
# Run from ExperimentLab: julia --project=examples examples/config/extras/value_semantics.jl
# Configurations of the same concrete type compare by their field values.
using ExperimentLab: AbstractAlgorithmConfig
using Test: @test

@option struct AccuracySettings <: AbstractAlgorithmConfig
    tolerance::Float64 = 1e-8
end

a = AccuracySettings()
b = AccuracySettings(; tolerance=1e-8)
c = AccuracySettings(; tolerance=1e-6)
@test a == b
@test a != c
@test isequal(a, b)
@test hash(a) == hash(b)

# Dict uses isequal and hash, so an equivalent configuration finds the same key.
labels = Dict(a => "strict")
@test labels[b] == "strict"

# Floating-point field semantics are preserved: == and isequal can differ.
unknown = AccuracySettings(; tolerance=NaN)
@test !(unknown == unknown)
@test isequal(unknown, unknown)
nothing
