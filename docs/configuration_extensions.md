# Configuration definitions and extensions

Use `Configurations.@option` directly. It creates ordinary Julia structs with
keyword constructors and supplies defaults and dictionary conversion:

```julia
using ExperimentLab, Configurations

@option struct Solver <: AbstractAlgorithmConfig
    tolerance::Float64 = 1e-8
    maxiter::Int = 100
end

settings = Solver(maxiter=80)
data = to_dict(settings)
restored = from_dict(Solver, data)
```

ExperimentLab does not wrap `@option` or maintain a second schema/registry.
JSON files contain these dictionaries. `readconfig(path, T)` requires a concrete
option type; parameterized roots can use `typeof(settings)`. JSON is parameter
interchange, not a replacement for native checkpoints. Arbitrary Julia objects
need an explicit upstream conversion; plain Julia structs can still use tree
construction/display without opting into JSON.

## Explicit type identity in JSON

Use Configurations' `Reflect` field when a configuration node must identify its
strategy to readers that do not already know its Julia type:

```julia
@option "MyPackage.DirectMethod" struct DirectMethod <: AbstractAlgorithmConfig
    type::Reflect
end

writeconfig(stdout, DirectMethod())
# {"type":"MyPackage.DirectMethod"}
```

`Reflect` is a zero-size serialization marker with an automatic default. Users
do not supply it when constructing or updating parameters. ExperimentLab omits
it from editable trees, tree defaults and display, including fallback display.
An ordinary parameter named `type` is unaffected. Inner constructors must accept
and preserve the marker along with their other stored fields so Configurations
and Accessors can reconstruct the value.

Add the marker to each nested option type whose identity must appear in JSON.
The alias above is for a non-parametric type; without an alias, `Reflect` emits
the full Julia type name, including concrete type parameters. Reading still
uses `readconfig(path, T)` with a concrete type. Keep the default
`include_defaults=true` when exporting these identities: Configurations may
omit the marker along with other defaults when `include_defaults=false`.

This is opt-in. Existing option types without a marker still serialize only
their parameter fields; ExperimentLab does not inject a second type schema.

## Validation and updates

Keep validation in positional inner constructors. `@option` supplies keyword
constructors, while Accessors uses standard ConstructionBase reconstruction.
For a parametric type with an inner constructor, provide both a concrete inner
constructor (`Settings{S}(...)`) and an inferred outer constructor
(`Settings(child::S, ...) where S = Settings{S}(child, ...)`). This supports
concrete dictionary loading and changing field types through Accessors.

Non-inferable type parameters may need an owner-defined
`ConstructionBase.constructorof` method. Tree hooks do not alter object updates.

## Third-party fields

Use Configurations' documented conversion hooks, restricted to the owning type:

```julia
Configurations.to_dict(::Type{MySettings}, x::ExternalPolicy) = Dict("rank" => x.rank)
Configurations.from_dict(::Type{MySettings}, ::Type{ExternalPolicy}, d::AbstractDict) =
    ExternalPolicy(d["rank"])
```

See [upstream conversion documentation](https://configurations.rogerluo.dev/stable/convert/).
The optional MatrixAlgebraKit extension supports truncation strategies and
Householder settings. Custom ordering functions and other external algorithms
require their own conversions. There is no automatic serialization of functions.

## Tree-specific hooks

These are qualified interfaces, not default exports:

- `configtree(config; style=:unicode, mode=:full)` renders an editable tree.
  `mode=:compact` obtains defaults from Configurations automatically.
- `config_fields(value)` returns constructor keywords as a NamedTuple; override
  only when tree keywords differ from stored fields.
- `config_constructor(value)` selects the unparameterized tree constructor.
  Explicit parameterized tree names are unsupported.
- `config_defaults(T)` can override compact tree defaults for a plain struct.
- `value_expression(value)` supplies one complete, single-line Julia expression
  for a custom leaf. Return `nothing` to use built-in container handling.

Explicit tree export raises `ConfigError` with field path and source location
when an expression cannot be reconstructed. Ordinary display falls back to a
readable representation marked `Display only`. Cyclic values are rejected.
