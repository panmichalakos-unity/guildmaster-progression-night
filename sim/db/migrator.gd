class_name Migrator
extends RefCounted

## SQLite migration runner (M0-004). Pure — no scene-tree dependencies.
##
## Contract (docs/decisions.md ADR-0004/0005):
##   * Every connection loads the godot-sqlite GDExtension via the idempotent
##     guard below (headless `-s` runs do not auto-load project GDExtensions).
##   * `PRAGMA foreign_keys = ON` on every connection (per-connection in SQLite).
##   * Each migration file runs inside ONE transaction owned by this runner —
##     migration files must NOT contain their own BEGIN/COMMIT.
##   * Applied files are recorded in `schema_migration` by filename; reruns
##     are no-ops (idempotent).
##
## godot-sqlite v4.7 facts this relies on (probed in M0-002/M0-004):
##   * `query()` executes multi-statement scripts.
##   * `error_message` carries the SQLite error after a failed `query()`.
##   * The `foreign_keys` property enables the pragma at open time.

const GDSQLITE_EXTENSION := "res://addons/godot-sqlite/gdsqlite.gdextension"
const DEFAULT_MIGRATIONS_DIR := "res://data/migrations"

## Bootstrap DDL — must stay shape-identical to schema_migration in 0001_init.sql.
const _BOOTSTRAP_SQL := """
CREATE TABLE IF NOT EXISTS schema_migration (
    migration_id   INTEGER PRIMARY KEY,
    filename       TEXT    NOT NULL UNIQUE,
    applied_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);
"""


## Idempotent GDExtension guard (ADR-0004). Safe to call on every open.
static func ensure_sqlite_loaded() -> void:
	if not ClassDB.class_exists("SQLite"):
		GDExtensionManager.load_extension(GDSQLITE_EXTENSION)


## Opens (or creates) the SQLite DB at `db_path` with foreign keys ON.
## Returns the SQLite instance, or null on failure.
static func open_db(db_path: String) -> Variant:
	ensure_sqlite_loaded()
	if not ClassDB.class_exists("SQLite"):
		push_error("Migrator: godot-sqlite extension is not available (%s)" % GDSQLITE_EXTENSION)
		return null
	var db: Variant = ClassDB.instantiate("SQLite")
	db.path = db_path
	db.foreign_keys = true
	if not db.open_db():
		push_error("Migrator: failed to open DB at '%s': %s" % [db_path, db.error_message])
		return null
	return db


## Applies all pending migrations in filename order.
## Returns: { ok: bool, applied: Array[String], skipped: Array[String],
##            failed_file: String, error: String }
static func migrate(db: Variant, migrations_dir: String = DEFAULT_MIGRATIONS_DIR) -> Dictionary:
	var result := {"ok": true, "applied": [], "skipped": [], "failed_file": "", "error": ""}
	if not db.query(_BOOTSTRAP_SQL):
		return _fail(result, "(bootstrap)", db.error_message)

	var files := _list_migration_files(migrations_dir)
	if files.is_empty():
		return _fail(result, "(none)", "no .sql migration files found in %s" % migrations_dir)

	var already_applied := _applied_filenames(db)
	for filename in files:
		if filename in already_applied:
			result.skipped.append(filename)
			continue
		var sql := _read_file(migrations_dir.path_join(filename))
		if sql.is_empty():
			return _fail(result, filename, "could not read migration file")
		db.query("BEGIN TRANSACTION;")
		if not db.query(sql):
			var err: String = db.error_message
			db.query("ROLLBACK;")
			return _fail(result, filename, err)
		if not db.query_with_bindings(
			"INSERT INTO schema_migration (filename) VALUES (?);", [filename]
		):
			var err: String = db.error_message
			db.query("ROLLBACK;")
			return _fail(result, filename, "failed to record migration: %s" % err)
		db.query("COMMIT;")
		result.applied.append(filename)
	return result


## Filenames of migrations on disk that have not been applied yet.
static func list_pending(
	db: Variant, migrations_dir: String = DEFAULT_MIGRATIONS_DIR
) -> Array[String]:
	var pending: Array[String] = []
	db.query(_BOOTSTRAP_SQL)
	var already_applied := _applied_filenames(db)
	for filename in _list_migration_files(migrations_dir):
		if filename not in already_applied:
			pending.append(filename)
	return pending


static func _fail(result: Dictionary, filename: String, error: String) -> Dictionary:
	result.ok = false
	result.failed_file = filename
	result.error = error
	push_error("Migrator: migration '%s' failed: %s" % [filename, error])
	return result


static func _list_migration_files(migrations_dir: String) -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(migrations_dir)
	if dir == null:
		push_error("Migrator: cannot open migrations dir '%s'" % migrations_dir)
		return files
	for filename in dir.get_files():
		if filename.get_extension() == "sql":
			files.append(filename)
	files.sort()  # numbered files (0001_..., 0002_...) apply in order
	return files


static func _applied_filenames(db: Variant) -> Array[String]:
	var applied: Array[String] = []
	db.query("SELECT filename FROM schema_migration ORDER BY migration_id;")
	for row in db.query_result:
		applied.append(str(row["filename"]))
	return applied


static func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
