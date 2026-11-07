include(joinpath(@__DIR__, "..", "setup.jl"))
using ExperimentLab, ResumableFunctions

@resumable function subtotal(n::Int)::Int
    total = 0
    for i in 1:n
        total += i
        @yield total
    end
    return total
end

@resumable function two_sums()::Int
    first = @yieldfrom subtotal(2)
    second = @yieldfrom subtotal(3)
    return first + second
end

# Print child progress: 1, 3, 1, 3, 6.
session = start_run(two_sums(); onstep=(_, value) -> println(value))
@show fetch(session)  # 9: the two final answers added together.
nothing
