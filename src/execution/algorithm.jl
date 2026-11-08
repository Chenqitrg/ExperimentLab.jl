"""
    AbstractAlgorithmState

Algorithm-owned numerical state used by [`algorithm_steps`](@ref). Concrete types
choose their own fields; execution status and control requests belong to Session.
An algorithm state is not a stored StateRef or a serialized generator.

The default `copy_state` deep-copies a value. Algorithms may specialize it to
produce a smaller snapshot and provide their own numerical restoration function.
"""
abstract type AbstractAlgorithmState end

"""
    algorithm_steps(state::AbstractAlgorithmState)

Return a ResumableFunctions generator that advances `state`. Algorithm packages
extend this function: first `import ExperimentLab: algorithm_steps`, then define
an unqualified `@resumable function algorithm_steps(state::MyState)`.

Yield algorithm-specific progress after each safe pause/capture boundary and
return the final result when finished. Progress and result types are unrestricted.
Use `@yieldfrom algorithm_steps(child)` to forward a nested algorithm's progress
and receive its final result. Only one driver may advance a state at a time.

Run with `start_run(algorithm_steps(state); onstep=...)`. This protocol does not
impose fields, automatically save state, or require ordinary generators passed to
`start_run` to use an AbstractAlgorithmState.
"""
function algorithm_steps end
