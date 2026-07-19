class_name Digest
extends RefCounted

## The end-of-week digest (M5-005) — the REPORT beat of the turn loop. Built ONLY
## from persisted audit/state tables (pull, pull_participant, raid_lineup,
## player_week_state, treasury_ledger, week_action, guild_encounter_progress...),
## never from UI state — a save reload rebuilds the same digest.
##
##   Digest.build(db, week_id) -> Dictionary   (sections below)
##   Digest.lines(digest)      -> PackedStringArray  (deterministic render)
##
## Scope note: the digest is built at the week's REPORT beat, and some sections
## (treasury balances, membership, encounter bests) read state as of NOW — rebuild
## a PAST week's digest after further play and those figures reflect the present.
## A history view needs persisted digests; that is future work, not this ticket.
##
## Later systems appear as EXPLICIT `todo` strings on their section (loot awards →
## M6, applicants → M8, objectives → M9) — placeholders, never fake data. Output
## carries no wall-clock anywhere: same save, same digest, byte for byte.
##
## Presentation rule (docs/guildmaster-presentation.md, the "closest yet" fix):
## never print progress-percent to a player — the closest attempt speaks the
## boss's REMAINING health, where lower is better.

## Read-model presentation thresholds — what the digest points at, not sim tuning.
## (The bench-streak threshold is NOT here: BenchCost owns it, from bench tuning.)
const AT_RISK_MORALE := 30
const EXHAUSTED_FATIGUE := 70


## Every section, from the save alone.
static func build(db: Variant, week_id: int) -> Dictionary:
	return {
		"week": _week(db, week_id),
		"raids": _raids(db, week_id),
		"progression": _progression(db, week_id),
		"ratings": _ratings(db, week_id),
		"loot": _loot(db, week_id),
		"roster": _roster(db, week_id),
		"economy": _economy(db, week_id),
		"actions": _actions(db, week_id),
		"applicants": _applicants(db),
		"objectives": _objectives(db, week_id),
	}


## The digest as printable lines — the smoke's output and the UI's first draft.
static func lines(digest: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var week: Dictionary = digest["week"]
	out.append("=== Week %d digest ===" % int(week.get("week_number", 0)))

	var raids: Array = digest["raids"]
	if raids.is_empty():
		out.append("No raid was played this week.")
	for raid: Dictionary in raids:
		if str(raid["status"]) != "completed":
			out.append("The raid on day %d was %s." % [int(raid["day"]), str(raid["status"])])
			continue
		if str(raid["event_type"]) == "dungeon":
			# the "week isn't wasted" decision (M5-003) — say so, never drop it
			out.append("The raid on day %d ran as a dungeon night (converted)." % int(raid["day"]))
			continue
		out.append(
			(
				"Raid night (day %d): %d pulls — %d kills, %d wipes."
				% [int(raid["day"]), int(raid["pulls"]), int(raid["kills"]), int(raid["wipes"])]
			)
		)
		for boss: Dictionary in raid["bosses"]:
			if bool(boss["killed"]):
				out.append("  %s: DOWN in %d pulls." % [str(boss["name"]), int(boss["attempts"])])
			else:
				# the campaign's best attempt, owned as such — per-pull hp is not
				# persisted, so "closest TONIGHT" is not derivable from the save
				var closest := (
					""
					if int(boss["closest_remaining_pct"]) >= 100
					else " Best so far: boss at %d%% health." % int(boss["closest_remaining_pct"])
				)
				var wall := (
					""
					if str(boss["top_cause_label"]).is_empty()
					else " Wall: %s." % str(boss["top_cause_label"])
				)
				(
					out
					. append(
						(
							"  %s: %d wipes over %d pulls.%s%s"
							% [
								str(boss["name"]),
								int(boss["wipes"]),
								int(boss["attempts"]),
								closest,
								wall,
							]
						)
					)
				)

	var progression: Dictionary = digest["progression"]
	if not progression.is_empty():
		(
			out
			. append(
				(
					"Progression: %d/%d bosses down in %s."
					% [
						int(progression["bosses_down"]),
						int(progression["bosses_total"]),
						str(progression["raid_name"]),
					]
				)
			)
		)

	var ratings: Array = digest["ratings"]
	if not ratings.is_empty():
		var top: Dictionary = ratings[0]
		var low: Dictionary = ratings[ratings.size() - 1]
		(
			out
			. append(
				(
					"Raider of the week: %s (%.1f over %d pulls); struggled: %s (%.1f)."
					% [
						str(top["handle"]),
						float(top["avg_rating"]),
						int(top["pulls"]),
						str(low["handle"]),
						float(low["avg_rating"]),
					]
				)
			)
		)

	var roster: Dictionary = digest["roster"]
	out.append(
		(
			"Roster: %d raiders — morale avg %d, fatigue avg %d."
			% [int(roster["members"]), int(roster["avg_morale"]), int(roster["avg_fatigue"])]
		)
	)
	var at_risk: Array = roster["at_risk"]
	if not at_risk.is_empty():
		out.append("  Morale risk: %s." % ", ".join(_handles_of(at_risk)))
	var exhausted: Array = roster["exhausted"]
	if not exhausted.is_empty():
		out.append("  Running on fumes: %s." % ", ".join(_handles_of(exhausted)))
	for cost: Dictionary in roster["bench_costs"]:
		(
			out
			. append(
				(
					"  %s has sat out %d straight raid nights — morale -%d, loyalty -%d."
					% [
						str(cost["handle"]),
						int(cost["streak"]),
						int(cost["morale_ding"]),
						int(cost["loyalty_ding"]),
					]
				)
			)
		)

	var economy: Dictionary = digest["economy"]
	(
		out
		. append(
			(
				"Treasury: gold %+d, mats %+d this week (now %dg, %d mats, %d consumables)."
				% [
					int(economy["gold_delta"]),
					int(economy["mats_delta"]),
					int(economy["gold"]),
					int(economy["mats"]),
					int(economy["consumables"]),
				]
			)
		)
	)

	var actions: Array = digest["actions"]
	if actions.is_empty():
		out.append("No weekly actions were taken.")
	for action: Dictionary in actions:
		(
			out
			. append(
				(
					"  %s -> %s %d (%s, by %s)"
					% [
						str(action["slug"]),
						str(action["output_type"]),
						int(action["output_qty"]),
						str(action["outcome"]),
						str(action["decided_by"]),
					]
				)
			)
		)

	var loot: Dictionary = digest["loot"]
	out.append("Loot: %d awarded, %d pending." % [int(loot["awarded"]), int(loot["unawarded"])])
	if not str(loot["todo"]).is_empty():
		out.append("  TODO(M6): %s" % str(loot["todo"]))

	var applicants: Dictionary = digest["applicants"]
	out.append("Applicants: %d." % int(applicants["count"]))
	if not str(applicants["todo"]).is_empty():
		out.append("  TODO(M8): %s" % str(applicants["todo"]))

	var objectives: Dictionary = digest["objectives"]
	for item: Dictionary in objectives["items"]:
		out.append("Objective: %s — %s." % [str(item["display_name"]), str(item["target"])])
	if not str(objectives["todo"]).is_empty():
		out.append("  TODO(M9): %s" % str(objectives["todo"]))
	return out


# --- sections -----------------------------------------------------------------


static func _week(db: Variant, week_id: int) -> Dictionary:
	db.query_with_bindings("SELECT week_number, season_id FROM week WHERE week_id = ?;", [week_id])
	if db.query_result.is_empty():
		return {}
	var row: Dictionary = db.query_result[0]
	return {
		"week_id": week_id,
		"week_number": int(row["week_number"]),
		"season_id": int(row["season_id"]),
	}


## Raid nights AND raids converted to dungeon nights (M5-003's "the week isn't
## wasted" decision) — dropping the converted event implied the opposite.
static func _raids(db: Variant, week_id: int) -> Array[Dictionary]:
	db.query_with_bindings(
		(
			"SELECT event_id, day, status, event_type FROM calendar_event"
			+ " WHERE week_id = ? AND event_type IN ('raid', 'dungeon')"
			+ " AND status IN ('completed', 'cancelled') ORDER BY day, event_id;"
		),
		[week_id]
	)
	var raids: Array[Dictionary] = []
	for event_row in db.query_result.duplicate():
		var event_id := int(event_row["event_id"])
		var raid := {
			"event_id": event_id,
			"day": int(event_row["day"]),
			"status": str(event_row["status"]),
			"event_type": str(event_row["event_type"]),
			"pulls": 0,
			"kills": 0,
			"wipes": 0,
			"bosses": [] as Array[Dictionary],
		}
		if str(event_row["status"]) == "completed" and str(event_row["event_type"]) == "raid":
			_fill_raid_pulls(db, event_id, raid)
		raids.append(raid)
	return raids


static func _fill_raid_pulls(db: Variant, event_id: int, raid: Dictionary) -> void:
	db.query_with_bindings(
		(
			"SELECT e.slug, e.display_name, e.encounter_id, p.outcome, p.wipe_reason"
			+ " FROM pull p JOIN encounter e ON e.encounter_id = p.encounter_id"
			+ " WHERE p.event_id = ? ORDER BY p.pull_id;"
		),
		[event_id]
	)
	var by_boss := {}
	var bosses: Array[Dictionary] = raid["bosses"]
	for row in db.query_result.duplicate():
		var slug := str(row["slug"])
		if not by_boss.has(slug):
			by_boss[slug] = {
				"slug": slug,
				"name": str(row["display_name"]),
				"encounter_id": int(row["encounter_id"]),
				"attempts": 0,
				"wipes": 0,
				"killed": false,
				"cause_counts": {},
				"top_cause_label": "",
				"closest_remaining_pct": 100,
			}
			bosses.append(by_boss[slug])
		var boss: Dictionary = by_boss[slug]
		boss["attempts"] = int(boss["attempts"]) + 1
		raid["pulls"] = int(raid["pulls"]) + 1
		if str(row["outcome"]) == "kill":
			boss["killed"] = true
			raid["kills"] = int(raid["kills"]) + 1
			continue
		raid["wipes"] = int(raid["wipes"]) + 1
		boss["wipes"] = int(boss["wipes"]) + 1
		# pull.wipe_reason leads with the cause code ("tank_survival: margin ...");
		# the persisted slice before ':' is the tallyable cause (NightReport's rule)
		var cause := str(row["wipe_reason"]).get_slice(":", 0).strip_edges()
		if not cause.is_empty():
			var counts: Dictionary = boss["cause_counts"]
			counts[cause] = int(counts.get(cause, 0)) + 1

	for boss: Dictionary in bosses:
		var counts: Dictionary = boss["cause_counts"]
		var dominant := ""
		var best := 0
		for cause: String in counts:
			if int(counts[cause]) > best or (int(counts[cause]) == best and cause < dominant):
				dominant = cause
				best = int(counts[cause])
		if best >= 2:
			boss["top_cause_label"] = str(Diagnosis.CAUSE_LABELS.get(dominant, dominant))
		if not bool(boss["killed"]):
			db.query_with_bindings(
				(
					"SELECT gep.best_attempt_pct FROM guild_encounter_progress gep"
					+ " JOIN guild g ON g.guild_id = gep.guild_id AND g.is_player_guild = 1"
					+ " WHERE gep.encounter_id = ?;"
				),
				[int(boss["encounter_id"])]
			)
			if not db.query_result.is_empty():
				# best_attempt_pct stores PROGRESS; the player hears remaining health
				boss["closest_remaining_pct"] = 100 - int(db.query_result[0]["best_attempt_pct"])


static func _progression(db: Variant, week_id: int) -> Dictionary:
	db.query_with_bindings(
		(
			"SELECT r.raid_id, r.display_name FROM raid r"
			+ " JOIN week w ON w.season_id = r.season_id WHERE w.week_id = ?"
			+ " ORDER BY r.raid_id LIMIT 1;"
		),
		[week_id]
	)
	if db.query_result.is_empty():
		return {}
	var raid_row: Dictionary = db.query_result[0]
	var raid_id := int(raid_row["raid_id"])
	db.query_with_bindings("SELECT COUNT(*) AS n FROM encounter WHERE raid_id = ?;", [raid_id])
	var total := int(db.query_result[0]["n"])
	db.query_with_bindings(
		(
			"SELECT COUNT(*) AS n FROM guild_encounter_progress gep"
			+ " JOIN guild g ON g.guild_id = gep.guild_id AND g.is_player_guild = 1"
			+ " JOIN encounter e ON e.encounter_id = gep.encounter_id"
			+ " WHERE e.raid_id = ? AND gep.first_kill_at IS NOT NULL;"
		),
		[raid_id]
	)
	return {
		"raid_name": str(raid_row["display_name"]),
		"bosses_total": total,
		"bosses_down": int(db.query_result[0]["n"]),
	}


static func _ratings(db: Variant, week_id: int) -> Array[Dictionary]:
	db.query_with_bindings(
		(
			"SELECT p.handle, COUNT(*) AS pulls, AVG(pp.performance_rating) AS avg_r"
			+ " FROM pull_participant pp"
			+ " JOIN pull pl ON pl.pull_id = pp.pull_id"
			+ " JOIN calendar_event ce ON ce.event_id = pl.event_id"
			+ " JOIN avatar a ON a.avatar_id = pp.avatar_id"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " WHERE ce.week_id = ? GROUP BY pp.avatar_id"
			+ " ORDER BY avg_r DESC, p.handle;"
		),
		[week_id]
	)
	var out: Array[Dictionary] = []
	for row in db.query_result:
		(
			out
			. append(
				{
					"handle": str(row["handle"]),
					"pulls": int(row["pulls"]),
					"avg_rating": snappedf(float(row["avg_r"]), 0.1),
				}
			)
		)
	return out


static func _loot(db: Variant, week_id: int) -> Dictionary:
	db.query_with_bindings(
		(
			"SELECT COUNT(*) AS total,"
			+ " SUM(CASE WHEN ld.awarded_to_player_id IS NULL THEN 1 ELSE 0 END) AS pending"
			+ " FROM loot_drop ld JOIN pull pl ON pl.pull_id = ld.pull_id"
			+ " JOIN calendar_event ce ON ce.event_id = pl.event_id WHERE ce.week_id = ?;"
		),
		[week_id]
	)
	var row: Dictionary = db.query_result[0]
	var total := int(row["total"])
	# SUM over zero rows is NULL — godot-sqlite hands that back as a null Variant
	var pending: int = 0 if row["pending"] == null else int(row["pending"])
	db.query_with_bindings(
		(
			"SELECT COUNT(*) AS n FROM pull p"
			+ " JOIN calendar_event ce ON ce.event_id = p.event_id"
			+ " WHERE ce.week_id = ? AND p.outcome = 'kill';"
		),
		[week_id]
	)
	var kills := int(db.query_result[0]["n"])
	var todo := ""
	if kills > 0 and total == 0:
		todo = (
			"kills happened but no LOOT_DROP rows exist yet — drops, awards and the"
			+ " claims panel land in M6."
		)
	return {"awarded": total - pending, "unawarded": pending, "todo": todo}


static func _roster(db: Variant, week_id: int) -> Dictionary:
	db.query(
		(
			"SELECT COUNT(*) AS n FROM guild_membership gm"
			+ " JOIN guild g ON g.guild_id = gm.guild_id AND g.is_player_guild = 1"
			+ " WHERE gm.status IN ('member', 'trial');"
		)
	)
	var members := int(db.query_result[0]["n"])

	db.query_with_bindings(
		(
			"SELECT p.handle, pws.morale, pws.fatigue FROM player_week_state pws"
			+ " JOIN player p ON p.player_id = pws.player_id"
			+ " JOIN guild_membership gm ON gm.player_id = pws.player_id"
			+ " JOIN guild g ON g.guild_id = gm.guild_id AND g.is_player_guild = 1"
			+ " WHERE pws.week_id = ? AND gm.status IN ('member', 'trial')"
			+ " ORDER BY p.handle;"
		),
		[week_id]
	)
	var morale_sum := 0
	var fatigue_sum := 0
	var count := 0
	var at_risk: Array[Dictionary] = []
	var exhausted: Array[Dictionary] = []
	for row in db.query_result.duplicate():
		count += 1
		morale_sum += int(row["morale"])
		fatigue_sum += int(row["fatigue"])
		if int(row["morale"]) <= AT_RISK_MORALE:
			at_risk.append({"handle": str(row["handle"]), "morale": int(row["morale"])})
		if int(row["fatigue"]) >= EXHAUSTED_FATIGUE:
			exhausted.append({"handle": str(row["handle"]), "fatigue": int(row["fatigue"])})

	return {
		"members": members,
		"avg_morale": 0 if count == 0 else roundi(float(morale_sum) / float(count)),
		"avg_fatigue": 0 if count == 0 else roundi(float(fatigue_sum) / float(count)),
		"at_risk": at_risk,
		"exhausted": exhausted,
		# the streak walk AND the price live in BenchCost (M5-007) — the same
		# deterministic function the week roll applies, so the digest reports
		# exactly what was (or will be) charged, never a parallel estimate
		"bench_costs": BenchCost.assess(db, week_id),
	}


static func _economy(db: Variant, week_id: int) -> Dictionary:
	db.query_with_bindings(
		(
			"SELECT tl.resource_type, SUM(tl.amount) AS delta FROM treasury_ledger tl"
			+ " JOIN guild g ON g.guild_id = tl.guild_id AND g.is_player_guild = 1"
			+ " WHERE tl.week_id = ? GROUP BY tl.resource_type;"
		),
		[week_id]
	)
	var deltas := {"gold": 0, "mats": 0, "consumable": 0}
	for row in db.query_result.duplicate():
		deltas[str(row["resource_type"])] = int(row["delta"])

	db.query(
		(
			"SELECT gt.gold, gt.mats FROM guild_treasury gt"
			+ " JOIN guild g ON g.guild_id = gt.guild_id AND g.is_player_guild = 1;"
		)
	)
	var gold := 0
	var mats := 0
	if not db.query_result.is_empty():
		gold = int(db.query_result[0]["gold"])
		mats = int(db.query_result[0]["mats"])
	db.query(
		(
			"SELECT COALESCE(SUM(gs.quantity), 0) AS n FROM guild_stockpile gs"
			+ " JOIN guild g ON g.guild_id = gs.guild_id AND g.is_player_guild = 1;"
		)
	)
	return {
		"gold_delta": int(deltas["gold"]),
		"mats_delta": int(deltas["mats"]),
		"gold": gold,
		"mats": mats,
		"consumables": int(db.query_result[0]["n"]),
	}


static func _actions(db: Variant, week_id: int) -> Array[Dictionary]:
	db.query_with_bindings(
		(
			"SELECT at.slug, wa.target_ref, wa.output_type, wa.output_qty, wa.outcome,"
			+ " wa.decided_by FROM week_action wa"
			+ " JOIN action_type at ON at.action_type_id = wa.action_type_id"
			+ " JOIN guild g ON g.guild_id = wa.guild_id AND g.is_player_guild = 1"
			+ " WHERE wa.week_id = ? ORDER BY wa.action_id;"
		),
		[week_id]
	)
	var out: Array[Dictionary] = []
	for row in db.query_result.duplicate():
		(
			out
			. append(
				{
					"slug": str(row["slug"]),
					# NULLABLE columns coerce explicitly — str(null) is "<null>" and
					# int(null) errors (the godot-sqlite trap from M5-003/004)
					"target_ref": "" if row["target_ref"] == null else str(row["target_ref"]),
					"output_type": "" if row["output_type"] == null else str(row["output_type"]),
					"output_qty": 0 if row["output_qty"] == null else int(row["output_qty"]),
					"outcome": "" if row["outcome"] == null else str(row["outcome"]),
					"decided_by": str(row["decided_by"]),
				}
			)
		)
	return out


static func _applicants(db: Variant) -> Dictionary:
	db.query(
		(
			"SELECT COUNT(DISTINCT pa.player_id) AS n FROM prospect_assessment pa"
			+ " JOIN guild g ON g.guild_id = pa.guild_id AND g.is_player_guild = 1"
			+ " LEFT JOIN guild_membership gm ON gm.player_id = pa.player_id"
			+ " AND gm.guild_id = pa.guild_id"
			+ " WHERE gm.player_id IS NULL;"
		)
	)
	var count := int(db.query_result[0]["n"])
	var todo := ""
	if count == 0:
		todo = "no applicant pipeline yet — scouting, channels and trials land in M8."
	return {"count": count, "todo": todo}


static func _objectives(db: Variant, week_id: int) -> Dictionary:
	db.query_with_bindings("SELECT season_id FROM week WHERE week_id = ?;", [week_id])
	if db.query_result.is_empty():
		return {"items": [], "todo": "week has no season — cannot resolve objectives."}
	var season_id := int(db.query_result[0]["season_id"])
	db.query_with_bindings(
		(
			"SELECT ot.display_name, so.target, so.result FROM season_objective so"
			+ " JOIN objective_type ot ON ot.objective_type_id = so.objective_type_id"
			+ " WHERE so.season_id = ? ORDER BY so.priority, so.objective_id;"
		),
		[season_id]
	)
	var items: Array[Dictionary] = []
	for row in db.query_result.duplicate():
		(
			items
			. append(
				{
					"display_name": str(row["display_name"]),
					"target": str(row["target"]),
					"result": "" if row["result"] == null else str(row["result"]),
				}
			)
		)
	var todo := ""
	if items.is_empty():
		todo = "objectives are issued at season start and graded at season end — M9."
	return {"items": items, "todo": todo}


static func _handles_of(rows: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in rows:
		out.append(str(row["handle"]))
	return out
