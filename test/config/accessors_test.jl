using Accessors: @set, @reset
using Test, ExperimentLab

include("../../examples/config/support/example_types.jl")
using .ReviewExample

@testset "review configurations use standard reconstruction" begin
    original = OptimizationSettings()
    changed = @set original.solver.maxiter = 80
    @test changed.solver.maxiter == 80
    @test original.solver.maxiter == 50
    @test changed.sweep === original.sweep

    # Both keyword construction and positional reconstruction enforce the invariant.
    @test_throws ArgumentError SweepSettings(; min_sweeps=0)
    @test_throws ArgumentError SweepSettings(0, 10)
    @test_throws ArgumentError (@set original.sweep.min_sweeps = 0)
    @test (@set original.sweep.max_sweeps = 30).sweep.max_sweeps == 30

    settings = original
    @reset settings.solver = DirectMethod()
    @test settings.solver isa DirectMethod
    @test typeof(settings) !== typeof(original)
    @test original.solver isa IterativeMethod

    # Standard Julia statements commit separately; a later failure does not undo them.
    @reset settings.verbosity = 0
    @test_throws ArgumentError (@reset settings.sweep.min_sweeps = 0)
    @test settings.verbosity == 0
    @test settings.sweep === original.sweep
end
