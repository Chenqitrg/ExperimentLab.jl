"""
    value_expression(value) -> Union{String,Nothing}

Extension hook for a leaf's reconstructible, single-line Julia expression.
Return `nothing` to delegate to built-in container handling. Explicit methods
take precedence over that handling. Unsupported objects fail during export.
"""
value_expression(x) = nothing
value_expression(x::Union{Nothing,Missing,Bool,String,Char,Symbol,Float16,Float32,Float64}) = repr(x)
value_expression(x::Int) = repr(x)
value_expression(x::Union{Int8,Int16,Int32,Int128,UInt8,UInt16,UInt32,UInt64,UInt128}) =
    _qualified_name(typeof(x)) * "(" * repr(x) * ")"

function _value_expression(value, active, mode, path)
    return _config_at(path) do
        if value isa AbstractAlgorithmConfig
            return _with_object(active, value) do
                fields = _config_fields(value, mode)
                isempty(fields) && return _constructor_name(config_constructor(value)) * "()"
                arguments = [string(k) * "=" * _value_expression(v, active, mode, path * "/" * string(k))
                             for (k, v) in pairs(fields)]
                _constructor_name(config_constructor(value)) * "(; " * join(arguments, ", ") * ")"
            end
        end
        expression = value_expression(value)
        if expression !== nothing
            expression isa AbstractString || throw(ArgumentError("value_expression must return text or nothing"))
            occursin('\n', expression) && throw(ArgumentError("value_expression must fit on one line"))
            parsed = Meta.parse(expression)
            (parsed === nothing || (parsed isa Expr && parsed.head in (:toplevel, :error, :incomplete))) &&
                throw(ArgumentError("value_expression must contain one complete expression"))
            return String(expression)
        end
        if value isa NamedTuple
            _check_namedtuple_types(value)
            values = [repr(k) * " => " * _value_expression(v, active, mode, path * "/" * string(k))
                      for (k, v) in pairs(value)]
            return "(; " * join(values, ", ") * ")"
        elseif value isa Tuple
            values = [_value_expression(v, active, mode, path * "/[$i]") for (i, v) in enumerate(value)]
            return "(" * join(values, ", ") * (isempty(values) ? "" : ",") * ")"
        elseif value isa Vector
            return _with_object(active, value) do
                T = eltype(value)
                T isa DataType && isempty(T.parameters) ||
                    throw(ArgumentError("vector element type $T needs an explicit codec"))
                values = [_value_expression(v, active, mode, path * "/[$i]") for (i, v) in enumerate(value)]
                _qualified_name(T) * "[" * join(values, ", ") * "]"
            end
        end
        throw(ArgumentError("no Julia-expression codec for $(typeof(value))"))
    end
end

"""
    configtree(config; style=:unicode, mode=:full) -> String

Lower-level explicit tree export; ordinary `display` uses this automatically.
This function is public but not exported. Qualified constructors require their defining
modules to be loaded in the caller. `style=:indent` uses two-space indentation.
`mode=:compact` omits only fields named by the owner's `config_defaults` hook.
"""
function configtree(config::AbstractAlgorithmConfig; style=:unicode, mode=:full)
    style in (:unicode, :indent) || throw(ArgumentError("style must be :unicode or :indent"))
    _check_mode(mode)
    io = IOBuffer()
    active = IdDict()
    _config_at("root") do
        println(io, _constructor_name(config_constructor(config)))
        _tree_fields(io, config, "", 1, "root", active, style, mode)
    end
    return String(take!(io))
end

function _tree_fields(io, config, prefix, depth, path, active, style, mode)
    return _with_object(active, config) do
        fields = _config_fields(config, mode)
        for (i, (key, value)) in enumerate(pairs(fields))
            childpath = path * "/" * string(key)
            _config_at(childpath) do
                lastchild = i == length(fields)
                marker = style === :unicode ? prefix * (lastchild ? "└─ " : "├─ ") : "  "^depth
                print(io, marker, key, ": ")
                if value isa AbstractAlgorithmConfig && !isempty(_config_fields(value, mode))
                    println(io, _constructor_name(config_constructor(value)))
                    _tree_fields(io, value, prefix * (lastchild ? "   " : "│  "), depth + 1,
                                 childpath, active, style, mode)
                else
                    println(io, _value_expression(value, active, mode, childpath))
                end
            end
        end
    end
end
