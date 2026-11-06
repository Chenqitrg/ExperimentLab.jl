include(joinpath(@__DIR__, "setup.jl"))

# A small LoopTNR-style example: sample diagnostics, no tensor calculation.
using ExperimentLab
using Logging, LoggingExtras
import LoggingFormats, JSON

struct SweepCompleted <: AbstractLogEvent
    rg_step::Int
    sweep::Int
    cost::Float64
    elapsed_seconds::Float64
end
registry = EventRegistry("looptnr.sweep.v1" => SweepCompleted)
path = joinpath(mktempdir(), "looptnr.jsonl")

# The terminal prints a short summary. It need not print the whole Julia event.
terminal = FormatLogger(stderr) do io, log
    data = log.kwargs[:data]
    println(io, "RG ", data.rg_step, " / sweep ", data.sweep,
        " | cost=", data.cost, " | elapsed=", data.elapsed_seconds, " s")
end

open(path, "a") do io
    disk = MinLevelLogger(FormatLogger(
        LoggingFormats.JSON(; recursive=true, nest_kwargs=false), io), Logging.Info)
    # Change only this terminal threshold to Logging.Warn to silence Info summaries.
    logger = TeeLogger(disk, MinLevelLogger(terminal, Logging.Info))
    with_logger(logger) do
        for (sweep, cost, elapsed) in ((1, 1e-3, 0.4), (2, 1e-5, 0.8), (3, 1e-8, 1.2))
            event = SweepCompleted(1, sweep, cost, elapsed)
            @info "Sweep completed" event_record(registry, event)... execution_id="trial-001"
        end
    end
end

@show path
records = JSON.parse.(readlines(path))
costs = [record["data"]["cost"] for record in records]
@show costs  # [0.001, 1.0e-5, 1.0e-8]
@show records[end]["data"]["elapsed_seconds"]  # 1.2
# Event names/fields are ours; formatting, filtering, routing and writing are library-owned.
nothing
