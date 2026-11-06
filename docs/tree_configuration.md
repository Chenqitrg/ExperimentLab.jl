# Tree construction and configuration interchange

Configurations are ordinary Julia structs with keyword constructors. This
package does not define a new language for declaring types. A tree constructs
new values; it does not construct a default object and modify it afterward.

## Julia input

```julia
using ExperimentLab
using Configurations: @option

@option struct Solver <: AbstractAlgorithmConfig
    tolerance::Float64 = 1e-8
end
@option struct Run{S} <: AbstractAlgorithmConfig
    solver::S
    count::Int
end

solver = @config """
Solver
  tolerance: 1e-10
"""

config = @config """
Run
├─ solver: solver
└─ count: 4
"""
```

Alternatively, expand `solver: Solver` and place its fields underneath. Every
structural branch explicitly names an `AbstractAlgorithmConfig` subtype. A
leaf can be any single-line Julia expression, including a local variable or
constructor call. Expressions run once in written order. Put multiline values
in variables first. The macro accepts literal strings, not runtime text or
string interpolation. Runtime file input is JSON; ordinary Julia source files
can contain `@config` calls and be included normally.

The root is a type name (optionally qualified). Use `EmptyConfig` for an empty
root and `field: EmptyConfig()` for an empty leaf. Graphical indentation uses
three-character ancestor segments (`│  ` or spaces), followed by `├─ ` or
`└─ `. Plain indentation uses two spaces per level. Do not mix styles. Duplicate
fields, malformed connectors, missing levels, or invalid Julia expressions
fail with tree line information. Constructors receive final keyword values;
their own validation remains authoritative.

## Updating a configuration

Use [Accessors.jl](https://juliaobjects.github.io/Accessors.jl/stable/) directly:

```julia
using Accessors: @set, @reset

@reset config.solver.tolerance = 1e-12
changed = @set config.solver.tolerance = 1e-14
```

`@set` returns a new value. `@reset` also assigns the result back to its target.
The original configuration and aliases to it remain unchanged. Paths use Julia
property/index syntax, including ordinary structs, tuples and arrays. They are
not limited to nested algorithm configurations.

Scattered changes are ordinary Julia statements:

```julia
@reset config.solver.tolerance = 1e-10
@reset config.count = 8
```

Each statement takes effect immediately after successful reconstruction.
A failure in a later statement does not undo earlier successful statements.
When several fields must change together to satisfy an invariant, construct
and replace their enclosing subtree in one statement. To prepare a candidate
without rebinding the original, update a separate local variable first.
Unchanged mutable leaves may remain shared; updates are not deep copies.

Accessors uses ConstructionBase's standard positional reconstruction protocol,
not `config_constructor` or `config_fields`. Those hooks serve tree
interchange only. Updates address Julia properties, which may differ from
constructor keywords. Put validation in inner constructors and forward
keyword constructors to them. See the [author guide](configuration_extensions.md)
for special types with non-inferable parameters.

## Viewing and copying

```julia
config          # Automatic tree display in the REPL or notebook.
display(config) # The same display from a script.
@show config;   # Variable name plus a reconstructible @config expression.
```

Copy the displayed tree into `@config`, or copy the complete expression from
`@show`. Display includes every constructor field. Qualified names identify the
modules that must be loaded when reconstructing the configuration.

When a value cannot be reconstructed from text, display marks the output
`Display only`. Such output remains readable but cannot be copied back as a
constructor. JSON conversion follows Configurations.jl and JSON.jl; define conversion methods
for third-party field types.

## JSON files

```julia
writeconfig("run.json", config)
restored = readconfig("run.json", typeof(config))
```

The file contains an ordinary nested dictionary, without constructor IDs or a
custom schema. `Configurations.to_dict` supplies the data; JSON.jl encodes it.
Reading calls `Configurations.from_dict` with the concrete type supplied by the
caller. Required fields, defaults, and unknown-key checks belong to Configurations.
Both functions also accept streams, such as `readconfig(IOBuffer(text), Run{Solver})`.

For a parametric configuration, `typeof(config)` fixes the nested field types.
To choose a different solver type, pass the corresponding concrete configuration
type, or use Configurations' union/type-alias facilities in the type definition.
JSON does not automatically recreate arbitrary Julia expressions or functions.

To work directly with data, use the upstream API:

```julia
using Configurations: to_dict, from_dict

data = to_dict(config)
data["count"] = 8
changed = from_dict(typeof(config), data)
```

`writeconfig(path, config; include_defaults=false)` omits default-valued fields.
There are no ExperimentLab registries, binding nodes, or scalar tags.
Third-party values use the upstream conversion interface described in the
[author guide](configuration_extensions.md).

## Review examples

Follow [01–06](../examples/config/README.md) to construct one optimization configuration
and revise it through paths. The main walkthrough centers on construction and updates;
[optional examples](../examples/config/extras/README.md) cover JSON, equality, and
external policies separately. The configuration area contributes four exported entry points:

- `AbstractAlgorithmConfig`: define a configuration type.
- `@config`: construct from a tree.
- `readconfig`: read JSON.
- `writeconfig`: write JSON.

The update examples additionally import `@set` and `@reset` from Accessors.

## Package dependencies and extensions

The core depends on Configurations.jl and JSON.jl. MatrixAlgebraKit support
lives in an optional Julia extension. ExperimentLab is independent of MPSKit's
type hierarchy. Specialized values may require support from their owning package.

Maintainers can consult [configuration extensions](configuration_extensions.md)
for custom tree expressions and upstream field conversions.
