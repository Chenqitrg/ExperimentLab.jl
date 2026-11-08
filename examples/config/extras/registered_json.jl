# Run from ExperimentLab: julia --project=. examples/config/extras/registered_json.jl
using ExperimentLab, Configurations
using Test: @test

# These structs contain algorithm parameters only.
@option struct JSONDirectMethod <: AbstractAlgorithmConfig end
@option struct JSONIterativeMethod <: AbstractAlgorithmConfig
    maxiter::Int = 50
end
@option struct JSONSettings{S} <: AbstractAlgorithmConfig
    solver::S = JSONDirectMethod()
    tolerance::Float64 = 1e-8
end

# Register the parametric constructor once, not every JSONSettings{S} specialization.
const JSON_CONFIGS = ExperimentLab.ConfigRegistry(
    "demo.direct" => JSONDirectMethod,
    "demo.iterative" => JSONIterativeMethod,
    "demo.settings" => JSONSettings,
)
ExperimentLab.config_registry(::Type{<:JSONSettings}) = JSON_CONFIGS

settings = JSONSettings(solver=JSONIterativeMethod(maxiter=80))
display(settings)
record = ExperimentLab.config_record(JSON_CONFIGS, settings)
@show record["type"]
@show record["parameters"]["solver"]

# The file remains available for interactive inspection during this Julia session.
path = joinpath(mktempdir(), "settings.json")
writeconfig(path, settings)
println(read(path, String))

# The registry resolves names and reconstructs nested types. No Julia expression
# from the file is evaluated, and the caller need not know JSONSettings{...}.
restored = readconfig(path, JSON_CONFIGS)
@test restored == settings
@test typeof(restored) === typeof(settings)
@test readconfig(path, typeof(settings)) == settings
@show path
nothing
