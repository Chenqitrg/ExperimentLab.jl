@enum RunStatus::UInt8 RUNNING PAUSED COMPLETED CANCELLED FAILED
@enum ControlRequest::UInt8 CONTINUE PAUSE CANCEL

"""
    Session

A generator and its single driver Task. Use `start_run` to create one.
Control requests and actual status are synchronized by a condition; the driver
alone publishes status. Do not advance the generator outside its session.
"""
mutable struct Session{G,F}
    generator::G
    onstep::F
    store::Union{Nothing,DataStore}
    execution::Union{Nothing,ExecutionRef}
    condition::Threads.Condition
    status::RunStatus
    request::ControlRequest
    task::Union{Nothing,Task}
    # Arbitrary final return values cross this boundary once, not on each step.
    result::Base.RefValue{Any}
    failure::Union{Nothing,CapturedException}
end

"""
    start_run(generator; onstep=nothing, threaded=Threads.nthreads(:default) > 1)

Start a ResumableFunctions generator. Each yielded value is passed to
`onstep(session, value)` when supplied. `fetch(session)` obtains the final
`return` value. Callback failures fail the session just like algorithm errors.
"""
function start_run(generator::ResumableFunctions.FiniteStateMachineIterator;
        onstep=nothing, threaded::Bool=Threads.nthreads(:default) > 1)
    return _start_run(generator, onstep, threaded, nothing, nothing)
end

function _start_run(generator, onstep, threaded::Bool, store, execution)
    session = Session(generator, onstep, store, execution, Threads.Condition(), RUNNING, CONTINUE,
        nothing, Ref{Any}(), nothing)
    lock(session.condition) do
        session.task = threaded ? Threads.@spawn(_drive!(session)) : @async(_drive!(session))
    end
    return session
end

"""Return the actual status, not a pending pause/cancel request."""
run_status(session::Session) = lock(() -> session.status, session.condition)

_terminal(status::RunStatus) = status in (COMPLETED, CANCELLED, FAILED)

function _reject_self_wait(session::Session)
    current_task() === session.task && throw(ArgumentError(
        "a session callback cannot wait for its own driver"))
end

"""
    pause!(session; wait=false)

Request a pause after the current step and its callback. With `wait=true`, wait
until the driver acknowledges PAUSED or terminates. Check `run_status` to tell
which occurred. A cancellation request or terminal state is left unchanged.
Inside `onstep`, use only the nonblocking form.
"""
function pause!(session::Session; wait::Bool=false)
    wait && _reject_self_wait(session)
    lock(session.condition) do
        if !_terminal(session.status) && session.request != CANCEL
            session.request = PAUSE
        end
        if wait
            while session.status != PAUSED && !_terminal(session.status)
                Base.wait(session.condition)
            end
        end
    end
    return session
end

"""Revoke a pending pause or wake a paused driver. A cancelled/terminal run cannot resume."""
function resume!(session::Session)
    lock(session.condition) do
        (_terminal(session.status) || session.request == CANCEL) && throw(
            ArgumentError("cannot resume a terminal or cancelling session"))
        session.request = CONTINUE
        notify(session.condition; all=true)
    end
    return session
end

"""Request cancellation at the next boundary, waking a paused driver if needed."""
function cancel!(session::Session)
    lock(session.condition) do
        if !_terminal(session.status)
            session.request = CANCEL
            notify(session.condition; all=true)
        end
    end
    return session
end

"""
    wait(session)

Wait for termination, including across pauses. Use `pause!(session; wait=true)`
to wait for a pause instead. Recorded algorithm/callback errors are thrown by
`fetch`, not `wait`.
"""
function Base.wait(session::Session)
    _reject_self_wait(session)
    wait(something(session.task))
    return session
end

"""Wait for completion and return the generator's final value; report failure or cancellation."""
function Base.fetch(session::Session)
    wait(session)
    status = run_status(session)
    status == COMPLETED && return session.result[]
    status == FAILED && throw(something(session.failure))
    throw(ArgumentError("session was cancelled; no final result is available"))
end

function Base.show(io::IO, session::Session)
    print(io, "Session(status=", run_status(session), ")")
end
Base.show(io::IO, ::MIME"text/plain", session::Session) = show(io, session)

"""
    ExperimentLab.describe(session)

Return JSON-ready live status, pending control request, and storage identity.
Does not wait for completion, read disk, or include the generator or result payload.
Use `describe(store, session.execution)` for the persisted ownership tree.
"""
function describe(session::Session)
    status, request, failure = lock(session.condition) do
        (session.status, session.request, session.failure)
    end
    store = session.store
    execution = session.execution
    error = failure === nothing ? nothing :
        (; type=string(typeof(failure.ex)), message=sprint(showerror, failure.ex))
    return (; schema=1, kind="session", status=lowercase(string(status)),
        request=lowercase(string(request)), result_available=status == COMPLETED, error,
        store=store === nothing ? nothing : (; id=string(store.id), path=store.path),
        execution=execution === nothing ? nothing : describe(execution))
end
