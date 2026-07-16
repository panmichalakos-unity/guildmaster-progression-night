class_name PrepDecisions
extends RefCounted

## Planning-time raid decisions (M5-003) — the two "can't raid tonight" walls turned
## into choices (raid-prep doc §"Undermanned" / §"Undergeared").
##
##   UNDERMANNED (too few available, or a role missing):
##     run_short — proceed with fewer bodies (weaker checks), or
##     cancel    — stall progression, the cost of a thin week.
##
##   UNDERGEARED (too weak for the planned bosses) — a per-boss readiness preview
##   grades raid gear vs each boss's expected gear (the MI-009 contract):
##     downshift — attempt only the boss subset you can gear (farm the front), or
##     convert   — scrap the raid for a dungeon (a Gearing event; the week isn't wasted).
##
## Decisions mutate the CALENDAR_EVENT / raid plan, never a parallel state.

## The x1.00 gear anchor: a fresh guild averages ilvl 18.9 (guildmaster-encounter-
## contracts.md §0). A lineup's gear "multiplier" is its avg equipped ilvl over this.
const PAR_ILVL := 18.9

## Grades, worst -> best, and the ratio (lineup gear ÷ boss expected gear) that earns each.
const GRADE_READY := "ready"
const GRADE_TIGHT := "tight"
const GRADE_UNDERGEARED := "undergeared"
const GRADE_HEAVILY := "heavily"
const GRADE_LABELS := {
	"ready": "✓ Ready",
	"tight": "~ Tight",
	"undergeared": "⚠ Undergeared",
	"heavily": "✗ Heavily undergeared",
}

const LINEUP_SIZE := 20
## Same minima the raid-prep comp check uses (RaidPrep.ROLE_MINIMA).
const ROLE_MINIMA := {"tank": 2, "healer": 5}

# --- undergeared: the readiness preview ---------------------------------------


## The gear multiplier of a lineup (avg equipped item level over the x1.00 anchor).
static func lineup_gear_mult(db: Variant, lineup_avatar_ids: Array) -> float:
	if lineup_avatar_ids.is_empty():
		return 0.0
	var placeholders := ", ".join(lineup_avatar_ids.map(func(_a): return "?"))
	db.query_with_bindings(
		"SELECT AVG(item_level) AS avg_ilvl FROM avatar WHERE avatar_id IN (%s);" % placeholders,
		lineup_avatar_ids
	)
	var avg_ilvl := float(db.query_result[0]["avg_ilvl"])
	return avg_ilvl / PAR_ILVL


## One boss's grade for a given lineup gear multiplier vs its expected gear.
static func grade_for(gear_mult: float, expected_gear: float) -> String:
	var ratio := gear_mult / maxf(0.001, expected_gear)
	if ratio >= 1.0:
		return GRADE_READY
	if ratio >= 0.9:
		return GRADE_TIGHT
	if ratio >= 0.75:
		return GRADE_UNDERGEARED
	return GRADE_HEAVILY


## Per-boss readiness for the season's raid vs this lineup. Returns rows of
## {boss_slug, boss_name, expected_gear, grade, label} in raid order.
static func readiness_preview(db: Variant, lineup_avatar_ids: Array, season_id: int) -> Array:
	var gear_mult := lineup_gear_mult(db, lineup_avatar_ids)
	db.query_with_bindings(
		(
			"SELECT e.slug, e.display_name, ec.expected_gear FROM encounter e"
			+ " JOIN raid r ON r.raid_id = e.raid_id"
			+ " JOIN encounter_contract ec ON ec.encounter_id = e.encounter_id"
			+ " WHERE r.season_id = ? ORDER BY e.boss_order;"
		),
		[season_id]
	)
	var preview: Array[Dictionary] = []
	for boss: Dictionary in db.query_result:
		var grade := grade_for(gear_mult, float(boss["expected_gear"]))
		(
			preview
			. append(
				{
					"boss_slug": str(boss["slug"]),
					"boss_name": str(boss["display_name"]),
					"expected_gear": float(boss["expected_gear"]),
					"grade": grade,
					"label": str(GRADE_LABELS[grade]),
				}
			)
		)
	return preview


## The boss subset worth attempting tonight — the ones this lineup can gear on
## (Ready or Tight). "Farm the front, gear for the back." Feeds a downshift.
static func gearable_subset(db: Variant, lineup_avatar_ids: Array, season_id: int) -> Array:
	var subset: Array[String] = []
	for boss: Dictionary in readiness_preview(db, lineup_avatar_ids, season_id):
		if str(boss["grade"]) in [GRADE_READY, GRADE_TIGHT]:
			subset.append(str(boss["boss_slug"]))
	return subset


# --- undermanned: the manning check -------------------------------------------


## Whether the available pool can field a legal raid. Returns
## {available, minimum, short: bool, roles_missing: [String]}.
static func manning(db: Variant, event_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM event_availability WHERE event_id = ? AND available = 1;",
		[event_id]
	)
	var available := int(db.query_result[0]["n"])

	# role coverage among the AVAILABLE pool (each player's active avatar's role)
	db.query_with_bindings(
		(
			"SELECT r.slug AS role_slug, COUNT(*) AS n FROM event_availability ea"
			+ " JOIN avatar a ON a.player_id = ea.player_id AND a.is_active = 1"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE ea.event_id = ? AND ea.available = 1 GROUP BY r.slug;"
		),
		[event_id]
	)
	var by_role := {}
	for row: Dictionary in db.query_result:
		by_role[str(row["role_slug"])] = int(row["n"])

	var roles_missing: Array[String] = []
	for role_slug: String in ROLE_MINIMA:
		if int(by_role.get(role_slug, 0)) < int(ROLE_MINIMA[role_slug]):
			roles_missing.append(role_slug)

	return {
		"available": available,
		"minimum": LINEUP_SIZE,
		"short": available < LINEUP_SIZE or not roles_missing.is_empty(),
		"roles_missing": roles_missing,
	}


# --- the four decisions -------------------------------------------------------


## Proceed undermanned. No structural change — the lineup simply fields fewer than 20,
## which the resolver handles as weaker lanes. Returns true (the choice is always valid).
static func run_short(_db: Variant, _event_id: int) -> bool:
	return true


## Stall the night — progression cost of a thin week.
static func cancel(db: Variant, event_id: int) -> bool:
	if not _is_scheduled(db, event_id):
		return false
	return db.query_with_bindings(
		"UPDATE calendar_event SET status = 'cancelled' WHERE event_id = ?;", [event_id]
	)


## Scrap the raid, turn the slot into a dungeon (Gearing) run. A CALENDAR_EVENT type
## change — the raid link and any downshift subset are cleared.
static func convert_to_dungeon(db: Variant, event_id: int) -> bool:
	if not _is_scheduled(db, event_id):
		return false
	return db.query_with_bindings(
		(
			"UPDATE calendar_event SET event_type = 'dungeon', raid_id = NULL,"
			+ " target_boss_subset = NULL WHERE event_id = ?;"
		),
		[event_id]
	)


## Attempt only `boss_slugs` tonight (farm the front, gear for the back). Records the
## subset on the event; the raid stays a raid. Empty list clears back to the full raid.
static func downshift(db: Variant, event_id: int, boss_slugs: Array) -> bool:
	if not _is_scheduled(db, event_id):
		return false
	var subset: Variant = ",".join(boss_slugs) if not boss_slugs.is_empty() else null
	return db.query_with_bindings(
		"UPDATE calendar_event SET target_boss_subset = ? WHERE event_id = ?;", [subset, event_id]
	)


## These are PLAN-time decisions (raid-prep doc): only a still-`scheduled` event may be
## cancelled / converted / downshifted. Refuse loudly on an in-progress or completed
## night rather than silently rewriting a raid the player already played.
static func _is_scheduled(db: Variant, event_id: int) -> bool:
	db.query_with_bindings("SELECT status FROM calendar_event WHERE event_id = ?;", [event_id])
	return not db.query_result.is_empty() and str(db.query_result[0]["status"]) == "scheduled"
