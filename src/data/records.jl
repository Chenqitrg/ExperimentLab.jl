# Accept any input here so invalid steps receive the same descriptive ArgumentError.
function check_step(step)
    step isa Integer && !(step isa Bool) && 0 <= step <= 2^53-1 ||
        throw(ArgumentError("step must be a nonnegative exact JSON integer"))
    return nothing
end

algorithm_path(store::DataStore, id::UUID) = joinpath(store.path, "algorithms", string(id) * ".jld2")

"""Register one fixed configuration. Equal configurations are never merged automatically."""
function record_algorithm!(store::DataStore, config::AbstractAlgorithmConfig;
        label::AbstractString="", metadata=(;))
    ismutabletype(typeof(config)) && throw(ArgumentError("algorithm configurations must be immutable"))
    frozen = deepcopy(config)
    encoded = config_document(frozen)
    details = plain_data(metadata)
    provider = plain_data(implementation(frozen))
    return change!(store) do document
        ref = add_record!(document, store, :algorithm; label=String(label),
            config=encoded, config_type=stored_type_name(frozen), metadata=details,
            config_format="jld2-v1", implementation=provider)
        write_native(algorithm_path(store, ref.id), (; schema=1, algorithm=string(ref.id), value=frozen))
        document["algorithms"][string(ref.id)]["julia_config"] = "algorithms/$(ref.id).jld2"
        return ref
    end
end

"""Restore a detached algorithm configuration from trusted Julia storage."""
function load_algorithm(store::DataStore, ref::AlgorithmRef)
    record = info(store, ref)
    record["config_format"] == "jld2-v1" ||
        throw(ArgumentError("unsupported algorithm configuration format"))
    payload = read_native(algorithm_path(store, ref.id))
    payload isa NamedTuple && get(payload, :schema, nothing) === 1 &&
        get(payload, :algorithm, nothing) == string(ref.id) &&
        get(payload, :value, nothing) isa AbstractAlgorithmConfig ||
        throw(ArgumentError("invalid algorithm configuration"))
    stored_type_name(payload.value) == record["config_type"] ||
        throw(ArgumentError("algorithm configuration type does not match its record"))
    return payload.value
end

"""Record one execution under a configuration, with an optional cross-branch input link."""
function record_execution!(store::DataStore, algorithm::AlgorithmRef;
        initial_state::Union{Nothing,StateRef}=nothing,
        label::AbstractString="", provenance=(;))
    origin = plain_data(provenance)
    return change!(store) do document
        initial_state === nothing || lookup(document, store, initial_state)
        ref = add_record!(document, store, :execution; parent=algorithm, label=String(label),
            initial_state=initial_state === nothing ? nothing : ref_data(initial_state),
            provenance=origin, julia_version=string(VERSION), status="running")
        document["executions"][string(ref.id)]["log_path"] = relative_log_path(ref)
        return ref
    end
end

function finish_execution!(store::DataStore, execution::ExecutionRef;
        status::AbstractString="completed", exception=nothing)
    status in ("completed", "failed", "cancelled") || throw(ArgumentError("unknown final status"))
    exception === nothing || status == "failed" ||
        throw(ArgumentError("only failed executions can record an exception"))
    failure = exception === nothing ? nothing :
        Dict("type" => string(typeof(exception)), "message" => sprint(showerror, exception))
    change!(store) do document
        record = lookup(document, store, execution)
        record["status"] == "running" || throw(ArgumentError("execution already finished"))
        record["status"] = status
        record["finished"] = timestamp()
        failure === nothing || (record["error"] = failure)
    end
    return execution
end

"""Register a produced state under a running execution, without copying or saving its tensor."""
function record_state!(store::DataStore, execution::ExecutionRef;
        step, label::AbstractString="", metadata=(;))
    check_step(step)
    encoded = plain_data(metadata)
    return change!(store) do document
        run = lookup(document, store, execution)
        run["status"] == "running" || throw(ArgumentError("cannot add states to a finished execution"))
        add_record!(document, store, :state; parent=execution, label=String(label), step,
            metadata=encoded, availability="never_persisted")
    end
end

"""Read the direct parent reference. Algorithm roots return nothing."""
function parent_ref(store::DataStore, ref::RecordRef)
    document = current_index(store)
    parent = lookup(document, store, ref)["parent"]
    parent === nothing && return nothing
    result = data_ref(store, parent)
    lookup(document, store, result)
    return result
end

"""List direct children in creation-time/ID order; input links are not ownership edges."""
function children(store::DataStore, ref::RecordRef)
    document = current_index(store)
    lookup(document, store, ref)
    key = ref_data(ref)
    entries = [(kind, record) for (kind, name) in pairs(TABLES)
               for record in values(document[name]) if record["parent"] == key]
    sort!(entries; by=x -> (x[2]["created"], x[2]["id"]))
    return RecordRef[RecordRef{kind}(store.id, UUID(record["id"])) for (kind, record) in entries]
end
