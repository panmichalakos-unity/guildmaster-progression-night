extends SceneTree

## M0-005 headless seed-loader smoke.
## Usage: godot --headless -s tools/smoke/seed_smoke.gd
##
## In a disposable :memory: DB: migrate, load data/seeds twice (idempotency),
## verify row counts and slug lookups. Exits 0 on PASS, 1 on FAIL.

const MigratorScript := preload("res://sim/db/migrator.gd")
const SeedLoaderScript := preload("res://sim/db/seed_loader.gd")

var _failures: PackedStringArray = []


func _init() -> void:
	_run()
	if _failures.is_empty():
		print("SEED SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("SEED SMOKE FAIL: %s" % failure)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: %s" % label)
	else:
		_failures.append(label)


func _count(db: Variant, table: String) -> int:
	db.query("SELECT COUNT(*) AS n FROM %s;" % table)
	return int(db.query_result[0]["n"])


func _run() -> void:
	var db: Variant = MigratorScript.open_db(":memory:")
	if db == null:
		_failures.append("could not open :memory: DB")
		return
	var migrated: Dictionary = MigratorScript.migrate(db)
	if not migrated.ok:
		_failures.append("migration failed: %s" % migrated.error)
		return

	# 1. first load
	var first: Dictionary = SeedLoaderScript.load_seeds(db)
	_check(first.ok, "seed load ok (err='%s' file='%s')" % [first.error, first.failed_file])
	_check(first.files.size() == 17, "manifest loaded 17 files, got %d" % first.files.size())
	_check(_count(db, "role") == 4, "role has 4 rows")
	_check(_count(db, "slot") == 7, "slot has 7 rows")
	_check(_count(db, "class") == 6, "class has 6 rows (M1-001)")
	_check(_count(db, "spec") == 18, "spec has 18 rows (M1-001)")
	_check(_count(db, "spec_utility") == 21, "spec_utility has 21 links (M1-001)")
	_check(_count(db, "encounter") == 4, "encounter has 4 bosses (M1-002)")
	_check(_count(db, "event_type") == 7, "event_type has the core-7 (M1-002)")
	_check(_count(db, "encounter_event") == 21, "encounter_event has 21 placements (M1-002)")
	_check(_count(db, "loot_item") == 23, "loot_item has 23 rows: 16 drops + 7 vendor (M1-003)")
	_check(_count(db, "consumable") == 10, "consumable has 10 rows (M1-003)")

	# 2. slug integrity
	db.query("SELECT role_id FROM role WHERE slug = 'tank';")
	_check(db.query_result.size() == 1, "slug lookup 'tank' resolves")
	db.query("SELECT slot_id FROM slot WHERE slug = 'weapon';")
	_check(db.query_result.size() == 1, "slug lookup 'weapon' resolves")

	# 3. idempotency: reload changes nothing, ids stay stable
	db.query("SELECT role_id FROM role WHERE slug = 'healer';")
	var healer_id_before := int(db.query_result[0]["role_id"])
	var second: Dictionary = SeedLoaderScript.load_seeds(db)
	_check(second.ok, "reload ok")
	_check(_count(db, "role") == 4 and _count(db, "slot") == 7, "reload row counts unchanged")
	db.query("SELECT role_id FROM role WHERE slug = 'healer';")
	_check(
		int(db.query_result[0]["role_id"]) == healer_id_before,
		"reload preserves integer ids (upsert, not replace)"
	)

	# 4. useful counts for the content author (per manifest table)
	print("  -- row counts --")
	for entry: Dictionary in first.files:
		print("  %s: %d rows" % [entry.table, _count(db, str(entry.table))])

	db.close_db()
