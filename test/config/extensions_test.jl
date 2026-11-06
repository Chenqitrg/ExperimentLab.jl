using Configurations: @option
using JSON, MatrixAlgebraKit

@option struct CodecSettings{T} <: AbstractAlgorithmConfig
    value::T
    label::String = "settings"
end

@testset "MatrixAlgebraKit tree and Configurations conversions" begin
    for value in (notrunc(), truncrank(8), truncerror(; atol=1e-8, rtol=1e-6, p=1),
                  truncrank(4) & truncerror(; rtol=1e-10),
                  MatrixAlgebraKit.Householder(; blocksize=16, positive=false))
        original = CodecSettings(; value)
        @test isequal(include_string(@__MODULE__, "@config " * repr(configtree(original))), original)
        io = IOBuffer()
        writeconfig(io, original)
        encoded = String(take!(io))
        @test isequal(readconfig(IOBuffer(encoded), typeof(original)), original)
        if value isa MatrixAlgebraKit.TruncationByOrder
            @test JSON.parse(encoded)["value"]["rev"] === true
        elseif value isa MatrixAlgebraKit.TruncationByError
            @test JSON.parse(encoded)["value"]["p"] isa Integer
        end
    end
    original = CodecSettings(value=MatrixAlgebraKit.TruncationByOrder(2, identity, true))
    mktempdir() do dir
        path = joinpath(dir, "config.json")
        write(path, "keep existing file")
        @test_throws ArgumentError writeconfig(path, original)
        @test read(path, String) == "keep existing file"
    end
end
