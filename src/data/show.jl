function Base.show(io::IO, store::DataStore)
    print(io, "DataStore(")
    show(io, store.path)
    print(io, ")")
end
function Base.show(io::IO, ref::RecordRef{K}) where K
    print(io, "RecordRef(", K, ", ", ref.id, ")")
end
function Base.show(io::IO, captured::StateSnapshot)
    print(io, "StateSnapshot(", captured.id, ", ", nameof(typeof(captured.value)), ")")
end
function Base.show(io::IO, ::MIME"text/plain", store::DataStore)
    get(io, :compact, false) ? show(io, store) : showtree(io, store)
    return nothing
end
Base.show(io::IO, ::MIME"text/plain", ref::RecordRef) = show(io, ref)
function Base.show(io::IO, ::MIME"text/plain", captured::StateSnapshot)
    show(io, captured)
    get(io, :compact, false) || print(io, "\n  State ID: ", captured.state.id,
        "\n  Storage: independent in-memory copy; persistence is explicit")
    return nothing
end
