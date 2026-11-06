module ExperimentLab

using Dates
using UUIDs
using Serialization
using AlgorithmConfigLab: AbstractAlgorithmConfig, writeconfig
import JSON

export AbstractLogEvent, EventRegistry, event_record

export DataStore, record_state!
export capture, save_snapshot!, load_snapshot
export AbstractMeasurement, AbstractMeasurementResult, measure, measure!, load_result
public record_algorithm!, load_algorithm, record_execution!, finish_execution!, info, records
public parent_ref, children, showtree
public copy_state, delete_snapshot!, pin_snapshot!, release_pin!
public result_data, start_measurement!, finish_measurement!, fail_measurement!, load_measurement
public load_result_data
public describe

include("data/types.jl")
include("data/encoding.jl")
include("data/storage.jl")
include("data/records.jl")
include("data/snapshots.jl")
include("data/measurement.jl")
include("data/describe.jl")
include("data/show.jl")
include("data/tree.jl")

"""Base type for immutable, explicitly registered diagnostic event structs."""
abstract type AbstractLogEvent end
include("logging/events.jl")
include("logging/show.jl")
end
