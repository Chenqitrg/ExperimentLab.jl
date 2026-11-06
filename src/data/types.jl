"""A local scientific-data directory. Use one coordinated writer per directory."""
struct DataStore
    path::String
    id::UUID
    lock::ReentrantLock
end

"""A typed identity scoped to a single data directory."""
struct RecordRef{K}
    store_id::UUID
    id::UUID
end
const AlgorithmRef = RecordRef{:algorithm}
const ExecutionRef = RecordRef{:execution}
const StateRef = RecordRef{:state}
const SnapshotRef = RecordRef{:snapshot}
const MeasurementRef = RecordRef{:measurement}
const PinRef = RecordRef{:pin}

const TABLES = (algorithm="algorithms", execution="executions", state="states",
                snapshot="snapshots", measurement="measurements", pin="pins")
const PARENT_KIND = (algorithm=nothing, execution=:algorithm, state=:execution,
                     snapshot=:state, measurement=:state, pin=:snapshot)
table(kind::Symbol) = hasproperty(TABLES, kind) ? getproperty(TABLES, kind) :
    throw(ArgumentError("unknown record kind $kind"))
timestamp() = Dates.format(now(UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"

function lookup(document::AbstractDict, store::DataStore, ref::RecordRef{K}) where K
    ref.store_id == store.id || throw(ArgumentError("reference belongs to a different store"))
    entries = document[table(K)]
    haskey(entries, string(ref.id)) || throw(ArgumentError("unknown $K reference $(ref.id)"))
    return entries[string(ref.id)]
end

ref_data(ref::RecordRef{K}) where K = Dict("kind" => string(K), "id" => string(ref.id))
function data_ref(store::DataStore, data::AbstractDict)
    kind = Symbol(data["kind"])
    table(kind)
    return RecordRef{kind}(store.id, UUID(data["id"]))
end

function add_record!(document::AbstractDict, store::DataStore, kind::Symbol;
        parent::Union{Nothing,RecordRef}=nothing, id::UUID=uuid4(), fields...)
    expected = getproperty(PARENT_KIND, kind)
    if expected === nothing
        parent === nothing || throw(ArgumentError("$kind must be a root record"))
    else
        parent isa RecordRef{expected} || throw(ArgumentError("$kind requires a $expected parent"))
        lookup(document, store, parent)
    end
    entries = document[table(kind)]
    haskey(entries, string(id)) && throw(ArgumentError("record identity already exists"))
    entries[string(id)] = Dict{String,Any}(
        "id" => string(id), "created" => timestamp(),
        "parent" => parent === nothing ? nothing : ref_data(parent),
        (string(k) => v for (k,v) in fields)...)
    return RecordRef{kind}(store.id, id)
end
