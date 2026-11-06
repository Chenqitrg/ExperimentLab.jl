"""
    ExperimentLab.describe(store[, root]; maxdepth=8, maxnodes=100)

Return a detached, JSON-ready ownership tree for AI/frontend inspection. Read only
index metadata: configurations, statuses, provenance, and payload paths are included;
tensors, result values, and native Julia objects are never loaded. Input links are
references, not expanded children. This is a description, not a restorable store.

`child_count` counts all direct children; `omitted_children` counts those not shown.
`truncated` is true if this node or any descendant omits children. The node budget
covers record nodes (not the store header); a selected root consumes one node.
Depth zero describes only the root/header. Limits do not cap arbitrary metadata size.
"""
function describe(store::DataStore, root::Union{Nothing,RecordRef}=nothing;
        maxdepth::Integer=8, maxnodes::Integer=100)
    maxdepth >= 0 || throw(ArgumentError("maxdepth must be nonnegative"))
    maxnodes > 0 || throw(ArgumentError("maxnodes must be positive"))
    document = current_index(store)
    root === nothing || lookup(document, store, root)
    entries, descendants = reference_tree(document)
    remaining = Ref(maxnodes)
    function describe_children(key::Union{Nothing,Tuple{Symbol,String}}, depth::Integer)
        keys = get(descendants, key, Tuple{Symbol,String}[])
        children = NamedTuple[]
        if depth < maxdepth
            for child in keys
                remaining[] == 0 && break
                push!(children, describe_node(child, depth + 1))
            end
        end
        omitted_children = length(keys) - length(children)
        return (; children, child_count=length(keys), omitted_children,
            truncated=omitted_children > 0 || any(child -> child.truncated, children))
    end
    function describe_node(key::Tuple{Symbol,String}, depth::Integer)
        remaining[] -= 1
        # Index fields are metadata only; sorting also stabilizes JSON field order.
        record = entries[key]
        fields = (; (Symbol(name) => record[name] for name in sort!(collect(keys(record))))...)
        return (; schema=1, kind=string(key[1]), store_id=string(store.id),
            fields..., describe_children(key, depth)...)
    end
    limits = (; maxdepth, maxnodes)
    if root === nothing
        counts = (; (Symbol(name) => length(document[name]) for name in values(TABLES))...)
        return (; schema=1, kind="data_store", id=string(store.id), path=store.path,
            counts, limits, describe_children(nothing, 0)...)
    end
    key = (Symbol(describe(root).kind), string(root.id))
    return (; describe_node(key, 0)..., limits)
end

"""Describe a bare reference's identity; supply `store` to include metadata and children."""
describe(ref::RecordRef{K}) where K =
    (; schema=1, kind=string(K), store_id=string(ref.store_id), id=string(ref.id))
describe(snapshot::StateSnapshot) =
    (; schema=1, kind="captured_state", id=string(snapshot.id),
        state_id=string(snapshot.state.id), store_id=string(snapshot.state.store_id),
        value_type=string(typeof(snapshot.value)))
