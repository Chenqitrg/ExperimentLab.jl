include("../setup.jl")
using Configurations: @option
# Run from ExperimentLab: julia --project=examples examples/config/extras/truncation_policy.jl
# MatrixAlgebraKit truncation strategies have reconstructible configuration-tree displays.
using ExperimentLab: AbstractAlgorithmConfig, @config
using Accessors: @set, @reset
import MatrixAlgebraKit
using MatrixAlgebraKit: notrunc, truncrank, truncerror
using Test: @test

@option struct CompressionSettings{T} <: AbstractAlgorithmConfig
    truncation::T = notrunc()
end

original = CompressionSettings()
changed = @set original.truncation = truncrank(8) & truncerror(; rtol=1e-6)
shown = sprint(show, MIME"text/plain"(), changed)
print(shown)
@test isequal(include_string(@__MODULE__, "@config " * repr(shown)), changed)
@test occursin("notrunc()", sprint(show, MIME"text/plain"(), original))
# This package displays and stores the policy; it does not truncate tensors.
nothing
