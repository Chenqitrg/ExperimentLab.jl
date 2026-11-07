include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab, ResumableFunctions

@resumable function sum_steps(n::Int)::Int
    total = 0
    for i in 1:n
        total += i
        @yield total  # Progress after each step.
    end
    return total     # Final answer.
end

session = start_run(sum_steps(3))
@show fetch(session)  # 6
nothing
