extends SceneTree

## M5-005 multi-week smoke — the whole M5 loop, repeated. Genesis, then for each
## week: read the inbox, roll availability, spend the action budget, advance the
## turn loop through the raid night (fielding only who availability cleared,
## persisting the lineup so bench streaks accrue) and the rest night, and print
## the end-of-week digest. Rebuilds from the same seed and diffs the full output
## for determinism.
##
##   godot --headless -s tools/smoke/multiweek_smoke.gd -- --seed 12345 --weeks 3
##
## Exits 0 on PASS, 1 on FAIL.

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _int_arg("--seed", 12345)
	var weeks := _int_arg("--weeks", 3)
	print("MULTIWEEK SMOKE: seed=%d weeks=%d" % [seed_value, weeks])

	var output_a := _run(seed_value, weeks)
	if output_a.is_empty():
		printerr("MULTIWEEK SMOKE FAIL: produced nothing")
		quit(1)
		return
	print(output_a)

	if _run(seed_value, weeks) != output_a:
		_failures.append("non-deterministic: same seed produced a different campaign")

	if _failures.is_empty():
		print("MULTIWEEK SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("MULTIWEEK SMOKE FAIL: %s" % failure)
		quit(1)


func _run(seed_value: int, weeks: int) -> String:
	var handle := Genesis.new_in_memory({"seed": seed_value})
	if handle.is_empty():
		return ""
	var db: Variant = handle["db"]
	var guild_id := int(handle["guild_id"])
	var lines: PackedStringArray = []

	for week_index in weeks:
		var state := GameState.read(db)
		var week_id := int(state["week_id"])
		var week_number := _week_number(db, week_id)
		lines.append("--- week %d ---" % week_number)

		# PLAN: who can make the raid, and what needs attention
		var raid_event := _scheduled_raid(db, week_id)
		if raid_event > 0:
			var avail := Availability.roll_for_event(
				db, raid_event, RngStream.derive(seed_value, "availability/w%d" % week_number)
			)
			lines.append("availability: %d can raid" % int(avail.get("available", -1)))
		lines.append("inbox: %s" % _inbox_summary(db, week_id))

		# the week's actions — three lanes, leaving budget headroom
		var party := _member_ids(db, 4)
		var rng := RngStream.derive(seed_value, "actions/w%d" % week_number)
		for step: Array in [
			["farm_mats", "mats", party],
			["drill", str(party[0]), [party[0]]],
			["rest_week", "", []],
		]:
			var acted := ActionResolver.resolve_and_persist(
				db, guild_id, week_id, step[0], str(step[1]), step[2], rng.substream(step[0])
			)
			if not bool(acted["ok"]):
				_failures.append("week %d %s failed: %s" % [week_number, step[0], acted["error"]])

		# ADVANCE: step the loop through the week's events
		var guard := 0
		while guard < 12:
			guard += 1
			var advanced := TurnLoop.advance(db)
			var kind := str(advanced["kind"])
			if kind == "event":
				var event: Dictionary = advanced["event"]
				if str(event["event_type"]) == "raid":
					var night := _play_night(db, seed_value, guild_id, event, week_number)
					if night.is_empty():
						db.close_db()
						return "\n".join(lines)
					lines.append(night)
				TurnLoop.complete_event(db, int(event["event_id"]))
			elif kind == "week_rolled" or kind == "season_complete":
				# REPORT: the digest of the week just played
				lines.append_array(Digest.lines(Digest.build(db, week_id)))
				if kind == "season_complete":
					# the season is over — stop the campaign, not just the week,
					# or --weeks past the season end replays the final week
					lines.append("season complete — grading is M9's job")
					db.close_db()
					return "\n".join(lines)
				break
			else:
				_failures.append("week %d: unexpected advance kind '%s'" % [week_number, kind])
				break

	db.close_db()
	return "\n".join(lines)


## Field the best available 20 (or fewer — running short is a legal night), persist
## the lineup so the bench record exists, and play the night headless.
func _play_night(
	db: Variant, seed_value: int, guild_id: int, event: Dictionary, week_number: int
) -> String:
	var event_id := int(event["event_id"])
	db.query_with_bindings(
		"SELECT player_id FROM event_availability WHERE event_id = ? AND available = 1;", [event_id]
	)
	var pool: Array = db.query_result.duplicate().map(func(r): return int(r["player_id"]))
	# an empty pool means NOBODY rolled available — auto_lineup would read it as
	# "no filter" and field the whole roster, silently inverting the situation
	if pool.is_empty():
		_failures.append("week %d: nobody available to field" % week_number)
		return ""
	var lineup := PullInputLoader.auto_lineup(db, pool)
	if lineup.is_empty():
		_failures.append("week %d: the available pool fills no lineup slot" % week_number)
		return ""
	if not RaidPrep.persist_lineup(db, event_id, lineup):
		_failures.append("week %d: lineup persist failed" % week_number)
		return ""
	var prep := RaidPrep.build(db, event_id, lineup)
	var night := (
		NightRunner
		. run_night(
			db,
			# a per-week night seed: the campaign seed is the root, the week disambiguates
			seed_value + week_number * 7919,
			guild_id,
			event_id,
			{
				"lineup_ids": prep["lineup_ids"],
				"assignments": prep["assignments"],
				"consumable_tier": "basic",
			}
		)
	)
	if not bool(night.get("ok", false)):
		_failures.append("week %d night failed: %s" % [week_number, night.get("error", "?")])
		return ""
	var report: Dictionary = night["report"]
	return "night (%d fielded): %s" % [lineup.size(), str(report["summary_line"])]


func _inbox_summary(db: Variant, week_id: int) -> String:
	var counts := Inbox.counts(Inbox.build(db, week_id))
	if counts.is_empty():
		return "empty"
	var kinds: Array = counts.keys()
	kinds.sort()
	var parts: PackedStringArray = []
	for kind: String in kinds:
		parts.append("%s=%d" % [kind, int(counts[kind])])
	return " ".join(parts)


func _scheduled_raid(db: Variant, week_id: int) -> int:
	db.query_with_bindings(
		(
			"SELECT event_id FROM calendar_event WHERE week_id = ? AND event_type = 'raid'"
			+ " AND status = 'scheduled' ORDER BY day LIMIT 1;"
		),
		[week_id]
	)
	if db.query_result.is_empty():
		return -1
	return int(db.query_result[0]["event_id"])


func _member_ids(db: Variant, count: int) -> Array:
	db.query_with_bindings(
		(
			"SELECT gm.player_id FROM guild_membership gm"
			+ " JOIN guild g ON g.guild_id = gm.guild_id AND g.is_player_guild = 1"
			+ " WHERE gm.status IN ('member', 'trial') ORDER BY gm.player_id LIMIT ?;"
		),
		[count]
	)
	return db.query_result.duplicate().map(func(r): return int(r["player_id"]))


func _week_number(db: Variant, week_id: int) -> int:
	db.query_with_bindings("SELECT week_number FROM week WHERE week_id = ?;", [week_id])
	return int(db.query_result[0]["week_number"])


func _int_arg(flag: String, fallback: int) -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == flag and i + 1 < args.size():
			return int(args[i + 1])
	return fallback
