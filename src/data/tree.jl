function reference_tree(document::AbstractDict)
    # Build adjacency once. Only direct parent links define ownership.
    entries = Dict{Tuple{Symbol,String},Dict{String,Any}}()
    descendants = Dict{Union{Nothing,Tuple{Symbol,String}},Vector{Tuple{Symbol,String}}}()
    for (kind, name) in pairs(TABLES), record in values(document[name])
        key = (kind, record["id"])
        entries[key] = record
        parent = record["parent"]
        parentkey = parent === nothing ? nothing : (Symbol(parent["kind"]), parent["id"])
        push!(get!(descendants, parentkey, Tuple{Symbol,String}[]), key)
    end
    for keys in values(descendants)
        sort!(keys; by=key -> (entries[key]["created"], key[2]))
    end
    return entries, descendants
end

ref_name(kind::Symbol) = uppercasefirst(string(kind)) * "Ref"
short_id(id::Union{UUID,AbstractString}) = first(string(id), 8)

function tree_label(kind::Symbol, record::AbstractDict)
    parts = String[ref_name(kind) * " " * short_id(record["id"])]
    label = get(record, "label", "")
    isempty(label) || push!(parts, repr(label))
    for field in ("config_type", "status", "availability")
        haskey(record, field) && push!(parts, record[field])
    end
    haskey(record, "step") && push!(parts, "step=$(record["step"])")
    kind === :snapshot && push!(parts, record["stored"] ? "stored" : "removed")
    kind === :pin && push!(parts, "owner=" * repr(record["owner"]))
    return join(parts, " · ")
end

"""
    ExperimentLab.showtree(io, store, root=nothing; maxdepth=8, maxnodes=100)

Display ownership from index metadata only. Input links are arrows, never expanded.
Omit `root` for the whole store. Limits include input-link lines; depth zero shows
only the selected root (or the store header). No scientific payload is loaded.
"""
function showtree(io::IO, store::DataStore, root::Union{Nothing,RecordRef}=nothing;
        maxdepth::Integer=8, maxnodes::Integer=100)
    maxdepth >= 0 || throw(ArgumentError("maxdepth must be nonnegative"))
    maxnodes > 0 || throw(ArgumentError("maxnodes must be positive"))
    document = current_index(store)
    root === nothing || lookup(document, store, root)
    entries, descendants = reference_tree(document)
    remaining = Ref(maxnodes)
    truncated = Ref(false)
    function draw(key::Tuple{Symbol,String}, prefix::AbstractString,
            marker::AbstractString, depth::Integer)
        remaining[] -= 1
        record = entries[key]
        print(io, '\n', prefix, marker, tree_label(key[1], record))
        continuation = prefix * (marker == "└─ " ? "   " : "│  ")
        descend(key, record, continuation, depth)
    end
    function descend(key::Union{Nothing,Tuple{Symbol,String}},
            record::Union{Nothing,AbstractDict}, prefix::AbstractString, depth::Integer)
        owned = get(descendants, key, Tuple{Symbol,String}[])
        links = record === nothing ? String[] : [
            name * " → " * ref_name(Symbol(record[name]["kind"])) * " " * short_id(record[name]["id"])
            for name in ("initial_state", "input_snapshot") if get(record, name, nothing) !== nothing]
        total = length(owned) + length(links)
        total == 0 && return
        if depth >= maxdepth
            print(io, '\n', prefix, "└─ … (depth limit)")
            return
        end
        for i in 1:total
            truncated[] && return
            if remaining[] == 0
                truncated[] = true
                print(io, '\n', prefix, "└─ … (node limit)")
                return
            end
            marker = i == total ? "└─ " : "├─ "
            if i <= length(owned)
                draw(owned[i], prefix, marker, depth + 1)
            else
                remaining[] -= 1
                print(io, '\n', prefix, marker, links[i - length(owned)])
            end
        end
    end
    if root === nothing
        show(io, store)
        descend(nothing, nothing, "", 0)
    else
        key = (Symbol(describe(root).kind), string(root.id))
        remaining[] -= 1
        print(io, tree_label(key[1], entries[key]))
        descend(key, entries[key], "", 0)
    end
    return nothing
end
showtree(store::DataStore, root::Union{Nothing,RecordRef}=nothing; kwargs...) =
    showtree(stdout, store, root; kwargs...)
