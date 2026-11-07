# Record-bound logs

`ExperimentLab.with_log(store, owner) do ... end` appends Info, Warn and Error
messages to the execution or measurement identified by `owner`. A StateRef is
not required to log an execution's start. Event structs and registration remain
optional: ordinary `@info "Started"` works.

Execution and measurement creation stores a relative `log_path` in the existing
index record. Refs themselves are unchanged; there is no LogRef. Paths are:

```text
logs/executions/<execution-id>.jsonl
logs/measurements/<measurement-id>.jsonl
```

Each new execution has a new UUID, even under the same configuration. Re-entering
the same log scope appends instead of replacing the file. The file is created when
the scope opens; an unused scope leaves an empty file. Before the first scope there
is only a recorded path. `info` and `describe` expose that path without opening it.
Moving the entire store preserves these relative links.

## Output and ownership

LoggingExtras.FormatLogger and LoggingFormats.JSON handle JSON Lines output.
ExperimentLab's small RecordLogger attaches `store_id`, `owner = (kind, id)` and
a UTC `timestamp` to every message, overriding attempts to spoof those fields.
Other fields, including event names, steps and costs, remain ordinary log metadata.
The library supplies level, message and Julia source-location fields.

The scope replaces the current task's logger and restores it on exit. Messages
inside it go to its file, including third-party messages; there is no implicit
terminal mirroring or forwarding into a surrounding run's file. Nested scopes
select their own owner and restore the surrounding owner afterward.

File writes and per-message flushes happen under the coordinated store's lock.
Because Julia IOStream append mode seeks on open, the wrapper seeks to the current
end under that same lock before each write. This protects overlapping scopes with
separate handles. As with data mutations, independently opened stores or processes
must not write concurrently. The coarse store lock also serializes log writes with
data publication; this stage prioritizes a small, correct implementation.

Each handled message is flushed before `@info` returns, so another reader can
observe it before the scope closes. A frontend should consume complete
newline-terminated lines and retry an incomplete trailing line later. Flush is
visibility, not an fsync or a guarantee against power loss.

## Errors and task lifetime

Write, seek and flush failures propagate as `LogWriteError`, retaining the original
cause. The wrapper disables Logging's exception swallowing, so it does not attempt
to report a failed file write through the same broken file. Open/close failures also
propagate. Calculation exceptions escape the scope, and the file closes on exit.
There is no promise to repair a partial last line after a failed write.

`measure!` rethrows log output failures, including those wrapped by `@sync` or
`fetch`/`wait`, instead of converting them into an ordinary failed measurement
result. The incomplete measurement remains running;
this helper does not mark executions or measurements successful or manage their
recovery. Recorded Sessions coordinate their own execution record separately.

Julia child tasks can inherit the logger, but `with_log` is not a task supervisor.
Use `@sync` or await/fetch tasks **inside** the scope. Task failures propagate through
those Julia mechanisms. A task that uses the logger after the scope closes receives
an error. Unawaited task errors cannot automatically stop a producer in another task.

## Recorded Sessions

`start_run(store, algorithm_ref, generator)` opens the execution log inside its
driver Task and keeps it open through pauses. The driver closes it before marking
a successful/cancelled execution terminal, and records failures when possible.
Use this entry point instead of manually wrapping and finalizing a Session.
Ordinary `with_log` scopes keep their existing explicit lifetime contract.

## Measurements

`measure!` creates an attempt and automatically opens its own log around `measure`.
Messages from the calculation and its awaited child tasks belong to that attempt,
even inside a recorded Session. On exit, the surrounding execution logger is
restored. Measurement messages are not duplicated in the execution log; follow
the StateRef's measurement children and their `log_path` to find them.

The log closes before either completion or ordinary calculation failure is
published. Even a calculation with no messages creates an empty log. Opening,
writing, flushing and closing errors propagate; incomplete attempts remain
running for an external coordinator to inspect. No synthetic log events are added.

For an external coordinator, `start_measurement!`, `with_log(store, attempt)` and
`finish_measurement!` remain available as explicit operations.

LoggingExtras and LoggingFormats are now direct dependencies because the package
actually writes bound logs. Event/result encoding contracts have not changed.
No package version is increased and no old-index compatibility migration is added.
