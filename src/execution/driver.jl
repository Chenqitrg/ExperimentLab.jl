# Forward progress while capturing the distinct final return value. This uses
# the upstream macro, not generated object fields or a new algorithm protocol.
@resumable function _capture_result(generator::G, result)::E where {
        E,G<:ResumableFunctions.FiniteStateMachineIterator{E}}
    result[] = @yieldfrom generator
end

# Only the driver calls this, holding the condition lock. All actual status
# changes go through this point; public commands change requests instead.
function _set_status!(session::Session, status::RunStatus)
    session.status = status
    notify(session.condition; all=true)
    return nothing
end

function _await_permission(session::Session)
    lock(session.condition) do
        while session.request == PAUSE
            _set_status!(session, PAUSED)
            wait(session.condition)
        end
        if session.request == CANCEL
            return false
        end
        _set_status!(session, RUNNING)
        return true
    end
end

# Advance only; terminal status is published after resources and records finish.
function _advance!(session::Session)
    driver = _capture_result(session.generator, session.result)
    while _await_permission(session)
        next = iterate(driver)
        next === nothing && return COMPLETED
        isnothing(session.onstep) || session.onstep(session, next[1])
        yield()  # Let REPL/control tasks run even with one Julia thread.
    end
    return CANCELLED
end

function _drive!(session::Session)
    outcome, failure = FAILED, nothing
    try
        outcome = _run_session(session)
    catch err
        backtrace = catch_backtrace()
        failure = CapturedException(err, backtrace)
        if session.execution !== nothing
            try
                finish_execution!(session.store, session.execution; status="failed", exception=err)
            catch storage_error
                # Keep the original failure if even the failed record cannot be written.
                failure = CapturedException(CompositeException([
                    failure, CapturedException(storage_error, catch_backtrace())]), backtrace)
            end
        end
    end
    lock(session.condition) do
        session.failure = failure
        _set_status!(session, outcome)
    end
    return nothing
end
