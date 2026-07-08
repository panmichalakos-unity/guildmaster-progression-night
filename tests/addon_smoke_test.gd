extends GdUnitTestSuite

## M0-002 smoke suite: proves the GdUnit4 runner executes and the
## godot-sqlite GDExtension loads and functions. No gameplay logic here.
##
## NOTE for M0-004 (migration service): headless `-s` script runs do not
## auto-load project GDExtensions in Godot 4.7, so any headless entry point
## must call _ensure_sqlite_loaded() (idempotent) before using the SQLite
## class. Class path: `SQLite` via res://addons/godot-sqlite/gdsqlite.gdextension.

const GDSQLITE_EXTENSION := "res://addons/godot-sqlite/gdsqlite.gdextension"


static func _ensure_sqlite_loaded() -> void:
	# Idempotent: load_extension returns OK on first load and
	# ALREADY_LOADED on subsequent calls; both leave the class registered.
	if not ClassDB.class_exists("SQLite"):
		GDExtensionManager.load_extension(GDSQLITE_EXTENSION)


func test_runner_executes() -> void:
	assert_bool(true).is_true()


func test_godot_sqlite_extension_file_present() -> void:
	assert_bool(FileAccess.file_exists(GDSQLITE_EXTENSION)).is_true()


func test_godot_sqlite_extension_loads_and_registers() -> void:
	_ensure_sqlite_loaded()
	assert_bool(ClassDB.class_exists("SQLite")).is_true()


func test_godot_sqlite_in_memory_roundtrip() -> void:
	_ensure_sqlite_loaded()
	var db = ClassDB.instantiate("SQLite")
	db.path = ":memory:"
	assert_bool(db.open_db()).is_true()
	assert_bool(db.query("CREATE TABLE smoke (id INTEGER PRIMARY KEY, note TEXT);")).is_true()
	assert_bool(db.query("INSERT INTO smoke (note) VALUES ('m0-002');")).is_true()
	assert_bool(db.query("SELECT COUNT(*) AS n FROM smoke;")).is_true()
	assert_int(int(db.query_result[0]["n"])).is_equal(1)
	db.close_db()
