# Guildmaster: Progression Night

A data-driven guild-management game prototype: assemble a raid, make preparation decisions, run deterministic encounters and inspect why the team succeeded or failed.

**Author and project owner: Panos Michalakos.** Independent side project built with Godot 4.7, GDScript and SQLite. The playable slice and simulation are implemented; the full game and commercial release are unfinished.

## Why this project is interesting technically

The game treats content as relational data and simulation results as inspectable state. It is an example of applying data-modeling and validation practices to a creative domain.

| Engineering concern | Implementation to inspect |
| --- | --- |
| Relational modeling | [Numbered schema migrations](data/migrations/) and [data-model reference](docs/guildmaster-data-model.md) |
| Transactional schema changes | [Migration runner](sim/db/migrator.gd): per-migration transactions, foreign-key enforcement and an applied-migration ledger |
| Reproducible content loading | [Seed loader](sim/db/seed_loader.gd): ordered manifest, slug-to-ID reference resolution and stable-ID upserts |
| Data quality without the engine | [Python seed checker](tools/seed_check.py): SQLite constraint checks, references, coverage and repeat-load integrity |
| Deterministic simulation | [Seeded RNG](sim/rng/rng_stream.gd), [pull resolution](sim/resolution/pull_resolver.gd) and focused tests |
| Persistence | [Save/load](sim/campaign/save_load.gd), schema/build compatibility checks and round-trip tests |
| UI separation | `game/ui/` presents campaign and simulation state rather than implementing a second simulation |

For a shorter guided explanation, start with [engineering notes](docs/engineering-overview.md). The detailed design documents remain available for deeper review; they include plans and should not be read as claims that every feature is complete.

## Quick check: Python only

```bash
python tools/seed_check.py
```

Python 3.12 is the CI baseline. The checker uses only the standard library: it applies the actual schema and seed data in memory, checks constraints and loads the seeds again to verify stable counts and IDs. This is the fastest way to inspect the data-engineering part without installing Godot.

## Run the playable slice

Use **Godot 4.7 stable**, not an arbitrary 4.x editor. Open `project.godot`, allow the import to finish and press **F6 on `game/scenes/main.tscn` or F5**. The project includes the SQLite and GdUnit4 add-ons; no external service is required.

Choose a seed (for example `133742`) and select **Assemble the Raid**. Inspect the raid-preparation, combat-log and post-night report tabs. The slice demonstrates one raid night; this is not a complete multi-season game or a release build.

The SQLite binaries currently checked in cover Windows x86-64 and Linux x86-64. Other platforms require compatible add-on binaries before running the project.

## Validate the implementation

```bash
python -m pip install 'gdtoolkit==4.5.*'
gdformat --check sim/ game/ tests/ tools/smoke/
gdlint sim/ game/ tests/ tools/smoke/
python tools/seed_check.py
godot --headless --import
godot --headless --quit
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/
godot --headless -s tools/smoke/migrate_smoke.gd
godot --headless -s tools/smoke/seed_smoke.gd
```

[CI](.github/workflows/ci.yml) also exercises roster generation, the vertical slice, the first-night scenario and balance contracts. [Validation evidence](docs/showcase-validation.md) records the checks actually executed. Test evidence is not a claim that the game is finished or balanced for release.

## Decisions and limitations

- SQLite makes save state local and inspectable. It is not a distributed production data platform.
- Stable slugs identify authored content; integer IDs support references inside each campaign database.
- Simulation code stays outside scene presentation, making seeded scenarios and state transitions testable.
- Explicit encounter contracts and diagnostic output make outcomes explainable, rather than relying on an opaque success roll.
- The migration smoke test checks the six shipped migrations and 52 tables explicitly. Future schema changes must update that contract deliberately.
- Gameplay, content breadth, presentation, tuning and release packaging are still in progress. Specifications and backlogs document intent, not completed scope.

Third-party add-ons are credited in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Original project code remains reserved-rights unless the owner grants another licence.
