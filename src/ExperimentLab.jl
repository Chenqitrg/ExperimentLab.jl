module ExperimentLab

using Dates
using UUIDs
import ResumableFunctions
using ResumableFunctions: @resumable, @yieldfrom
import JLD2
import Configurations
import JSON
import Logging, LoggingExtras, LoggingFormats

export AbstractAlgorithmConfig, @config, readconfig, writeconfig
public ConfigError, configtree
public config_constructor, config_fields, config_defaults, value_expression

export AbstractLogEvent, EventRegistry, event_record

export start_run, pause!, resume!, cancel!, run_status
public Session, RunStatus, RUNNING, PAUSED, COMPLETED, CANCELLED, FAILED

export DataStore, record_state!
export capture, save_snapshot!, load_snapshot
export AbstractMeasurement, AbstractMeasurementResult, measure, measure!, load_result
public record_algorithm!, load_algorithm, record_execution!, finish_execution!, info, records
public parent_ref, children, showtree
public copy_state, delete_snapshot!, pin_snapshot!, release_pin!
public result_data, start_measurement!, finish_measurement!, fail_measurement!, load_measurement
public load_result_data
public describe
public with_log

include("config/algorithm_config.jl")
include("config/construction.jl")
include("config/tree_parser.jl")
include("config/tree_output.jl")
include("config/files.jl")

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
include("logging/binding.jl")

include("execution/session.jl")
include("execution/driver.jl")
include("execution/binding.jl")
end
