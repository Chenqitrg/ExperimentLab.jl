using Configurations, JSON

@testset "plain JSON uses Configurations defaults and concrete types" begin
    original = Nested(child=Leaf(count=7), enabled=false)
    mktempdir() do dir
        path = joinpath(dir, "config.json")
        writeconfig(path, original)
        @test JSON.parsefile(path)["child"]["count"] == 7
        @test readconfig(path, typeof(original)) == original
        @test readconfig(IOBuffer("{}"), typeof(original)) == Nested()
        @test_throws Configurations.InvalidKeyError readconfig(IOBuffer("{\"unknown\":1}"), Leaf)
        @test_throws ArgumentError readconfig(IOBuffer("{}"), Nested)
        writeconfig(path, Nested(); include_defaults=false)
        @test isempty(JSON.parsefile(path))
        @test readconfig(path, typeof(original)) == Nested()
    end
    @test_throws ArgumentError readconfig(IOBuffer("{\"min_sweeps\":0}"), SweepSettings)
    io = IOBuffer()
    writeconfig(io, OptimizationSettings())
    @test readconfig(IOBuffer(take!(io)), typeof(OptimizationSettings())) == OptimizationSettings()
end
