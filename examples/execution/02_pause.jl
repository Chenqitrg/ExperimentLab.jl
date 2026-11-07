include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab, ResumableFunctions

@resumable function counting(n::Int)::Int
    for i in 1:n
        @yield i
    end
    return n
end

session = start_run(counting(5); threaded=false)
yield()  # Let the background task begin.
pause!(session; wait=true)
@show run_status(session)  # ExperimentLab.PAUSED

resume!(session)
@show fetch(session)  # 5
nothing
