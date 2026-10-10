# Engineering walkthrough

This is a game prototype, with data-engineering patterns visible in its implementation. The most useful review path is the model, loading contract, simulation boundary and executable checks.

## 1. Content and campaign state have different lifecycles

CSV seeds describe authored content: roles, classes, specializations, encounters, loot and tuning. A dependency-ordered manifest loads that content into a migrated SQLite schema. Runtime campaign state and encounter facts live alongside it, under explicit foreign keys and constraints.

Start with `data/seeds/manifest.json`, `data/migrations/0001_init.sql` and `docs/guildmaster-data-model.md`. Later migrations extend the initial model. The full design reference includes planned functionality; executable code and tests establish the implemented subset.

## 2. Loading should preserve identity

`sim/db/seed_loader.gd` resolves authored slugs to integer foreign keys and loads the manifest transactionally. Upserts preserve IDs instead of deleting and replacing referenced records. Repeat-load checks in `tools/seed_check.py` and the GDScript tests exercise this contract.

The Python checker mirrors loading conventions to catch data errors before an editor run. This duplication is intentional and requires both implementations to stay aligned.

## 3. Reproducibility is a debugging tool

RNG behavior is centralized in `sim/rng/rng_stream.gd`. Campaign and encounter code consume seeded streams; tests verify repeatability. That lets a failed scenario be reproduced and examined instead of treating the outcome as untraceable randomness.

Review `sim/resolution/pull_resolver.gd` with `tests/pull_resolver_test.gd`, then inspect save/load tests for persistence and replay behavior. Determinism is scoped to the implemented inputs and engine behavior, not a promise of identical results across arbitrary future versions.

## 4. Presentation reads the simulation

`game/ui/` renders preparation choices, encounter logs and reports. The core calculation remains in `sim/`, separating presentation changes from simulation behavior. The visible slice makes the architecture inspectable; it is not a finished game.

## 5. Checks must evolve with the schema

The original migration smoke asserted only the initial migration and 51 tables. The shipped schema has six migrations and 52 tables. The showcase update corrects those explicit expectations while retaining fresh-load, no-op rerun, foreign-key and reopen checks.

The stronger evidence is the combination of schema constraints, seed integrity checks, simulation tests and scenario smokes. Passing unit tests alone would not establish that the project boots or that every content contract holds.

The seed-loader smoke also had initial-content counts after the catalogue had grown. Its expectations now match 20 manifest files, 10 encounters, 58 event placements and 61 loot items. Stable-ID and repeat-load assertions remain in place.
