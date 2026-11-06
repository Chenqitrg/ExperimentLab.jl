# Run from ExperimentLab: julia --project=examples examples/config/extras/json_files.jl
# Save the same optimization configuration used in the main walkthrough.
include("../support/setup.jl")
using ExperimentLab: readconfig, writeconfig
using Test: @test

original = OptimizationSettings(; solver=IterativeMethod(; maxiter=80), verbosity=0)

mktempdir() do directory
    path = joinpath(directory, "settings.json")
    writeconfig(path, original)
    println(read(path, String))
    restored = readconfig(path, typeof(original))
    @test isequal(restored, original)
end
# The concrete type supplies field types and defaults. The file contains plain data.
# This example cleans up its temporary file.
nothing
