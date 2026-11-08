# Generator execution

ExperimentLab runs ResumableFunctions generators in a controllable background
Task. Algorithms use ordinary loops, `@yield` for progress, and `return` for
the final result. Stateful algorithms can implement the shared `algorithm_steps`
interface below; plain generators remain supported without an algorithm-state type.

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

## Algorithm state protocol

`AbstractAlgorithmState` marks algorithm-owned numerical state. It does not require
particular fields or contain Session control state. Algorithm packages extend the
shared `algorithm_steps` generic to construct a generator for their state:

```julia
using ExperimentLab, ResumableFunctions
import ExperimentLab: algorithm_steps

mutable struct SumState <: AbstractAlgorithmState
    limit::Int
    completed::Int
    total::Int
end

@resumable function algorithm_steps(state::SumState)::Int
    while state.completed < state.limit
        state.completed += 1
        state.total += state.completed
        @yield state.completed
    end
    return (; total=state.total)
end

state = SumState(3, 0, 0)
session = start_run(algorithm_steps(state))
fetch(session) # (total = 6,)
```

Import the generic before defining the unqualified `@resumable` method. A step
must leave the numerical state safe to inspect or capture before yielding. The
yielded value and final result may have any type; ExperimentLab imposes no shared
progress fields. Nested algorithms use `@yieldfrom algorithm_steps(child)`.
Do not drive two generators that mutate the same state concurrently.

PMPSLab's `AbstractSplitState` and LoopTNRLab's `LoopTNRState` subtype
`AbstractAlgorithmState`. Both extend `ExperimentLab.algorithm_steps`; the old
`split_steps` and `tnr_steps` entry points have been removed. Their initialization
and numerical restoration functions remain package-specific.

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
Saving tensors with JLD2 does not by itself restore a paused generator. `capture`
uses `copy_state`, whose default is `deepcopy`; an algorithm may specialize it to
produce a compact snapshot. Numerical restoration remains algorithm-owned. After
restoring a state, create a new generator with `algorithm_steps(restored)` and
pass it to `start_run`. Arbitrary-value snapshots remain supported.

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

PMPSLab and LoopTNRLab supply methods of `ExperimentLab.algorithm_steps`.
They use these same Session controls and recorded entry points; numerical snapshot
capture and restoration remain in the domain packages.
