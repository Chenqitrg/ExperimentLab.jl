# Only activities own logs. States and snapshots can be mentioned in messages.
const LogOwner = Union{ExecutionRef,MeasurementRef}
relative_log_path(ref::RecordRef{K}) where K = "logs/$(table(K))/$(ref.id).jsonl"

"""A log output failure, distinct from an ordinary measurement calculation error."""
struct LogWriteError{E} <: Exception
    cause::E
end
function Base.showerror(io::IO, error::LogWriteError)
    print(io, "log output failed: ")
    showerror(io, error.cause)
end

# Preserve output failures wrapped by fetch/wait or @sync in measurement code.
function is_log_failure(error)
    error isa LogWriteError && return true
    error isa CompositeException && return any(is_log_failure, error.exceptions)
    error isa TaskFailedException && return any(
        item -> is_log_failure(item.exception), Base.current_exceptions(error.task; backtrace=false))
    return false
end

# FormatLogger handles formatting, writing and per-message flushing. This wrapper
# supplies record identity, synchronizes writers and makes failures escape @info.
struct RecordLogger{L,C} <: Logging.AbstractLogger
    sink::L
    context::C
    lock::ReentrantLock
end
Logging.min_enabled_level(::RecordLogger) = Logging.Info
Logging.shouldlog(::RecordLogger, args...) = true
Logging.catch_exceptions(::RecordLogger) = false

function Logging.handle_message(logger::RecordLogger, args...; kwargs...)
    lock(logger.lock) do
        try
            isopen(logger.sink.stream) || error("log scope is closed; await tasks before leaving with_log")
            # IOStream append mode seeks only on open. Re-seek under the shared
            # lock so overlapping scopes cannot write through stale file offsets.
            seekend(logger.sink.stream)
            fields = (; kwargs..., logger.context..., timestamp=timestamp())
            Logging.handle_message(logger.sink, args...; fields...)
        catch error
            error isa InterruptException && rethrow()
            throw(LogWriteError(error))
        end
    end
    return nothing
end

function record_logger(io::IO, store::DataStore, ref::RecordRef{K}) where K
    formatter = LoggingFormats.JSON(; recursive=true, nest_kwargs=false)
    sink = LoggingExtras.FormatLogger(io; always_flush=true) do output, event
        formatter(output, event)
    end
    context = (; store_id=string(store.id), owner=(; kind=string(K), id=string(ref.id)))
    return RecordLogger(sink, context, store.lock)
end

"""
    ExperimentLab.with_log(f, store, owner)

Append Info-and-higher messages to an execution or measurement's JSON Lines file.
Automatically attach authoritative `store_id`, `owner` and UTC `timestamp` fields.
Every message is flushed before its logging call returns. Output failures throw;
there is no terminal fallback. Return `f()`'s result and restore the prior logger.

The file is created on entering the scope, even when there are no messages.
Use one coordinated store writer. Await child tasks (for example with `@sync`)
inside the scope: this function closes the file on exit and is not a task manager.
It neither changes activity status nor automatically binds `measure!` to a new log.
"""
function with_log(f, store::DataStore, ref::LogOwner)
    relative = info(store, ref)["log_path"]
    relative == relative_log_path(ref) || throw(ArgumentError("invalid log path for record"))
    path = joinpath(store.path, relative)
    mkpath(dirname(path))
    return open(path, "a") do io
        Logging.with_logger(f, record_logger(io, store, ref))
    end
end
