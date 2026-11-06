# Review examples

Start with [01_data_and_events.jl](01_data_and_events.jl). It introduces the two
migrated areas using one small vector. It does not imply automatic log/data binding.

Then follow one area at a time:

- [Data](data/README.md): snapshots, measurements, retention, provenance and trees.
- [Events](logging/README.md): schemas, validation, codecs and inspection.
- [Optional logging integrations](logging/integrations/README.md): external logging
  libraries, in their own environment.

Each script starts with setup and leaves its variables at top level. Run the whole
file in VS Code; for selected sections, execute setup and imports first. Restart
Julia when changing a struct definition. Example environments do not add optional
logging libraries to the core package's dependencies.
