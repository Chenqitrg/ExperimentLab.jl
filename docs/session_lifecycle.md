# Session lifecycle

One Session owns one generator and one driver Task for its entire lifetime.
ResumableFunctions holds the algorithm's local variables and execution position.
ExperimentLab holds control requests and actual status.

## Requests and status

Only the driver publishes status; commands update a request under a
`Threads.Condition` lock. `CONTINUE`, `PAUSE`, and `CANCEL` are internal requests.
A pause request does not imply that active numerical work has stopped.

| Actual state | `pause!` | `resume!` | `cancel!` |
| --- | --- | --- | --- |
| RUNNING | Request pause unless cancelling | Revoke pause; reject if cancelling | Request cancellation |
| PAUSED | Remain paused | Wake the same Task unless cancelling | Wake it to finish cancellation |
| COMPLETED / CANCELLED / FAILED | No change | Error | No change |

At a boundary, the driver waits on the condition while PAUSE is requested.
Waiting releases the lock and consumes no polling CPU. Resume changes the
request and notifies the condition. Cancel cannot be revoked.

A boundary comes before each generator advance, after the previous callback
has finished. A control request cannot interrupt arbitrary numerical code or a
blocked callback. Cancellation does not run the remainder of the generator;
resources must not be held across yields expecting a finalizer in the generator
tail to run on cancellation.

`@yield` produces progress. Only reaching the generator's `return` or ordinary
end produces COMPLETED. The final yielded value can therefore be paused or
cancelled before its return is reached; no lookahead executes an extra step to
predict completion. If return or an exception occurs during an active advance,
completion/failure is published even when a stop request arrived meanwhile.

## Waiting and failure

- `pause!(session; wait=true)` returns once PAUSED or a terminal state is visible.
  Check `run_status` to distinguish those outcomes. With multiple controllers,
  a concurrent resume may revoke that pause; coordinate conflicting commands.
- `wait(session)` waits until the driver exits. It does not return merely because
  the driver is parked. Resume or cancel a paused Session before waiting for its
  termination from the same interactive task.
- `fetch(session)` waits and returns the generator's final value for COMPLETED.
  It throws the captured exception for FAILED and an ArgumentError for CANCELLED.
- Algorithm and callback exceptions both fail the Session and wake waiters.
- A callback may request pause/cancel. It must not call wait, fetch, or blocking
  pause on its own Session; those operations reject self-waits.

Startup publishes the Task handle under the condition lock before the first
advance. No Session method starts a replacement Task. The generator is owned by
one Session and must not be manually advanced concurrently.

## Live inspection

`ExperimentLab.describe(session)` returns JSON-ready metadata without waiting for
completion or reading disk. `status` is the acknowledged state; `request` is the
latest control request, so `"running"` with `"pause"` is possible. Terminal status
takes precedence over any remaining request. `result_available` means `fetch` can
return a successful final result; the payload itself is omitted. Failures include
an error type and message, without a stack trace.

Recorded sessions also include the store identity/path and execution reference.
Use `describe(store, session.execution)` separately for the persisted tree. Its
status can differ during a live pause or after a storage failure.

## Recorded sessions

The advancement loop returns a terminal outcome to the driver; it no longer
publishes completion/cancellation before finalization. For recorded sessions,
the driver closes the log and commits the execution outcome first. If either
operation fails, the Session becomes FAILED instead. Terminal Session state thus
means the driver's finalization attempt has finished. A store that cannot accept
writes may retain a running record even though its Session has failed.

Pause is an in-memory control state; it does not rewrite the stored execution.
The log remains open while the driver waits. `wait` and `fetch` include final log
closure and the attempted record update. The driver never holds its condition
lock during file I/O. See [recorded execution](execution.md#recorded-execution).
