extends GdUnitTestSuite

## M0-004: migration service tests. Uses :memory: DBs — nothing touches disk.

const MigratorScript := preload("res://sim/db/migrator.gd")

const BAD_MIGRATIONS_DIR := "res://tests/fixtures/migrations_bad"


func _open_memory_db() -> Variant:
	var db: Variant = MigratorScript.open_db(":memory:")
	assert_object(db).is_not_null()
	return db


func test_fresh_migrate_applies_0001_exactly_once() -> void:
	var db: Variant = _open_memory_db()
	var result: Dictionary = MigratorScript.migrate(db)
	assert_bool(result.ok).is_true()
	assert_array(result.applied).is_equal(
		[
			"0001_init.sql",
			"0002_spec_defense_cap.sql",
			"0003_encounter_contract.sql",
			"0004_involvement.sql",
			"0005_turn_cursor.sql",
		]
	)
	db.query(
		"SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
	)
	assert_int(int(db.query_result[0]["n"])).is_equal(52)
	db.close_db()


func test_migrate_is_idempotent() -> void:
	var db: Variant = _open_memory_db()
	MigratorScript.migrate(db)
	var rerun: Dictionary = MigratorScript.migrate(db)
	assert_bool(rerun.ok).is_true()
	assert_array(rerun.applied).is_empty()
	assert_array(rerun.skipped).is_equal(
		[
			"0001_init.sql",
			"0002_spec_defense_cap.sql",
			"0003_encounter_contract.sql",
			"0004_involvement.sql",
			"0005_turn_cursor.sql",
		]
	)
	assert_array(MigratorScript.list_pending(db)).is_empty()
	db.close_db()


func test_foreign_keys_pragma_is_on() -> void:
	var db: Variant = _open_memory_db()
	db.query("PRAGMA foreign_keys;")
	assert_int(int(db.query_result[0]["foreign_keys"])).is_equal(1)
	db.close_db()


func test_migration_state_is_recorded() -> void:
	var db: Variant = _open_memory_db()
	MigratorScript.migrate(db)
	db.query("SELECT filename FROM schema_migration ORDER BY migration_id;")
	assert_int(db.query_result.size()).is_equal(5)
	assert_str(str(db.query_result[0]["filename"])).is_equal("0001_init.sql")
	assert_str(str(db.query_result[1]["filename"])).is_equal("0002_spec_defense_cap.sql")
	assert_str(str(db.query_result[2]["filename"])).is_equal("0003_encounter_contract.sql")
	assert_str(str(db.query_result[3]["filename"])).is_equal("0004_involvement.sql")
	assert_str(str(db.query_result[4]["filename"])).is_equal("0005_turn_cursor.sql")
	db.close_db()


func test_failed_migration_names_file_and_rolls_back() -> void:
	var db: Variant = _open_memory_db()
	var result: Dictionary = MigratorScript.migrate(db, BAD_MIGRATIONS_DIR)
	assert_bool(result.ok).is_false()
	assert_str(result.failed_file).is_equal("0001_bad.sql")
	assert_str(result.error).is_not_empty()
	# transaction rolled back: the file's first (valid) statement must be gone
	db.query("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name='ok_table';")
	assert_int(int(db.query_result[0]["n"])).is_equal(0)
	# and nothing recorded as applied
	db.query("SELECT COUNT(*) AS n FROM schema_migration;")
	assert_int(int(db.query_result[0]["n"])).is_equal(0)
	db.close_db()
