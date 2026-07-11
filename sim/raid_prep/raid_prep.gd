class_name RaidPrep
extends RefCounted

## Raid-prep read model (M4-002). Pure: build(db, event_id, lineup_ids) ->
## the comp-check report the prep screen renders. The three axes from
## docs/guildmaster-raid-prep.md — ROLE coverage, UTILITY coverage, RANGE
## balance — plus gear readiness, all derived from seed rows (spec_utility,
## the night's encounter_event placements). No UI, no sim math; the screen
## renders this and the resolver consumes the `assignments` it produces.

const LINEUP_SIZE := 20
## A 20-lineup wants at least this many of each; below = a warning.
const ROLE_MINIMA := {"tank": 2, "healer": 5}
const DPS_MIN := 12
## Key utilities and the warning shown when the LINEUP brings none.
const KEY_UTILITIES := {
	"rekindle": "No battle-rez tonight (Rekindle) — a death is a lost body",
	"countercast": "No interrupt (Countercast) — enemy casts go unchecked",
	"stormsurge": "No haste burst (Stormsurge) — bring a Channeler",
}

## Combat log outcome/effect categories that count as "harmful" for range profiling.
const _HARMFUL_CATEGORIES := ["death", "duty_check", "tank_check"]


## The full prep report. `lineup_ids` empty -> auto-fill the best-geared 20.
static func build(db: Variant, event_id: int, lineup_ids: Array[int] = []) -> Dictionary:
	var lineup := lineup_ids if not lineup_ids.is_empty() else PullInputLoader.auto_lineup(db)
	var lineup_set := {}
	for avatar_id in lineup:
		lineup_set[int(avatar_id)] = true

	var roster := _roster(db)
	var lineup_rows: Array[Dictionary] = []
	var bench_rows: Array[Dictionary] = []
	for row: Dictionary in roster:
		if lineup_set.has(int(row["avatar_id"])):
			lineup_rows.append(row)
		else:
			bench_rows.append(row)

	var coverage := {"tank": 0, "healer": 0, "melee": 0, "ranged": 0}
	for row: Dictionary in lineup_rows:
		coverage[str(row["role_slug"])] += 1

	var utilities := _lineup_utilities(db, lineup)
	var range_profile := _range_profile(db, event_id, coverage)
	var assignments := _default_assignments(db, lineup_rows)

	return {
		"lineup": lineup_rows,
		"bench": bench_rows,
		"lineup_ids": lineup,
		"coverage": coverage,
		"utilities": utilities,
		"range": range_profile,
		"assignments": assignments["by_avatar"],
		"assignment_summary": assignments["summary"],
		"warnings": _warnings(lineup_rows, coverage, utilities, range_profile),
		"ready": lineup.size() == LINEUP_SIZE,
	}


## Move an avatar between lineup and bench; returns the new lineup_ids (or the
## same list if the move is illegal — full lineup / already benched).
static func toggle(lineup_ids: Array[int], avatar_id: int) -> Array[int]:
	var result: Array[int] = lineup_ids.duplicate()
	if avatar_id in result:
		result.erase(avatar_id)
	elif result.size() < LINEUP_SIZE:
		result.append(avatar_id)
	return result


# --- axes ---------------------------------------------------------------------


static func _roster(db: Variant) -> Array:
	db.query(
		(
			"SELECT a.avatar_id, p.handle, r.slug AS role_slug, s.display_name AS spec_name,"
			+ " a.gear_score, a.item_level, a.familiarity, a.hit_capped, a.uncrittable"
			+ " FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE a.is_active = 1"
			+ " ORDER BY r.role_id, a.gear_score DESC, p.handle;"
		)
	)
	return db.query_result.duplicate()


## {utility_slug: {display_name, providers: [handle]}} the LINEUP brings.
static func _lineup_utilities(db: Variant, lineup: Array) -> Dictionary:
	if lineup.is_empty():
		return {}
	var placeholders: Array[String] = []
	var ids: Array = []
	for avatar_id in lineup:
		placeholders.append("?")
		ids.append(avatar_id)
	db.query_with_bindings(
		(
			"SELECT u.slug, u.display_name, p.handle"
			+ " FROM avatar a"
			+ " JOIN spec_utility su ON su.spec_id = a.spec_id"
			+ " JOIN raid_utility u ON u.utility_id = su.utility_id"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " WHERE a.avatar_id IN (%s) ORDER BY u.slug, p.handle;" % ", ".join(placeholders)
		),
		ids
	)
	var utilities := {}
	for row in db.query_result:
		var slug := str(row["slug"])
		if not utilities.has(slug):
			utilities[slug] = {"display_name": str(row["display_name"]), "providers": []}
		utilities[slug]["providers"].append(str(row["handle"]))
	return utilities


## The night's range PROFILE from the raid's harmful event placements
## (COALESCE selector — ADR-0010), vs the lineup's melee/ranged split.
static func _range_profile(db: Variant, event_id: int, coverage: Dictionary) -> Dictionary:
	(
		db
		. query_with_bindings(
			(
				"SELECT COALESCE(ee.target_selector, et.target_selector) AS sel, COUNT(*) AS n"
				+ " FROM calendar_event ce"
				+ " JOIN encounter e ON e.raid_id = ce.raid_id"
				+ " JOIN encounter_event ee ON ee.encounter_id = e.encounter_id"
				+ " JOIN event_type et ON et.event_type_id = ee.event_type_id"
				+ " WHERE ce.event_id = ? AND et.effect_category IN ('death', 'duty_check', 'tank_check')"
				+ " GROUP BY sel;"
			),
			[event_id]
		)
	)
	var melee_pressure := 0
	var ranged_pressure := 0
	for row in db.query_result:
		match str(row["sel"]):
			"melee":
				melee_pressure = int(row["n"])
			"ranged":
				ranged_pressure = int(row["n"])
	return {
		"lineup_melee": int(coverage["melee"]),
		"lineup_ranged": int(coverage["ranged"]),
		"night_melee_pressure": melee_pressure,
		"night_ranged_pressure": ranged_pressure,
	}


# --- warnings -----------------------------------------------------------------


static func _warnings(
	lineup: Array, coverage: Dictionary, utilities: Dictionary, range_profile: Dictionary
) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []

	if lineup.size() != LINEUP_SIZE:
		warnings.append(_warn("warn", "Lineup has %d of %d raiders" % [lineup.size(), LINEUP_SIZE]))
	for role_slug in ROLE_MINIMA:
		var have := int(coverage.get(role_slug, 0))
		var want := int(ROLE_MINIMA[role_slug])
		if have < want:
			warnings.append(_warn("warn", "Only %d %ss (%d recommended)" % [have, role_slug, want]))
	var dps := int(coverage["melee"]) + int(coverage["ranged"])
	if dps < DPS_MIN:
		warnings.append(_warn("warn", "Only %d DPS (%d recommended)" % [dps, DPS_MIN]))

	for utility_slug: String in KEY_UTILITIES:
		if not utilities.has(utility_slug):
			warnings.append(_warn("warn", str(KEY_UTILITIES[utility_slug])))

	# range balance: a melee-heavy lineup into a melee-punishing night (or v/v)
	var melee := int(range_profile["lineup_melee"])
	var ranged := int(range_profile["lineup_ranged"])
	if (
		int(range_profile["night_melee_pressure"]) > int(range_profile["night_ranged_pressure"])
		and melee > ranged
	):
		warnings.append(
			_warn("warn", "%d melee into a melee-punishing night — consider more ranged" % melee)
		)
	elif (
		int(range_profile["night_ranged_pressure"]) > int(range_profile["night_melee_pressure"])
		and ranged > melee
	):
		warnings.append(
			_warn("warn", "%d ranged into a ranged-punishing night — consider more melee" % ranged)
		)

	# gear readiness: the main tank must be crit-immune (the gear gate)
	var main_tank := _highest_geared(lineup, "tank")
	if not main_tank.is_empty() and int(main_tank["uncrittable"]) == 0:
		warnings.append(
			_warn(
				"warn", "Main tank %s is not uncrittable — spike-death risk" % main_tank["handle"]
			)
		)

	if warnings.is_empty():
		warnings.append(_warn("ok", "Comp looks solid — lineup is raid-ready"))
	return warnings


static func _warn(severity: String, text: String) -> Dictionary:
	return {"severity": severity, "text": text}


# --- assignments --------------------------------------------------------------


## Auto-assignments feeding the resolver: main/off tank, interrupt rotation
## (Countercast providers), cooldown caller (Stormsurge). Returns
## {by_avatar: {avatar_id: [{assignment_type, target}]}, summary: [String]}.
static func _default_assignments(db: Variant, lineup: Array) -> Dictionary:
	var by_avatar := {}
	var summary: Array[String] = []

	var tanks := _by_role(lineup, "tank")
	if not tanks.is_empty():
		_add_assignment(by_avatar, int(tanks[0]["avatar_id"]), "tank", "main")
		summary.append("Main tank: %s" % tanks[0]["handle"])
	if tanks.size() > 1:
		_add_assignment(by_avatar, int(tanks[1]["avatar_id"]), "tank", "off")
		summary.append("Off tank: %s" % tanks[1]["handle"])

	var interrupters := _providers(db, lineup, "countercast")
	var interrupt_names: Array[String] = []
	for row: Dictionary in interrupters.slice(0, 3):
		_add_assignment(by_avatar, int(row["avatar_id"]), "interrupt", "adds")
		interrupt_names.append(str(row["handle"]))
	if not interrupt_names.is_empty():
		summary.append("Interrupts: %s" % ", ".join(interrupt_names))

	var surge := _providers(db, lineup, "stormsurge")
	if not surge.is_empty():
		_add_assignment(by_avatar, int(surge[0]["avatar_id"]), "cooldown", "lust")
		summary.append("Cooldown/lust: %s" % surge[0]["handle"])

	return {"by_avatar": by_avatar, "summary": summary}


static func _add_assignment(
	by_avatar: Dictionary, avatar_id: int, assignment_type: String, target: String
) -> void:
	if not by_avatar.has(avatar_id):
		by_avatar[avatar_id] = []
	by_avatar[avatar_id].append({"assignment_type": assignment_type, "target": target})


## Lineup rows that provide `utility_slug`, gear-desc (best first).
static func _providers(db: Variant, lineup: Array, utility_slug: String) -> Array:
	if lineup.is_empty():
		return []
	var placeholders: Array[String] = []
	var ids: Array = []
	for row: Dictionary in lineup:
		placeholders.append("?")
		ids.append(int(row["avatar_id"]))
	ids.append(utility_slug)
	db.query_with_bindings(
		(
			"SELECT a.avatar_id, p.handle FROM avatar a"
			+ " JOIN spec_utility su ON su.spec_id = a.spec_id"
			+ " JOIN raid_utility u ON u.utility_id = su.utility_id"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " WHERE a.avatar_id IN (%s) AND u.slug = ?" % ", ".join(placeholders)
			+ " ORDER BY a.gear_score DESC;"
		),
		ids
	)
	return db.query_result.duplicate()


static func _by_role(lineup: Array, role_slug: String) -> Array:
	var out: Array = []
	for row: Dictionary in lineup:
		if str(row["role_slug"]) == role_slug:
			out.append(row)
	return out


static func _highest_geared(lineup: Array, role_slug: String) -> Dictionary:
	var best := {}
	for row: Dictionary in lineup:
		if str(row["role_slug"]) != role_slug:
			continue
		if best.is_empty() or int(row["gear_score"]) > int(best["gear_score"]):
			best = row
	return best
