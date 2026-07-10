class_name PullChecks
extends RefCounted

## Resolution stage 3 (M3-002 / M3a): margin -> sigmoid check resolution.
##
##   margin  = raid_output - boss_demand
##   P(pass) = sigmoid(margin / scale)
##
## Saturated margin -> decisive (one-shot or clean wipe); margin ~ 0 -> the
## coin-flip zone the 60-80% win-rate target lives in. HARD checks (tank
## survival, dps/enrage) use the steeper curve — a cliff, not a slope. The
## tank check is deliberately near-binary: a non-uncrittable main tank eats
## a flat margin penalty (the era-authentic gear gate).
##
## Every check carries a `detail` string naming numbers AND a culprit hint —
## the legible-failure fodder wipe_reason (M3-004) and the why-view read.

const DEFAULTS := {
	"sigmoid_scale": 12.0,
	"hard_check_sigmoid_scale": 7.0,
	"uncrittable_gate_penalty": 25.0,
	"tank_healing_share": 0.35,
}

const HARD_CHECKS := ["dps", "tank"]


## Resolves the four M3a checks against aggregated lanes. Deterministic given
## (input, lane_data, rng). Returns contract-shaped checks[] (PullContracts).
static func resolve(input: Dictionary, lane_data: Dictionary, rng: RngStream) -> Array[Dictionary]:
	var demands := Contribution.demands(input, lane_data)
	var checks: Array[Dictionary] = []
	checks.append(_check("dps", float(lane_data["dps"]), demands["dps"], input, lane_data, rng))
	checks.append(
		_check("healing", float(lane_data["hps"]), demands["healing"], input, lane_data, rng)
	)
	checks.append(_tank_check(input, lane_data, demands, rng))
	checks.append(
		_check("mechanic", float(lane_data["mechanic"]), demands["mechanic"], input, lane_data, rng)
	)
	return checks


## P(pass) for a margin under the given tuning — exposed for harness/tests.
static func pass_probability(margin: float, check: String, tuning: Dictionary) -> float:
	var key := "hard_check_sigmoid_scale" if check in HARD_CHECKS else "sigmoid_scale"
	var scale := float(tuning.get(key, DEFAULTS[key]))
	return 1.0 / (1.0 + exp(-margin / scale))


static func _check(
	kind: String,
	output: float,
	demand: float,
	input: Dictionary,
	lane_data: Dictionary,
	rng: RngStream
) -> Dictionary:
	var margin := output - demand
	var probability := pass_probability(margin, kind, input["tuning"])
	var passed := rng.randf() < probability
	return {
		"check": kind,
		"margin": margin,
		"passed": passed,
		"detail":
		(
			"%s %.1f vs demand %.1f (margin %+.1f, p=%.2f)%s"
			% [kind, output, demand, margin, probability, _culprit_hint(kind, lane_data)]
		),
	}


## Tank survival: near-binary. Non-uncrittable main tank eats the gate penalty.
static func _tank_check(
	input: Dictionary, lane_data: Dictionary, demands: Dictionary, rng: RngStream
) -> Dictionary:
	var tuning: Dictionary = input["tuning"]
	var main_tank := Contribution.find_main_tank(input["participants"])
	# tank survival = tank EHP/mitigation + healers keeping the tank up (doc):
	# thin or dead healing lets tanks drop even at par gear.
	var healing_support := (
		float(lane_data["hps"])
		* float(tuning.get("tank_healing_share", DEFAULTS["tank_healing_share"]))
	)
	var tank_output := float(lane_data["tank"]) + healing_support
	var margin := tank_output - float(demands["tank"])
	var gate_note := ""
	if not main_tank.is_empty() and int(main_tank.get("uncrittable", 0)) == 0:
		var penalty := float(
			tuning.get("uncrittable_gate_penalty", DEFAULTS["uncrittable_gate_penalty"])
		)
		margin -= penalty
		gate_note = (
			"; %s is NOT uncrittable (gate -%d)" % [main_tank.get("handle", "tank"), penalty]
		)
	var probability := pass_probability(margin, "tank", tuning)
	var passed := rng.randf() < probability
	return {
		"check": "tank",
		"margin": margin,
		"passed": passed,
		"detail":
		(
			"tank %.1f (+%.1f heals) vs demand %.1f (margin %+.1f, p=%.2f)%s; main tank: %s"
			% [
				float(lane_data["tank"]),
				healing_support,
				float(demands["tank"]),
				margin,
				probability,
				gate_note,
				main_tank.get("handle", "none"),
			]
		),
	}


## Names the weakest link in the lane — the culprit hint legibility feeds on.
static func _culprit_hint(kind: String, lane_data: Dictionary) -> String:
	var lane_roles := {
		"dps": ["melee", "ranged"], "healing": ["healer"], "mechanic": [], "tank": ["tank"]
	}
	var roles: Array = lane_roles.get(kind, [])
	if roles.is_empty():
		return ""
	var weakest := {}
	for entry: Dictionary in lane_data["contributions"]:
		if entry.get("excluded", false) or str(entry["role_slug"]) not in roles:
			continue
		if weakest.is_empty() or float(entry["contribution"]) < float(weakest["contribution"]):
			weakest = entry
	if weakest.is_empty():
		return ""
	return "; weakest: %s (%.1f)" % [weakest["handle"], weakest["contribution"]]
