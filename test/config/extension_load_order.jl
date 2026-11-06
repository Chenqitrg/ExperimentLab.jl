using Test
if get(ENV, "CONFIG_EXTENSION_ORDER", "core-first") == "extensions-first"
    using MatrixAlgebraKit, JSON
    using ExperimentLab
else
    using ExperimentLab
    using JSON, MatrixAlgebraKit
end
@test !isnothing(Base.get_extension(ExperimentLab, :ExperimentLabMatrixAlgebraKitExt))
@test occursin("notrunc", ExperimentLab.value_expression(MatrixAlgebraKit.notrunc()))
