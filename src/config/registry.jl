"""
    ConfigRegistry("stable.name" => OptionType, ...)
    ConfigRegistry(first_registry, other_registries...)

Map external names to immutable `@option` configuration types or parametric
constructors. Composition rejects conflicting names/types. Treat as read-only.
Unlike EventRegistry, configurations support both encoding and reconstruction.
"""
struct ConfigRegistry
    names::Dict{Type,String}
    constructors::Dict{String,Type}

    function ConfigRegistry(entries::Pair...)
        names = Dict{Type,String}()
        constructors = Dict{String,Type}()
        for (name, type) in entries
            name isa AbstractString && !isempty(strip(name)) ||
                throw(ArgumentError("configuration names must be nonempty strings"))
            type isa Type && type <: AbstractAlgorithmConfig &&
                !isabstracttype(type) && !ismutabletype(type) && Configurations.is_option(type) ||
                throw(ArgumentError("register an immutable @option configuration type or constructor"))
            (haskey(names, type) || haskey(constructors, name)) &&
                throw(ArgumentError("duplicate configuration name or type: $name"))
            names[type] = String(name)
            constructors[String(name)] = type
        end
        new(names, constructors)
    end
end

function ConfigRegistry(first::ConfigRegistry, rest::ConfigRegistry...)
    entries = copy(first.constructors)
    for registry in rest, (name, type) in registry.constructors
        haskey(entries, name) && entries[name] !== type &&
            throw(ArgumentError("conflicting configuration name: $name"))
        entries[name] = type
    end
    return ConfigRegistry(collect(pairs(entries))...)
end

const EMPTY_CONFIG_REGISTRY = ConfigRegistry()

"""Author hook: supply a registry for a configuration family without changing its fields."""
config_registry(::Type{<:AbstractAlgorithmConfig}) = EMPTY_CONFIG_REGISTRY

function _config_registry(registry::ConfigRegistry, T::Type{<:AbstractAlgorithmConfig})
    owned = config_registry(T)
    registry === owned && return registry
    isempty(owned.names) && return registry
    isempty(registry.names) && return owned
    return ConfigRegistry(registry, owned)
end

_config_name(registry::ConfigRegistry, T::Type) = T isa Union ? nothing :
    get(registry.names, T, get(registry.names, Base.typename(T).wrapper, nothing))

function describe(registry::ConfigRegistry)
    configurations = sort!([(; name, type=string(type))
        for (type, name) in registry.names]; by=entry -> entry.name)
    return (; schema=1, kind="config_registry", configurations)
end

Base.show(io::IO, registry::ConfigRegistry) =
    print(io, "ConfigRegistry(", length(registry.names), " configurations)")
