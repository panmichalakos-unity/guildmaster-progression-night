extends GdUnitTestSuite

## M0-005: seed loader tests. :memory: DBs — nothing touches disk.

const MigratorScript := preload("res://sim/db/migrator.gd")
const SeedLoaderScript := preload("res://sim/db/seed_loader.gd")

const REF_FIXTURE_DIR := "res://tests/fixtures/seeds_ref"
const BAD_REF_FIXTURE_DIR := "res://tests/fixtures/seeds_bad_ref"


func _migrated_db() -> Variant:
	var db: Variant = MigratorScript.open_db(":memory:")
	assert_object(db).is_not_null()
	assert_bool(MigratorScript.migrate(db).ok).is_true()
	return db


func _count(db: Variant, table: String) -> int:
	db.query("SELECT COUNT(*) AS n FROM %s;" % table)
	return int(db.query_result[0]["n"])


func test_structural_seeds_load() -> void:
	var db: Variant = _migrated_db()
	var result: Dictionary = SeedLoaderScript.load_seeds(db)
	assert_bool(result.ok).is_true()
	assert_int(_count(db, "role")).is_equal(4)
	assert_int(_count(db, "slot")).is_equal(7)
	db.close_db()


func test_reload_is_idempotent_and_preserves_ids() -> void:
	var db: Variant = _migrated_db()
	SeedLoaderScript.load_seeds(db)
	db.query("SELECT role_id FROM role WHERE slug = 'melee';")
	var id_before := int(db.query_result[0]["role_id"])
	var rerun: Dictionary = SeedLoaderScript.load_seeds(db)
	assert_bool(rerun.ok).is_true()
	assert_int(_count(db, "role")).is_equal(4)
	db.query("SELECT role_id FROM role WHERE slug = 'melee';")
	assert_int(int(db.query_result[0]["role_id"])).is_equal(id_before)
	db.close_db()


func test_slug_refs_resolve_to_integer_fks() -> void:
	var db: Variant = _migrated_db()
	assert_bool(SeedLoaderScript.load_seeds(db).ok).is_true()  # roles first
	var result: Dictionary = SeedLoaderScript.load_seeds(db, REF_FIXTURE_DIR)
	assert_bool(result.ok).is_true()
	(
		db
		. query(
			"""
		SELECT s.slug, c.slug AS class_slug, r.slug AS role_slug, s.spec_difficulty
		FROM spec s JOIN class c ON c.class_id = s.class_id
		JOIN role r ON r.role_id = s.role_id WHERE s.slug = 'test_spec';
	"""
		)
	)
	assert_int(db.query_result.size()).is_equal(1)
	assert_str(str(db.query_result[0]["class_slug"])).is_equal("test_class")
	assert_str(str(db.query_result[0]["role_slug"])).is_equal("tank")
	assert_int(int(db.query_result[0]["spec_difficulty"])).is_equal(42)
	db.close_db()


func test_bridge_table_upsert_with_declared_key() -> void:
	var db: Variant = _migrated_db()
	SeedLoaderScript.load_seeds(db)
	# real seeds already populate bridges (M1-001) — assert the DELTA
	var links_before := _count(db, "spec_utility")
	assert_bool(SeedLoaderScript.load_seeds(db, REF_FIXTURE_DIR).ok).is_true()
	assert_int(_count(db, "spec_utility")).is_equal(links_before + 1)
	# reload: bridge rows must not duplicate (ON CONFLICT ... DO NOTHING)
	assert_bool(SeedLoaderScript.load_seeds(db, REF_FIXTURE_DIR).ok).is_true()
	assert_int(_count(db, "spec_utility")).is_equal(links_before + 1)
	db.close_db()


func test_unknown_ref_slug_fails_naming_file_and_rolls_back() -> void:
	var db: Variant = _migrated_db()
	SeedLoaderScript.load_seeds(db)
	var spec_count_before := _count(db, "spec")
	var result: Dictionary = SeedLoaderScript.load_seeds(db, BAD_REF_FIXTURE_DIR)
	assert_bool(result.ok).is_false()
	assert_str(result.failed_file).is_equal("spec.csv")
	assert_str(result.error).contains("no_such_class")
	# transaction rolled back: nothing from the bad load persisted
	assert_int(_count(db, "spec")).is_equal(spec_count_before)
	db.close_db()


func test_missing_manifest_fails_cleanly() -> void:
	var db: Variant = _migrated_db()
	var result: Dictionary = SeedLoaderScript.load_seeds(db, "res://tests/fixtures/does_not_exist")
	assert_bool(result.ok).is_false()
	assert_str(result.error).is_not_empty()
	db.close_db()
