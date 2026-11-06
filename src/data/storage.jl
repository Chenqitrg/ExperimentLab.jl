# Stage next to the destination so rename is a local-filesystem publication boundary.
# This does not promise fsync durability or support independently opened writers.
function atomic_write(f, path::AbstractString)
    temporary, io = mktemp(dirname(path))
    try
        f(io)
        flush(io)
        close(io)
        Base.Filesystem.rename(temporary, path)
    finally
        isopen(io) && close(io)
        ispath(temporary) && rm(temporary)
    end
    return nothing
end

function write_json(path::AbstractString, document::Union{AbstractDict,NamedTuple})
    text = JSON.json(document) * "\n"
    atomic_write(path) do io
        write(io, text) == ncodeunits(text) || error("incomplete JSON write")
    end
end

function read_index(path::AbstractString)
    document = JSON.parsefile(joinpath(path, "index.json"); dicttype=Dict{String,Any})
    document isa AbstractDict && get(document, "schema", nothing) === 1 &&
        get(document, "kind", nothing) == "algorithm_data" ||
        throw(ArgumentError("unsupported ExperimentLab index"))
    UUID(document["id"])
    all(name -> get(document, name, nothing) isa AbstractDict, values(TABLES)) ||
        throw(ArgumentError("invalid record tables"))
    return document
end

function DataStore(path::AbstractString)
    root = abspath(path)
    mkpath(root)
    index = joinpath(root, "index.json")
    if !isfile(index)
        isempty(readdir(root)) || throw(ArgumentError("new stores require an empty directory"))
        document = Dict{String,Any}("schema" => 1, "kind" => "algorithm_data",
            "id" => string(uuid4()), "created" => timestamp(), "julia_version" => string(VERSION),
            (name => Dict{String,Any}() for name in values(TABLES))...)
        for directory in ("tensors", "measurements", "algorithms")
            mkdir(joinpath(root, directory))
        end
        write_json(index, document)
    end
    document = read_index(root)
    return DataStore(root, UUID(document["id"]), ReentrantLock())
end

function current_index(store::DataStore)
    document = read_index(store.path)
    UUID(document["id"]) == store.id || throw(ArgumentError("data directory identity changed"))
    return document
end

function change!(f, store::DataStore)
    lock(store.lock) do
        document = current_index(store)
        result = f(document)
        write_json(joinpath(store.path, "index.json"), document)
        return result
    end
end

"""Read detached metadata without deserializing scientific payloads."""
function info(store::DataStore, ref::RecordRef)
    document = current_index(store)
    return lookup(document, store, ref)
end

"""List typed references in stable creation-time/ID order; arrival is not step order."""
function records(store::DataStore, kind::Symbol)
    entries = values(current_index(store)[table(kind)])
    ordered = sort!(collect(entries); by=x -> (x["created"], x["id"]))
    return [RecordRef{kind}(store.id, UUID(entry["id"])) for entry in ordered]
end
