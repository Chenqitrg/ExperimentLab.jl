mutable struct _ConfigTreeNode
    field::Union{Symbol,Nothing}
    value::String
    line::Int
    prefix::String
    children::Vector{_ConfigTreeNode}
end

_tree_error(message, line, source) = throw(ConfigError("root", ArgumentError(message); line, source))

function _parse_config_tree(text::String, source)
    entries = [(i, String(rstrip(s))) for (i, s) in enumerate(split(text, '\n')) if !isempty(strip(s))]
    isempty(entries) && _tree_error("empty tree", 1, source)
    any(e -> occursin('\t', e[2]), entries) && _tree_error("use spaces instead of tabs", first(entries)[1], source)
    margin = minimum(length(s) - length(lstrip(s)) for (_, s) in entries)
    entries = [(i, String(chop(s; head=margin, tail=0))) for (i, s) in entries]
    line, roottext = first(entries)
    root = _ConfigTreeNode(nothing, strip(chopsuffix(roottext, ":")), line, "", _ConfigTreeNode[])
    stack = [root]
    graphical = length(entries) > 1 && occursin(r"[├└]─", entries[2][2])
    for (line, textline) in entries[2:end]
        depth, body, prefix = if graphical
            m = match(r"^((?:│  |   )*)([├└]─ )(.*)$", textline)
            isnothing(m) && _tree_error("invalid tree connector", line, source)
            (length(m[1]) ÷ 3 + 1, m[3], m[1] * m[2])
        else
            spaces = length(textline) - length(lstrip(textline))
            spaces > 0 && iseven(spaces) || _tree_error("use two spaces per level", line, source)
            (spaces ÷ 2, lstrip(textline), "")
        end
        depth <= length(stack) || _tree_error("missing parent level", line, source)
        parts = split(body, ':'; limit=2)
        length(parts) == 2 || _tree_error("expected field: value", line, source)
        name, value = strip.(parts)
        Base.isidentifier(name) || _tree_error("invalid field name $name", line, source)
        isempty(value) && _tree_error("missing value for $name", line, source)
        resize!(stack, depth)
        parent = last(stack)
        any(n -> n.field == Symbol(name), parent.children) &&
            _tree_error("duplicate field $name", line, source)
        child = _ConfigTreeNode(Symbol(name), String(value), line, String(prefix), _ConfigTreeNode[])
        push!(parent.children, child)
        push!(stack, child)
    end
    graphical && _check_connectors(root, "", source)
    return root
end

function _check_connectors(node, prefix, source)
    for (i, child) in enumerate(node.children)
        lastchild = i == length(node.children)
        expected = prefix * (lastchild ? "└─ " : "├─ ")
        child.prefix == expected || _tree_error("connector disagrees with tree structure; expected $(repr(expected))", child.line, source)
        _check_connectors(child, prefix * (lastchild ? "   " : "│  "), source)
    end
end

_type_path(x) = x isa Symbol || (x isa Expr && x.head === :. && length(x.args) == 2 &&
    _type_path(x.args[1]) && x.args[2] isa QuoteNode && x.args[2].value isa Symbol)

function _tree_expression(node, path, source; root=false)
    parsed = _config_at(path, node.line, source) do
        expression = Meta.parse(node.value)
        expression isa Expr && expression.head in (:toplevel, :error, :incomplete) &&
            throw(ArgumentError("expected one complete Julia expression"))
        expression
    end
    if !root && isempty(node.children)
        return Expr(:call, GlobalRef(@__MODULE__, :_config_at), Expr(:->, Expr(:tuple), parsed),
                    path, node.line, source)
    end
    _type_path(parsed) || throw(ConfigError(path, ArgumentError("branch must explicitly name a type"); line=node.line, source))
    kwargs = Expr(:tuple, Expr(:parameters,
        (Expr(:kw, child.field, _tree_expression(child, path * "/" * string(child.field), source))
         for child in node.children)...))
    constructor = Expr(:call, GlobalRef(@__MODULE__, :_config_at),
                       Expr(:->, Expr(:tuple), parsed), path, node.line, source)
    return Expr(:call, GlobalRef(@__MODULE__, :_config_construct), constructor, kwargs, path, node.line, source)
end

"""
    @config """ * "\"\"\"tree\"\"\"" * """

Construct a configuration from a literal tree. The root and each structural branch
name configuration types; leaves are Julia expressions in the caller's scope.
Unicode connectors or two-space indentation express nesting. No defaults are
guessed: this expands to keyword constructor calls, not updates to an instance.
"""
macro config(text)
    text isa String || throw(ArgumentError("@config requires a literal tree; put variables in leaf expressions"))
    source = string(__source__.file)
    return esc(_tree_expression(_parse_config_tree(text, source), "root", source; root=true))
end
