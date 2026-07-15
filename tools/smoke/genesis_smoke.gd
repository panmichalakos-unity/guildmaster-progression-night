extends SceneTree

## M5-001 guild-genesis smoke. Creates a campaign in a disposable :memory: DB and
## prints a CANONICAL digest of its starting state, then proves determinism by
## rebuilding and diffing.
##
##   godot --headless -s tools/smoke/genesis_smoke.gd -- --seed 12345
##
## The digest excludes wall-clock columns (game_state.created_at) — determinism
## means "same seed -> same campaign STATE", not same timestamp. Exits 0 on PASS.

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_arg()
	print("GENESIS SMOKE: seed=%d" % seed_value)

	var digest_a := _build_digest(seed_value)
	if digest_a.is_empty():
		printerr("GENESIS SMOKE FAIL: genesis returned nothing")
		quit(1)
		return
	print(digest_a)

	# determinism: same seed, byte-identical digest
	var digest_b := _build_digest(seed_value)
	if digest_a != digest_b:
		_failures.append("non-deterministic: same seed produced two different campaigns")

	# a different seed must actually differ (else the seed is not wired through)
	var digest_c := _build_digest(seed_value + 1)
	if digest_c == digest_a:
		_failures.append("seed is not wired through: seed %d == seed %d" % [seed_value, seed_value + 1])

	if _failures.is_empty():
		print("GENESIS SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("GENESIS SMOKE FAIL: %s" % failure)
		quit(1)


## A stable, timestamp-free text digest of the campaign's starting state.
func _build_digest(seed_value: int) -> String:
	var handle := Genesis.new_in_memory({"seed": seed_value})
	if handle.is_empty():
		return ""
	var db: Variant = handle["db"]
	var lines: PackedStringArray = []

	var state := GameState.read(db)
	lines.append(
		(
			"save-root: expansion=%d season=%d week=%d phase=%s rng_seed=%d"
			% [
				int(state["expansion_id"]),
				int(state["season_id"]),
				int(state["week_id"]),
				state["phase"],
				int(state["rng_seed"]),
			]
		)
	)

	var config := GameConfig.read(db)
	lines.append(
		(
			"config: difficulty=%s involvement=%s sack_risk=%d (pulls=%s loot=%s recruit=%s)"
			% [
				config["difficulty"],
				config["involvement_default"],
				int(config["sack_risk_enabled"]),
				config["involvement_pulls"],
				config["involvement_loot"],
				config["involvement_recruitment"],
			]
		)
	)

	lines.append(
		(
			"guild: %s  rep=%s  gold=%s  loot=%s  members=%d"
			% [
				handle["guild_name"],
				_scalar(db, "SELECT reputation FROM guild WHERE guild_id = %d" % handle["guild_id"]),
				_scalar(db, "SELECT gold FROM guild_treasury WHERE guild_id = %d" % handle["guild_id"]),
				_scalar(
					db, "SELECT active_loot_system FROM guild_config WHERE guild_id = %d" % handle["guild_id"]
				),
				int(_scalar(db, "SELECT COUNT(*) FROM guild_membership WHERE status = 'member'")),
			]
		)
	)

	var sc: Dictionary = handle["scenario"]
	lines.append(
		(
			"night one: incumbent=%s/%s(CRIT) -> fix=%s/%s(IMMUNE)  raid_event=%d"
			% [sc["incumbent_handle"], sc["incumbent_spec"], sc["fix_handle"], sc["fix_spec"], handle["event_id"]]
		)
	)

	db.close_db()
	return "\n".join(lines)


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	if db.query_result.is_empty():
		return "?"
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]


func _seed_arg() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 12345
