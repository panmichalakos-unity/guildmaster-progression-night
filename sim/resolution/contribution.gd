class_name Contribution
extends RefCounted

## Resolution stages 1+2 (M3-002 / M3a): per-participant contribution and
## lane aggregation. Pure math over PullContracts participant snapshots.
##
##   contribution = throughput_ceiling      (gear: what the kit COULD do)
##                x skill_realization        (execution/proficiency/familiarity;
##                                            spec_difficulty bites only when
##                                            skill is low)
##                x situational_mods         (morale/fatigue/form/consumables,
##                                            each clamped, product clamped)
##                x (1 +- variance)          (width set by Consistency)
##
## Lanes are normalized against a REFERENCE COMP (tuning `reference_comp`,
## the standard 20-man: 2 tanks / 5 healers / 13 dps) — NOT the actual lane
## size. That is what makes comp a decision: fielding 3 healers yields 3/5 of
## reference HPS (thin healing genuinely hurts), extra DPS genuinely adds, and
## deaths drag a lane down because the sum shrinks while the divisor doesn't.
## Key coupling (stage 2): healing demand = base + avoidable damage eaten
## (low raid Awareness) + tank wear — computed in `demands()`.
##
## Every constant here is symbolic; overridable via input.tuning, defaults
## mirror data/seeds/tuning.json `resolution`. The M3-005 harness judges.

const DEFAULTS := {
	"contribution_variance": 0.1,
	"ceiling_per_ilvl": 2.2,
	"awareness_demand_rate": 0.01,
	"tank_wear_demand_rate": 0.02,
	"par_tank_ilvl": 22,
}

## The standard 20-man lane sizes every lane is measured against.
const REFERENCE_COMP := {"tank": 2, "healer": 5, "dps": 13}


## Stage 1 for one participant. Deterministic given (participant, tuning, rng).
## Returns {contribution, ceiling, realization, situational, variance_roll}.
static func compute(participant: Dictionary, tuning: Dictionary, rng: RngStream) -> Dictionary:
	var ceiling := _ceiling(participant, tuning)
	var realization := _skill_realization(participant)
	var situational := _situational_mods(participant, tuning)
	var width := _variance_width(participant, tuning)
	var variance_roll := rng.randf_range(-width, width)
	var contribution := ceiling * realization * situational * (1.0 + variance_roll)
	return {
		"avatar_id": int(participant["avatar_id"]),
		"handle": str(participant.get("handle", "?")),
		"role_slug": str(participant["role_slug"]),
		"contribution": contribution,
		"ceiling": ceiling,
		"realization": realization,
		"situational": situational,
		"variance_roll": variance_roll,
	}


## Stage 2: aggregate participant contributions into raid lanes.
## Returns {dps, hps, mechanic, tank, counts, avg_awareness, contributions}.
## `exclude` (avatar_ids) lets the M3-003 timeline drop the dead and re-run.
static func lanes(
	participants: Array, tuning: Dictionary, rng: RngStream, exclude: Dictionary = {}
) -> Dictionary:
	var contributions: Array[Dictionary] = []
	var sums := {"tank": 0.0, "healer": 0.0, "melee": 0.0, "ranged": 0.0}
	var starting := {"tank": 0, "healer": 0, "melee": 0, "ranged": 0}
	var awareness_sum := 0.0
	var alive := 0
	for participant: Dictionary in participants:
		starting[str(participant["role_slug"])] += 1
		var entry := compute(participant, tuning, rng)
		entry["excluded"] = exclude.has(int(participant["avatar_id"]))
		contributions.append(entry)
		if entry["excluded"]:
			continue
		sums[entry["role_slug"]] += entry["contribution"]
		awareness_sum += float(participant["awareness"])
		alive += 1

	# reference-comp divisors: comp size is a DECISION, not a normalization
	var ref_comp: Dictionary = tuning.get("reference_comp", REFERENCE_COMP)
	return {
		"dps": (sums["melee"] + sums["ranged"]) / maxi(1, int(ref_comp.get("dps", 13))),
		"hps": sums["healer"] / maxi(1, int(ref_comp.get("healer", 5))),
		"tank": sums["tank"] / maxi(1, int(ref_comp.get("tank", 2))),
		"mechanic": _mechanic_lane(participants, exclude),
		"avg_awareness": awareness_sum / maxi(1, alive),
		"counts": starting,
		"alive": alive,
		"contributions": contributions,
	}


## Stage 2's demand side — where "it all connects". Returns per-check demands
## derived from the encounter plus the coupling terms.
static func demands(input: Dictionary, lane_data: Dictionary) -> Dictionary:
	var tuning: Dictionary = input["tuning"]
	var encounter: Dictionary = input["encounter"]
	var avoidable_pressure := (
		maxf(0.0, 55.0 - float(lane_data["avg_awareness"])) * _tune(tuning, "awareness_demand_rate")
	)
	var main_tank := find_main_tank(input["participants"])
	var tank_ilvl := float(main_tank.get("item_level", 0)) if not main_tank.is_empty() else 0.0
	var tank_wear := (
		maxf(0.0, _tune(tuning, "par_tank_ilvl") - tank_ilvl)
		* _tune(tuning, "tank_wear_demand_rate")
	)
	return {
		"dps": float(encounter["dps_check"]),
		"healing": float(encounter["healing_check"]) * (1.0 + avoidable_pressure + tank_wear),
		"tank": float(encounter["difficulty"]),
		"mechanic": float(encounter["difficulty"]),
		"avoidable_pressure": avoidable_pressure,
		"tank_wear": tank_wear,
	}


## The main tank: assignment target "main", else the first tank in the lineup.
static func find_main_tank(participants: Array) -> Dictionary:
	var first_tank := {}
	for participant: Dictionary in participants:
		if str(participant["role_slug"]) != "tank":
			continue
		if first_tank.is_empty():
			first_tank = participant
		for assignment: Dictionary in participant.get("assignments", []):
			if (
				str(assignment.get("assignment_type", "")) == "tank"
				and str(assignment.get("target", "")) == "main"
			):
				return participant
	return first_tank


# --- stage-1 internals --------------------------------------------------------


static func _ceiling(participant: Dictionary, tuning: Dictionary) -> float:
	var avg_ilvl := float(participant["gear_score"]) / 7.0
	return avg_ilvl * _tune(tuning, "ceiling_per_ilvl")


## Execution x proficiency x familiarity; spec_difficulty bites only below
## the skill line (hard spec + low skill = liability, + high skill = monster).
static func _skill_realization(participant: Dictionary) -> float:
	var skill := (
		float(participant["execution"]) * 0.5
		+ float(participant["role_proficiency"]) * 0.25
		+ float(participant["familiarity"]) * 0.25
	)
	var difficulty_bite := maxf(0.0, float(participant["spec_difficulty"]) - skill) * 0.4
	var effective := clampf(skill - difficulty_bite, 5.0, 95.0)
	return 0.35 + effective / 100.0 * 0.6


## Multiplicative state mods, each clamped ~0.85-1.15, product clamped 0.7-1.3.
static func _situational_mods(participant: Dictionary, tuning: Dictionary) -> float:
	var morale_mod := clampf(1.0 + (float(participant["morale"]) - 50.0) * 0.003, 0.85, 1.15)
	var fatigue_mod := clampf(1.0 - float(participant["fatigue"]) * 0.003, 0.85, 1.15)
	var form_mod := clampf(1.0 + (float(participant["form"]) - 50.0) * 0.002, 0.85, 1.15)
	var consumable_mod := 1.0 + _best_consumable_bonus(participant, tuning)
	return clampf(morale_mod * fatigue_mod * form_mod * consumable_mod, 0.7, 1.3)


static func _best_consumable_bonus(participant: Dictionary, tuning: Dictionary) -> float:
	var consumables: Dictionary = tuning.get(
		"consumables", {"premium_contribution_bonus": 0.08, "basic_contribution_bonus": 0.04}
	)
	var best := 0.0
	for consumable: Dictionary in participant.get("consumables", []):
		match str(consumable.get("tier", "")):
			"premium":
				best = maxf(best, float(consumables.get("premium_contribution_bonus", 0.08)))
			"basic":
				best = maxf(best, float(consumables.get("basic_contribution_bonus", 0.04)))
	return best


## Steady raiders draw narrow, spiky ones draw wide.
static func _variance_width(participant: Dictionary, tuning: Dictionary) -> float:
	var base := _tune(tuning, "contribution_variance")
	return base * (1.5 - float(participant["consistency"]) / 100.0)


## Mechanic-handling lane: mean awareness of the living, familiarity-weighted.
static func _mechanic_lane(participants: Array, exclude: Dictionary) -> float:
	var total := 0.0
	var alive := 0
	for participant: Dictionary in participants:
		if exclude.has(int(participant["avatar_id"])):
			continue
		total += (float(participant["awareness"]) * 0.8 + float(participant["familiarity"]) * 0.2)
		alive += 1
	return total / maxi(1, alive)


static func _tune(tuning: Dictionary, key: String) -> float:
	return float(tuning.get(key, DEFAULTS[key]))
