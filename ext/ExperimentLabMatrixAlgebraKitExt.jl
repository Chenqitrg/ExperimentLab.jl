module ExperimentLabMatrixAlgebraKitExt

using ExperimentLab
import Configurations
import MatrixAlgebraKit
using MatrixAlgebraKit: TruncationStrategy

ExperimentLab._show_algorithm_config_value(io::IO, value::TruncationStrategy) =
    print(io, nameof(typeof(value)), "(...)")

function ExperimentLab._show_algorithm_config_value(io::IO, ::MatrixAlgebraKit.NoTruncation)
    print(io, "notrunc()")
    return nothing
end

function ExperimentLab._show_algorithm_config_value(
        io::IO,
        strategy::MatrixAlgebraKit.TruncationByOrder,
    )
    if strategy.by === abs && strategy.rev
        print(io, "truncrank(", strategy.howmany, ")")
    else
        print(io, "TruncationByOrder(...)")
    end
    return nothing
end

function ExperimentLab._show_algorithm_config_value(
        io::IO,
        strategy::MatrixAlgebraKit.TruncationByError,
    )
    if strategy.p != 2 || (!iszero(strategy.atol) && !iszero(strategy.rtol))
        print(io, "TruncationByError(...)")
    elseif iszero(strategy.atol) && iszero(strategy.rtol)
        print(io, "truncerror()")
    elseif iszero(strategy.atol)
        print(io, "truncerror(rtol=", strategy.rtol, ")")
    else
        print(io, "truncerror(atol=", strategy.atol, ")")
    end
    return nothing
end

function ExperimentLab._show_algorithm_config_value(
        io::IO,
        strategy::MatrixAlgebraKit.TruncationIntersection,
    )
    for (index, component) in enumerate(strategy.components)
        index > 1 && print(io, " & ")
        ExperimentLab._show_algorithm_config_value(io, component)
    end
    return nothing
end

ExperimentLab._show_algorithm_config_value(io::IO, algorithm::MatrixAlgebraKit.Algorithm) =
    print(io, MatrixAlgebraKit.name(algorithm))

ExperimentLab._show_algorithm_config_value(io::IO, algorithm::MatrixAlgebraKit.AbstractAlgorithm) =
    print(io, nameof(typeof(algorithm)))

# Editable display uses the expression codecs below; the methods above serve
# readable fallbacks when a configuration contains unsupported values.
const EL = ExperimentLab
const MAK = MatrixAlgebraKit

EL.value_expression(::MAK.NoTruncation) = "MatrixAlgebraKit.notrunc()"
function EL.value_expression(value::MAK.TruncationByOrder)
    value.by === abs || throw(ArgumentError("custom truncation ordering needs its own codec"))
    return "MatrixAlgebraKit.TruncationByOrder($(value.howmany), Base.abs, $(value.rev))"
end
function EL.value_expression(value::MAK.TruncationByError)
    args = join((EL.value_expression(x) for x in (value.atol, value.rtol, value.p)), ", ")
    return "MatrixAlgebraKit.TruncationByError(" * args * ")"
end
function EL.value_expression(value::MAK.TruncationIntersection)
    args = join(EL.value_expression.(value.components), ", ")
    return "MatrixAlgebraKit.TruncationIntersection((" * args * ",))"
end

const DRIVERS = (MAK.DefaultDriver, MAK.LAPACK, MAK.CUSOLVER, MAK.ROCSOLVER, MAK.GLA, MAK.Native, MAK.GS)
function EL.value_expression(value::MAK.Driver)
    typeof(value) in DRIVERS || throw(ArgumentError("unsupported MatrixAlgebraKit driver"))
    return "MatrixAlgebraKit." * string(nameof(typeof(value))) * "()"
end
function EL.value_expression(value::MAK.Algorithm)
    MAK.name(value) === :Householder || throw(ArgumentError("no expression codec for algorithm $(MAK.name(value))"))
    kwargs = EL._value_expression(value.kwargs, IdDict(), :full, "algorithm")
    return "MatrixAlgebraKit.Algorithm{:Householder}(" * kwargs * ")"
end

# Configurations conversions are restricted to our configuration owners.
const Owner = EL.AbstractAlgorithmConfig
Configurations.to_dict(::Type{<:Owner}, ::MAK.NoTruncation) = Dict{String,Any}()
Configurations.from_dict(::Type{<:Owner}, ::Type{MAK.NoTruncation}, ::AbstractDict) = MAK.notrunc()
function Configurations.to_dict(::Type{<:Owner}, x::MAK.TruncationByOrder)
    x.by === abs || throw(ArgumentError("only abs truncation ordering supports JSON"))
    return Dict{String,Any}("howmany" => x.howmany, "rev" => x.rev)
end
Configurations.from_dict(::Type{<:Owner}, ::Type{MAK.TruncationByOrder{typeof(abs)}}, d::AbstractDict) =
    MAK.TruncationByOrder(d["howmany"], abs, d["rev"])
Configurations.to_dict(::Type{<:Owner}, x::MAK.TruncationByError) =
    Dict{String,Any}("atol" => x.atol, "rtol" => x.rtol, "p" => x.p)
Configurations.from_dict(::Type{<:Owner}, ::Type{T}, d::AbstractDict) where {T<:MAK.TruncationByError} =
    T(d["atol"], d["rtol"], d["p"])
Configurations.to_dict(::Type{O}, x::MAK.TruncationIntersection) where {O<:Owner} =
    [Configurations.to_dict(O, c) for c in x.components]
function Configurations.from_dict(::Type{O}, ::Type{MAK.TruncationIntersection{T}}, values::AbstractVector) where {O<:Owner,T<:Tuple}
    length(values) == fieldcount(T) || throw(ArgumentError("truncation component count differs"))
    return MAK.TruncationIntersection(Tuple(Configurations.from_dict(O, t, v) for (t,v) in zip(fieldtypes(T), values)))
end
Configurations.to_dict(::Type{<:Owner}, ::MAK.Driver) = Dict{String,Any}()
Configurations.from_dict(::Type{<:Owner}, ::Type{T}, ::AbstractDict) where {T<:MAK.Driver} = T()
function Configurations.to_dict(::Type{O}, x::MAK.Algorithm{:Householder}) where {O<:Owner}
    return Dict(string(k) => Configurations.to_dict(O, v) for (k,v) in pairs(x.kwargs))
end
function Configurations.from_dict(::Type{O}, ::Type{MAK.Algorithm{:Householder,T}}, d::AbstractDict) where {O<:Owner,T<:NamedTuple}
    kwargs = T(Tuple(Configurations.from_dict(O, t, d[string(k)]) for (k,t) in zip(fieldnames(T), fieldtypes(T))))
    return MAK.Algorithm{:Householder}(kwargs)
end

end
