@testset "Bounded metadata-only Ref tree" begin
    mktempdir() do path
        store = DataStore(path)
        a = AD.record_algorithm!(store, ExampleRun(); label="first")
        run = AD.record_execution!(store, a; label="original")
        state = record_state!(store, run; step=7)
        saved = save_snapshot!(store, capture(state, [2.0]))
        attempt = measure!(store, SmallestValues(), saved)
        b = AD.record_algorithm!(store, ExampleRun(16); label="second")
        branch = AD.record_execution!(store, b; initial_state=state, label="branch")
        for dir in ("algorithms", "tensors", "measurements")
            for file in readdir(joinpath(path, dir); join=true)
                endswith(file, ".bin") && write(file, "unreadable payload")
            end
        end
        output = sprint(AD.showtree, store)
        @test all(name -> occursin(name, output),
            ("AlgorithmRef", "ExecutionRef", "StateRef", "SnapshotRef", "MeasurementRef"))
        @test occursin("step=7", output)
        @test occursin("completed", output)
        @test occursin("initial_state → StateRef", output)
        @test occursin("input_snapshot → SnapshotRef", output)
        @test occursin("├─", output)
        @test repr(MIME"text/plain"(), store) == output
        subtree = sprint(io -> AD.showtree(io, store, run))
        @test startswith(subtree, "ExecutionRef")
        @test !occursin("second", subtree)
        @test !occursin("branch", subtree)
        shallow = sprint(io -> AD.showtree(io, store; maxdepth=1))
        @test !occursin("step=7", shallow)
        @test occursin("…", shallow)
        limited = sprint(io -> AD.showtree(io, store; maxnodes=2))
        @test length(split(limited, '\n')) <= 4
        @test occursin("…", limited)
        @test_throws ArgumentError AD.showtree(devnull, store; maxnodes=0)
        @test_throws ArgumentError AD.showtree(devnull, store; maxdepth=-1)
        mktempdir() do other
            @test_throws ArgumentError AD.showtree(devnull, DataStore(other), state)
        end
    end
end
