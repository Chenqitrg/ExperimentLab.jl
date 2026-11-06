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
