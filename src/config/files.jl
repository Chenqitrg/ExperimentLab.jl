"""
    readconfig(path_or_io, ::Type{T})

Read JSON into a concrete configuration type defined with `Configurations.@option`.
Nested fields and defaults follow `Configurations.from_dict`.
For a parameterized configuration, pass `typeof(settings)`.
"""
function readconfig(io::IO, ::Type{T}) where {T<:AbstractAlgorithmConfig}
    return Configurations.from_dict(T, JSON.parse(read(io, String); dicttype=Dict{String,Any}))
end
readconfig(path::AbstractString, ::Type{T}) where {T<:AbstractAlgorithmConfig} =
    open(io -> readconfig(io, T), path)

"""
    writeconfig(path_or_io, config; include_defaults=true)

Write the plain dictionary produced by `Configurations.to_dict` as JSON.
Encode before opening a file so conversion errors do not
truncate an existing destination.
"""
function writeconfig(io::IO, config::AbstractAlgorithmConfig; include_defaults=true)
    JSON.json(io, Configurations.to_dict(config; include_defaults))
    println(io)
    return nothing
end

function writeconfig(path::AbstractString, config::AbstractAlgorithmConfig; kwargs...)
    io = IOBuffer()
    writeconfig(io, config; kwargs...)
    write(path, take!(io))
    return nothing
end
