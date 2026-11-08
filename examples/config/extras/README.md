# Optional configuration examples

Read the [construction and update walkthrough](../README.md) first. These examples are
independent topics. The file example reuses the main walkthrough's optimization
types; the other examples introduce small types only as needed.

| File | Topic |
| --- | --- |
| [json_files.jl](json_files.jl) | Save and load with `writeconfig(path, settings)` and `readconfig(path, typeof(settings))` |
| [registered_json.jl](registered_json.jl) | Name configuration nodes through an external registry; restore a nested parametric configuration |
| [truncation_policy.jl](truncation_policy.jl) | Display and replace MatrixAlgebraKit policies |
| [value_semantics.jl](value_semantics.jl) | Equality, hashing, and dictionary keys |

Run from the ExperimentLab repository, for example:

```sh
julia --project=examples examples/config/extras/json_files.jl
```
