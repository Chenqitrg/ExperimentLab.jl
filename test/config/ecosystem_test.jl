using ExperimentLab: configtree
# Run with the sibling LoopTNRLab project; deliberately not a core test dependency.
using Test, ExperimentLab
using PMPSLab, LoopTNRLab
using TensorKit: MatrixAlgebraKit
using LatticeIteratorLab, TensorLinearSolveLab
using ExperimentLab: JSON

@testset "real configuration full and compact round trips" begin
    for original in (ProjectorGaugeFix(), TruncatedTransferPolicy(),
                     ALSSplit(; solver=CholeskySolve(), sweep=CircularSweep(; max_sweeps=3)),
                     default_looptnr(; max_rg_steps=2, dcut=8))
        for style in (:unicode, :indent), mode in (:full, :compact)
            tree = configtree(original; style, mode)
            restored = include_string(@__MODULE__, "@config " * repr(tree))
            @test isequal(restored, original)
        end
        for mode in (:full, :compact)
            io = IOBuffer()
            writeconfig(io, original; include_defaults=(mode === :full))
            @test isequal(readconfig(IOBuffer(take!(io)), typeof(original)), original)
        end
        @test length(configtree(original; mode=:compact)) < length(configtree(original))
    end
    original = default_looptnr(; max_rg_steps=2, dcut=8)
    tree = configtree(original; mode=:compact)
    @test occursin("max_rg_steps: 2", tree)
    @test !occursin("orthogonalization_algorithm:", tree)
end
