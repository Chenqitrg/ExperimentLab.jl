"""
    readconfig(path_or_io, ::Type{T}; registry=config_registry(T))
    readconfig(path_or_io, registry::ConfigRegistry)

Read parameter dictionaries with a known concrete type, or tagged configurations
through a registry. Names are looked up, never evaluated as Julia expressions.
Defaults and concrete field conversion use Configurations. Registered parametric
constructors infer their parameters from reconstructed children.
"""
function readconfig(io::IO, ::Type{T}; registry::ConfigRegistry=config_registry(T)) where {T<:AbstractAlgorithmConfig}
    return _decode_config(T, JSON.parse(read(io, String); dicttype=Dict{String,Any}), registry)
end
readconfig(path::AbstractString, ::Type{T}; kwargs...) where {T<:AbstractAlgorithmConfig} =
    open(io -> readconfig(io, T; kwargs...), path)
readconfig(io::IO, registry::ConfigRegistry) = readconfig(io, AbstractAlgorithmConfig; registry)
readconfig(path::AbstractString, registry::ConfigRegistry) =
    open(io -> readconfig(io, registry), path)

"""
    writeconfig(path_or_io, config; registry=config_registry(typeof(config)), include_defaults=true)

Write configuration parameters as JSON. Registered nodes include an external
`type` and a `parameters` object; unregistered nodes retain plain parameters.
Encode before opening a file so conversion errors do not
truncate an existing destination.
"""
function writeconfig(io::IO, config::AbstractAlgorithmConfig;
        registry::ConfigRegistry=config_registry(typeof(config)), include_defaults=true)
    JSON.json(io, _encode_config(config, registry, Configurations.ToDictOption(; include_defaults)))
    println(io)
    return nothing
end

function writeconfig(path::AbstractString, config::AbstractAlgorithmConfig; kwargs...)
    io = IOBuffer()
    writeconfig(io, config; kwargs...)
    write(path, take!(io))
    return nothing
end
