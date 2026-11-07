import JSON

@testset "Session inspection is JSON-ready and nonblocking" begin
    entered, release = Channel{Nothing}(1), Channel{Nothing}(1)
    session = start_run(gated_step(entered, release, Int[]); threaded=false)
    take!(entered)
    try
        pause!(session)
        @test applicable(ExperimentLab.describe, session)
        if applicable(ExperimentLab.describe, session)
            description = ExperimentLab.describe(session)
            @test description.status == "running"
            @test description.request == "pause"
            @test description.execution === nothing
            @test description.store === nothing
            @test !description.result_available
            @test JSON.parse(JSON.json(description))["kind"] == "session"
            put!(release, nothing)
            wait_for_status(session, ExperimentLab.PAUSED)
            @test ExperimentLab.describe(session).status == "paused"
        end
    finally
        isready(release) || put!(release, nothing)
        cancel!(session)
        wait(session)
    end
    if applicable(ExperimentLab.describe, session)
        @test ExperimentLab.describe(session).status == "cancelled"
        completed = start_run(sum_steps(2); threaded=false)
        fetch(completed)
        @test ExperimentLab.describe(completed).result_available
        failed = start_run(failing_steps(); threaded=false)
        wait(failed)
        description = ExperimentLab.describe(failed)
        @test description.status == "failed"
        @test occursin("algorithm failure", description.error.message)
        @test !description.result_available
    end
end
