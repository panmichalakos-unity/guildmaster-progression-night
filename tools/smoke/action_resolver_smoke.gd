extends SceneTree

## M5-004 action-resolver smoke. Creates a campaign, spends the week's action budget
## across all five lanes, prints each outcome and the state it wrote, then rebuilds
## and diffs for determinism.
##
##   godot --headless -s tools/smoke/action_resolver_smoke.gd -- --seed 12345
##
## Exits 0 on PASS, 1 on FAIL.

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_arg()
	print("ACTION RESOLVER SMOKE: seed=%d" % seed_value)

	var digest_a := _run(seed_value)
	if digest_a.is_empty():
		printerr("ACTION RESOLVER SMOKE FAIL: produced nothing")
		quit(1)
		return
	print(digest_a)

	if _run(seed_value) != digest_a:
		_failures.append("non-deterministic: same seed produced different weeks")

	if _failures.is_empty():
		print("ACTION RESOLVER SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("ACTION RESOLVER SMOKE FAIL: %s" % failure)
		quit(1)


func _run(seed_value: int) -> String:
	var handle := Genesis.new_in_memory({"seed": seed_value})
	if handle.is_empty():
		return ""
	var db: Variant = handle["db"]
	var guild_id := int(handle["guild_id"])
	var week_id := int(handle["week_id"])
	var rng := RngStream.derive(seed_value, "week_actions")
	var lines: PackedStringArray = []

	# a party of the first four members for the dungeon; one trainee for the drill
	db.query("SELECT player_id FROM guild_membership ORDER BY player_id LIMIT 4;")
	var party: Array = db.query_result.duplicate().map(func(r): return int(r["player_id"]))
	var trainee := int(party[0])

	var plan := [
		["dungeon_run", "party", party, {}],
		["drill", str(trainee), [trainee], {}],
		["farm_mats", "mats", party, {}],
		["one_on_one", str(trainee), [trainee], {}],
		["rest_week", "", [], {}],
	]
	for step: Array in plan:
		var result := ActionResolver.resolve_and_persist(
			db, guild_id, week_id, step[0], str(step[1]), step[2], rng.substream(step[0]), step[3]
		)
		if not bool(result["ok"]):
			lines.append("%-14s FAILED: %s" % [step[0], result["error"]])
			continue
		lines.append(
			(
				"%-14s -> %s %d (%s)"
				% [step[0], result["output_type"], int(result["output_qty"]), result["outcome"]]
			)
		)

	# the budget wall: a sixth action must be refused
	var sixth := ActionResolver.resolve_and_persist(
		db, guild_id, week_id, "spec_test", "extra", [int(party[1])], rng.substream("sixth")
	)
	lines.append(
		(
			"6th action refused: %s"
			% ("yes — " + str(sixth["error"]) if not bool(sixth["ok"]) else "NO (budget broken!)")
		)
	)

	# the state the week wrote
	db.query("SELECT gold, mats FROM guild_treasury;")
	var t: Dictionary = db.query_result[0]
	db.query_with_bindings("SELECT COALESCE(SUM(marks), 0) AS m FROM avatar;", [])
	var marks := int(db.query_result[0]["m"])
	db.query_with_bindings(
		"SELECT COALESCE(AVG(fatigue), -1) AS f FROM player_week_state WHERE week_id = ?;",
		[week_id]
	)
	(
		lines
		. append(
			(
				"state: gold=%s mats=%s roster_marks=%d avg_fatigue=%.1f ledger_rows=%d week_actions=%d"
				% [
					t["gold"],
					t["mats"],
					marks,
					float(db.query_result[0]["f"]),
					int(_scalar(db, "SELECT COUNT(*) FROM treasury_ledger")),
					int(_scalar(db, "SELECT COUNT(*) FROM week_action")),
				]
			)
		)
	)

	db.close_db()
	return "\n".join(lines)


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]


func _seed_arg() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 12345
