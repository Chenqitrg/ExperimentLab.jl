using Test, ExperimentLab, ResumableFunctions

@resumable function sum_steps(n::Int)::Int
    total = 0
    for i in 1:n
        total += i
        @yield total
    end
    return total
end

@resumable function nested_sums()::Int
    first = @yieldfrom sum_steps(2)
    second = @yieldfrom sum_steps(3)
    return first + second
end

@resumable function nested_waits(release)::Int
    result = @yieldfrom nested_sums()
    take!(release)
    return result
end

@testset "generator entry point" begin
    @test applicable(start_run, sum_steps(3))
end

function wait_for_status(session, status)
    outcome = timedwait(() -> run_status(session) == status, 10; pollint=0.001)
    if outcome != :ok
        cancel!(session)
        error("session did not reach $status; got $(run_status(session))")
    end
end

@resumable function mixed_progress()
    @yield nothing
    @yield (cost=0.1,)
    return "finished"
end

@resumable function failing_steps()::Int
    @yield 1
    error("algorithm failure")
end

@resumable function gated_step(entered, release, values)::Int
    put!(entered, nothing)
    take!(release)
    push!(values, 1)
    @yield 1
    push!(values, 2)
    return 2
end

@testset "generator sessions (threaded=$threaded)" for threaded in (false, true)
    @testset "progress differs from the final result" begin
        events = Int[]
        session = start_run(nested_sums(); threaded,
            onstep=(_, value) -> push!(events, value))
        @test fetch(session) == 9
        @test events == [1, 3, 1, 3, 6]
        @test run_status(session) == ExperimentLab.COMPLETED
        @test fetch(start_run(sum_steps(0); threaded)) == 0
        seen = Union{Nothing,NamedTuple{(:cost,),Tuple{Float64}}}[]
        @test fetch(start_run(mixed_progress(); threaded,
            onstep=(_, value) -> push!(seen, value))) == "finished"
        @test seen == [nothing, (cost=0.1,)]
    end

    @testset "pause preserves the driver and nested position" begin
        events = Int[]
        release = Channel{Nothing}(1)
        session = start_run(nested_waits(release); threaded,
            onstep=(s, value) -> begin
                push!(events, value)
                length(events) == 3 && pause!(s)
            end)
        wait_for_status(session, ExperimentLab.PAUSED)
        driver = session.task
        @test !istaskdone(driver)
        @test events == [1, 3, 1]
        waiter = @async wait(session)
        yield()
        @test !istaskdone(waiter)
        pause!(session; wait=true)
        @sync for _ in 1:5
            Threads.@spawn resume!(session)
        end
        put!(release, nothing)
        @test fetch(session) == 9
        wait(waiter)
        @test session.task === driver
        @test events == [1, 3, 1, 3, 6]
        @test_throws ArgumentError resume!(session)
        pause!(session)
        cancel!(session)
        @test fetch(session) == 9
    end

    @testset "pause is acknowledged only after active work finishes" begin
        entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
        values = Int[]
        session = start_run(gated_step(entered, release, values); threaded)
        take!(entered)
        pause!(session)
        @test run_status(session) == ExperimentLab.RUNNING
        stopper = @async pause!(session; wait=true)
        yield()
        @test !istaskdone(stopper)
        put!(release, nothing)
        wait(stopper)
        @test run_status(session) == ExperimentLab.PAUSED
        @test values == [1]
        cancel!(session)
        wait(session)
        @test run_status(session) == ExperimentLab.CANCELLED
        @test values == [1]
        @test_throws ArgumentError fetch(session)
        @test_throws ArgumentError resume!(session)
        cancel!(session)
        pause!(session; wait=true)
        @test run_status(session) == ExperimentLab.CANCELLED
    end

    @testset "pause also waits for a successful callback to finish" begin
        entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
        progress = Int[]
        session = start_run(sum_steps(3); threaded, onstep=(s, value) -> begin
            put!(entered, nothing)
            take!(release)
            push!(progress, value)
        end)
        take!(entered)
        pause!(session)
        stopper = @async pause!(session; wait=true)
        yield()
        @test run_status(session) == ExperimentLab.RUNNING
        @test !istaskdone(stopper)
        @test isempty(progress)
        put!(release, nothing)
        wait(stopper)
        @test run_status(session) == ExperimentLab.PAUSED
        @test progress == [1]
        cancel!(session)
        wait(session)
    end

    @testset "resume revokes a pending pause; cancellation cannot be revoked" begin
        entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
        session = start_run(gated_step(entered, release, Int[]); threaded)
        take!(entered)
        pause!(session)
        resume!(session)
        put!(release, nothing)
        @test fetch(session) == 2

        entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
        session = start_run(gated_step(entered, release, Int[]); threaded)
        take!(entered)
        cancel!(session)
        pause!(session)
        @test_throws ArgumentError resume!(session)
        put!(release, nothing)
        wait(session)
        @test run_status(session) == ExperimentLab.CANCELLED
    end

    @testset "errors are retained and wake pause waiters" begin
        failed = start_run(failing_steps(); threaded)
        wait(failed)
        @test run_status(failed) == ExperimentLab.FAILED
        @test_throws CapturedException fetch(failed)
        @test failed.failure.ex isa ErrorException

        entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
        failed = start_run(sum_steps(2); threaded, onstep=(s, value) -> begin
            put!(entered, nothing)
            take!(release)
            error("callback failure")
        end)
        take!(entered)
        pause!(failed)
        stopper = @async pause!(failed; wait=true)
        put!(release, nothing)
        wait(stopper)
        @test run_status(failed) == ExperimentLab.FAILED
        @test_throws CapturedException fetch(failed)
    end

    @testset "a driver cannot wait for itself" begin
        for operation in (wait, fetch, s -> pause!(s; wait=true))
            failed = start_run(sum_steps(2); threaded,
                onstep=(s, _) -> operation(s))
            wait(failed)
            @test run_status(failed) == ExperimentLab.FAILED
            @test failed.failure.ex isa ArgumentError
        end
    end

    @testset "last yield is a valid pause before return" begin
        session = start_run(sum_steps(1); threaded,
            onstep=(s, _) -> pause!(s))
        wait_for_status(session, ExperimentLab.PAUSED)
        resume!(session)
        @test fetch(session) == 1
    end
end
