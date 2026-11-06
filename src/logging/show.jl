"""
    ExperimentLab.describe(registry)

Return detached, JSON-ready event and codec mappings. Names are sorted; codecs
are not executed and captured callable state is not exposed. This describes the
schema, not a logger, file, execution, or saved event.
"""
function describe end

function encoder_label(encoder)
    type = typeof(encoder)
    name = encoder isa Function ? nameof(encoder) : nameof(type)
    startswith(string(name), "#") && return "anonymous function"
    return string(parentmodule(type), ".", name)
end

function describe(registry::EventRegistry)
    events = sort!([(; name, type=string(type)) for (type, name) in registry.names]; by=x -> x.name)
    codecs = sort!([(; type=string(type), encoder=encoder_label(encoder))
                    for (type, encoder) in registry.codecs]; by=x -> x.type)
    return (; schema=1, kind="event_registry", events, codecs)
end

function Base.show(io::IO, registry::EventRegistry)
    print(io, "EventRegistry(", length(registry.names), " events, ",
        length(registry.codecs), " field encoders)")
end

function Base.show(io::IO, ::MIME"text/plain", registry::EventRegistry)
    show(io, registry)
    get(io, :compact, false) && return nothing
    info = describe(registry)
    limit = get(io, :limit, true) ? max(1, div(displaysize(io)[1] - 5, 2)) : typemax(Int)
    for (title, entries) in (("Events", info.events), ("Field encoders", info.codecs))
        isempty(entries) && continue
        print(io, "\n  ", title, ":")
        for item in Iterators.take(entries, limit)
            print(io, "\n    ")
            if title == "Events"
                show(io, item.name)
                print(io, " → ", item.type)
            else
                print(io, item.type, " → ", item.encoder)
            end
        end
        length(entries) <= limit || print(io, "\n    … ", length(entries) - limit, " more")
    end
    return nothing
end
