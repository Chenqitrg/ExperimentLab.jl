using Configurations: @option
using ExperimentLab: ConfigError
using ExperimentLab: configtree
using Test, ExperimentLab

module TreeFixtures
using Configurations: @option
using ExperimentLab
@option struct Solver <: AbstractAlgorithmConfig
    tol::Float64 = 1e-8
    maxiter::Int = 100
end
@option struct Run{S,V} <: AbstractAlgorithmConfig
    solver::S
    count::Int
    value::V = nothing
end
struct Empty <: AbstractAlgorithmConfig end
@option struct UnicodeSettings <: AbstractAlgorithmConfig
    χ::Int = 2
end
struct Positive <: AbstractAlgorithmConfig
    count::Int
    function Positive(; count=1)
        count > 0 || throw(DomainError(count, "must be positive"))
        new(count)
    end
end
struct Derived <: AbstractAlgorithmConfig
    twice::Int
    function Derived(twice::Int)
        iseven(twice) || throw(ArgumentError("twice must be even"))
        new(twice)
    end
end
Derived(; value) = Derived(2value)
end

@testset "tree constructors and caller scope" begin
    calls = Int[]
    next(i) = (push!(calls, i); i)
    config = @config """
    TreeFixtures.Run
    ├─ solver: TreeFixtures.Solver
    │  ├─ tol: 1e-10
    │  └─ maxiter: next(1)
    ├─ count: next(2)
    └─ value: "x:y"
    """
    @test config.solver.tol == 1e-10
    @test config.solver.maxiter == 1
    @test config.count == 2
    @test config.value == "x:y"
    @test calls == [1, 2]
    child = config.solver
    second = @config """
      TreeFixtures.Run
        solver: child
        count: 2
        value: "x:y"
    """
    @test isequal(config, second)
    @test second.solver === child
    @test (@config "TreeFixtures.Empty") isa TreeFixtures.Empty
    @test (@config "TreeFixtures.UnicodeSettings\n  χ: 8").χ == 8
    let maxiter=7, constructor=:shadow, kwargs=:shadow
        @test (@config "TreeFixtures.Solver\n  maxiter: maxiter").maxiter == 7
    end
end

capture_error(f) = try f(); nothing catch err; err end
expand_tree(text) = macroexpand(@__MODULE__, Expr(:macrocall, Symbol("@config"), LineNumberNode(1), text))

@testset "tree syntax and constructor diagnostics" begin
    for text in (
        "", "TreeFixtures.Run\n    count: 2", "TreeFixtures.Solver\n  tol: 1e-8\n  tol: 1e-9",
        "TreeFixtures.Solver\n\ttol: 1e-8", "TreeFixtures.Solver\n└─ tol: 1e-8\n└─ maxiter: 2",
        "TreeFixtures.Run\n├─ solver: TreeFixtures.Solver\n   └─ tol: 1e-8\n└─ count: 2",
        "TreeFixtures.Solver\n  maxiter: 1; 2", "TreeFixtures.Solver\n  maxiter: (",
    )
        @test capture_error(() -> expand_tree(text)) !== nothing
    end
    @test_throws ConfigError (@config "TreeFixtures.Solver\n  missing: 2")
    @test_throws ConfigError (@config "TreeFixtures.Run\n  count: 2")
    @test_throws ConfigError (@config "Int\n  x: 2")
    err = capture_error(() -> @config """
    TreeFixtures.Run
      solver: TreeFixtures.Positive
        count: -1
      count: 2
    """)
    @test err isa ConfigError
    @test err.cause isa DomainError
    @test occursin("solver", sprint(showerror, err))
    @test occursin("line", sprint(showerror, err))
    err = capture_error(() -> @config "TreeFixtures.Solver\n  tol: error(\"leaf failed\")")
    @test err isa ConfigError
    @test occursin("tol", sprint(showerror, err))
    err = capture_error(() -> @config "TreeFixtures.Run\n  solver: NoSuchConstructor\n    count: 2\n  count: 2")
    @test err isa ConfigError
    @test occursin("solver", sprint(showerror, err))
end

ExperimentLab.config_fields(x::TreeFixtures.Derived) = (; value=x.twice ÷ 2)

function reconstruct_tree(text)
    return include_string(@__MODULE__, "@config " * repr(text), "generated-config.jl")
end

@testset "editable tree output and explicit defaults" begin
    for original in (
        TreeFixtures.Empty(), TreeFixtures.UnicodeSettings(; χ=8), TreeFixtures.Derived(; value=3),
        TreeFixtures.Run(; solver=TreeFixtures.Solver(), count=3),
        TreeFixtures.Run(; solver=TreeFixtures.Solver(; tol=1e-12), count=3,
                        value=("a\nb", :x, Float32(0.25), Int8(2), [1, 2], (; x=2))),
    ), style in (:unicode, :indent), mode in (:full, :compact)
        tree = configtree(original; style, mode)
        @test isequal(reconstruct_tree(tree), original)
    end
    tree = configtree(TreeFixtures.Solver(); mode=:compact)
    @test !occursin("maxiter:", tree)
    @test occursin("count: 3", configtree(TreeFixtures.Run(; solver=TreeFixtures.Empty(), count=3); mode=:compact))
    @test_throws ConfigError configtree(TreeFixtures.Run(; solver=TreeFixtures.Empty(), count=1, value=stdout))
    cyclic = Any[]
    push!(cyclic, cyclic)
    @test_throws ConfigError configtree(TreeFixtures.Run(; solver=TreeFixtures.Empty(), count=1, value=cyclic))
    @test_throws ArgumentError configtree(TreeFixtures.Empty(); style=:other)
    @test_throws ArgumentError configtree(TreeFixtures.Empty(); mode=:other)
end
