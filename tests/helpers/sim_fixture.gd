class_name SimFixture
extends RefCounted

## THE sim test fixture pattern (M2-001). Every deterministic sim test builds
## on these three moves — do not invent parallel setups:
##
##   1. `SimFixture.new_campaign_db()` — a fully migrated + seeded :memory: DB
##      (the exact pipeline guild genesis uses; nothing touches disk).
##   2. `SimFixture.rng("my_system")` — a named stream off the fixed TEST_SEED.
##   3. Determinism proof: run the unit twice with freshly derived streams and
##      assert the outputs are IDENTICAL (see rng_stream_test.gd for shape).
##
## Sim code under test must accept (input_state, rng) explicitly — if a test
## can't inject these, the code under test is breaking the purity rule.

const MigratorScript := preload("res://sim/db/migrator.gd")
const SeedLoaderScript := preload("res://sim/db/seed_loader.gd")

## Fixed master seed for tests. Tests may use others locally to prove
## divergence, but fixtures and golden expectations key off this one.
const TEST_SEED := 133742


## Migrated + seeded :memory: DB, or null (caller asserts non-null).
static func new_campaign_db() -> Variant:
	var db: Variant = MigratorScript.open_db(":memory:")
	if db == null:
		return null
	if not MigratorScript.migrate(db).ok:
		db.close_db()
		return null
	if not SeedLoaderScript.load_seeds(db).ok:
		db.close_db()
		return null
	return db


## Named stream off the fixed test seed.
static func rng(stream_name: String) -> RngStream:
	return RngStream.derive(TEST_SEED, stream_name)
