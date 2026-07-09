class_name RosterReport
extends RefCounted

## Roster inspection read model (M2-004). Pure: build(db) -> structured report;
## to_text(report) renders it for terminals. The M4 lineup UI must consume
## build() rather than re-interpreting roster tables itself.

const LINEUP_MINIMA := {"tank": 2, "healer": 5}
const LINEUP_DPS_MIN := 13


## Structured roster summary: players (joined with avatar/class/spec/preset),
## role coverage, utility coverage, and human-readable issue flags.
static func build(db: Variant) -> Dictionary:
	db.query(
		(
			"SELECT p.player_id, p.handle, ls.slug AS life_preset, p.execution, p.awareness,"
			+ " p.consistency, p.potential, p.ego, p.loyalty_current, p.volatility,"
			+ " p.time_budget_hrs, p.attendance_reliability,"
			+ " c.display_name AS class_name, s.display_name AS spec_name, r.slug AS role_slug,"
			+ " a.item_level, a.gear_score, a.familiarity, a.hit_capped, a.uncrittable"
			+ " FROM player p"
			+ " JOIN avatar a ON a.player_id = p.player_id AND a.is_active = 1"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN class c ON c.class_id = a.class_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " LEFT JOIN life_situation ls ON ls.life_situation_id = p.life_situation_id"
			+ " ORDER BY r.role_id, a.gear_score DESC, p.handle;"
		)
	)
	var players: Array = db.query_result.duplicate()

	var coverage := {"tank": 0, "healer": 0, "melee": 0, "ranged": 0}
	for row in players:
		coverage[str(row["role_slug"])] += 1

	db.query(
		(
			"SELECT u.slug, COUNT(DISTINCT a.avatar_id) AS providers"
			+ " FROM raid_utility u"
			+ " LEFT JOIN spec_utility su ON su.utility_id = u.utility_id"
			+ " LEFT JOIN avatar a ON a.spec_id = su.spec_id AND a.is_active = 1"
			+ " GROUP BY u.slug ORDER BY u.slug;"
		)
	)
	var utilities := {}
	for row in db.query_result:
		utilities[str(row["slug"])] = int(row["providers"])

	return {
		"players": players,
		"coverage": coverage,
		"utilities": utilities,
		"issues": _issues(coverage, utilities),
	}


static func _issues(coverage: Dictionary, utilities: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	for role_slug in LINEUP_MINIMA:
		if int(coverage.get(role_slug, 0)) < int(LINEUP_MINIMA[role_slug]):
			issues.append(
				(
					"only %d %s(s) — a 20-lineup wants %d+"
					% [coverage.get(role_slug, 0), role_slug, LINEUP_MINIMA[role_slug]]
				)
			)
	var dps := int(coverage.get("melee", 0)) + int(coverage.get("ranged", 0))
	if dps < LINEUP_DPS_MIN:
		issues.append("only %d dps — a 20-lineup wants %d+" % [dps, LINEUP_DPS_MIN])
	for utility_slug in ["rekindle", "stormsurge", "countercast"]:
		if int(utilities.get(utility_slug, 0)) == 0:
			issues.append("no %s provider on the roster (comp gap)" % utility_slug)
	return issues


## Terminal rendering: fixed-width roster table + coverage + issues + fingerprint.
static func to_text(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append(
		(
			"%-14s %-15s %-11s %-7s %4s %4s %4s  %s"
			% ["HANDLE", "LIFE", "SPEC", "ROLE", "GS", "ILVL", "FAM", "EXE/AWA/CON POT EGO LOY"]
		)
	)
	lines.append("-".repeat(96))
	for p: Dictionary in report["players"]:
		var caps := ""
		if int(p["uncrittable"]) == 1:
			caps = " [UC]"
		elif int(p["hit_capped"]) == 1:
			caps = " [HC]"
		(
			lines
			. append(
				(
					"%-14s %-15s %-11s %-7s %4d %4d %4d  %3d/%3d/%3d %3d %3d %3d%s"
					% [
						str(p["handle"]),
						str(p["life_preset"]),
						str(p["spec_name"]),
						str(p["role_slug"]),
						int(p["gear_score"]),
						int(p["item_level"]),
						int(p["familiarity"]),
						int(p["execution"]),
						int(p["awareness"]),
						int(p["consistency"]),
						int(p["potential"]),
						int(p["ego"]),
						int(p["loyalty_current"]),
						caps,
					]
				)
			)
		)
	var coverage: Dictionary = report["coverage"]
	lines.append("-".repeat(96))
	(
		lines
		. append(
			(
				"coverage: %d tank / %d healer / %d melee / %d ranged (%d total)"
				% [
					coverage["tank"],
					coverage["healer"],
					coverage["melee"],
					coverage["ranged"],
					report["players"].size(),
				]
			)
		)
	)
	var utility_bits: PackedStringArray = []
	var utilities: Dictionary = report["utilities"]
	for slug in utilities:
		utility_bits.append("%s:%d" % [slug, utilities[slug]])
	lines.append("utilities: %s" % " ".join(utility_bits))
	var issues: Array = report["issues"]
	if issues.is_empty():
		lines.append("issues: none — 20-lineup viable")
	else:
		for issue in issues:
			lines.append("issue: %s" % issue)
	lines.append("roster fingerprint: %x" % RngStream.fingerprint("\n".join(lines)))
	return "\n".join(lines)
