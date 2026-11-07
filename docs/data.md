# Data storage

Save scientific states and measurement results without coupling storage to
algorithm execution or log routing. Operations are synchronous; the caller decides
when to copy, calculate, write, wait, or run work in another task.

Start with the [numbered REPL examples](../examples/data/README.md). Every example uses
small inputs, leaves variables accessible, and can run independently.

## The two paths

```text
live state → capture (copy) → save_snapshot! → Julia binary payload
live state → measure!                     → Julia result + JSON view
saved snapshot → load_snapshot → measure!  → another Julia result + JSON view
```

Saving a tensor and doing a measurement are independent choices. `record_state!`
records a produced state under an execution without copying or saving a tensor. Costs, timing and
convergence diagnostics belong to the logging area; this area stores scientific
results such as spectra and state tensors.

```julia
using ExperimentLab
using ExperimentLab

struct MatrixPreparation <: AbstractAlgorithmConfig end
store = DataStore("results/my-run") # Creates a new empty directory or opens a store.
algorithm = ExperimentLab.record_algorithm!(store, MatrixPreparation())
run = ExperimentLab.record_execution!(store, algorithm)
state = record_state!(store, run; step=1, label="initial state")
tensor = [1.0 0.0; 0.0 2.0]
captured = capture(state, tensor)  # Independent copy in memory; no tensor file yet.
saved = save_snapshot!(store, captured)
restored = load_snapshot(store, saved)
```

`capture` must run while the producer is not changing the source. Afterward, the
producer may mutate its own tensor. Treat `captured.value` as read-only; multiple
read-only consumers can share it. Its storage remains live while callers retain
references. `copy_state` defaults to `deepcopy`; scientific packages with external,
device, or custom mutable buffers must specialize and verify that adapter. The
initial tests cover ordinary Julia arrays and nested mutable storage, not every
tensor backend. Tensor-specific integration is a later stage.

Re-saving the same retained capture returns the same snapshot identity without
rewriting its payload or metadata. Separately captured objects get separate payloads.
Once analysis retention is removed, capture a new state instead of resurrecting
the old identity. Each StateRef denotes one state; create a new state
reference when the producer advances to a different state.

## Measurements

Define an immutable configuration and implement ordinary Julia dispatch:

```julia
using LinearAlgebra

struct MatrixSpectrum <: AbstractMeasurement end
struct SpectrumResult <: AbstractMeasurementResult
    levels::Vector{Float64}
end
ExperimentLab.measure(::MatrixSpectrum, matrix) =
    SpectrumResult(eigvals(Hermitian(matrix)))

attempt = measure!(store, MatrixSpectrum(), tensor; state)
load_result(store, attempt).levels
```

`measure(definition, input)` only calculates. `measure!` additionally publishes
a new attempt, calls the measurement, and saves its result. It does not copy or
persist an in-memory input. Measurement methods must treat their inputs as
read-only. `measure!(store, definition, saved)` loads an existing snapshot first.
The captured-state overload measures an independent in-memory copy without
requiring a tensor file.

Each invocation has a new attempt ID, even when input and configuration repeat.
`load_result(store, attempt)` restores the original Julia result struct, including
its concrete field types, array dimensions, and values. Every load creates an
independent object. After restarting Julia, load the package defining the result
type first (or define the example struct again). There is no writer-side type
registry to retain or supply. Coordinators can use qualified `start_measurement!`,
`finish_measurement!`, and
`fail_measurement!` to persist separately calculated results.

Measurement configurations also retain their original Julia objects. Restore
one without supplying constructor mappings, including for running or failed attempts:

```julia
definition = ExperimentLab.load_measurement(store, attempt)
typeof(definition) # MatrixSpectrum
```

The configuration binary is written before the attempt is published. Load the
package defining the configuration type before reading it in a new Julia session.
Missing or unreadable binaries produce an error rather than a dictionary fallback.

The index also retains the plain configuration dictionary for inspection.
Native loading restores the saved Julia value. For deliberate JSON reconstruction,
use `ExperimentLab.readconfig(path, typeof(settings))` with the concrete option
type (or `Configurations.from_dict` for an in-memory dictionary). Configuration
JSON is never evaluated as Julia code; there are no constructor mappings.
The implementation module/package identity, available package version and Julia
version are recorded. Use explicit provenance metadata for a source revision or
other environment facts; stored configuration is not source-code archiving or a
reproducibility guarantee.

## Result encoding

Each completed result has two representations: a JLD2 file for
`load_result`, and a JSON document for frontends and other languages. These are
small measurement results, not extra copies of the input tensor. Both files must
finish writing before the attempt is marked completed. The result must not be
mutated during `finish_measurement!`.

To explicitly inspect the JSON view from Julia, use the qualified function:

```julia
plain = ExperimentLab.load_result_data(store, attempt)
plain["levels"]
```

This path requires neither the scientific result type nor the binary file.
`load_result` never silently falls back to a dictionary if its binary payload
cannot be read.

For the JSON view, `ExperimentLab.result_data(result)` defaults to the result
struct's named fields. The supported plain values are null, booleans, strings,
finite Float16/32/64 values, machine integers in `-(2^53-1):(2^53-1)`, tuples,
arrays, named tuples and dictionaries with name keys. Opaque values require an
explicit `result_data` adapter; there is no automatic traversal of arbitrary
nested structs, complex-number conversion, or non-finite-number replacement.

Vectors become JSON arrays. Multidimensional arrays become objects with `shape`,
`layout="column-major"`, and flattened `values`; numerical arrays in results are
not classified as tensor snapshots. Encoded results are independent of later
mutation of the original result object. A custom JSON adapter does not change the
Julia object restored by `load_result`; no inverse JSON adapter is required.

## Reading provenance

The everyday exports are `DataStore`, `record_state!`, `capture`, `save_snapshot!`,
`load_snapshot`, `AbstractMeasurement`, `AbstractMeasurementResult`, `measure`,
`measure!`, and `load_result`. Coordination and inspection methods are qualified:

```julia
ExperimentLab.info(store, state)       # Detached metadata, no tensor load.
ExperimentLab.info(store, saved)
ExperimentLab.info(store, attempt)
ExperimentLab.records(store, :measurement) # All attempt references.
ExperimentLab.describe(store)           # JSON-ready ownership tree.
```

`records` accepts `:algorithm`, `:execution`, `:state`, `:snapshot`,
`:measurement`, and `:pin`. Its stable creation-time/ID order is not numerical
step order. Read a state's `step` to order results from concurrent producers.

## A Ref ownership tree

```text
AlgorithmRef (fixed configuration)
├─ ExecutionRef
│  ├─ StateRef (step 1)
│  │  ├─ SnapshotRef
│  │  │  └─ PinRef
│  │  └─ MeasurementRef (configuration + status + result)
│  └─ StateRef (step 2)
└─ ExecutionRef (another run of the same configuration)
```

Every node stores only its direct `parent` as a `{kind, id}` link. Children are
derived from those links. Roots have no parent. Refs themselves remain small
`RecordRef{K}(store_id, id)` values; all storage operations take `store` explicitly.
No separate runtime execution wrapper is involved.

`record_algorithm!(store, config; label, constructors, metadata)` always creates a
new AlgorithmRef, even for equal parameters. It copies the immutable-top-level
configuration and saves both JSON and a native Julia representation. Explicitly
reuse that Ref for multiple runs; changed parameters require a new registration.
`load_algorithm(store, algorithm)` restores the original configuration type.

`record_execution!(store, algorithm; initial_state, label, provenance)` creates a
run under that algorithm. These calls record facts supplied by the caller; they
start no computation. `finish_execution!` records completion, failure or cancellation.
A running execution is required to register a new state. Measurements and snapshots
may be added to an existing state after the execution finishes.

`initial_state` is an optional link to an existing StateRef in the same store,
including one under another algorithm. It describes input provenance and does not
change ownership. A measurement of a saved snapshot similarly has an
`input_snapshot` link as well as its state parent. Neither link copies or pins a
tensor. If the producer advances, register a new StateRef before capture/measurement.
The caller is responsible for associating the actual tensor with that state;
the store validates references, not the numerical computation.

```julia
ExperimentLab.parent_ref(store, saved) == state
ExperimentLab.parent_ref(store, state) == run
ExperimentLab.children(store, state)
display(store) # Automatic Ref tree; reads index metadata only.
ExperimentLab.showtree(stdout, store, run) # One subtree.
ExperimentLab.showtree(stdout, store; maxdepth=3, maxnodes=30)
```

Input links appear as arrows and are never recursively expanded. Display defaults
to depth 8 and 100 node/link lines, with truncation markers. Bare Refs stay compact
because they do not carry a store handle. No configuration, tensor or result
binary is loaded to display a tree. `describe(store)` provides the corresponding structured metadata tree.
There is no standalone external-input registration: every saved state and recorded
measurement must belong to an existing execution through a StateRef.

## Structured descriptions for AI and frontends

Qualified `ExperimentLab.describe` returns a detached,
JSON-ready description with `schema=1`. It shares the same generic function as event-registry descriptions and remains qualified.

```julia
using JSON

description = ExperimentLab.describe(store)       # Whole ownership tree.
run_description = ExperimentLab.describe(store, run) # One execution subtree.
json_text = JSON.json(run_description)
summary = ExperimentLab.describe(store, run; maxdepth=0)
```

Each node includes its full ID, kind, store ID, direct parent, and stored metadata:
configuration JSON, labels, status, step, provenance, and payload paths where
applicable. `children` expands only ownership. `initial_state` and `input_snapshot`
remain `{kind, id}` links, including links outside the selected subtree. A subtree
retains its parent link even though the parent is not expanded.

Defaults are depth 8 and 100 record nodes. The selected Ref counts as one node;
the store header does not. `child_count` is the total number of direct children,
`omitted_children` counts direct children excluded by limits, and `truncated` is
true if any part of that subtree is omitted. `limits` records the requested bounds.
These limits bound tree expansion, not the size of arbitrary user metadata.
The order is the same creation-time/ID order used by the text tree. Text display
also budgets arrow lines; the JSON description keeps those links inside each node.

Inspection reads only `index.json`, never tensor, configuration, or result payload
files. Results are represented by status/type/path; explicitly call `load_result`
or `load_result_data` to read the scientific values. The description is not a
backup or a reconstructible store. Mutating it does not change stored records.
`describe(ref)` without a store still reports identity only, and `describe(captured)`
reports capture metadata without inspecting the captured value.

See [07_structured_descriptions.jl](../examples/data/07_structured_descriptions.jl) for a
complete REPL example, including writing the description to a JSON file.

## Retention and checkpoint sharing

All measurement attempts and results are retained. For tensors, callers choose
which states to capture/save: every step, selected steps, final only, or none.
To keep only the latest, save it and explicitly delete older analysis snapshots.

```julia
pin = ExperimentLab.pin_snapshot!(store, saved; owner="checkpoint-001")
# Publish an algorithm-specific checkpoint referencing saved and this pin.
ExperimentLab.delete_snapshot!(store, saved)
load_snapshot(store, saved) # Still available because the checkpoint has a pin.

# After deleting that checkpoint:
ExperimentLab.release_pin!(store, pin)
```

The pin adds only metadata; it shares the snapshot payload. Multiple checkpoints
may pin the same payload. The payload is deleted only after analysis retention
and every pin have been released. Pin **before** publishing a checkpoint; release
only after it no longer needs the tensor. This package does not save restart
state or restore algorithms. That protocol belongs to the external integration.

Historical measurement references do not pin tensors. A state's availability is
`never_persisted`, `available`, or `removed`; its metadata remains after pruning.
An in-memory consumer owns its loaded/captured value. A future consumer which
still needs to load a file must hold a pin. Different data directories cannot
reference each other's states or payloads; cross-store imports are unsupported.

## Storage, publication and failures

```text
store/
  index.json                    # Versioned provenance, statuses and references.
  algorithms/<id>.jld2          # Original fixed algorithm configuration.
  tensors/<snapshot-id>.jld2    # Julia tensor payloads.
  measurements/<id>.json       # Frontend-readable scientific result documents.
  measurements/<id>.jld2       # Original Julia result type and values.
  measurements/<id>.config.jld2 # Original measurement configuration.
```

The format has schema version 1, independent of the package version. JSON index
tables are `algorithms`, `executions`, `states`, `snapshots`, `measurements`, and `pins`. Result
documents contain `schema`, `kind="measurement_result"`, `attempt`, `type`, and
`data`. Type strings are descriptions, not executable constructors.

Payloads finish writing before a new index is published by a same-directory
rename. Readers use only committed index records, so incomplete/orphan payloads
are not completed results. The local filesystem must support atomic rename;
fsync/power-loss durability and distributed filesystems are not promised.
Metadata is kept in one index and rewritten per mutation; this first backend is
for modest run histories, not a high-volume database.

Use one coordinated `DataStore` writer per directory. It serializes operations
with its lock. Reopened stores may inspect published metadata, but separate writer
objects/processes must not mutate concurrently. Tensor-loading readers that race
retention need a pin. Live computations never read this store to make stopping
decisions.

Ordinary measurement calculation errors become `failed` attempts with exception
type/message; a later invocation makes a new attempt. Interrupts, invalid result
types, encoding errors and storage failures propagate. If completion cannot be
published, its attempt stays `running` with no result reference. An external
coordinator can report it as failed later; it must not treat it as completed.
Storage errors must stop producer advancement at the integration layer.

Failure may leave unreferenced payload files. Readers ignore these; no automatic
orphan deletion or restart recovery is provided. Removing a payload publishes its
unavailability before deleting bytes, so a deletion failure leaves an orphan
rather than a falsely available record.

All native Julia payloads use JLD2 with one root entry named `value`. Snapshot
files contain the captured value directly; configuration and result files contain
a small envelope with schema, owner ID, and the original value. Load the packages
that define these types before reading, and use the original code and dependency
environment. JLD2 does not provide application-level migrations for changed types.
JSON-only readers never load binary payloads. The storage layer creates no background tasks and has no memory admission
controller, remote transport or scientific tensor adapters. Live generator
execution is documented separately in [execution controls](execution.md). Execution and
measurement records also hold relative `log_path` fields; see [record-bound logs](log-binding.md).

## Validation

```sh
OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=1 JULIA_NUM_PRECOMPILE_TASKS=1 julia --project=. -e 'using Pkg; Pkg.test(; julia_args=["-O0", "--threads=1"])'
```

Tests use tiny states and deterministic failures, including blocked publication,
nested mutation, pins, failed measurements and metadata-only reads.
