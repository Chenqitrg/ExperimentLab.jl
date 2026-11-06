# Construct a tree, then update it through paths

Start with [00_define_options.jl](00_define_options.jl). It directly defines a
type with `Configurations.@option`, constructs it with keywords and `@config`,
and converts it to and from a dictionary. All variables remain available in the
REPL; this example does not wrap its definitions in a module.

The main walkthrough follows one optimization configuration from creation to
revision. All six files use the same types, fields, and starting values:

```text
OptimizationSettings
├─ solver: IterativeMethod
│  ├─ tolerance: 1e-8
│  └─ maxiter: 50
├─ sweep: SweepSettings
│  ├─ min_sweeps: 1
│  └─ max_sweeps: 10
└─ verbosity: 1
```

`@option` defines a type, its defaults, and dictionary conversion (Configurations.jl).
`@config` constructs a value from a tree (ExperimentLab).
Accessors' `@reset settings.solver.tolerance = value`
updates the current variable; `candidate = @set settings.solver.tolerance = value`
creates a separate value. Paths use ordinary Julia dots and indexing.
Several updates are several statements, each taking effect separately.

## Main walkthrough: read 01 through 06

| Step | Question answered | Main idea |
| --- | --- | --- |
| [01_create_config.jl](01_create_config.jl) | How do I create the initial configuration? | `@config`, constructor defaults, graphical and two-space forms |
| [02_update_one_path.jl](02_update_one_path.jl) | How do I change one setting? | `@reset` for the current variable; `@set` for a separate candidate |
| [03_update_scattered_paths.jl](03_update_scattered_paths.jl) | How do I change parameters in different places? | A flat list of complete paths; before/after display |
| [04_replace_subtree.jl](04_replace_subtree.jl) | How do I switch a solver or reuse a subtree? | Construct a subtree with `@config`, replace it with `@reset` |
| [05_copy_display.jl](05_copy_display.jl) | Can I reuse what is displayed? | Copy into `@config`, then apply a small path update |
| [06_validation_and_order.jl](06_validation_and_order.jl) | When do validation and update order matter? | Sequential validation, failed updates preserve the binding, whole-subtree replacement |

**03 is the usual workflow for changing scattered parameters.** Each file
recreates the same initial configuration, so it can run independently. Later
files do not execute earlier examples. Assertions make the expected changes and
unchanged fields visible.

The `@option` definitions in [support/example_types.jl](support/example_types.jl)
play the role of types supplied by an algorithm package. They include nested
configurations and constructor validation. After example 00, read this short
file to see how the main walkthrough's types are defined.
The small setup file loads those types once per session. Display includes their
module prefix, such as `Main.ReviewExample.IterativeMethod`, so copied output
identifies the correct constructor.

## Running the walkthrough

From ExperimentLab:

```sh
julia --project=examples -e 'using Pkg; Pkg.instantiate()'
julia --project=examples examples/config/00_define_options.jl
julia --project=examples examples/config/01_create_config.jl
julia --project=examples examples/config/03_update_scattered_paths.jl
```

In an editor, select the `examples` environment as the Julia project. Start a
fresh Julia session when switching from the old examples or changing the shared
type definitions. The six main files can then run independently or in order in
the same session. They end with `nothing` to suppress the final test result.
Use `display(settings)` to inspect a tree, or `@show settings;` to include the
variable name without a second REPL display of its return value.

## Optional topics

The [extras](extras/README.md) are separate from the main walkthrough:

- [JSON files](extras/json_files.jl): `writeconfig(path, settings)` and `readconfig(path, typeof(settings))`.
- [External truncation policies](extras/truncation_policy.jl): replace a numerical policy as a whole.
- [Value semantics](extras/value_semantics.jl): equality, hashing, and dictionary keys.

## Rules to retain

- Import `@option` from Configurations to define types and defaults.
- `@config` constructs values; omitted arguments use those defaults.
- Import `@set` and `@reset` from Accessors directly.
- `@set` creates a new value; `@reset` also rebinds the target.
- `settings.solver` selects a subtree; `settings.solver.maxiter` selects a field.
- Each statement validates through ordinary positional reconstruction.
- A failed statement does not undo earlier successful statements.
- Unchanged mutable leaves may remain shared; updates are not deep copies.

ExperimentLab exports `AbstractAlgorithmConfig`, `@config`, `readconfig`,
and `writeconfig`. Definitions and dictionary conversion belong to Configurations;
update machinery belongs to Accessors and ConstructionBase.
