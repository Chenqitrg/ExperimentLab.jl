# Recorded Sessions

User approved connecting Session execution, events and stored records. No version
bump, compatibility layer, commit or tensor-domain migration.

## Contract

- `start_run(store, algorithm::AlgorithmRef, generator; onstep, threaded, label,
  initial_state, provenance)` creates a fresh ExecutionRef before scheduling.
- Session exposes `store` and `execution`; unrecorded sessions expose nothing.
- The driver owns the existing with_log scope through pauses and callbacks.
  Ordinary algorithm/callback messages carry authoritative execution ownership.
- Yield values are not implicitly encoded as logs, measurements or snapshots.
- Stored execution stays running until terminal. Completion/cancellation is
  published to Session only after log closure and persisted final status.
- Algorithm/callback/log failures fail the Session and attempt to mark the record
  failed with exception details. Failure to persist must not hide the original
  exception or advertise success; preserve both errors. No retries/recovery engine.
- Child tasks must finish before the generator returns. No automatic child-task
  supervision or measurement log scoping is introduced.

## Steps

- [x] Add recorded-session tests and observe the missing entry point.
- [x] Extract generator advancement from driver finalization; add optional typed
  store/ref fields, a recorded overload, automatic log scope and terminal write.
- [x] Exercise completion, repeated runs, pause/resume, cancellation, exceptions,
  log-open/write failure, record-write failure and foreign algorithm references.
- [x] Add one short English example, update documentation and run the combined
  suite plus execution examples using small inputs and limited threads.

## Verification

- The entry-point test failed before implementation (no matching recorded start).
- Full ExperimentLab suite passed 773 assertions with two Julia threads and one
  BLAS thread. Existing unrecorded controls and data/log tests remain green.
- All four execution examples ran in fresh single-thread processes from `/tmp`.
- Independent read-only review found no correctness defects. Its coverage
  suggestion was added: a callback failure plus blocked failure-record storage
  preserves both captured errors and the original callback message.
- Driver source remains one Task and one status publisher. Execution source is
  224 lines across session, driver and binding; no additional control framework.
- Versions unchanged, no commit, no numerical-package runs.

## Scope decisions

Child tasks must be awaited by the algorithm; cancellation does not execute the
rest of its generator body for cleanup. These existing contracts remain explicit.
Manual mutation of driver-owned finalization and independent writers to the same
store are unsupported. Automatic measurement scopes and tensor persistence are
not part of execution-log binding.
