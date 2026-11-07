# JLD2 Storage Implementation Plan

**Goal:** Use JLD2 for all native Julia payloads while keeping JSON metadata and frontend results. Remove the obsolete ExecutionLab checkpoint subsystem; do not merge the packages.

**Constraints:** No package version bumps or backward compatibility wrappers. No generator checkpoint implementation. Keep typed results, reference associations, snapshot retention, and failure-before-publication behavior.

- [x] Add tests proving all four payload kinds are ordinary JLD2 files and retain their Julia types; observe failure with the old backend.
- [x] Replace Serialization with JLD2 and use one same-directory temporary-file publication helper for JSON and JLD2. Close JLD2 before publishing; avoid buffering a complete tensor in memory.
- [x] Adapt fault-injection and metadata-only inspection tests to JLD2; retain fresh-process typed restoration coverage.
- [x] Remove ExecutionLab checkpoint code, API, dependency, tests, and current documentation; preserve generator control tests.
- [x] Run both package suites and relevant examples. Keep changes uncommitted and the two packages independent.

## Verification

- The initial format test failed against the Serialization backend as expected.
- ExperimentLab: 571 assertions passed (15 boundary, 145 configuration, 252 data,
  159 logging), including separate-process type restoration and failed-write
  preservation of an already published JLD2 file.
- ExecutionLab: 89 assertions passed with two Julia threads, exercising both
  cooperative and threaded controls. The package no longer loads JLD2.
- All seven data examples and all three execution examples ran successfully in
  fresh single-thread Julia processes launched from `/tmp`.
- Versions remain 0.1.0. Packages remain separate and changes are uncommitted.
- No tensor backend, MPS optimization, or LoopTNR calculation was run.
