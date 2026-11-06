# Dynamic dictionaries are confined to storage/JSON boundaries, not tensor work.
function plain_data(value, path::AbstractString="data", depth::Integer=0)
    depth <= 32 || throw(ArgumentError("$path: cyclic or excessively nested data"))
    if value === nothing || value isa Union{Bool,AbstractString}
        return value isa AbstractString ? String(value) : value
    elseif value isa Union{Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64}
        -(2^53-1) <= value <= 2^53-1 || throw(ArgumentError("$path: integer exceeds exact JSON range"))
        return value
    elseif value isa Union{Float16,Float32,Float64}
        isfinite(value) || throw(ArgumentError("$path: non-finite number needs an explicit encoding"))
        return Float64(value)
    elseif value isa NamedTuple || value isa AbstractDict
        encoded = Dict{String,Any}()
        for (key,item) in pairs(value)
            key isa Union{Symbol,AbstractString} || throw(ArgumentError("$path: object keys must be names"))
            name = string(key)
            haskey(encoded, name) && throw(ArgumentError("$path: duplicate JSON key $name"))
            encoded[name] = plain_data(item, "$path.$key", depth+1)
        end
        return encoded
    elseif value isa Tuple || value isa AbstractVector
        return [plain_data(item, "$path[$i]", depth+1) for (i,item) in enumerate(value)]
    elseif value isa AbstractArray
        return Dict("shape" => collect(size(value)), "layout" => "column-major",
                    "values" => plain_data(vec(value), path, depth+1))
    end
    throw(ArgumentError("$path: unsupported value $(typeof(value)); supply plain data explicitly"))
end

function config_document(config::AbstractAlgorithmConfig; constructors=())
    io = IOBuffer()
    writeconfig(io, config; constructors)
    return plain_data(JSON.parse(String(take!(io))), "config")
end

function implementation(config)
    mod = parentmodule(typeof(config))
    id = Base.PkgId(mod)
    version = Base.pkgversion(mod)
    return (; module_name=string(mod), package_name=id.name,
        package_uuid=isnothing(id.uuid) ? nothing : string(id.uuid),
        package_version=isnothing(version) ? nothing : string(version),
        julia_version=string(VERSION))
end
