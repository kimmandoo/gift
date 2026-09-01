# Changelog

## 2026-09-02

- fix(task3): drained stream output without reporting capture overflow.
- feat(task3): added the safe Git executor, discovery, redaction, and settings bridge.
- docs(task3): specified the safe Git executor and installation design.
- docs(repo): documented date-grouped changelog entries.
- fix(scaffold): resolved the FRB code generator from PATH instead of a user-specific path.

## 2026-09-01

- docs(tasks): extracted and established centralized task tracking board.
- test(harness): verified bare remote repository support and finalized clean-room test harness.
- fix(harness): hardened test repository isolation from global Git signing and unsafe paths.
- fix(scaffold): excluded generated bridge bindings from Rust formatting.
- fix(scaffold): preserved canonical generated bridge output after Rust formatting.
- build(scaffold): integrated Cargokit so desktop builds package the Rust bridge.
- test(scaffold): asserted the exact Branchline core version and documented the Windows build limitation.
- build(scaffold): scaffolded the Branchline desktop bridge.
