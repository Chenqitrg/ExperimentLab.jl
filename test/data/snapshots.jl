struct BrokenPayload end
JLD2.writeas(::Type{BrokenPayload}) = String
JLD2.wconvert(::Type{String}, ::BrokenPayload) = error("cannot serialize")

struct BlockIndexPublication
    root::String
end
JLD2.writeas(::Type{BlockIndexPublication}) = String
function JLD2.wconvert(::Type{String}, value::BlockIndexPublication)
    mv(joinpath(value.root, "index.json"), joinpath(value.root, "saved-index.json"))
    mkdir(joinpath(value.root, "index.json"))
    return "unpublished payload"
end

@testset "Snapshot copies detach storage and a capture is persisted once" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        state = (tensor=[1.0, 2.0], nested=[[3.0]])
        captured = capture(source, state)
        state.tensor[1] = 99.0
        state.nested[1][1] = 88.0
        @test captured.value.tensor == [1.0, 2.0]
        @test captured.value.nested == [[3.0]]
        saved = save_snapshot!(store, captured)
        @test AD.info(store, source)["availability"] == "available"
        index_path = joinpath(path, "index.json")
        payload_path = only(readdir(joinpath(path, "tensors"); join=true))
        index_before = stat(index_path)
        payload_before = stat(payload_path)
        @test save_snapshot!(store, captured) == saved
        @test (stat(index_path).inode, stat(index_path).mtime) ==
              (index_before.inode, index_before.mtime)
        @test (stat(payload_path).inode, stat(payload_path).mtime) ==
              (payload_before.inode, payload_before.mtime)
        @test length(readdir(joinpath(path, "tensors"))) == 1
        @test length(AD.records(store, :snapshot)) == 1
        reopened = DataStore(path)
        restored = load_snapshot(reopened, saved)
        @test restored.tensor == [1.0, 2.0]
        restored.tensor[1] = -1.0
        @test load_snapshot(store, saved).tensor == [1.0, 2.0]
        mktempdir() do other_path
            other = DataStore(other_path)
            @test_throws ArgumentError save_snapshot!(other, captured)
            @test isempty(readdir(joinpath(other_path, "tensors")))
            @test_throws ArgumentError load_snapshot(other, saved)
        end
    end
end

@testset "Pins share one payload and survive analysis retention" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        saved = save_snapshot!(store, capture(source, [1.0]))
        first_pin = AD.pin_snapshot!(store, saved; owner="checkpoint-A")
        second_pin = AD.pin_snapshot!(store, saved; owner="checkpoint-B")
        @test length(readdir(joinpath(path, "tensors"))) == 1
        AD.delete_snapshot!(store, saved)
        @test !AD.info(store, saved)["retained"]
        @test load_snapshot(DataStore(path), saved) == [1.0]
        AD.release_pin!(store, first_pin)
        @test load_snapshot(store, saved) == [1.0]
        AD.release_pin!(store, second_pin)
        @test isempty(readdir(joinpath(path, "tensors")))
        @test AD.info(store, source)["availability"] == "removed"
        @test_throws ArgumentError load_snapshot(store, saved)
        @test_throws ArgumentError AD.pin_snapshot!(store, saved; owner="too late")
        @test_throws ArgumentError AD.release_pin!(store, second_pin)
        latest_source = test_state(store)
        latest = save_snapshot!(store, capture(latest_source, [2.0]))
        @test load_snapshot(store, latest) == [2.0]
        @test length(AD.records(store, :snapshot)) == 2 # Metadata is retained.
        @test length(readdir(joinpath(path, "tensors"))) == 1
    end
end

@testset "Payload and publication failures never expose a saved snapshot" begin
    mktempdir() do path
        store = DataStore(path)
        source = test_state(store)
        @test_throws ErrorException save_snapshot!(store, capture(source, BrokenPayload()))
        @test isempty(AD.records(store, :snapshot))
        @test isempty(readdir(joinpath(path, "tensors")))
        @test AD.info(store, source)["availability"] == "never_persisted"

        captured = capture(source, BlockIndexPublication(path))
        @test_throws Exception save_snapshot!(store, captured)
        rm(joinpath(path, "index.json")) # Remove the injected directory, not payload data.
        mv(joinpath(path, "saved-index.json"), joinpath(path, "index.json"))
        @test isempty(AD.records(DataStore(path), :snapshot))
        @test AD.info(store, source)["availability"] == "never_persisted"
        @test length(readdir(joinpath(path, "tensors"))) == 1 # An ignored orphan is not a commit.
    end
end
