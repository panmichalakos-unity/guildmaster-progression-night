class_name PullFixtures
extends RefCounted

## Shared resolver fixtures (M3-001) — stub-level PullInput shapes that every
## M3 task tests against. Pure/synthetic (no DB): 20-raider lineups built
## programmatically, encounter numbers arranged to force each scenario.
## All fixtures validate clean against PullContracts.validate_input().
##
##   clean_kill()       overgeared roster, low demands -> decisive kill zone
##   mechanic_failure() sloppy awareness vs high-severity avoidable events
##   dps_pressure()     enrage-tight: dps_check far above what gear delivers
##   healing_pressure() healing wall: sustain demand above the healer lane
##   tank_pressure()    gear-gate: main tank NOT uncrittable vs tank checks

const STANDARD_LINEUP := {"tank": 2, "healer": 5, "melee": 6, "ranged": 7}  # = 20

## event_type_slug -> effect_category, mirroring data/seeds/event_type.csv so
## fixtures drive the timeline exactly as the real seed rows would.
const _CATEGORY := {
	"avoidable_death": "death",
	"cascade_death": "death",
	"clutch_save": "save",
	"near_death": "tension",
	"cooldown_moment": "surge",
	"assigned_duty": "duty_check",
	"tank_swap": "tank_check",
}

## event_type_slug -> roll_attribute, also mirroring event_type.csv.
const _ROLL_ATTR := {
	"avoidable_death": "awareness",
	"cascade_death": "",
	"clutch_save": "consistency",
	"near_death": "consistency",
	"cooldown_moment": "execution",
	"assigned_duty": "execution",
	"tank_swap": "awareness",
}


static func clean_kill() -> Dictionary:
	# numbers chosen so margins sit ~+35..40: the SATURATED zone where the
	# hard sigmoid reads >=0.95 — "over-geared -> one-shot" per the doc
	var input := _base_input("training_krogg", 20, 20, 20)
	input["participants"] = _lineup({"gear_score": 260, "execution": 75, "awareness": 70})
	input["events"] = [
		_event("ck_p1_avoidable", 1, "avoidable_death", "random", 25, 80),
		_event("ck_p1_clutch", 1, "clutch_save", "random", 30, 60),
	]
	return input


static func mechanic_failure() -> Dictionary:
	var input := _base_input("sloppy_morvane", 40, 45, 55)
	input["participants"] = _lineup({"gear_score": 150, "execution": 55, "awareness": 25})
	input["events"] = [
		_event("mf_p1_fire", 1, "avoidable_death", "random", 70, 140),
		_event("mf_p1_fire_ranged", 1, "avoidable_death", "ranged", 65, 120),
		_event("mf_p2_fire", 2, "avoidable_death", "melee", 75, 140),
	]
	_add_phase(input, 2, "boss_hp<=50")
	return input


static func dps_pressure() -> Dictionary:
	var input := _base_input("enrage_ignarok", 85, 45, 60)
	input["participants"] = _lineup({"gear_score": 130, "execution": 50})
	input["events"] = [
		_event("dp_p1_cooldown", 1, "cooldown_moment", "assigned", 50, 100),
		_event("dp_p1_avoidable", 1, "avoidable_death", "random", 45, 90),
	]
	return input


static func healing_pressure() -> Dictionary:
	var input := _base_input("slagbeast_wall", 45, 85, 55)
	# thin healing: only 3 healers on the night (the roster decision that hurts)
	input["participants"] = _lineup(
		{"gear_score": 150, "execution": 55}, {"tank": 2, "healer": 3, "melee": 7, "ranged": 8}
	)
	input["events"] = [
		_event("hp_p1_cascade", 1, "cascade_death", "random", 60, 120),
		_event("hp_p1_cleave", 1, "avoidable_death", "melee", 55, 110),
	]
	return input


static func tank_pressure() -> Dictionary:
	var input := _base_input("gatewarden_gate", 40, 50, 45)
	var participants := _lineup({"gear_score": 150, "execution": 55})
	for p: Dictionary in participants:
		if str(p["role_slug"]) == "tank":
			p["uncrittable"] = 0  # the gear gate: nobody is crit-immune
			p["gear_score"] = 120
	input["participants"] = participants
	input["events"] = [
		_event("tp_p1_swap", 1, "tank_swap", "tank", 65, 140),
		_event("tp_p1_spike", 1, "near_death", "tank", 55, 110),
	]
	return input


## All five, keyed by name — for parameterized suites and the harness.
static func all() -> Dictionary:
	return {
		"clean_kill": clean_kill(),
		"mechanic_failure": mechanic_failure(),
		"dps_pressure": dps_pressure(),
		"healing_pressure": healing_pressure(),
		"tank_pressure": tank_pressure(),
	}


# --- builders ----------------------------------------------------------------


static func _base_input(
	slug: String, dps_check: int, healing_check: int, difficulty: int
) -> Dictionary:
	var input := PullContracts.make_input()
	input["encounter"] = {
		"slug": slug,
		"dps_check": dps_check,
		"healing_check": healing_check,
		"difficulty": difficulty,
		"phase_count": 1,
	}
	input["phases"] = [{"slug": "%s_p1" % slug, "phase_order": 1, "entry_condition": ""}]
	input["tuning"] = {
		"winrate_target_band": [0.6, 0.8],
		"sigmoid_scale": 12,
		"hard_check_sigmoid_scale": 7,
		"tank_healing_share": 0.35,
		"reference_comp": {"tank": 2, "healer": 5, "dps": 13},
		"contribution_variance": 0.1,
	}
	return input


static func _add_phase(input: Dictionary, phase_order: int, entry_condition: String) -> void:
	var slug := str(input["encounter"]["slug"])
	input["phases"].append(
		{
			"slug": "%s_p%d" % [slug, phase_order],
			"phase_order": phase_order,
			"entry_condition": entry_condition
		}
	)
	input["encounter"]["phase_count"] = phase_order


static func _event(
	slug: String,
	phase_order: int,
	event_type_slug: String,
	selector: String,
	severity: int,
	weight: int
) -> Dictionary:
	return {
		"slug": slug,
		"phase_order": phase_order,
		"event_type_slug": event_type_slug,
		"trigger": "fixture",
		"target_selector": selector,
		"roll_attribute": str(_ROLL_ATTR.get(event_type_slug, "awareness")),
		"effect_category": str(_CATEGORY.get(event_type_slug, "tension")),
		"log_template": "{name} meets the %s." % event_type_slug,
		"severity": severity,
		"weight": weight,
	}


## A 20-raider lineup with per-role numbering; `overrides` patch every
## participant, `composition` overrides STANDARD_LINEUP role counts.
static func _lineup(overrides: Dictionary = {}, composition: Dictionary = {}) -> Array:
	var counts := STANDARD_LINEUP.duplicate()
	for role in composition:
		counts[role] = composition[role]
	var participants := []
	var next_id := 1
	for role: String in ["tank", "healer", "melee", "ranged"]:
		for i in int(counts.get(role, 0)):
			var p := _participant(next_id, role, "%s_%d" % [role, i + 1])
			for key in overrides:
				p[key] = overrides[key]
			participants.append(p)
			next_id += 1
	return participants


static func _participant(id: int, role: String, handle: String) -> Dictionary:
	return {
		"avatar_id": id,
		"player_id": id,
		"handle": handle,
		"role_slug": role,
		"spec_slug": "fixture_%s_spec" % role,
		"spec_difficulty": 50,
		"gear_score": 150,
		"item_level": 21,
		"familiarity": 50,
		"hit_capped": 1,
		"uncrittable": 1 if role == "tank" else 0,
		"execution": 55,
		"awareness": 55,
		"consistency": 55,
		"role_proficiency": 65,
		"morale": 55,
		"fatigue": 20,
		"form": 50,
		"assignments": [{"assignment_type": "tank", "target": "main"}] if role == "tank" else [],
		"consumables": [{"slug": "hearthstew", "tier": "basic"}],
	}
