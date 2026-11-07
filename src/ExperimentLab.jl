module ExperimentLab

using Dates
using UUIDs
import Configurations, JLD2, JSON
import Logging, LoggingExtras, LoggingFormats
import ResumableFunctions
using ResumableFunctions: @resumable, @yieldfrom

# Shared inspection API; call as ExperimentLab.describe(...).
public describe

# Each area declares its own API and implementation files in this same module.
include("config/config.jl")
include("data/data.jl")
include("logging/logging.jl")
include("execution/execution.jl")

end
