"""Base type for immutable, explicitly registered diagnostic event structs."""
abstract type AbstractLogEvent end

"""
    EventRegistry("stable.event.v1" => EventType, ...; codecs=())

Register concrete immutable event types. Special field types require an explicit
`Type => encoder` pair in `codecs`; encoders must return supported plain values.
Treat a registry as read-only after construction.
"""
struct EventRegistry
    names::Dict{DataType,String}
    # Different encoder functions have different types; this is an I/O boundary.
    codecs::Dict{DataType,Any}

    function EventRegistry(entries::Pair...; codecs=())
        names = Dict{DataType,String}()
        for (name, type) in entries
            name isa AbstractString && !isempty(strip(name)) ||
                throw(ArgumentError("event names must be nonempty strings"))
            type isa DataType && isconcretetype(type) && !ismutabletype(type) &&
                type <: AbstractLogEvent ||
                throw(ArgumentError("register a concrete immutable AbstractLogEvent type"))
            (haskey(names, type) || name in values(names)) &&
                throw(ArgumentError("duplicate event name or type: $name"))
            names[type] = String(name)
        end
        encoders = Dict{DataType,Any}()
        for (type, encoder) in codecs
            type isa DataType && isconcretetype(type) ||
                throw(ArgumentError("codec keys must be concrete types"))
            haskey(encoders, type) && throw(ArgumentError("duplicate codec for $type"))
            encoders[type] = encoder
        end
        new(names, encoders)
    end
end

const BasicInteger = Union{Int8,Int16,Int32,Int64,UInt8,UInt16,UInt32,UInt64}
const BasicFloat = Union{Float16,Float32,Float64}

function encode_value(value, codecs, path, depth=0)
    depth <= 32 || throw(ArgumentError("$path: nested value too deep or cyclic"))
    if codecs !== nothing && haskey(codecs, typeof(value))
        # Codec output must be plain data, not another chain of opaque objects.
        return encode_value(codecs[typeof(value)](value), nothing, path, depth + 1)
    end
    return encode_plain(value, codecs, path, depth)
end

function encode_plain(value, codecs, path, depth)
    if value === nothing || value isa Bool || value isa AbstractString
        return value isa AbstractString ? String(value) : value
    elseif value isa BasicInteger
        -(2^53 - 1) <= value <= 2^53 - 1 ||
            throw(ArgumentError("$path: integer is outside the exact JSON frontend range; provide a codec"))
        return value
    elseif value isa BasicFloat
        isfinite(value) || throw(ArgumentError("$path: non-finite number requires an explicit codec"))
        return Float64(value)
    elseif value isa NamedTuple
        items = map(keys(value), values(value)) do key, item
            encode_value(item, codecs, "$path.$key", depth + 1)
        end
        return NamedTuple{keys(value)}(items)
    elseif value isa Tuple
        return map(value, ntuple(identity, Val(length(value)))) do item, index
            encode_value(item, codecs, "$path[$index]", depth + 1)
        end
    elseif value isa AbstractVector
        return map(value, eachindex(value)) do item, index
            encode_value(item, codecs, "$path[$index]", depth + 1)
        end
    end
    throw(ArgumentError("$path: unsupported field type $(typeof(value)); provide an explicit codec"))
end

"""
    event_record(registry, event)

Validate a registered event and return its stable name and detached, JSON-ready
field data as a typed NamedTuple. Unsupported values raise an error; nothing is
stringified implicitly.
"""
function event_record(registry::EventRegistry, event::AbstractLogEvent)
    type = typeof(event)
    haskey(registry.names, type) || throw(ArgumentError("unregistered event type $type"))
    values = ntuple(Val(fieldcount(type))) do index
        encode_value(getfield(event, index), registry.codecs, String(fieldname(type, index)))
    end
    data = NamedTuple{fieldnames(type)}(values)
    return (; event=registry.names[type], data)
end
