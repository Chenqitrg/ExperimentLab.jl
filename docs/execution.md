# Generator execution

ExperimentLab runs ResumableFunctions generators in a controllable background
Task. Algorithms use ordinary loops, `@yield` for progress, and `return` for
the final result. They do not implement an ExperimentLab run type or step protocol.

```julia
using ExperimentLab
using ResumableFunctions

@resumable function sum_steps(n::Int)::Int
    total = 0
    for i in 1:n
        total += i
        @yield total
    end
    return total
end

session = start_run(sum_steps(3); onstep=(_, value) -> println(value))
fetch(session)  # 6
```

For nesting, `answer = @yieldfrom child(...)` forwards the child's progress
and assigns its final return value to `answer`. See
[the nested example](../examples/execution/03_nested.jl).

## Controls

| Operation | Meaning |
| --- | --- |
| `start_run(generator; onstep=nothing, threaded=...)` | Start one driver Task |
| `pause!(session)` | Request a pause at the next boundary |
| `pause!(session; wait=true)` | Wait until paused or terminated |
| `resume!(session)` | Revoke a pending pause or wake the paused Task |
| `cancel!(session)` | Request cancellation, including when paused |
| `run_status(session)` | Read the actual lifecycle state |
| `wait(session)` | Wait for termination, across any pauses |
| `fetch(session)` | Wait and return the final answer, or report failure/cancellation |

A callback is `onstep(session, value)`. It can request pause/cancel without
capturing an uninitialized outer variable. Waiting for its own session is an
error. Progress values can be numbers, named tuples, custom structs, or `nothing`.
They need not inherit an event type. Each callback must finish before pause is
acknowledged; callbacks run outside the control lock.

There are five actual states: `RUNNING`, `PAUSED`, `COMPLETED`, `CANCELLED`, and
`FAILED`, accessed as `ExperimentLab.PAUSED`, etc. Pending requests are separate
from status. A pause leaves the Julia process and driver Task alive. A terminal
session cannot resume. Create a fresh generator for a new run.

With multiple Julia threads, the default runs the driver on a worker thread;
otherwise it runs cooperatively and yields between progress values. Control is
cooperative in both modes: a numerical operation must reach its next yield (or
return/throw) before the driver can act. Do not manually advance a generator
while a Session owns it, or give the same generator to two Sessions.

## Checkpoint scope

The execution controller handles live generators and has no checkpoint API.
Saving tensors with JLD2 does not by itself restore a paused generator; generator restart/resume from disk remains a separate design step.
Existing algorithms using the removed run protocol need a later migration.

## Review

Start with [the examples](../examples/execution/README.md), then read
[src/execution/driver.jl](../src/execution/driver.jl) and
[src/execution/session.jl](../src/execution/session.jl).
The [lifecycle guide](session_lifecycle.md) covers boundary and failure rules.

## Recorded execution

```julia
algorithm = ExperimentLab.record_algorithm!(store, settings)
session = start_run(store, algorithm, my_generator(settings);
    label="first run", onstep=(_, value) -> @info "Progress" value)
result = fetch(session)
record = ExperimentLab.info(store, session.execution)
```

Every recorded start creates a fresh ExecutionRef under the supplied AlgorithmRef.
The caller builds the generator from the intended configuration; the controller
does not inspect its arguments. `label`, `provenance` and `initial_state` are
forwarded to execution registration. Foreign references fail before work begins.
An already-created ExecutionRef is not accepted, so two Sessions cannot claim the
same execution through this API. Repeated runs get separate records and log files.

`Session` holds the live generator and Task. `session.execution` identifies its
persisted record, and `session.store` is the coordinated store. These fields are
`nothing` for `start_run(generator)`. Starting an unrecorded session writes no
files implicitly; it retains the caller's logging context.

For a recorded session, the driver owns the `with_log` scope. All ordinary logs
from the algorithm and callback carry the execution identity, including messages
before the first yield. Each message is flushed. The scope stays open through
pauses and closes on termination; callers need not hold an external scope open.
Child tasks must still finish before the algorithm returns.

Yielded progress goes to `onstep(session, value)` only. It is not implicitly
serialized or logged: it may contain large tensors. The callback can emit a log
or call `record_state!(session.store, session.execution; step=...)`, followed by
capture/save when desired. Measurement log scopes remain explicit.

## Completion and failures

Stored status stays `running` while a Session is active or paused; `run_status`
provides live pause state. Normal completion/cancellation closes the log and
persists `completed`/`cancelled` before publishing a terminal Session status.
Algorithm, callback, log-open/write/close and record-write errors fail the Session.
The driver attempts to persist `failed` with exception type/message. Failure to
record that outcome retains both exceptions; it cannot guarantee a disk status
update when the store is unwritable. In that case a record can remain `running`.

`fetch` waits for this finalization and throws captured failures. `wait` still
waits without rethrowing recorded errors. Do not call `finish_execution!` manually
for a recorded Session; its driver owns that transition. Finalization does not
synthesize log messages: ordinary algorithm logs and the terminal record serve
their separate roles. No automatic tensor snapshots or disk restart are added.

MPSSplitLab and LoopTNRLab now supply `split_steps` and `tnr_steps` generators.
They use these same Session controls and recorded entry points; numerical snapshot
capture and restoration remain in the domain packages.
