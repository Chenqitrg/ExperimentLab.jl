"""
    start_run(store, algorithm::AlgorithmRef, generator; onstep=nothing,
              threaded=Threads.nthreads(:default) > 1, label="",
              initial_state=nothing, provenance=(;))

Create a fresh execution under `algorithm` and start its generator. Access its
record through `session.execution` and its store through `session.store`.
The driver owns the execution log scope, including pauses and callbacks.
Yielded values are passed to `onstep`; they are not automatically stored.

`fetch` waits for log closure and the final record update. Algorithm, callback,
log and storage failures fail the Session. If failure recording also fails, both
exceptions are retained. Stored records stay running during pauses. Child tasks
must be awaited by the algorithm before it returns; no task supervisor is added.
"""
function start_run(store::DataStore, algorithm::AlgorithmRef,
        generator::ResumableFunctions.FiniteStateMachineIterator;
        onstep=nothing, threaded::Bool=Threads.nthreads(:default) > 1,
        label::AbstractString="", initial_state::Union{Nothing,StateRef}=nothing,
        provenance=(;))
    execution = record_execution!(store, algorithm; label, initial_state, provenance)
    return _start_run(generator, onstep, threaded, store, execution)
end

function _run_session(session::Session)
    session.execution === nothing && return _advance!(session)
    outcome = with_log(session.store, session.execution) do
        _advance!(session)
    end
    # The log has closed successfully before publishing a completed/cancelled record.
    finish_execution!(session.store, session.execution;
        status=outcome == COMPLETED ? "completed" : "cancelled")
    return outcome
end
