"""
    AbstractAlgorithmConfig

Base type for immutable algorithm configuration values. Configurations compare
and hash by concrete type and field values, including nested configurations.
Concrete configurations with fields should expose a keyword constructor so
call sites identify every setting by name. Positional construction is an
implementation detail used only when validation or normalization is required.
"""
abstract type AbstractAlgorithmConfig end

_algorithm_config_name(config::AbstractAlgorithmConfig) =
    nameof(typeof(config))

_show_algorithm_config_value(io::IO, value) =
    show(IOContext(io, :compact => true), value)

# Fallback for values without an expression codec; this is display, not export.
function _show_algorithm_config_fields(io, config, prefix, active=IdDict())
    if haskey(active, config)
        println(io, prefix, "<cycle>")
        return nothing
    end
    active[config] = nothing
    try
        fields = fieldnames(typeof(config))
        for (index, field) in enumerate(fields)
            islast = index == length(fields)
            branch = islast ? "└─ " : "├─ "
            child_prefix = prefix * (islast ? "   " : "│  ")
            value = getfield(config, field)
            print(io, prefix, branch, field, ": ")
            if value isa AbstractAlgorithmConfig
                print(io, _algorithm_config_name(value))
                if isempty(fieldnames(typeof(value)))
                    println(io, "()")
                else
                    println(io)
                    _show_algorithm_config_fields(io, value, child_prefix, active)
                end
            else
                _show_algorithm_config_value(io, value)
                println(io)
            end
        end
    finally
        delete!(active, config)
    end
    return nothing
end

function _show_config_summary(io, config)
    print(io, _algorithm_config_name(config))
    print(io, isempty(fieldnames(typeof(config))) ? "()" : "(...)")
    return nothing
end

function _display_config_tree(io, config)
    try
        return configtree(config)
    catch err
        err isa ConfigError || rethrow()
        println(io, "# Display only: no editable tree at ", err.path)
        println(io, _algorithm_config_name(config), ":")
        _show_algorithm_config_fields(io, config, "")
        return nothing
    end
end

function Base.show(io::IO, ::MIME"text/plain", config::AbstractAlgorithmConfig)
    get(io, :compact, false) && return _show_config_summary(io, config)
    tree = _display_config_tree(io, config)
    isnothing(tree) || print(io, tree)
    return nothing
end

function Base.show(io::IO, config::AbstractAlgorithmConfig)
    get(io, :compact, false) && return _show_config_summary(io, config)
    tree = _display_config_tree(io, config)
    isnothing(tree) && return nothing
    # Julia's @show calls this method. Escape the surrounding string literal,
    # preserving physical newlines so the tree remains readable.
    print(io, "@config ", repeat(string('"'), 3), '\n')
    for character in tree
        character in ('\\', '"', '$') && print(io, '\\')
        print(io, character)
    end
    print(io, repeat(string('"'), 3))
    return nothing
end

function Base.:(==)(left::T, right::T) where {T<:AbstractAlgorithmConfig}
    return all(
        field -> getfield(left, field) == getfield(right, field),
        fieldnames(T),
    )
end

function Base.isequal(left::T, right::T) where {T<:AbstractAlgorithmConfig}
    return all(
        field -> isequal(getfield(left, field), getfield(right, field)),
        fieldnames(T),
    )
end

function Base.hash(config::T, seed::UInt) where {T<:AbstractAlgorithmConfig}
    result = hash(T, seed)
    for field in fieldnames(T)
        result = hash(getfield(config, field), result)
    end
    return result
end
