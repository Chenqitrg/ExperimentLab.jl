@testset "Structured descriptions for AI inspection" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = AD.record_algorithm!(store, ExampleRun(); label="settings")
        run = AD.record_execution!(store, algorithm; label="first", provenance=(revision="abc",))
        state = record_state!(store, run; step=1)
        saved = save_snapshot!(store, capture(state, [2.0]))
        attempt = measure!(store, SmallestValues(), saved)
        branch = AD.record_execution!(store, algorithm; initial_state=state, label="branch")
        branch_state = record_state!(store, branch; step=2)
        AD.finish_execution!(store, run)
        # Inspection must not load any scientific data, including result JSON.
        for directory in ("tensors", "algorithms", "measurements")
            for file in readdir(joinpath(path, directory); join=true)
                write(file, "unreadable payload")
            end
        end
        description = AD.describe(store)
        @test description.kind == "data_store"
        @test !description.truncated
        @test description.child_count == 1
        root = only(description.children)
        @test root.id == string(algorithm.id)
        @test root.parent === nothing
        @test root.config["root"]["kwargs"]["chi"] == 8
        @test root.child_count == 2
        data = JSON.parse(JSON.json(description))
        @test data["children"][1]["kind"] == "algorithm"
        @test data["limits"] == Dict("maxdepth"=>8, "maxnodes"=>100)
        subtree = AD.describe(store, run)
        @test subtree.status == "completed"
        @test subtree.parent == Dict("kind"=>"algorithm", "id"=>string(algorithm.id))
        @test subtree.provenance["revision"] == "abc"
        state_node = only(subtree.children)
        @test state_node.step == 1
        @test state_node.availability == "available"
        measurement = only(filter(node -> node.kind == "measurement", state_node.children))
        @test measurement.id == string(attempt.id)
        @test measurement.input_snapshot == Dict("kind"=>"snapshot", "id"=>string(saved.id))
        @test measurement.result == "measurements/$(attempt.id).json"
        @test isempty(measurement.children)
        branch_node = AD.describe(store, branch)
        @test branch_node.initial_state == Dict("kind"=>"state", "id"=>string(state.id))
        @test only(branch_node.children).id == string(branch_state.id)
        @test !occursin("unreadable payload", JSON.json(description))
        # Returned metadata is detached from disk and subsequent descriptions.
        root.config["root"]["kwargs"]["chi"] = 999
        @test AD.describe(store, algorithm).config["root"]["kwargs"]["chi"] == 8
        shallow = AD.describe(store, run; maxdepth=0)
        @test shallow.truncated && isempty(shallow.children)
        @test shallow.child_count == shallow.omitted_children == 1
        empty_tree = AD.describe(store; maxdepth=0)
        @test empty_tree.truncated && empty_tree.omitted_children == 1
        # A wide history remains bounded, and omitted children are explicit.
        for _ in 1:25
            AD.record_execution!(store, algorithm)
        end
        limited = AD.describe(store, algorithm; maxnodes=1)
        @test limited.truncated && isempty(limited.children)
        @test limited.omitted_children == limited.child_count == 27
        count_nodes(node) = 1 + sum(count_nodes, node.children; init=0)
        bounded = AD.describe(store; maxnodes=4)
        @test sum(count_nodes, bounded.children; init=0) == 4
        @test bounded.truncated
        @test_throws ArgumentError AD.describe(store; maxnodes=0)
        @test_throws ArgumentError AD.describe(store; maxdepth=-1)
        missing = AD.StateRef(store.id, AD.uuid4())
        @test_throws ArgumentError AD.describe(store, missing)
        mktempdir() do other
            @test_throws ArgumentError AD.describe(DataStore(other), state)
        end
    end
    mktempdir() do path
        empty_store = AD.describe(DataStore(path))
        @test !empty_store.truncated && isempty(empty_store.children)
        @test empty_store.child_count == empty_store.omitted_children == 0
    end
end
