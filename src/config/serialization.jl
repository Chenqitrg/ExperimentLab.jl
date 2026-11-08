# Configurations still owns defaults and field conversions. This layer adds
# external identities, then resolves only explicitly registered constructors.
function _encode_config(config::AbstractAlgorithmConfig, registry, options, depth=0)
    depth <= 32 || throw(ArgumentError("configuration nesting exceeds 32 levels"))
    owner = typeof(config)
    registry = _config_registry(registry, owner)
    parameters = Dict{String,Any}()
    for field in fieldnames(owner)
        value = getfield(config, field)
        options.include_defaults || value != Configurations.field_default(owner, field) || continue
        encoded = _encode_config_value(owner, value, registry, options, depth + 1)
        # Plain Union fields still use upstream aliases. Registered children have
        # their own discriminator and need no alias in the struct declaration.
        expected = fieldtype(owner, field)
        if value isa AbstractAlgorithmConfig && expected isa Union &&
                count(Configurations.is_option, Base.uniontypes(expected)) > 1 &&
                _config_name(_config_registry(registry, typeof(value)), typeof(value)) === nothing
            alias = Configurations.type_alias(typeof(value))
            alias === nothing && throw(ArgumentError("register the Union configuration $(typeof(value)) or provide a Configurations alias"))
            encoded = Dict(alias => encoded)
        end
        parameters[string(field)] = encoded
    end
    name = _config_name(registry, owner)
    return isnothing(name) ? parameters : Dict("type" => name, "parameters" => parameters)
end

function _encode_config_value(owner, value, registry, options, depth)
    depth <= 32 || throw(ArgumentError("configuration nesting exceeds 32 levels"))
    if value isa AbstractAlgorithmConfig
        return _encode_config(value, registry, options, depth)
    elseif value isa Union{Tuple,AbstractVector}
        return [_encode_config_value(owner, item, registry, options, depth + 1) for item in value]
    elseif value isa NamedTuple || value isa AbstractDict
        return Dict(string(key) => _encode_config_value(owner, item, registry, options, depth + 1)
            for (key, item) in pairs(value))
    end
    return Configurations.to_dict(owner, value, options)
end

"""Return a JSON-ready `type`/`parameters` record for a registered configuration."""
function config_record(registry::ConfigRegistry, config::AbstractAlgorithmConfig;
        include_defaults::Bool=true)
    registry = _config_registry(registry, typeof(config))
    isnothing(_config_name(registry, typeof(config))) &&
        throw(ArgumentError("unregistered configuration type $(typeof(config))"))
    encoded = _encode_config(config, registry, Configurations.ToDictOption(; include_defaults))
    # Match the actual JSON representation, including Symbols and any external
    # values handled by JSON.jl, so this agrees with stored config documents.
    return JSON.parse(JSON.json(encoded); dicttype=Dict{String,Any})
end

_config_envelope(value) = value isa AbstractDict &&
    length(value) == 2 && haskey(value, "type") && haskey(value, "parameters")

function _decode_config(T::Type{<:AbstractAlgorithmConfig}, document::AbstractDict,
        registry, depth=0)
    depth <= 32 || throw(ArgumentError("configuration nesting exceeds 32 levels"))
    registry = _config_registry(registry, T)
    constructor = T
    # Untagged, known concrete types still use ordinary Configurations dictionaries.
    # A real parameter named `type` is not metadata unless this node is registered.
    tagged = _config_envelope(document) &&
        (!isconcretetype(T) || _config_name(registry, T) !== nothing)
    if tagged
        name = document["type"]
        name isa AbstractString && haskey(registry.constructors, name) ||
            throw(ArgumentError("unregistered configuration name: $name"))
        candidate = registry.constructors[name]
        allowed = typeintersect(T, candidate)
        allowed !== Union{} ||
            throw(ArgumentError("configuration $name does not match $T"))
        constructor = isconcretetype(allowed) ? allowed : candidate
        document = document["parameters"]
        document isa AbstractDict || throw(ArgumentError("configuration parameters must be an object"))
    end
    Configurations.is_option(constructor) ||
        throw(ArgumentError("a registered configuration type is required"))
    !tagged && !isconcretetype(constructor) &&
        throw(ArgumentError("plain parameter dictionaries require a concrete configuration type"))
    fields = Dict{String,Any}()
    for (name, value) in document
        field = Symbol(name)
        if !(field in fieldnames(constructor))
            Configurations.ignore_extra(constructor) && continue
            throw(Configurations.InvalidKeyError(name, string.(collect(fieldnames(constructor)))))
        end
        expected = fieldtype(constructor, field)
        fields[name] = _decode_config_value(expected, value, registry, depth + 1)
    end
    # Configurations supplies defaults and construction. Parametric constructors
    # infer their type parameters from decoded children; fixed fields use the
    # owner's upstream conversion hooks.
    kwargs = (; (Symbol(name) => _config_field_value(constructor, Symbol(name), value)
        for (name, value) in fields)...)
    result = constructor(; kwargs...)
    result isa T || throw(ArgumentError("configuration constructor returned the wrong type"))
    return result
end

function _config_field_value(owner, name, value)
    expected = fieldtype(Base.unwrap_unionall(owner), name)
    if expected isa TypeVar
        # An untagged object could be an encoded external strategy. Do not
        # silently infer Dict as its Julia type when that identity is absent.
        value isa AbstractDict && !(expected.ub <: AbstractDict) && throw(ArgumentError(
            "$owner.$name has no concrete type for an untagged object; " *
            "read with typeof(config) and provide a Configurations field conversion"))
        value isa expected.ub || throw(ArgumentError(
            "$owner.$name cannot be reconstructed as $(expected.ub); " *
            "read with typeof(config) and provide a Configurations field conversion"))
        return value
    end
    expected isa Type || return value
    value isa AbstractAlgorithmConfig && value isa expected && return value
    if expected <: AbstractVector && value isa AbstractVector &&
            any(item -> item isa AbstractAlgorithmConfig, value) && all(item -> item isa eltype(expected), value)
        return convert(expected, value)
    end
    return Configurations.from_dict(owner, Configurations.OptionField(name), expected, value)
end

function _decode_config_value(expected, value, registry, depth)
    depth <= 32 || throw(ArgumentError("configuration nesting exceeds 32 levels"))
    expected isa TypeVar && (expected = expected.ub)
    if expected isa Union && value isa AbstractDict
        choices = filter(T -> T <: AbstractAlgorithmConfig, Base.uniontypes(expected))
        if !isempty(choices)
            _config_envelope(value) && return _decode_config(Union{choices...}, value, registry, depth)
            length(choices) == 1 && return _decode_config(only(choices), value, registry, depth)
            for choice in choices
                alias = Configurations.type_alias(choice)
                alias !== nothing && haskey(value, alias) &&
                    return _decode_config(choice, value[alias], registry, depth)
            end
            throw(ArgumentError("Union configuration needs a registered type or a Configurations alias"))
        end
    end
    if expected isa Type && expected <: AbstractAlgorithmConfig && value isa AbstractDict
        return _decode_config(expected, value, registry, depth)
    elseif expected === Any && _config_envelope(value)
        return _decode_config(AbstractAlgorithmConfig, value, registry, depth)
    elseif value isa AbstractDict && expected isa Type && expected <: NamedTuple && isconcretetype(expected)
        names = fieldnames(expected)
        Set(keys(value)) == Set(string.(names)) ||
            throw(ArgumentError("named tuple configuration fields do not match"))
        return NamedTuple{names}(map(name -> _decode_config_value(
            fieldtype(expected, name), value[string(name)], registry, depth + 1), names))
    elseif value isa AbstractDict && (expected === Any || expected isa Type && expected <: AbstractDict)
        element = expected === Any ? Any : valtype(expected)
        return Dict(key => _decode_config_value(element, item, registry, depth + 1)
            for (key, item) in value)
    elseif value isa AbstractVector && expected isa Type && expected <: Tuple && isconcretetype(expected)
        length(value) == fieldcount(expected) || throw(ArgumentError("configuration tuple length differs"))
        return Tuple(_decode_config_value(fieldtype(expected, i), item, registry, depth + 1)
            for (i, item) in enumerate(value))
    elseif value isa AbstractVector
        element = expected isa Type && expected <: AbstractVector ? eltype(expected) : Any
        return [_decode_config_value(element, item, registry, depth + 1) for item in value]
    end
    return value
end
