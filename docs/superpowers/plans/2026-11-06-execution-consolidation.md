# Execution Consolidation Implementation Plan

**Goal:** Move the reviewed generator controller into ExperimentLab without changing its behavior.

**Architecture:** One module owns `src/config/`, `src/execution/`, `src/data/`, and `src/logging/`. ResumableFunctions continues to own generator mechanics. Session and ExecutionRef remain distinct, explicitly composed runtime and storage objects.

**Tech Stack:** Julia 1.12, ResumableFunctions 1.0.8, existing ExperimentLab dependencies.

**Spec:** User approved consolidation after reviewing generator execution and checkpoint removal. Prior instruction: migrate in small reviewable steps, no compatibility requirements.

## Constraints

- No version bump, commit, compatibility wrapper, disk-resume feature or tensor algorithm migration.
- Preserve five control exports; keep Session/status names qualified and generator macros upstream.
- Retain the old checkout as a migration reference while old domain callers still refer to it; mark it retired.
- Keep logs and stored execution lifecycle explicit. Test composition without introducing an automatic coordinator.

## Review focus

- Preserve cooperative/threaded pause, cancellation, nested results, and error behavior.
- Ensure ExperimentLab owns the types and does not depend on ExecutionLab.
- Child tasks inherit record-bound logs; await completion before scope closes.
- Storage/log failures must escape measurement handling even through Session.fetch.
- Examples resolve their own environment and keep variables available in the REPL.

## Migration

- [x] Observe the missing execution API through an ownership test.
- [x] Move the two implementation files and existing tests, add the upstream dependency and five exports.
- [x] Test explicit data/log composition and fix any exception-wrapper integration gap.
- [x] Move three small examples and execution docs; update package stage and retirement notes.
- [x] Run the combined suite with two threads and examples in fresh processes, inspect the diff, leave uncommitted.

## Verification

- Ownership test failed before migration because `ExperimentLab.start_run` did not exist.
- Both controller files match the reviewed standalone implementations byte for byte.
- Combined two-thread package suite: 686 assertions passed, including cooperative
  and threaded controls, explicit storage/log composition and method ambiguities.
- A new integration test initially failed four assertions: Session.fetch wraps log
  errors in CapturedException, which measure! treated as an ordinary failed result.
  Recursive unwrapping makes all six assertions pass; the final shared helper is
  must_rethrow_measurement in src/data/measurement.jl.
- Three migrated execution examples, the existing bound-log example and snapshot
  example passed in five fresh single-thread processes launched from `/tmp`.
- No tensor calculations or downstream algorithm migrations were run. Package
  versions remain 0.1.0; changes are uncommitted.

## Final review

An independent read-only review found one additional integration defect: a
Session-wrapped InterruptException was converted into a failed measurement
record. A regression first failed two assertions; the shared measurement-abort
check now unwraps CapturedException, CompositeException and TaskFailedException
for both interrupts and log I/O errors. All three regression assertions and the
full 686-assertion suite pass. No other concrete defects were reported.

The migration decision is to keep Session/ExecutionRef coordination explicit and
retain the retired standalone checkout while old domain callers await migration.
Automatically binding lifecycle or deleting that checkout would be a separate
change. No compatibility adapters were introduced.
