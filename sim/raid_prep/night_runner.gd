class_name NightRunner
extends RefCounted

## Raid-night orchestrator (M4-003). Pure: turns a locked prep_result + campaign
## into pull-by-pull resolves via PullInputLoader + PullResolver. The combat-log
## UI only renders; this owns attempt counters, boss order, and persistence.

const MAX_ATTEMPTS_PER_BOSS := 8


## Encounter slugs for tonight's raid, in boss_order.
static func encounter_slugs(db: Variant, event_id: int) -> Array[String]:
	db.query_with_bindings(
		(
			"SELECT e.slug FROM calendar_event ce"
			+ " JOIN encounter e ON e.raid_id = ce.raid_id"
			+ " WHERE ce.event_id = ? ORDER BY e.boss_order, e.encounter_id;"
		),
		[event_id]
	)
	var slugs: Array[String] = []
	for row in db.query_result:
		slugs.append(str(row["slug"]))
	return slugs


## Display name for an encounter slug (empty if unknown).
static func encounter_name(db: Variant, encounter_slug: String) -> String:
	db.query_with_bindings("SELECT display_name FROM encounter WHERE slug = ?;", [encounter_slug])
	if db.query_result.is_empty():
		return encounter_slug
	return str(db.query_result[0]["display_name"])


## Resolve one pull and persist it. Returns:
##   {ok, result, pull_id, encounter_id, encounter_slug, encounter_name, attempt_number}
## or {ok:false, error:String} on failure.
static func resolve_pull(
	db: Variant,
	seed_value: int,
	guild_id: int,
	event_id: int,
	prep: Dictionary,
	encounter_slug: String,
	attempt_number: int
) -> Dictionary:
	var lineup: Array[int] = []
	for avatar_id in prep["lineup_ids"]:
		lineup.append(int(avatar_id))
	var overrides := {
		"guild_id": guild_id,
		"attempt_number": attempt_number,
		"assignments": prep.get("assignments", {}),
		"consumable_tier": str(prep.get("consumable_tier", "basic")),
	}
	var input := PullInputLoader.build(db, encounter_slug, lineup, overrides)
	var errors := PullContracts.validate_input(input)
	if not errors.is_empty():
		return {"ok": false, "error": "invalid input: %s" % ", ".join(errors)}

	var stream_name := "pull/%s/%d" % [encounter_slug, attempt_number]
	var result := PullResolver.resolve(input, RngStream.derive(seed_value, stream_name))
	var result_errors := PullContracts.validate_result(result)
	if not result_errors.is_empty():
		return {"ok": false, "error": "invalid result: %s" % ", ".join(result_errors)}

	db.query_with_bindings("SELECT encounter_id FROM encounter WHERE slug = ?;", [encounter_slug])
	var encounter_id := int(db.query_result[0]["encounter_id"])
	var pull_id := PullResolver.persist(db, guild_id, event_id, encounter_id, result)
	if pull_id < 0:
		return {"ok": false, "error": "persist failed"}

	return {
		"ok": true,
		"result": result,
		"pull_id": pull_id,
		"encounter_id": encounter_id,
		"encounter_slug": encounter_slug,
		"encounter_name": encounter_name(db, encounter_slug),
		"attempt_number": attempt_number,
	}


## Headless full-night run for smoke/tests. Each boss: pull until kill or
## MAX_ATTEMPTS_PER_BOSS, then advance. Returns {pulls: [...], report: Dictionary}.
static func run_night(
	db: Variant, seed_value: int, guild_id: int, event_id: int, prep: Dictionary
) -> Dictionary:
	var pulls: Array[Dictionary] = []
	for encounter_slug in encounter_slugs(db, event_id):
		var attempt := 1
		while attempt <= MAX_ATTEMPTS_PER_BOSS:
			var step := resolve_pull(
				db, seed_value, guild_id, event_id, prep, encounter_slug, attempt
			)
			if not bool(step.get("ok", false)):
				return {"ok": false, "error": step.get("error", "unknown"), "pulls": pulls}
			pulls.append(step)
			if str(step["result"]["pull"]["outcome"]) == "kill":
				break
			attempt += 1
	return {
		"ok": true,
		"pulls": pulls,
		"report": NightReport.build(db, pulls, guild_id),
	}
