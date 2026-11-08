using Test, ExperimentLab
using ResumableFunctions: ResumableFunctions, @resumable, @yield

@testset "algorithm protocol is public" begin
    @test isdefined(ExperimentLab, :AbstractAlgorithmState)
    @test isdefined(ExperimentLab, :algorithm_steps)
end

import ExperimentLab: algorithm_steps

mutable struct SumAlgorithmState <: AbstractAlgorithmState
    limit::Int
    completed::Int
    total::Int
end

@resumable function algorithm_steps(state::SumAlgorithmState)::Int
    while state.completed < state.limit
        state.completed += 1
        state.total += state.completed
        @yield state.completed
    end
    return (; total=state.total)
end

@testset "state protocol uses ordinary Session control (threaded=$threaded)" for threaded in (false, true)
    state = SumAlgorithmState(4, 0, 0)
    generator = algorithm_steps(state)
    @test state.completed == 0
    events = Int[]
    session = start_run(generator; threaded,
        onstep=(session, step) -> begin
            push!(events, step)
            step == 2 && pause!(session)
        end)
    paused = timedwait(() -> run_status(session) == ExperimentLab.PAUSED, 10)
    if paused != :ok
        cancel!(session)
        wait(session)
    end
    @test paused == :ok
    @test state.completed == 2
    @test state.total == 3
    @test events == [1, 2]

    # Default state copying remains usable without an algorithm-specific snapshot.
    saved = ExperimentLab.copy_state(state)
    @test saved !== state
    driver = session.task
    resume!(session)
    @test fetch(session) == (; total=10)
    @test session.task === driver
    @test events == [1, 2, 3, 4]

    remaining = Int[]
    @test fetch(start_run(algorithm_steps(saved); threaded,
        onstep=(_, step) -> push!(remaining, step))) == (; total=10)
    @test remaining == [3, 4]

    stopped = SumAlgorithmState(4, 0, 0)
    cancelled = start_run(algorithm_steps(stopped); threaded,
        onstep=(session, _) -> cancel!(session))
    wait(cancelled)
    @test stopped.completed == 1
    @test run_status(cancelled) == ExperimentLab.CANCELLED
end
