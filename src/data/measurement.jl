"""Immutable, reconstructible configuration for a read-only scientific calculation."""
abstract type AbstractMeasurement <: AbstractAlgorithmConfig end
"""Scientific result; concrete types and calculations belong to scientific packages."""
abstract type AbstractMeasurementResult end
"""Scientific packages implement `measure(definition, input)`; no storage is implicit."""
function measure end

"""Return plain result fields. Specialize for opaque or non-JSON scientific values."""
function result_data(result::AbstractMeasurementResult)
    type = typeof(result)
    return NamedTuple{fieldnames(type)}(ntuple(i -> getfield(result, i), Val(fieldcount(type))))
end

"""Publish a running measurement attempt for an external coordinator or `measure!`."""
function start_measurement!(store::DataStore, definition::AbstractMeasurement, state::StateRef;
        input_snapshot::Union{Nothing,SnapshotRef}=nothing, metadata=(;))
    ismutabletype(typeof(definition)) && throw(ArgumentError("measurement configurations must be immutable"))
    config = config_document(definition)
    encoded = plain_data(metadata)
    provider = plain_data(implementation(definition))
    return change!(store) do document
        lookup(document, store, state)
        if input_snapshot !== nothing
            saved = lookup(document, store, input_snapshot)
            saved["parent"] == ref_data(state) || throw(ArgumentError("snapshot/state mismatch"))
        end
        ref = add_record!(document, store, :measurement; parent=state,
            input_snapshot=input_snapshot === nothing ? nothing : ref_data(input_snapshot),
            config, implementation=provider, metadata=encoded, status="running",
            config_type=string(typeof(definition)),
            julia_config_format="julia-serialization-v1", result=nothing, error=nothing)
        atomic_write(measurement_config_path(store, ref.id)) do io
            serialize(io, (; schema=1, attempt=string(ref.id), value=definition))
        end
        document["measurements"][string(ref.id)]["julia_config"] = "measurements/$(ref.id).config.bin"
        document["measurements"][string(ref.id)]["log_path"] = relative_log_path(ref)
        return ref
    end
end

function running_attempt(document::AbstractDict, store::DataStore, ref::MeasurementRef)
    record = lookup(document, store, ref)
    record["status"] == "running" || throw(ArgumentError("measurement attempt is already finished"))
    return record
end

result_path(store::DataStore, id::UUID) = joinpath(store.path, "measurements", string(id) * ".json")
native_result_path(store::DataStore, id::UUID) = joinpath(store.path, "measurements", string(id) * ".bin")
measurement_config_path(store::DataStore, id::UUID) = joinpath(store.path, "measurements", string(id) * ".config.bin")

"""Encode and persist a result before publishing completion. Failures propagate."""
function finish_measurement!(store::DataStore, ref::MeasurementRef, result::AbstractMeasurementResult)
    payload = (; schema=1, kind="measurement_result", attempt=string(ref.id),
        type=string(typeof(result)), data=plain_data(result_data(result), "result"))
    change!(store) do document
        record = running_attempt(document, store, ref)
        atomic_write(native_result_path(store, ref.id)) do io
            serialize(io, (; schema=1, attempt=string(ref.id), value=result))
        end
        write_json(result_path(store, ref.id), payload)
        record["status"] = "completed"
        record["finished"] = timestamp()
        record["result"] = "measurements/$(ref.id).json"
        record["julia_result"] = "measurements/$(ref.id).bin"
        record["julia_result_format"] = "julia-serialization-v1"
        record["result_type"] = string(typeof(result))
    end
    return ref
end

"""Persist a failed calculation without erasing earlier attempts."""
function fail_measurement!(store::DataStore, ref::MeasurementRef, error)
    failure = Dict("type" => string(typeof(error)), "message" => sprint(showerror, error))
    change!(store) do document
        record = running_attempt(document, store, ref)
        record["status"] = "failed"
        record["finished"] = timestamp()
        record["error"] = failure
    end
    return ref
end

"""
    measure!(store, definition, input; state, ...)
    measure!(store, definition, saved_snapshot; ...)

Measure synchronously and retain a new attempt. Ordinary calculation exceptions
produce failed records. Interrupts, encoding errors and storage errors propagate.
The input is not copied or saved; the measurement must treat it as read-only.
"""
function measure!(store::DataStore, definition::AbstractMeasurement, input;
        state::StateRef, kwargs...)
    ref = start_measurement!(store, definition, state; kwargs...)
    result = try
        measure(definition, input)
    catch error
        (error isa InterruptException || is_log_failure(error)) && rethrow()
        return fail_measurement!(store, ref, error)
    end
    # Encoding/persistence is deliberately outside the calculation-failure catch.
    return finish_measurement!(store, ref, result)
end

measure!(store::DataStore, definition::AbstractMeasurement, captured::StateSnapshot; kwargs...) =
    measure!(store, definition, captured.value; state=captured.state, kwargs...)

function measure!(store::DataStore, definition::AbstractMeasurement, ref::SnapshotRef; kwargs...)
    saved = info(store, ref)
    value = load_snapshot(store, ref)
    state = data_ref(store, saved["parent"])
    return measure!(store, definition, value; state, input_snapshot=ref, kwargs...)
end

"""
    load_result(store, attempt)

Restore the original Julia result type and values from a trusted binary payload.
Load the package defining that type first, using a compatible Julia environment.
Use qualified `load_result_data` for the independent, frontend-readable JSON data.
"""
function load_result(store::DataStore, ref::MeasurementRef)
    record = info(store, ref)
    record["status"] == "completed" || throw(ArgumentError("measurement has no completed result"))
    get(record, "julia_result_format", nothing) == "julia-serialization-v1" ||
        throw(ArgumentError("measurement has no supported Julia result payload"))
    payload = open(deserialize, native_result_path(store, ref.id))
    payload isa NamedTuple && get(payload, :schema, nothing) === 1 &&
        get(payload, :attempt, nothing) == string(ref.id) &&
        get(payload, :value, nothing) isa AbstractMeasurementResult ||
        throw(ArgumentError("invalid Julia result payload"))
    string(typeof(payload.value)) == record["result_type"] ||
        throw(ArgumentError("Julia result type does not match its record"))
    return payload.value
end

"""Read the JSON representation without loading scientific types or binary payloads."""
function load_result_data(store::DataStore, ref::MeasurementRef)
    record = info(store, ref)
    record["status"] == "completed" || throw(ArgumentError("measurement has no completed result"))
    result = JSON.parsefile(result_path(store, ref.id); dicttype=Dict{String,Any})
    get(result, "schema", nothing) === 1 && get(result, "kind", nothing) == "measurement_result" &&
        get(result, "attempt", nothing) == string(ref.id) || throw(ArgumentError("invalid result document"))
    return result["data"]
end

"""
    ExperimentLab.load_measurement(store, attempt)

Restore the original measurement configuration, even for running or failed attempts.
Load its defining package first and use trusted files in a compatible Julia environment.
Constructor mappings are unnecessary; JSON configuration remains in `info(store, attempt)`.
"""
function load_measurement(store::DataStore, ref::MeasurementRef)
    record = info(store, ref)
    get(record, "julia_config_format", nothing) == "julia-serialization-v1" ||
        throw(ArgumentError("measurement has no supported Julia configuration payload"))
    payload = open(deserialize, measurement_config_path(store, ref.id))
    payload isa NamedTuple && get(payload, :schema, nothing) === 1 &&
        get(payload, :attempt, nothing) == string(ref.id) &&
        get(payload, :value, nothing) isa AbstractMeasurement ||
        throw(ArgumentError("invalid Julia measurement configuration"))
    string(typeof(payload.value)) == record["config_type"] ||
        throw(ArgumentError("measurement configuration type does not match its record"))
    return payload.value
end
