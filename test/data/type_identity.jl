module ImportSensitiveTypes
using ExperimentLab
using Configurations: @option
export ImportedSettings, ImportedMeasurement, ImportedResult
@option struct ImportedSettings <: AbstractAlgorithmConfig
    count::Int = 2
end
@option struct ImportedMeasurement <: AbstractMeasurement end
struct ImportedResult <: AbstractMeasurementResult
    count::Int
end
ExperimentLab.measure(::ImportedMeasurement, input) = ImportedResult(length(input))
end
using .ImportSensitiveTypes

@testset "Native type validation is independent of caller imports" begin
    mktempdir() do path
        store = DataStore(path)
        algorithm = AD.record_algorithm!(store, ImportSensitiveTypes.ImportedSettings())
        execution = AD.record_execution!(store, algorithm)
        state = record_state!(store, execution; step=1)
        attempt = measure!(store, ImportSensitiveTypes.ImportedMeasurement(), [1, 2]; state)
        # Stored names must stay qualified even when Main imports the types.
        @test AD.info(store, algorithm)["config_type"] == "Main.ImportSensitiveTypes.ImportedSettings"
        @test AD.info(store, attempt)["config_type"] == "Main.ImportSensitiveTypes.ImportedMeasurement"
        @test AD.info(store, attempt)["result_type"] == "Main.ImportSensitiveTypes.ImportedResult"
        @test AD.load_algorithm(store, algorithm) isa ImportSensitiveTypes.ImportedSettings
        @test AD.load_measurement(store, attempt) isa ImportSensitiveTypes.ImportedMeasurement
        @test load_result(store, attempt).count == 2
    end
end
