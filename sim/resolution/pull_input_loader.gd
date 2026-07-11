class_name PullInputLoader
extends RefCounted

## Builds contract-valid PullInputs from REAL campaign rows (M3-005; M4 reuses
## this — the UI must not re-invent roster/encounter interpretation).
##
##   var lineup := PullInputLoader.auto_lineup(db)            # 20 avatar_ids
##   var input := PullInputLoader.build(db, "gatewarden_krogg", lineup)
##   var result := PullResolver.resolve(input, rng)
##
## Reads: encounter + phases + placements (selector = COALESCE(placement,
## event_type) — the ADR-0010 override), participants (avatar x player x spec
## x role x proficiency), guild_encounter_progress, and tuning.json. Volatile
## state (morale/fatigue/form) defaults to neutral until M5 owns
## player_week_state snapshots.

const NEUTRAL_STATE := {"morale": 55, "fatigue": 20, "form": 50}


## A harness-grade 20-lineup: best-geared 2 tanks / 5 healers / 13 dps.
## (M4's raid-prep screen owns the real, player-driven lineup.)
static func auto_lineup(db: Variant) -> Array[int]:
	var picked: Array[int] = []
	for role_count: Array in [["tank", 2], ["healer", 5], ["melee", 6], ["ranged", 7]]:
		db.query_with_bindings(
			(
				"SELECT a.avatar_id FROM avatar a"
				+ " JOIN spec s ON s.spec_id = a.spec_id"
				+ " JOIN role r ON r.role_id = s.role_id"
				+ " WHERE r.slug = ? AND a.is_active = 1"
				+ " ORDER BY a.gear_score DESC, a.avatar_id LIMIT ?;"
			),
			[role_count[0], role_count[1]]
		)
		for row in db.query_result:
			picked.append(int(row["avatar_id"]))
	return picked


## Contract-valid PullInput for `encounter_slug` with the given lineup.
## `overrides`: {guild_id (progress lookup, default 1), attempt_number,
## consumable_tier ("basic"/"premium"/"" for none), gear_multiplier}.
static func build(
	db: Variant, encounter_slug: String, lineup: Array[int], overrides: Dictionary = {}
) -> Dictionary:
	var input := PullContracts.make_input()
	db.query_with_bindings(
		(
			"SELECT encounter_id, slug, display_name, dps_check, healing_check, difficulty,"
			+ " phase_count FROM encounter WHERE slug = ?;"
		),
		[encounter_slug]
	)
	assert(not db.query_result.is_empty(), "unknown encounter '%s'" % encounter_slug)
	var encounter: Dictionary = db.query_result[0]
	var encounter_id := int(encounter["encounter_id"])
	input["encounter"] = {
		"slug": str(encounter["slug"]),
		# the timeline's closing beat names the boss out loud (MI-004)
		"display_name": str(encounter["display_name"]),
		"dps_check": int(encounter["dps_check"]),
		"healing_check": int(encounter["healing_check"]),
		"difficulty": int(encounter["difficulty"]),
		"phase_count": int(encounter["phase_count"]),
	}

	db.query_with_bindings(
		(
			"SELECT slug, phase_order, entry_condition, display_name FROM encounter_phase"
			+ " WHERE encounter_id = ? ORDER BY phase_order;"
		),
		[encounter_id]
	)
	input["phases"] = db.query_result.duplicate()

	# the ADR-0010 range-profile rule: placement selector overrides the type's
	db.query_with_bindings(
		(
			"SELECT ee.slug, ep.phase_order, et.slug AS event_type_slug, et.trigger,"
			+ " COALESCE(ee.target_selector, et.target_selector) AS target_selector,"
			+ " et.roll_attribute, et.effect_category, et.log_template,"
			+ " ee.severity, ee.weight"
			+ " FROM encounter_event ee"
			+ " JOIN encounter_phase ep ON ep.phase_id = ee.phase_id"
			+ " JOIN event_type et ON et.event_type_id = ee.event_type_id"
			+ " WHERE ee.encounter_id = ? ORDER BY ep.phase_order, ee.slug;"
		),
		[encounter_id]
	)
	input["events"] = db.query_result.duplicate()

	input["participants"] = _participants(db, lineup, overrides)

	var guild_id := int(overrides.get("guild_id", 1))
	db.query_with_bindings(
		(
			"SELECT progress, attempt_count, best_attempt_pct FROM guild_encounter_progress"
			+ " WHERE guild_id = ? AND encounter_id = ?;"
		),
		[guild_id, encounter_id]
	)
	if not db.query_result.is_empty():
		input["encounter_progress"] = db.query_result[0].duplicate()
	input["attempt_number"] = int(overrides.get("attempt_number", 1))

	var tuning: Dictionary = Tuning.section("resolution").duplicate()
	tuning["consumables"] = Tuning.section("consumables")
	input["tuning"] = tuning
	return input


static func _participants(db: Variant, lineup: Array[int], overrides: Dictionary) -> Array:
	var gear_multiplier := float(overrides.get("gear_multiplier", 1.0))
	var consumable_tier := str(overrides.get("consumable_tier", "basic"))
	# raid-prep assignments (avatar_id -> [{assignment_type, target}]) from the
	# M4-002 screen. Absent -> the harness-grade auto main-tank default below.
	var assignments: Dictionary = overrides.get("assignments", {})
	# ONE query for the whole lineup (was 20 round-trips; review finding).
	# Rows are re-ordered to lineup order below — participant order drives
	# rng draw order, so it must stay exactly the caller's order.
	var placeholders: Array[String] = []
	var ids: Array = []
	for avatar_id in lineup:
		placeholders.append("?")
		ids.append(avatar_id)
	db.query_with_bindings(
		(
			"SELECT a.avatar_id, a.player_id, p.handle, r.slug AS role_slug,"
			+ " s.slug AS spec_slug, s.spec_difficulty, s.defense_cap_ilvl,"
			+ " a.gear_score, a.item_level,"
			+ " a.familiarity, a.hit_capped, a.uncrittable,"
			+ " p.execution, p.awareness, p.consistency,"
			+ " COALESCE(prp.proficiency, 50) AS role_proficiency"
			+ " FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " LEFT JOIN player_role_proficiency prp"
			+ " ON prp.player_id = a.player_id AND prp.role_id = r.role_id"
			+ " WHERE a.avatar_id IN (%s);" % ", ".join(placeholders)
		),
		ids
	)
	var by_id := {}
	for fetched in db.query_result:
		by_id[int(fetched["avatar_id"])] = fetched.duplicate()

	var participants := []
	var main_tank_assigned := false
	for avatar_id in lineup:
		assert(by_id.has(avatar_id), "unknown avatar_id %d" % avatar_id)
		var row: Dictionary = by_id[avatar_id]

		row["gear_score"] = roundi(float(row["gear_score"]) * gear_multiplier)
		row["item_level"] = roundi(float(row["item_level"]) * gear_multiplier)
		# caps DERIVE from gear (gear doc): recompute from the scaled ilvl via
		# THE shared rule — a heavily-geared tank must not keep its starter
		# not-uncrittable flag (M6-005 replaces the rule engine-wide later).
		# The threshold is the SPEC's own defense cap, so out-gearing the fight
		# still will not make a hide-armoured tank crit-immune (ADR-0025).
		var caps := AvatarGen.derive_caps(
			int(row["item_level"]), str(row["role_slug"]), int(row["defense_cap_ilvl"])
		)
		row["hit_capped"] = caps["hit_capped"]
		row["uncrittable"] = caps["uncrittable"]
		row["morale"] = NEUTRAL_STATE["morale"]
		row["fatigue"] = NEUTRAL_STATE["fatigue"]
		row["form"] = NEUTRAL_STATE["form"]
		row["consumables"] = (
			[]
			if consumable_tier.is_empty()
			else [{"slug": "harness_%s" % consumable_tier, "tier": consumable_tier}]
		)
		if not assignments.is_empty():
			row["assignments"] = assignments.get(int(avatar_id), [])
		elif str(row["role_slug"]) == "tank" and not main_tank_assigned:
			# no prep given: first tank in gear order becomes main tank
			row["assignments"] = [{"assignment_type": "tank", "target": "main"}]
			main_tank_assigned = true
		else:
			row["assignments"] = []
		participants.append(row)
	return participants
