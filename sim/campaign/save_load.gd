class_name SaveLoad
extends RefCounted

## The load/continue half of the save system (M5-006). Genesis (M5-001) creates
## campaigns; this opens existing ones. One save = one SQLite DB — there is no
## separate save-file format, so "loading" is: open the DB, prove it is a
## campaign from a build we can serve, run pending migrations forward, refresh
## the content seed rows, and hand back a live handle anchored on GAME_STATE.
##
##   SaveLoad.new_campaign(db_path, config)  -> {ok, db, ...genesis handle, path}
##   SaveLoad.open_campaign(db_path)         -> {ok, db, seed, guild_id, guild_name,
##                                               expansion_id, season_id, week_id,
##                                               phase, current_day, path}
##   SaveLoad.list_saves(dir)                -> [{path, file, guild_name, week_number}]
##
## Every failure is {ok:false, error} — loud and legible (a corrupt save, a save
## from a NEWER build, a non-campaign DB), never a silent reset. Determinism:
## nothing here rolls dice; reopening a save and advancing matches never having
## closed it, because all progression lives in the DB and night/action seeds
## derive from GAME_STATE.rng_seed + turn position, never the wall clock.

const DEFAULT_SAVES_DIR := "user://saves"


## File-based genesis: create the save DB at `db_path` and run guild genesis in
## it. Refuses to overwrite an existing file — deleting a campaign must be the
## caller's own explicit act.
static func new_campaign(db_path: String, config: Dictionary = {}) -> Dictionary:
	if FileAccess.file_exists(db_path):
		return {"ok": false, "error": "a save already exists at %s" % db_path}
	var dir := db_path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var db: Variant = Migrator.open_db(db_path)
	if db == null:
		return {"ok": false, "error": "could not create a database at %s" % db_path}
	if not Migrator.migrate(db).ok or not SeedLoader.load_seeds(db).ok:
		db.close_db()
		return {"ok": false, "error": "could not migrate/seed the new save"}
	var handle := Genesis.create_campaign(db, config)
	if handle.is_empty():
		db.close_db()
		return {"ok": false, "error": "genesis failed"}
	handle["ok"] = true
	handle["path"] = db_path
	return handle


## Open an existing campaign and resume at its persisted position. Validation
## order matters: prove the file exists and carries a migration ledger, REJECT a
## save from a newer build (it lists migrations this build has never heard of —
## running our "pending" list against it would corrupt, not upgrade), then run
## our own pending migrations forward and refresh the seed content (content rows
## are the BUILD's; campaign state is the SAVE's — a retuned boss reaches an old
## campaign on load, its progress does not reset).
static func open_campaign(db_path: String) -> Dictionary:
	if not FileAccess.file_exists(db_path):
		return {"ok": false, "error": "no save at %s" % db_path}
	var db: Variant = Migrator.open_db(db_path)
	if db == null:
		return {"ok": false, "error": "could not open %s" % db_path}

	if not db.query("SELECT filename FROM schema_migration ORDER BY migration_id;"):
		db.close_db()
		return {"ok": false, "error": "%s is not a campaign save (no migration ledger)" % db_path}
	var applied: Array[String] = []
	for row in db.query_result:
		applied.append(str(row["filename"]))

	var known := _known_migrations()
	for filename in applied:
		if not known.has(filename):
			db.close_db()
			return {
				"ok": false,
				"error":
				(
					(
						"save %s was written by a NEWER build (it carries migration '%s'"
						+ " this build does not know) — update the game to open it"
					)
					% [db_path, filename]
				),
			}

	if not Migrator.migrate(db).ok:
		db.close_db()
		return {"ok": false, "error": "pending migrations failed on %s" % db_path}
	if not SeedLoader.load_seeds(db).ok:
		db.close_db()
		return {"ok": false, "error": "content refresh failed on %s" % db_path}

	var state := GameState.read(db)
	if state.is_empty():
		db.close_db()
		return {"ok": false, "error": "%s has no campaign anchor (GAME_STATE empty)" % db_path}
	db.query("SELECT guild_id, display_name FROM guild WHERE is_player_guild = 1 LIMIT 1;")
	if db.query_result.is_empty():
		db.close_db()
		return {"ok": false, "error": "%s has no player guild" % db_path}
	var guild: Dictionary = db.query_result[0]

	return {
		"ok": true,
		"db": db,
		"path": db_path,
		"seed": int(state["rng_seed"]),
		"guild_id": int(guild["guild_id"]),
		"guild_name": str(guild["display_name"]),
		"expansion_id": int(state["expansion_id"]),
		"season_id": int(state["season_id"]),
		"week_id": int(state["week_id"]),
		"phase": str(state["phase"]),
		"current_day": int(state["current_day"]),
	}


## The campaigns in `dir`, for a Continue/Load menu: every .db file that opens
## and answers the two questions a save list needs (whose guild, which week).
## Files that do not are skipped, never deleted. Sorted by filename.
static func list_saves(dir: String = DEFAULT_SAVES_DIR) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var access := DirAccess.open(dir)
	if access == null:
		return found
	for file in access.get_files():
		if not file.ends_with(".db"):
			continue
		var path := dir.path_join(file)
		var db: Variant = Migrator.open_db(path)
		if db == null:
			continue
		var entry := {"path": path, "file": file}
		var readable: bool = db.query(
			(
				"SELECT g.display_name, w.week_number FROM game_state gs"
				+ " JOIN week w ON w.week_id = gs.week_id"
				+ " JOIN guild g ON g.is_player_guild = 1 WHERE gs.game_id = 1;"
			)
		)
		if readable and not db.query_result.is_empty():
			entry["guild_name"] = str(db.query_result[0]["display_name"])
			entry["week_number"] = int(db.query_result[0]["week_number"])
			found.append(entry)
		db.close_db()
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return str(a["file"]) < str(b["file"])
	)
	return found


## The migration files this build ships — the yardstick a save is measured
## against. (Migrator keeps its own private lister; six duplicated lines beat
## widening its API for one caller.)
static func _known_migrations() -> Dictionary:
	var known := {}
	var access := DirAccess.open("res://data/migrations")
	if access == null:
		return known
	for file in access.get_files():
		if file.ends_with(".sql"):
			known[file] = true
	return known
