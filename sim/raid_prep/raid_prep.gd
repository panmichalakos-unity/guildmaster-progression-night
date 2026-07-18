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

## MI-008 — every warning states the CONSEQUENCE, then the ACTION, then the MMO
## term in parentheses. A player who has never raided must be able to act on these
## without a glossary; a veteran must still see the word they expect. The `term`
## is the glossary key the UI hangs a tooltip on (progressive disclosure).
## See docs/guildmaster-terminology.md.
const KEY_UTILITIES := {
	"rekindle":
	{
		"text":
		(
			"Nobody can revive a fallen raider mid-fight — every death is permanent for the"
			+ " rest of the pull, and each lost body costs the raid damage and healing."
			+ " Field a Rekindle caster (battle-rez)."
		),
		"term": "battle-rez",
	},
	"countercast":
	{
		"text":
		(
			"Nobody can cut off the boss's spellcasting — its worst spells will land on the"
			+ " raid unchecked. Field a Countercast caster (interrupt)."
		),
		"term": "interrupt",
	},
	"stormsurge":
	{
		"text":
		(
			"Nobody can push the raid's damage for a burst window — you lose your best shot"
			+ " at beating the boss's time limit. Field a Channeler (Stormsurge, a haste burst)."
		),
		"term": "haste burst",
	},
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
		var short := LINEUP_SIZE - lineup.size()
		if short > 0:
			(
				warnings
				. append(
					_warn(
						"warn",
						(
							(
								"You are taking %d raiders into a %d-raider fight — %d empty seat%s is"
								+ " output you simply do not have. Field %d more."
							)
							% [
								lineup.size(),
								LINEUP_SIZE,
								short,
								"" if short == 1 else "s",
								short,
							]
						)
					)
				)
			)

	for role_slug in ROLE_MINIMA:
		var have := int(coverage.get(role_slug, 0))
		var want := int(ROLE_MINIMA[role_slug])
		if have < want:
			warnings.append(_warn("warn", _role_shortfall(role_slug, have, want)))

	var dps := int(coverage["melee"]) + int(coverage["ranged"])
	if dps < DPS_MIN:
		warnings.append(
			_warn(
				"warn",
				(
					(
						"Only %d raiders are dealing damage — the boss will outlast you and its"
						+ " damage will become unsurvivable before it dies. Field at least %d"
						+ " (damage dealers, or DPS)."
					)
					% [dps, DPS_MIN]
				),
				"enrage"
			)
		)

	for utility_slug: String in KEY_UTILITIES:
		if not utilities.has(utility_slug):
			var utility: Dictionary = KEY_UTILITIES[utility_slug]
			warnings.append(_warn("warn", str(utility["text"]), str(utility["term"])))

	# range balance: a melee-heavy lineup into a melee-punishing night (or v/v)
	var melee := int(range_profile["lineup_melee"])
	var ranged := int(range_profile["lineup_ranged"])
	if (
		int(range_profile["night_melee_pressure"]) > int(range_profile["night_ranged_pressure"])
		and melee > ranged
	):
		warnings.append(
			_warn(
				"warn",
				(
					(
						"%d of your raiders fight from close range, and tonight's boss aims its"
						+ " worst attacks exactly there — they will be caught by mechanics they"
						+ " cannot avoid. Swap some for raiders who fight at a distance (melee"
						+ " vs ranged)."
					)
					% melee
				),
				"melee"
			)
		)
	elif (
		int(range_profile["night_ranged_pressure"]) > int(range_profile["night_melee_pressure"])
		and ranged > melee
	):
		warnings.append(
			_warn(
				"warn",
				(
					(
						"%d of your raiders fight at a distance, and tonight's boss punishes the"
						+ " back line — they will take damage they cannot avoid. Swap some for"
						+ " close-range raiders (melee vs ranged)."
					)
					% ranged
				),
				"ranged"
			)
		)

	# THE warning the first session hangs on (MI-003). It has to name the
	# consequence, name the fix, and say the quiet part out loud: field the tank
	# who looks WORSE on paper. See docs/guildmaster-terminology.md.
	var main_tank := _highest_geared(lineup, "tank")
	if not main_tank.is_empty() and int(main_tank["uncrittable"]) == 0:
		warnings.append(
			_warn(
				"warn",
				(
					(
						"Your main tank %s can be hit by a critical strike — one unlucky spike will"
						+ " kill him outright and end the pull, and no amount of healing prevents"
						+ " it. Field a tank who cannot be critically hit, even if their gear score"
						+ " is lower (uncrittable)."
					)
					% main_tank["handle"]
				),
				"uncrittable"
			)
		)

	if warnings.is_empty():
		warnings.append(
			_warn("ok", "Lineup looks raid-ready — roles, utilities and range are all covered.")
		)
	return warnings


## Role shortfalls in the language of what the role DOES, not what it is called.
static func _role_shortfall(role_slug: String, have: int, want: int) -> String:
	match role_slug:
		"tank":
			return (
				(
					"Only %d raider%s can hold the boss's attention — if one goes down there is"
					+ " nobody to take over and the raid folds. Field at least %d tanks."
				)
				% [have, "" if have == 1 else "s", want]
			)
		"healer":
			return (
				(
					"Only %d healers — they cannot keep up with the damage this fight puts out,"
					+ " and raiders will start dying with nothing coming. Field at least %d."
				)
				% [have, want]
			)
		_:
			return "Only %d %ss (%d recommended)." % [have, role_slug, want]


## `term` is the glossary key (data/seeds/glossary.json) the UI hangs a tooltip
## on. It is enrichment, never a requirement — the text must already be actionable
## on its own (MI-008).
static func _warn(severity: String, text: String, term: String = "") -> Dictionary:
	return {"severity": severity, "text": text, "term": term}


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


## Persist the night's lineup at event grain (M5-005). One row per active avatar of
## the player guild's current roster: fielded (is_benched=0, with the slot they
## fill) or benched (is_benched=1). Bench streaks — "Kessa has sat out three
## straight nights" — are DERIVED from this history (raid-prep doc: no new state),
## so a night that never persists its lineup never counts toward anyone's streak.
## Replaces any prior plan for the event; stamped with decided_by (ADR-0033).
static func persist_lineup(
	db: Variant, event_id: int, lineup_ids: Array[int], decided_by: String = "player"
) -> bool:
	if lineup_ids.is_empty():
		push_error("RaidPrep: refusing to persist an empty lineup for event %d" % event_id)
		return false
	# a played night's record is history, not a plan — never rewrite it (a re-plan
	# flow reusing the event id would silently hand fielded raiders bench streaks).
	# in_progress stays writable: the loop flips status before the night resolves.
	db.query_with_bindings("SELECT status FROM calendar_event WHERE event_id = ?;", [event_id])
	if (
		db.query_result.is_empty()
		or str(db.query_result[0]["status"]) in ["completed", "cancelled"]
	):
		push_error("RaidPrep: event %d is not writable — lineup refused" % event_id)
		return false
	var marks: Array[String] = []
	var ids: Array = []
	for avatar_id in lineup_ids:
		marks.append("?")
		ids.append(int(avatar_id))
	var in_list := ", ".join(marks)

	# the fielded side guards the same invariants the bench side does: every id must
	# be an active avatar of a current member whose availability (if rolled) says
	# they can come. One buggy caller must not distort the participation record.
	db.query_with_bindings(
		(
			"SELECT COUNT(*) AS n FROM avatar a"
			+ " JOIN guild_membership gm ON gm.player_id = a.player_id"
			+ " JOIN guild g ON g.guild_id = gm.guild_id AND g.is_player_guild = 1"
			+ " WHERE a.is_active = 1 AND gm.status IN ('member', 'trial')"
			+ " AND a.avatar_id IN (%s)" % in_list
			+ " AND NOT EXISTS (SELECT 1 FROM event_availability ea"
			+ " WHERE ea.event_id = ? AND ea.player_id = a.player_id"
			+ " AND ea.available = 0);"
		),
		ids + [event_id]
	)
	if int(db.query_result[0]["n"]) != lineup_ids.size():
		push_error(
			"RaidPrep: lineup for event %d includes raiders who are not fieldable" % event_id
		)
		return false

	db.query("BEGIN TRANSACTION;")
	if not db.query_with_bindings("DELETE FROM raid_lineup WHERE event_id = ?;", [event_id]):
		db.query("ROLLBACK;")
		return false
	var fielded_ok: bool = db.query_with_bindings(
		(
			"INSERT INTO raid_lineup (event_id, avatar_id, slot_role, is_benched, decided_by)"
			+ " SELECT ?, a.avatar_id, r.slug, 0, ? FROM avatar a"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE a.avatar_id IN (%s);" % in_list
		),
		[event_id, decided_by] + ids
	)
	# the rest of the current roster sat this one out — that IS the bench record.
	# But benched means COULD have played and wasn't fielded: a raider whose
	# availability roll said "can't make it" gets no row at all (attendance vs
	# participation — modeling conventions). No roll for the event = everyone counts.
	var benched_ok: bool = db.query_with_bindings(
		(
			"INSERT INTO raid_lineup (event_id, avatar_id, slot_role, is_benched, decided_by)"
			+ " SELECT ?, a.avatar_id, r.slug, 1, ? FROM avatar a"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " JOIN guild_membership gm ON gm.player_id = a.player_id"
			+ " JOIN guild g ON g.guild_id = gm.guild_id AND g.is_player_guild = 1"
			+ " WHERE a.is_active = 1 AND gm.status IN ('member', 'trial')"
			+ " AND a.avatar_id NOT IN (%s)" % in_list
			+ " AND NOT EXISTS (SELECT 1 FROM event_availability ea"
			+ " WHERE ea.event_id = ? AND ea.player_id = a.player_id"
			+ " AND ea.available = 0);"
		),
		[event_id, decided_by] + ids + [event_id]
	)
	if not fielded_ok or not benched_ok:
		push_error("RaidPrep: lineup persist failed: %s" % db.error_message)
		db.query("ROLLBACK;")
		return false
	db.query("COMMIT;")
	return true
