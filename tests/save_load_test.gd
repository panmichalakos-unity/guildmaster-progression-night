extends GdUnitTestSuite

## M5-006 — load/continue an existing campaign. The SQLite DB is the save:
## opening one validates the migration ledger, refuses newer-build saves,
## migrates forward, refreshes content, and resumes at the persisted position.
## Round-trips are lossless and continuing a reopened save is deterministic.

const SEED := 12345
const DIR := "user://test_saves"


func _path(file: String) -> String:
	var path := DIR.path_join(file)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	if db.query_result.is_empty():
		return null
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]


func _campaign_digest(db: Variant) -> String:
	var parts: PackedStringArray = []
	db.query(
		(
			"SELECT expansion_id, season_id, week_id, phase, current_day, rng_seed"
			+ " FROM game_state WHERE game_id = 1;"
		)
	)
	parts.append(str(db.query_result[0]))
	for sql in [
		"SELECT COUNT(*) AS n FROM player",
		"SELECT COALESCE(SUM(gear_score), 0) AS n FROM avatar",
		"SELECT COALESCE(SUM(marks), 0) AS n FROM avatar",
		"SELECT COUNT(*) AS n FROM guild_membership",
		"SELECT COUNT(*) AS n FROM encounter",
		"SELECT COALESCE(SUM(progress), 0) AS n FROM guild_encounter_progress",
	]:
		parts.append(str(_scalar(db, sql)))
	return " | ".join(parts)


func test_the_round_trip_is_lossless_and_campaign_state_survives() -> void:
	var path := _path("roundtrip.db")
	var created := SaveLoad.new_campaign(path, {"seed": SEED})
	assert_bool(bool(created["ok"])).is_true()
	var db: Variant = created["db"]
	# lived-in campaign state: marks earned, boss progress on the books
	db.query("UPDATE avatar SET marks = marks + 7 WHERE avatar_id = 1;")
	db.query_with_bindings(
		(
			"INSERT INTO guild_encounter_progress (guild_id, encounter_id, progress,"
			+ " attempt_count, best_attempt_pct) VALUES (?, 1, 55, 4, 55);"
		),
		[int(created["guild_id"])]
	)
	var before := _campaign_digest(db)
	db.close_db()

	var reopened := SaveLoad.open_campaign(path)
	assert_bool(bool(reopened["ok"])).is_true()
	assert_str(_campaign_digest(reopened["db"])).is_equal(before)
	assert_str(str(reopened["guild_name"])).is_equal(str(created["guild_name"]))
	reopened["db"].close_db()


func test_a_save_resumes_at_its_persisted_position() -> void:
	var path := _path("resume.db")
	var created := SaveLoad.new_campaign(path, {"seed": SEED})
	assert_bool(bool(created["ok"])).is_true()
	var db: Variant = created["db"]
	# stop ON the raid night, mid-week, and walk away
	var advanced := TurnLoop.advance(db)
	assert_str(str(advanced["kind"])).is_equal("event")
	db.close_db()

	var reopened := SaveLoad.open_campaign(path)
	assert_bool(bool(reopened["ok"])).is_true()
	assert_str(str(reopened["phase"])).is_equal("raid")
	assert_int(int(reopened["current_day"])).is_equal(3)
	# the loop remembers the unresolved night — resuming cannot skip it
	var blocked := TurnLoop.advance(reopened["db"])
	assert_str(str(blocked["kind"])).is_equal("blocked")
	reopened["db"].close_db()


func test_continuing_a_reopened_save_matches_never_closing_it() -> void:
	var digests: Array[String] = []
	for variant in ["reopened", "unbroken"]:
		var path := _path("determinism_%s.db" % variant)
		var handle := SaveLoad.new_campaign(path, {"seed": SEED})
		assert_bool(bool(handle["ok"])).is_true()
		var db: Variant = handle["db"]
		var stopped := TurnLoop.advance(db)
		TurnLoop.complete_event(db, int(stopped["event"]["event_id"]))

		if variant == "reopened":
			db.close_db()
			var back := SaveLoad.open_campaign(path)
			assert_bool(bool(back["ok"])).is_true()
			db = back["db"]

		# play out the rest of the week identically
		var guard := 0
		while guard < 8:
			guard += 1
			var advanced := TurnLoop.advance(db)
			if str(advanced["kind"]) == "event":
				TurnLoop.complete_event(db, int(advanced["event"]["event_id"]))
			elif str(advanced["kind"]) == "week_rolled":
				break
		digests.append(_campaign_digest(db))
		db.close_db()
	assert_str(digests[0]).is_equal(digests[1])


func test_a_newer_build_save_is_refused_with_the_reason_named() -> void:
	var path := _path("future.db")
	var created := SaveLoad.new_campaign(path, {"seed": SEED})
	assert_bool(bool(created["ok"])).is_true()
	created["db"].query(
		"INSERT INTO schema_migration (filename) VALUES ('9999_from_the_future.sql');"
	)
	created["db"].close_db()

	var refused := SaveLoad.open_campaign(path)
	assert_bool(bool(refused["ok"])).is_false()
	assert_str(str(refused["error"])).contains("NEWER")


func test_garbage_and_missing_files_fail_loudly_never_reset() -> void:
	var missing := SaveLoad.open_campaign(DIR.path_join("never_written.db"))
	assert_bool(bool(missing["ok"])).is_false()
	assert_str(str(missing["error"])).contains("no save")

	var garbage_path := _path("garbage.db")
	DirAccess.make_dir_recursive_absolute(DIR)
	var out := FileAccess.open(garbage_path, FileAccess.WRITE)
	out.store_string("this is not a database, it is a text file wearing a trenchcoat")
	out.close()
	var refused := SaveLoad.open_campaign(garbage_path)
	assert_bool(bool(refused["ok"])).is_false()
	assert_str(str(refused["error"])).contains("not a campaign save")
	# the garbage file was refused, not "helpfully" replaced
	assert_bool(FileAccess.file_exists(garbage_path)).is_true()


func test_new_campaign_never_overwrites_an_existing_save() -> void:
	var path := _path("precious.db")
	var created := SaveLoad.new_campaign(path, {"seed": SEED})
	assert_bool(bool(created["ok"])).is_true()
	created["db"].close_db()

	var second := SaveLoad.new_campaign(path, {"seed": SEED + 1})
	assert_bool(bool(second["ok"])).is_false()
	assert_str(str(second["error"])).contains("already exists")


func test_list_saves_finds_campaigns_and_skips_impostors() -> void:
	for stale in ["list_a.db", "list_b.db", "list_junk.db"]:
		_path(stale)  # clears leftovers from prior runs
	var a := SaveLoad.new_campaign(DIR.path_join("list_a.db"), {"seed": SEED})
	var b := SaveLoad.new_campaign(DIR.path_join("list_b.db"), {"seed": SEED + 1})
	assert_bool(bool(a["ok"]) and bool(b["ok"])).is_true()
	a["db"].close_db()
	b["db"].close_db()
	var junk := FileAccess.open(DIR.path_join("list_junk.db"), FileAccess.WRITE)
	junk.store_string("junk")
	junk.close()

	var saves := SaveLoad.list_saves(DIR)
	var files: Array[String] = []
	for entry: Dictionary in saves:
		files.append(str(entry["file"]))
		assert_int(int(entry["week_number"])).is_greater_equal(1)
	assert_bool(files.has("list_a.db")).is_true()
	assert_bool(files.has("list_b.db")).is_true()
	assert_bool(files.has("list_junk.db")).is_false()
