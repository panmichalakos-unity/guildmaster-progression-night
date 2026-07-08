extends SceneTree

## M0-004 headless migration smoke.
## Usage: godot --headless -s tools/smoke/migrate_smoke.gd
##
## Creates a disposable DB (user://smoke/migrate_smoke.db), proves:
##   1. fresh migrate applies 0001_init.sql exactly once,
##   2. rerun on the same connection applies nothing (idempotent),
##   3. reopen + rerun applies nothing (state persists in schema_migration),
##   4. expected table count and foreign_keys pragma,
## then deletes the DB. Exits 0 on PASS, 1 on FAIL.

const MigratorScript := preload("res://sim/db/migrator.gd")

const SMOKE_DIR := "user://smoke"
const SMOKE_DB := "user://smoke/migrate_smoke.db"
const EXPECTED_TABLES := 51  # 50 game tables + schema_migration (ADR-0005)

var _failures: PackedStringArray = []


func _init() -> void:
	_run()
	if _failures.is_empty():
		print("MIGRATE SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("MIGRATE SMOKE FAIL: %s" % failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		_failures.append(label)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SMOKE_DIR)
	if FileAccess.file_exists(SMOKE_DB):
		DirAccess.remove_absolute(SMOKE_DB)

	# 1. fresh DB: applies exactly 0001_init.sql
	var db: Variant = MigratorScript.open_db(SMOKE_DB)
	if db == null:
		_failures.append("could not open smoke DB")
		return
	var first: Dictionary = MigratorScript.migrate(db)
	_check(first.ok, "fresh migrate ok (err='%s' file='%s')" % [first.error, first.failed_file])
	_check(
		first.applied == ["0001_init.sql"],
		"fresh migrate applied exactly [0001_init.sql], got %s" % [first.applied]
	)

	# 2. rerun on same connection: idempotent
	var second: Dictionary = MigratorScript.migrate(db)
	_check(
		second.ok and second.applied.is_empty(), "rerun applied nothing, got %s" % [second.applied]
	)
	_check(
		second.skipped == ["0001_init.sql"],
		"rerun skipped [0001_init.sql], got %s" % [second.skipped]
	)

	# 3. table count + fk pragma on the live connection
	db.query(
		"SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
	)
	var table_count := int(db.query_result[0]["n"])
	_check(table_count == EXPECTED_TABLES, "table count %d == %d" % [table_count, EXPECTED_TABLES])
	db.query("PRAGMA foreign_keys;")
	_check(int(db.query_result[0]["foreign_keys"]) == 1, "PRAGMA foreign_keys is ON")
	db.close_db()

	# 4. reopen: migration state persisted
	var reopened: Variant = MigratorScript.open_db(SMOKE_DB)
	if reopened == null:
		_failures.append("could not reopen smoke DB")
		return
	var third: Dictionary = MigratorScript.migrate(reopened)
	_check(
		third.ok and third.applied.is_empty(),
		"reopen migrate applied nothing, got %s" % [third.applied]
	)
	_check(MigratorScript.list_pending(reopened).is_empty(), "no pending migrations after reopen")
	reopened.close_db()

	DirAccess.remove_absolute(SMOKE_DB)
	print("  cleaned up %s" % SMOKE_DB)
