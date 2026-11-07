# Review examples

Start with [01_data_and_events.jl](01_data_and_events.jl). It introduces the two
migrated areas using one small vector. It does not imply automatic log/data binding.

Next, [02_execution_logs.jl](02_execution_logs.jl) binds ordinary messages to a run,
reads them before the scope closes, appends more, and separates a second execution.

Then follow one area at a time:

- [Configuration](config/README.md): `@option`, tree construction, Accessors updates, and JSON files.
- [Execution](execution/README.md): run, pause, and nest small generators.
- [Data](data/README.md): snapshots, measurements, retention, provenance and trees.
- [Events](logging/README.md): schemas, validation, codecs and inspection.
- [Optional logging integrations](logging/integrations/README.md): external logging
  libraries, in their own environment.

Each script starts with setup and leaves its variables at top level. Run the whole
file in VS Code; for selected sections, execute setup and imports first. Restart
Julia when changing a struct definition. LoggingExtras and LoggingFormats are
core dependencies for bound output; only integration examples import them directly
to demonstrate additional application-controlled routing.
