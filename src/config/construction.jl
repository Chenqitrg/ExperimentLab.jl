"""A configuration failure with its field path, optional source location, and original `cause`."""
struct ConfigError <: Exception
    path::String
    line::Union{Nothing,Int}
    source::Union{Nothing,String}
    cause::Any
end
ConfigError(path, cause; line=nothing, source=nothing) = ConfigError(string(path), line, source, cause)

function Base.showerror(io::IO, err::ConfigError)
    print(io, "configuration ", err.path)
    isnothing(err.source) || print(io, " in ", err.source)
    isnothing(err.line) || print(io, " (line ", err.line, ")")
    print(io, ": ")
    showerror(io, err.cause)
end

function _config_at(f, path, line=nothing, source=nothing)
    try
        return f()
    catch err
        err isa InterruptException && rethrow()
        err isa ConfigError && rethrow()
        throw(ConfigError(path, err; line, source))
    end
end

"""Return the keyword constructor for tree interchange; unrelated to Accessors updates."""
config_constructor(config::AbstractAlgorithmConfig) = Base.typename(typeof(config)).wrapper

"""Return tree constructor keywords. Override when these differ from stored fields."""
config_fields(config::AbstractAlgorithmConfig) =
    NamedTuple{fieldnames(typeof(config))}(ntuple(i -> getfield(config, i), fieldcount(typeof(config))))

"""Explicit constructor defaults used only for compact output. Unknown defaults are retained."""
function config_defaults(::Type{T}) where {T<:AbstractAlgorithmConfig}
    Configurations.is_option(T) || return NamedTuple()
    return (; (name => value for name in fieldnames(T)
        for value in (Configurations.field_default(T, name),)
        if value !== Configurations.no_default && !(value isa Configurations.PartialDefault))...)
end

function _config_fields(config, mode)
    fields = config_fields(config)
    fields isa NamedTuple || throw(ArgumentError("config_fields must return a NamedTuple"))
    mode === :full && return fields
    defaults = config_defaults(typeof(config))
    defaults isa NamedTuple || throw(ArgumentError("config_defaults must return a NamedTuple"))
    return (; (k => v for (k, v) in pairs(fields)
               if !haskey(defaults, k) || !isequal(v, defaults[k]))...)
end

function _check_mode(mode)
    mode in (:full, :compact) || throw(ArgumentError("mode must be :full or :compact"))
end

function _config_construct(constructor, kwargs, path, line=nothing, source=nothing)
    return _config_at(path, line, source) do
        constructor isa Type && constructor <: AbstractAlgorithmConfig ||
            throw(ArgumentError("branch must name an AbstractAlgorithmConfig subtype"))
        constructor(; kwargs...)
    end
end

function _constructor_name(constructor)
    constructor isa Type && constructor <: AbstractAlgorithmConfig ||
        throw(ArgumentError("config_constructor must return a configuration type"))
    return _qualified_name(constructor)
end

function _qualified_name(type::Type)
    wrapper = Base.typename(Base.unwrap_unionall(type)).wrapper
    type === wrapper || throw(ArgumentError("parameterized constructor $type cannot be exported as a tree name; define an unparameterized tree constructor"))
    name = nameof(wrapper)
    Base.isidentifier(string(name)) || throw(ArgumentError("constructor has no printable identifier"))
    return join((Base.fullname(parentmodule(wrapper))..., name), ".")
end

# A recursion stack detects cycles without rejecting ordinary shared subtrees.
function _with_object(f, active, value)
    haskey(active, value) && throw(ArgumentError("cyclic configuration values cannot be exported"))
    active[value] = nothing
    try
        return f()
    finally
        delete!(active, value)
    end
end

function _check_namedtuple_types(value::NamedTuple)
    fieldtypes(typeof(value)) == map(typeof, Tuple(value)) ||
        throw(ArgumentError("named tuple with non-inferred field types needs an explicit codec"))
end
