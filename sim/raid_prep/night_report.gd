class_name NightReport
extends RefCounted

## Post-night report read model (M4-004). Pure aggregator over NightRunner pull
## steps + seed loot rows. The report screen only renders this dictionary.


## Build from NightRunner pull steps (each has result / encounter_* / attempt).
static func build(db: Variant, pulls: Array, guild_id: int = 1) -> Dictionary:
	var bosses: Array[Dictionary] = []
	var by_boss := {}
	var rating_totals := {}  # avatar_id -> {handle, role, sum, count, deaths}
	var wipe_reasons := {}
	var kills := 0
	var wipes := 0
	var loot_rows: Array[Dictionary] = []

	for step in pulls:
		var result: Dictionary = step["result"]
		var pull: Dictionary = result["pull"]
		var outcome := str(pull["outcome"])
		var slug := str(step["encounter_slug"])
		if not by_boss.has(slug):
			by_boss[slug] = {
				"slug": slug,
				"name": str(step["encounter_name"]),
				"attempts": 0,
				"killed": false,
				"last_wipe_reason": "",
				# MI-005: the structured diagnosis of the most recent wipe, and the
				# tally that makes RECURRENCE sayable ("the same wall, 4 pulls running")
				"last_diagnosis": {},
				"cause_counts": {},
				"wipes": 0,
				"recurrence": "",
			}
			bosses.append(by_boss[slug])
		var boss: Dictionary = by_boss[slug]
		boss["attempts"] = int(boss["attempts"]) + 1
		if outcome == "kill":
			boss["killed"] = true
			kills += 1
			if bool(result.get("drops_loot", false)):
				loot_rows.append_array(_loot_for_encounter(db, slug))
		else:
			wipes += 1
			boss["wipes"] = int(boss["wipes"]) + 1
			var reason := str(pull.get("wipe_reason", ""))
			boss["last_wipe_reason"] = reason
			var diagnosis: Dictionary = pull.get("diagnosis", {})
			boss["last_diagnosis"] = diagnosis

			# Tally the PRIMARY CAUSE, never the raw `wipe_reason`: that string
			# carries margins and probabilities ("margin -18.6, p=0.07"), so it is
			# unique per pull and every count silently came out as 1. Recurrence —
			# the thing that tells a player they are stuck on ONE wall — could not
			# surface at all.
			var cause := (
				str(diagnosis.get("primary_cause", ""))
				if not diagnosis.is_empty()
				else reason.get_slice(":", 0)
			)
			if not cause.is_empty():
				wipe_reasons[cause] = int(wipe_reasons.get(cause, 0)) + 1
				var counts: Dictionary = boss["cause_counts"]
				counts[cause] = int(counts.get(cause, 0)) + 1

		for participant: Dictionary in result["participants"]:
			var avatar_id := int(participant["avatar_id"])
			if not rating_totals.has(avatar_id):
				rating_totals[avatar_id] = {
					"avatar_id": avatar_id,
					"role_slug": str(participant.get("role_assigned", "")),
					"rating_sum": 0.0,
					"pulls": 0,
					"deaths": 0,
				}
			var row: Dictionary = rating_totals[avatar_id]
			row["rating_sum"] = float(row["rating_sum"]) + float(participant["performance_rating"])
			row["pulls"] = int(row["pulls"]) + 1
			if bool(participant.get("died", false)):
				row["deaths"] = int(row["deaths"]) + 1

	var handles := _handles(db, rating_totals.keys())
	var ratings: Array[Dictionary] = []
	for avatar_id in rating_totals:
		var row: Dictionary = rating_totals[avatar_id]
		var pulls_n := maxi(1, int(row["pulls"]))
		(
			ratings
			. append(
				{
					"avatar_id": avatar_id,
					"handle": str(handles.get(avatar_id, "?")),
					"role_slug": row["role_slug"],
					"avg_rating": snappedf(float(row["rating_sum"]) / float(pulls_n), 0.1),
					"pulls": pulls_n,
					"deaths": int(row["deaths"]),
				}
			)
		)
	ratings.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["avg_rating"]) > float(b["avg_rating"])
	)

	var top_wipes: Array[Dictionary] = []
	for cause: String in wipe_reasons:
		(
			top_wipes
			. append(
				{
					"reason": cause,
					"label": str(Diagnosis.CAUSE_LABELS.get(cause, cause)),
					"count": int(wipe_reasons[cause]),
				}
			)
		)
	top_wipes.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["count"]) > int(b["count"])
	)

	for boss: Dictionary in bosses:
		boss["recurrence"] = _recurrence(boss)

	var mvp := {} if ratings.is_empty() else ratings[0]
	var progress := _learning_progress(db, pulls, guild_id)

	return {
		"bosses": bosses,
		"kills": kills,
		"wipes": wipes,
		"pull_count": pulls.size(),
		"ratings": ratings,
		"top_wipe_reasons": top_wipes,
		"loot": loot_rows,
		"mvp": mvp,
		"learning": progress,
		"summary_line": _summary_line(bosses, kills, wipes),
	}


## "Tank survival failed 4 of your 5 pulls here." The single most useful sentence
## on the page: it tells the player whether they are being unlucky or whether they
## are hitting the SAME wall over and over and have not changed anything.
static func _recurrence(boss: Dictionary) -> String:
	var counts: Dictionary = boss["cause_counts"]
	var wipes := int(boss["wipes"])
	if counts.is_empty() or wipes < 2:
		return ""
	var dominant := ""
	var best := 0
	for cause: String in counts:
		if int(counts[cause]) > best:
			dominant = cause
			best = int(counts[cause])
	if best < 2:
		return ""
	var label := str(Diagnosis.CAUSE_LABELS.get(dominant, dominant))
	return "%s ended %d of your %d wipes here — the same wall, not bad luck." % [label, best, wipes]


static func _handles(db: Variant, avatar_ids: Array) -> Dictionary:
	if avatar_ids.is_empty():
		return {}
	var placeholders: Array[String] = []
	var ids: Array = []
	for avatar_id in avatar_ids:
		placeholders.append("?")
		ids.append(int(avatar_id))
	db.query_with_bindings(
		(
			"SELECT a.avatar_id, p.handle FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " WHERE a.avatar_id IN (%s);" % ", ".join(placeholders)
		),
		ids
	)
	var out := {}
	for row in db.query_result:
		out[int(row["avatar_id"])] = str(row["handle"])
	return out


static func _loot_for_encounter(db: Variant, encounter_slug: String) -> Array[Dictionary]:
	db.query_with_bindings(
		(
			"SELECT li.slug, li.display_name, li.item_level, s.slug AS slot_slug,"
			+ " li.spec_fit_tag, e.display_name AS encounter_name"
			+ " FROM loot_item li"
			+ " JOIN encounter e ON e.encounter_id = li.encounter_id"
			+ " JOIN slot s ON s.slot_id = li.slot_id"
			+ " WHERE e.slug = ? ORDER BY li.item_level DESC, li.slug;"
		),
		[encounter_slug]
	)
	var rows: Array[Dictionary] = []
	for row in db.query_result:
		rows.append(row.duplicate())
	return rows


static func _learning_progress(db: Variant, pulls: Array, guild_id: int) -> Array[Dictionary]:
	var seen := {}
	var out: Array[Dictionary] = []
	for step in pulls:
		var slug := str(step["encounter_slug"])
		if seen.has(slug):
			continue
		seen[slug] = true
		db.query_with_bindings(
			(
				"SELECT gep.progress, gep.attempt_count, e.display_name"
				+ " FROM guild_encounter_progress gep"
				+ " JOIN encounter e ON e.encounter_id = gep.encounter_id"
				+ " WHERE e.slug = ? AND gep.guild_id = ?;"
			),
			[slug, guild_id]
		)
		if db.query_result.is_empty():
			continue
		var row: Dictionary = db.query_result[0]
		(
			out
			. append(
				{
					"slug": slug,
					"name": str(row["display_name"]),
					"progress": int(row["progress"]),
					"attempt_count": int(row["attempt_count"]),
				}
			)
		)
	return out


static func _summary_line(bosses: Array, kills: int, wipes: int) -> String:
	var killed_names: Array[String] = []
	for boss: Dictionary in bosses:
		if bool(boss["killed"]):
			killed_names.append(str(boss["name"]))
	if killed_names.is_empty():
		return "Night ended with no kills (%d wipe%s)." % [wipes, "s" if wipes != 1 else ""]
	return (
		"Killed %d/%d bosses (%s) across %d wipe%s."
		% [
			kills,
			bosses.size(),
			", ".join(killed_names),
			wipes,
			"s" if wipes != 1 else "",
		]
	)
