using Configurations: @option
using Test, ExperimentLab

@option struct DisplaySettings{T} <: AbstractAlgorithmConfig
    value::T
    count::Int = 2
end
mutable struct DisplayCycle <: AbstractAlgorithmConfig
    child::Any
end
DisplayCycle(; child) = DisplayCycle(child)

@testset "automatic editable configuration display" begin
    for value in (3, "quote: \"; dollar: \$; slash: \\; newline: \n", (; key=2))
        settings = DisplaySettings(; value)
        tree = sprint(show, MIME"text/plain"(), settings)
        @test isequal(include_string(@__MODULE__, "@config " * repr(tree)), settings)
        text = sprint(show, settings)
        @test startswith(text, "@config \"\"\"\n")
        @test isequal(include_string(@__MODULE__, text), settings)
        mktemp() do path, io
            result = redirect_stdout(io) do
                @show settings
            end
            @test result === settings
            flush(io)
            @test isequal(include_string(@__MODULE__, read(path, String)), settings)
        end
    end
    settings = DisplaySettings(; value=3)
    @test sprint(show, settings; context=:compact=>true) == "DisplaySettings(...)"
    @test sprint(show, MIME"text/plain"(), settings; context=:compact=>true) == "DisplaySettings(...)"
    @test !Base.isexported(ExperimentLab, :configtree)
    @test isdefined(ExperimentLab, :configtree)
end

@testset "unsupported display stays readable and explicit" begin
    settings = DisplaySettings(; value=stdout)
    for showargs in ((), (MIME"text/plain"(),))
        text = sprint(show, showargs..., settings)
        @test occursin("Display only", text)
        @test occursin("value", text)
        @test !startswith(text, "@config")
    end
    cycle = DisplayCycle(nothing)
    cycle.child = cycle
    text = sprint(show, MIME"text/plain"(), cycle)
    @test occursin("Display only", text)
    @test occursin("cycle", text)
end
