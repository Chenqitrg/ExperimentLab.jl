"""Detached state owned by snapshot consumers. Treat `value` as read-only."""
struct StateSnapshot{T}
    id::UUID
    state::StateRef
    value::T
end

"""Copy all mutable state storage. Scientific types with external buffers must specialize this."""
copy_state(value) = deepcopy(value)

"""Copy while the producer is not mutating its input; no file is written yet."""
capture(state::StateRef, value) = StateSnapshot(uuid4(), state, copy_state(value))

payload_path(store::DataStore, id::UUID) = joinpath(store.path, "tensors", string(id) * ".jld2")

"""Synchronously persist a capture. Re-saving the same retained capture is idempotent."""
function save_snapshot!(store::DataStore, captured::StateSnapshot; metadata=(;))
    encoded = plain_data(metadata)
    ref = SnapshotRef(store.id, captured.id)
    return lock(store.lock) do
        document = current_index(store)
        state = lookup(document, store, captured.state)
        if haskey(document["snapshots"], string(captured.id))
            record = lookup(document, store, ref)
            record["retained"] || throw(ArgumentError("snapshot was removed; capture a new state"))
            return ref
        end
        write_native(payload_path(store, captured.id), captured.value)
        add_record!(document, store, :snapshot; id=captured.id, parent=captured.state,
            metadata=encoded, retained=true, stored=true,
            payload="tensors/$(captured.id).jld2", format="jld2-v1",
            implementation=plain_data(implementation(captured.value)))
        state["availability"] = "available"
        write_json(joinpath(store.path, "index.json"), document)
        return ref
    end
end

"""Load a trusted Julia payload. Inspection and listing never call this automatically."""
function load_snapshot(store::DataStore, ref::SnapshotRef)
    lock(store.lock) do
        record = lookup(current_index(store), store, ref)
        record["stored"] || throw(ArgumentError("snapshot payload was deliberately removed"))
        record["format"] == "jld2-v1" || throw(ArgumentError("unsupported payload format"))
        return read_native(payload_path(store, ref.id))
    end
end

"""
    ExperimentLab.pin_snapshot!(store, snapshot; owner)

Persist a payload reference before publishing an external checkpoint. Release the
pin only after that checkpoint no longer needs the payload. This does not copy it.
"""
function pin_snapshot!(store::DataStore, ref::SnapshotRef; owner::AbstractString)
    isempty(strip(owner)) && throw(ArgumentError("pin owner must be nonempty"))
    return change!(store) do document
        record = lookup(document, store, ref)
        record["stored"] || throw(ArgumentError("cannot pin a removed payload"))
        add_record!(document, store, :pin; parent=ref, owner=String(owner))
    end
end

function mark_unused!(document::AbstractDict, record::AbstractDict)
    pinned = any(pin -> pin["parent"]["id"] == record["id"], values(document["pins"]))
    remove = record["stored"] && !record["retained"] && !pinned
    if remove
        record["stored"] = false
        state = document["states"][record["parent"]["id"]]
        available = any(s -> s["parent"] == record["parent"] && s["stored"], values(document["snapshots"]))
        state["availability"] = available ? "available" : "removed"
    end
    return remove
end

"""Release analysis retention; checkpoint pins may still keep the payload available."""
function delete_snapshot!(store::DataStore, ref::SnapshotRef)
    remove = change!(store) do document
        record = lookup(document, store, ref)
        record["retained"] = false
        mark_unused!(document, record)
    end
    # Publish removal first. A deletion failure leaves an unreachable orphan, not a dangling record.
    remove && rm(payload_path(store, ref.id); force=true)
    return nothing
end

function release_pin!(store::DataStore, ref::PinRef)
    id, remove = change!(store) do document
        pin = lookup(document, store, ref)
        record = document["snapshots"][pin["parent"]["id"]]
        delete!(document["pins"], string(ref.id))
        (UUID(record["id"]), mark_unused!(document, record))
    end
    remove && rm(payload_path(store, id); force=true)
    return nothing
end
