# Store and reference tree.
export DataStore, record_state!
public record_algorithm!, load_algorithm, record_execution!, finish_execution!
public info, records, parent_ref, children, showtree

# Capture, persist and retain snapshots.
export capture, save_snapshot!, load_snapshot
public copy_state, delete_snapshot!, pin_snapshot!, release_pin!

# Define measurements and retain their results.
export AbstractMeasurement, AbstractMeasurementResult, measure, measure!, load_result
public result_data, load_measurement, load_result_data
public start_measurement!, finish_measurement!, fail_measurement!

include("types.jl")
include("encoding.jl")
include("storage.jl")
include("records.jl")
include("snapshots.jl")
include("measurement.jl")
include("describe.jl")
include("show.jl")
include("tree.jl")
