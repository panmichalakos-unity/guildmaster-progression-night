extends SceneTree

## M5-006 save/load smoke. Creates a file-backed campaign, closes it, reopens it
## and proves the round-trip is lossless; proves the save list finds it; proves a
## save from a newer build is refused. Runs the whole thing twice and diffs for
## determinism.
##
##   godot --headless -s tools/smoke/save_load_smoke.gd -- --seed 12345
##
## Exits 0 on PASS, 1 on FAIL.

const SAVES_DIR := "user://smoke_saves"

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_arg()
	print("SAVE/LOAD SMOKE: seed=%d" % seed_value)

	var digest_a := _run(seed_value)
	if digest_a.is_empty():
		printerr("SAVE/LOAD SMOKE FAIL: produced nothing")
		quit(1)
		return
	print(digest_a)

	if _run(seed_value) != digest_a:
		_failures.append("non-deterministic: same seed produced a different save")

	if _failures.is_empty():
		print("SAVE/LOAD SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("SAVE/LOAD SMOKE FAIL: %s" % failure)
		quit(1)


func _run(seed_value: int) -> String:
	_wipe_dir()
	var lines: PackedStringArray = []
	var path := SAVES_DIR.path_join("alpha.db")

	var created := SaveLoad.new_campaign(path, {"seed": seed_value})
	if not bool(created.get("ok", false)):
		_failures.append("new_campaign failed: %s" % created.get("error", "?"))
		return ""
	var before := _digest(created["db"])
	created["db"].close_db()

	var reopened := SaveLoad.open_campaign(path)
	if not bool(reopened.get("ok", false)):
		_failures.append("open_campaign failed: %s" % reopened.get("error", "?"))
		return ""
	var after := _digest(reopened["db"])
	reopened["db"].close_db()
	lines.append("round-trip: %s" % ("LOSSLESS" if before == after else "DIVERGED"))
	if before != after:
		_failures.append("round-trip diverged:\n  before %s\n  after  %s" % [before, after])
	lines.append(
		(
			"resumed at: week_id=%d day=%d phase=%s"
			% [int(reopened["week_id"]), int(reopened["current_day"]), str(reopened["phase"])]
		)
	)

	var saves := SaveLoad.list_saves(SAVES_DIR)
	(
		lines
		. append(
			(
				"saves found: %d (%s, week %d)"
				% [
					saves.size(),
					"" if saves.is_empty() else str(saves[0]["guild_name"]),
					0 if saves.is_empty() else int(saves[0]["week_number"]),
				]
			)
		)
	)
	if saves.size() != 1:
		_failures.append("list_saves found %d, expected 1" % saves.size())

	# a save from a NEWER build must be refused, with the reason named
	var future_path := SAVES_DIR.path_join("beta.db")
	var beta := SaveLoad.new_campaign(future_path, {"seed": seed_value + 1})
	if bool(beta.get("ok", false)):
		beta["db"].query(
			"INSERT INTO schema_migration (filename) VALUES ('9999_from_the_future.sql');"
		)
		beta["db"].close_db()
		var refused := SaveLoad.open_campaign(future_path)
		var rejected: bool = (
			not bool(refused.get("ok", false)) and str(refused.get("error", "")).contains("NEWER")
		)
		lines.append("newer-build save refused: %s" % ("yes" if rejected else "NO (danger!)"))
		if not rejected:
			_failures.append("a save from a newer build was not refused")

	return "\n".join(lines)


func _digest(db: Variant) -> String:
	var parts: PackedStringArray = []
	db.query(
		(
			"SELECT expansion_id, season_id, week_id, phase, current_day, rng_seed"
			+ " FROM game_state WHERE game_id = 1;"
		)
	)
	parts.append(str(db.query_result[0]))
	for probe: Array in [
		["players", "SELECT COUNT(*) AS n FROM player"],
		["gear", "SELECT COALESCE(SUM(gear_score), 0) AS n FROM avatar"],
		["encounters", "SELECT COUNT(*) AS n FROM encounter"],
		["guild", "SELECT display_name AS n FROM guild WHERE is_player_guild = 1"],
	]:
		db.query(probe[1])
		parts.append("%s=%s" % [probe[0], db.query_result[0]["n"]])
	return " | ".join(parts)


func _wipe_dir() -> void:
	var access := DirAccess.open(SAVES_DIR)
	if access == null:
		return
	for file in access.get_files():
		DirAccess.remove_absolute(SAVES_DIR.path_join(file))


func _seed_arg() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 12345
