# Diagnostic event schemas and explicit record-bound log scopes.
export AbstractLogEvent, EventRegistry, event_record
public with_log

include("events.jl")
include("show.jl")
include("binding.jl")
