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

ExperimentLab does not wrap `@option` or duplicate its defaults and validation.
Unregistered configurations use parameter dictionaries; `readconfig(path, T)`
then requires a concrete option type such as `typeof(settings)`. JSON is parameter
interchange, not a replacement for native checkpoints. Arbitrary Julia objects
need an explicit upstream conversion; plain Julia structs can still use tree
construction/display without opting into JSON.

## Explicit type identity in JSON

Keep serialization names outside the structs. A configuration registry maps
stable names to `@option` types or parametric constructors:

```julia
@option struct DirectMethod <: AbstractAlgorithmConfig end

const METHOD_CONFIGS = ExperimentLab.ConfigRegistry(
    "MyPackage.DirectMethod" => DirectMethod,
)
ExperimentLab.config_registry(::Type{DirectMethod}) = METHOD_CONFIGS

writeconfig(stdout, DirectMethod())
# {"type":"MyPackage.DirectMethod","parameters":{}}
```

`config_registry(T)` is an author hook. It lets ordinary `writeconfig(path, obj)`
and record storage discover the registry automatically. A caller can instead
provide `writeconfig(path, obj; registry)`. Nested configurations consult their
own hooks as well. Compose package entries with `ConfigRegistry(first, second)`;
duplicate identical entries are shared, while conflicting names/types throw.
There is no process-global mutable registration table.

Read with `readconfig(path, typeof(obj))`, or `readconfig(path, registry)` when
the file selects a registered root. JSON names are looked up, never evaluated.
Parameterized constructors infer their type parameters from decoded children;
non-inferable parameters require registering a concrete specialization. The
registry must cover children whose types cannot be determined from their parent.
Configurations still supplies defaults, concrete field conversion and validation.
Third-party field conversions remain the upstream hooks described below.
For example, a registered `SVDInitialization` identifies the wrapper, but its
MatrixAlgebraKit truncation field still needs a concrete owner type for loading.
Use `readconfig(path, typeof(config))` for such fields. An untagged JSON object
in an unconstrained type parameter is rejected rather than silently becoming a
Julia `Dict`; raw dictionary parameters should declare an `AbstractDict` bound
or be loaded with a concrete owner type.

`ExperimentLab.config_record(registry, obj)` returns the same JSON-ready record
without writing a file. `ExperimentLab.describe(registry)` describes its mappings.
These author interfaces remain qualified, like the existing tree hooks.

Registered nodes always retain their `type`, even with `include_defaults=false`.
An ordinary algorithm parameter called `type` lives inside `parameters` and does
not conflict. Structs, constructors, editable trees and Accessors updates require
no serialization fields or display exceptions. Unregistered nodes remain plain
parameter dictionaries; registering one subtree does not identify the rest of
an application automatically.

The domain packages register every production configuration: UpdateLab (2),
TensorLinearSolveLab (4), PMPSLab (3),
MPSSplitLab (12), and LoopTNRLab (2). Parent packages compose their dependencies'
registries. ExperimentLab does not depend on those packages. Stored algorithm
and measurement records use the same representation as `writeconfig`.

See the runnable [registry example](../examples/config/extras/registered_json.jl).

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
