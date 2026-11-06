# Review in the REPL

Start Julia with ExperimentLab active:

```sh
cd /Users/chenqimeng/Documents/GitHub/ExperimentLab
julia --project=.
```

Each file starts by activating and instantiating the examples environment, so
running a whole file directly in VS Code also works. For selected sections, run
setup and imports first, keeping each struct/function block together.
Variables are top-level and remain available for inspection. Define structs once;
restart Julia if you change their fields. Each file works on its own and uses
different type names, so they can also run consecutively in one session.

1. `01_snapshots.jl`: copy a mutable state, save it, reopen and load it.
2. `02_measurements.jl`: measure a small matrix without saving the matrix, then restore a typed Julia result.
3. `03_retention_and_checkpoints.jl`: retain one shared payload while a checkpoint
   needs it; remove it only after releasing every reference.
4. `04_provenance.jl`: walk from a measurement to its state, execution and fixed configuration.
5. `05_measurement_failures.jl`: inspect a failure, then retain a separate retry.
6. `06_reference_tree.jl`: reuse a configuration, branch from an old state, and display the Ref tree.
7. `07_structured_descriptions.jl`: describe that structure for AI/frontend readers, serialize JSON, and inspect truncation.

For example:

```julia
include("examples/data/01_snapshots.jl")
store
captured
saved
restored
ExperimentLab.describe(store)
```

Every store uses a real temporary directory. It stays accessible in the running
Julia session and is normally removed when Julia exits. Use a directory you choose
for permanent experiments. These examples do not launch background tasks or run
LoopTNR, MPS optimization or a CFT spectrum calculation.
