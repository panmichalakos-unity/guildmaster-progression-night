class_name Timeline
extends RefCounted

## Resolution stage 4 (M3-003 / M3b): phase timeline traversal + ENCOUNTER_EVENT
## firing + assigned-duty checks. Pure over the M3-001 contracts; calls the
## M3-002 lanes/checks (never duplicates that math).
##
## The engine is entirely DATA-DRIVEN — behavior comes from the seed rows'
## `effect_category` + `target_selector` + `roll_attribute` + `severity`, never
## from a boss slug. Adding a boss = adding ENCOUNTER_EVENT rows.
##
## Flow: walk phases in order -> each placed event fires (weight -> fire count)
## -> pick target(s) by selector among the LIVING -> roll roll_attribute vs
## severity (sigmoid) -> apply the category's effect (death / save / surge /
## duty / tank-gate) -> emit a PULL_EVENT-shaped combat-log row. Deaths remove
## bodies, so the final lane re-aggregation drops the fallen (cascade). Outcome
## = the M3-002 checks on the survivors + death collapse, and every wipe names
## the dominant failed check AND a culprit (legible failure).
##
## effect_category dispatch (from event_type seed rows):
##   death       avoidable_death (avoidable), cascade_death (follow-on overwhelm)
##   save        clutch_save (cancels the phase's most recent death)
##   tension     near_death (survives either way; flavor + rating nudge)
##   surge       cooldown_moment (assigned; success speeds the DPS check)
##   duty_check  assigned_duty (fail -> an add/soak kills a raider: cascade)
##   tank_check  tank_swap (fail + not uncrittable -> the tank dies)

const DEFAULTS := {
	"event_scale": 15.0,
	"cooldown_surge_bonus": 0.06,
	"collapse_death_fraction": 0.3,
	"severity_learning_rate": 0.08,
	"healing_deficit_lethality": 0.6,
}

## Combat-log outcome vocabulary. RatingEngine keys its deltas on THESE
## constants — never repeat the raw strings (review finding, ADR-0021).
const OUTCOME_DEATH := "death"
const OUTCOME_TANK_DEATH := "tank_death"
const OUTCOME_DUTY_FAIL := "duty_fail"
const OUTCOME_DUTY_OK := "duty_ok"
const OUTCOME_SAVE := "save"
const OUTCOME_SURGE := "surge"
const OUTCOME_SURVIVED := "survived"

const _ATTR_FIELD := {
	"awareness": "awareness", "consistency": "consistency", "execution": "execution"
}

# Primary-cause precedence: the failure the raid should diagnose first.
# MI-002: only these three can END a pull. healing/mechanic are pressure and
# appear as CONTRIBUTING FACTORS, never as the primary cause of a wipe.
const _WIPE_PRECEDENCE := ["tank", "collapse", "dps"]


## Runs the full timeline for a pull. Deterministic given (input, rng).
## Returns:
##   events        Array of contract event rows (the combat log)
##   deaths        Array[int] avatar_ids in death order
##   outcome       "kill" | "wipe"
##   wipe_reason   "" on kill; "<key>: <sentence w/ culprit>" on wipe
##   checks        final M3-002 checks on survivors
##   lanes         final lanes (survivors, surge applied)
##   progress_pct  0..100 how far the raid got (feeds encounter_progress, M3-004)
##   dps_surge     accumulated cooldown surge fraction
static func run(input: Dictionary, rng: RngStream) -> Dictionary:
	var participants: Array = input["participants"]
	var tuning: Dictionary = input["tuning"]
	var event_rng := rng.substream("events")

	# MI-002: healing PRESSURE is computed up front, from the full raid, and
	# fed into the timeline — a healing lane that cannot keep up makes death
	# events deadlier. This is HOW thin healing kills a raid now: through
	# bodies dropping in the log, not through a phantom independent wipe-roll.
	var opening_lanes := Contribution.lanes(participants, tuning, rng.substream("contribution"))
	var healing_deficit := PullChecks.healing_deficit(input, opening_lanes)

	var state := {
		"deaths": [] as Array[int],
		"dead_set": {},
		"deaths_this_phase": [] as Array[int],
		"dps_surge": 0.0,
		"assigned_failures": 0,
		"events": [] as Array[Dictionary],
		"sequence": 0,
		"healing_deficit": healing_deficit,
	}

	# learning arc: encounter familiarity shaves event severity — the raid
	# that has SEEN the fire stands in it less (avoidable-death rates down)
	var events: Array = input["events"]
	var progress := float(input.get("encounter_progress", {}).get("progress", 0))
	if progress > 0.0:
		var shave := progress * _tune(tuning, "severity_learning_rate")
		var adjusted: Array = []
		for event: Dictionary in events:
			var copy: Dictionary = event.duplicate()
			copy["severity"] = maxf(1.0, float(copy["severity"]) - shave)
			adjusted.append(copy)
		events = adjusted

	for phase: Dictionary in _sorted_phases(input["phases"]):
		state["deaths_this_phase"] = [] as Array[int]
		for event: Dictionary in _phase_events(events, int(phase["phase_order"])):
			# weight = firing rate in percent: 100 fires exactly once, 60 fires
			# 60% of pulls, 140 fires once plus a 40% second shot — every
			# authored value is a live tuning knob (review finding, ADR-0021)
			var weight := float(event.get("weight", 100))
			var fires := int(weight / 100.0)
			if event_rng.randf() < (weight - fires * 100.0) / 100.0:
				fires += 1
			for _shot in fires:
				_fire(event, phase, participants, state, tuning, event_rng)

	# re-aggregate lanes from the SAME contribution draws, minus the fallen
	# (substream("contribution") twice = identical values; deaths change only
	# the sums — the fork-doesn't-disturb-parent guarantee, ADR-0012).
	var final_lanes := Contribution.lanes(
		participants, tuning, rng.substream("contribution"), state["dead_set"]
	)
	final_lanes["dps"] = float(final_lanes["dps"]) * (1.0 + float(state["dps_surge"]))
	var checks := PullChecks.resolve(input, final_lanes, rng.substream("checks"))

	var verdict := _verdict(input, checks, state, final_lanes)
	return {
		"events": state["events"],
		"deaths": state["deaths"],
		"outcome": verdict["outcome"],
		"wipe_reason": verdict["wipe_reason"],
		"contributing_factors": verdict["contributing_factors"],
		"progress_pct": verdict["progress_pct"],
		"checks": checks,
		"lanes": final_lanes,
		"dps_surge": float(state["dps_surge"]),
		"healing_deficit": float(state["healing_deficit"]),
	}


# --- event firing -------------------------------------------------------------


static func _fire(
	event: Dictionary,
	phase: Dictionary,
	participants: Array,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	var category := str(event.get("effect_category", ""))
	var targets := _select_targets(event, participants, state["dead_set"], rng, 1)
	if targets.is_empty():
		return
	var target: Dictionary = targets[0]
	match category:
		"death":
			_resolve_death(event, phase, target, state, tuning, rng)
		"save":
			_resolve_save(event, phase, target, state, tuning, rng)
		"tension":
			_resolve_tension(event, phase, target, state, tuning, rng)
		"surge":
			_resolve_surge(event, phase, target, state, tuning, rng)
		"duty_check":
			_resolve_duty(event, phase, target, participants, state, tuning, rng)
		"tank_check":
			_resolve_tank(event, phase, target, state, tuning, rng)
		_:
			# unknown category: log a neutral beat so nothing fires silently
			_emit(state, event, phase, target, "n/a", "noop", _render(event, target, {}))


static func _resolve_death(
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	var attribute := str(event.get("roll_attribute", ""))
	# cascade_death (no roll attribute) is a FOLLOW-ON: it only bites once a
	# death has already happened this pull; otherwise the raid steadies.
	if attribute.is_empty() and state["deaths"].is_empty():
		_emit(state, event, phase, target, "-", "steadied", "The raid steadies — no cascade.")
		return
	# MI-002: a raid whose heals fell behind dies more. The deficit raises the
	# effective severity of EVERY death event — legible in the log as bodies
	# dropping, which is the honest expression of "the healing ran dry".
	var lethality := float(state["healing_deficit"]) * _tune(tuning, "healing_deficit_lethality")
	var roll := _roll(
		target,
		attribute if not attribute.is_empty() else "consistency",
		float(event["severity"]) + lethality,
		tuning,
		rng
	)
	if roll["handled"]:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"handled",
			"%s handles it clean." % target["handle"]
		)
	else:
		_kill(state, target)
		_emit(state, event, phase, target, roll["text"], OUTCOME_DEATH, _render(event, target, {}))


static func _resolve_save(
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	var roll := _roll(
		target,
		str(event.get("roll_attribute", "consistency")),
		float(event["severity"]),
		tuning,
		rng
	)
	var deaths_this_phase: Array = state["deaths_this_phase"]
	if roll["handled"] and not deaths_this_phase.is_empty():
		var saved_id: int = deaths_this_phase[deaths_this_phase.size() - 1]
		_revive(state, saved_id)
		var saved := _handle_for(state, saved_id)
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"save",
			"%s snaps off the save — %s lives." % [target["handle"], saved]
		)
	elif roll["handled"]:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"ready",
			"%s stands ready with the save." % target["handle"]
		)
	else:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"miss",
			"%s can't get the save off in time." % target["handle"]
		)


static func _resolve_tension(
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	var roll := _roll(
		target,
		str(event.get("roll_attribute", "consistency")),
		float(event["severity"]),
		tuning,
		rng
	)
	_emit(state, event, phase, target, roll["text"], OUTCOME_SURVIVED, _render(event, target, {}))


static func _resolve_surge(
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	var roll := _roll(
		target, str(event.get("roll_attribute", "execution")), float(event["severity"]), tuning, rng
	)
	if roll["handled"]:
		state["dps_surge"] = (float(state["dps_surge"]) + _tune(tuning, "cooldown_surge_bonus"))
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"surge",
			"Cooldowns drop on %s's call — the raid surges." % target["handle"]
		)
	else:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"fumble",
			"The cooldown window slips by unused."
		)


static func _resolve_duty(
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	participants: Array,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	# assigned-duty: the assignee blends role_proficiency + execution.
	var skill := (float(target["role_proficiency"]) + float(target["execution"])) / 2.0
	var roll := _roll_value(skill, float(event["severity"]), tuning, rng)
	if roll["handled"]:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"duty_ok",
			"%s handles the assignment — clean." % target["handle"]
		)
	else:
		state["assigned_failures"] = int(state["assigned_failures"]) + 1
		# the missed interrupt/soak lands on SOMEONE ELSE: cascade pressure
		# (assignee excluded — "X misses, X falls" reads as a bug; ADR-0021)
		var victim_exclude: Dictionary = state["dead_set"].duplicate()
		victim_exclude[int(target["avatar_id"])] = true
		var victim := _select_targets(
			{"target_selector": "random"}, participants, victim_exclude, rng, 1
		)
		if victim.is_empty():
			_emit(
				state,
				event,
				phase,
				target,
				roll["text"],
				"duty_fail",
				"%s misses the assignment — the raid eats it." % target["handle"]
			)
			return
		_kill(state, victim[0])
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"duty_fail",
			(
				"%s misses the assignment — %s falls to the unchecked cast."
				% [target["handle"], victim[0]["handle"]]
			)
		)


static func _resolve_tank(
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	state: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> void:
	var roll := _roll(
		target, str(event.get("roll_attribute", "awareness")), float(event["severity"]), tuning, rng
	)
	if roll["handled"]:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"swap_ok",
			"%s takes the swap right at the threshold." % target["handle"]
		)
	elif int(target.get("uncrittable", 0)) == 1:
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"scare",
			"%s eats a big hit but the armor holds." % target["handle"]
		)
	else:
		_kill(state, target)
		_emit(
			state,
			event,
			phase,
			target,
			roll["text"],
			"tank_death",
			"%s is not crit-immune — a spike gibs the tank." % target["handle"]
		)


# --- target selection ---------------------------------------------------------


static func _select_targets(
	event: Dictionary, participants: Array, dead_set: Dictionary, rng: RngStream, count: int
) -> Array[Dictionary]:
	var selector := str(event.get("target_selector", "random"))
	var living: Array[Dictionary] = []
	for p: Dictionary in participants:
		if not dead_set.has(int(p["avatar_id"])):
			living.append(p)
	if living.is_empty():
		return []

	var pool: Array[Dictionary] = []
	match selector:
		"tank", "healer", "melee", "ranged":
			for p: Dictionary in living:
				if str(p["role_slug"]) == selector:
					pool.append(p)
		"assigned":
			pool = _assigned_pool(living)
		_:  # random
			pool = living.duplicate()
	if pool.is_empty():
		pool = living.duplicate()  # selector role wiped out -> fall back to the raid

	var picked: Array[Dictionary] = []
	var bag := pool.duplicate()
	for _i in mini(count, bag.size()):
		var idx := rng.randi_range(0, bag.size() - 1)
		picked.append(bag[idx])
		bag.remove_at(idx)
	return picked


## Assigned pool: raiders who hold an assignment, best-executor first; if none
## are explicitly assigned, the raid's strongest hands take the duty.
static func _assigned_pool(living: Array[Dictionary]) -> Array[Dictionary]:
	var assigned: Array[Dictionary] = []
	for p: Dictionary in living:
		if not p.get("assignments", []).is_empty():
			assigned.append(p)
	var pool := assigned if not assigned.is_empty() else living.duplicate()
	pool.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["execution"]) > float(b["execution"])
	)
	return pool


# --- rolls --------------------------------------------------------------------


static func _roll(
	target: Dictionary, attribute: String, severity: float, tuning: Dictionary, rng: RngStream
) -> Dictionary:
	var field := str(_ATTR_FIELD.get(attribute, "consistency"))
	return _roll_value(float(target.get(field, 50)), severity, tuning, rng)


static func _roll_value(
	attribute_value: float, severity: float, tuning: Dictionary, rng: RngStream
) -> Dictionary:
	var scale := _tune(tuning, "event_scale")
	var probability := 1.0 / (1.0 + exp(-(attribute_value - severity) / scale))
	var handled := rng.randf() < probability
	return {
		"handled": handled,
		"probability": probability,
		"text":
		(
			"%s (a%.0f vs s%.0f, p=%.2f)"
			% ["pass" if handled else "fail", attribute_value, severity, probability]
		),
	}


# --- outcome ------------------------------------------------------------------


static func _verdict(
	input: Dictionary, checks: Array, state: Dictionary, _lanes: Dictionary
) -> Dictionary:
	var by_kind := {}
	for check: Dictionary in checks:
		by_kind[str(check["check"])] = check
	var deaths: Array = state["deaths"]
	var roster_size: int = input["participants"].size()
	var death_fraction := float(deaths.size()) / float(maxi(1, roster_size))
	var main_tank := Contribution.find_main_tank(input["participants"])
	var dead_set: Dictionary = state["dead_set"]
	var main_tank_dead: bool = (
		not main_tank.is_empty() and dead_set.has(int(main_tank["avatar_id"]))
	)

	# MI-002: ONLY gating checks (dps/tank) and raid collapse can wipe. Healing
	# and mechanic are PRESSURE — they already took their toll during the
	# timeline (deaths), and they resurface below as contributing factors.
	# A healthy raid's kill odds are now p(dps) x p(tank), not a 4-way product.
	var failures: Array[String] = []
	if main_tank_dead or not bool(by_kind["tank"]["passed"]):
		failures.append("tank")
	if death_fraction >= _tune(input["tuning"], "collapse_death_fraction"):
		failures.append("collapse")
	if not bool(by_kind["dps"]["passed"]):
		failures.append("dps")

	var progress := _progress_pct(by_kind["dps"], death_fraction)
	if failures.is_empty():
		return {
			"outcome": "kill",
			"wipe_reason": "",
			"progress_pct": 100,
			"contributing_factors": [] as Array[String],
		}

	var dominant := _dominant(failures)
	return {
		"outcome": "wipe",
		"wipe_reason": _wipe_reason(dominant, by_kind, state, main_tank, main_tank_dead),
		"progress_pct": progress,
		# groundwork for the MI-005 diagnostic hierarchy: what made it fatal
		"contributing_factors": _contributing_factors(by_kind, state, main_tank, death_fraction),
	}


## The coupled conditions that made the primary cause fatal (MI-005). Pressure
## lanes live HERE — as explanation — not as phantom independent wipes.
static func _contributing_factors(
	by_kind: Dictionary, state: Dictionary, main_tank: Dictionary, death_fraction: float
) -> Array[String]:
	var factors: Array[String] = []
	if not bool(by_kind["healing"]["passed"]):
		factors.append(
			(
				"healing lane fell %.1f short — deaths came faster than heals"
				% absf(float(by_kind["healing"]["margin"]))
			)
		)
	if not bool(by_kind["mechanic"]["passed"]):
		factors.append(
			(
				"raid awareness below the fight's demand (%.1f short) — avoidable damage piled up"
				% absf(float(by_kind["mechanic"]["margin"]))
			)
		)
	if not main_tank.is_empty() and int(main_tank.get("uncrittable", 0)) == 0:
		factors.append(
			"%s is not crit-immune — one spike can end a pull" % main_tank.get("handle", "the tank")
		)
	if int(state["assigned_failures"]) > 0:
		factors.append(
			(
				"%d assigned duty/duties missed — unchecked casts hit the raid"
				% int(state["assigned_failures"])
			)
		)
	if death_fraction > 0.0:
		factors.append(
			(
				"%d raider(s) down by the end — fewer bodies means less output and less healing"
				% state["deaths"].size()
			)
		)
	return factors


static func _dominant(failures: Array[String]) -> String:
	for key in _WIPE_PRECEDENCE:
		if key in failures:
			return key
	return failures[0]


static func _wipe_reason(
	dominant: String,
	by_kind: Dictionary,
	state: Dictionary,
	main_tank: Dictionary,
	main_tank_dead: bool
) -> String:
	match dominant:
		"tank":
			if main_tank_dead:
				var gate := (
					" (was not uncrittable)"
					if not main_tank.is_empty() and int(main_tank.get("uncrittable", 0)) == 0
					else ""
				)
				return "tank_survival: %s died%s" % [main_tank.get("handle", "the tank"), gate]
			return "tank_survival: %s" % by_kind["tank"]["detail"]
		"collapse":
			var first := (
				_handle_for(state, state["deaths"][0]) if not state["deaths"].is_empty() else "?"
			)
			return (
				"raid_collapse: %d raiders down (started with %s) — the raid can't hold"
				% [state["deaths"].size(), first]
			)
		"dps":
			return "dps_enrage: %s" % by_kind["dps"]["detail"]
		"healing":
			return "healing_sustain: %s" % by_kind["healing"]["detail"]
		_:
			return (
				"mechanic_execution: %d raiders down to avoidable damage" % state["deaths"].size()
			)


static func _progress_pct(dps_check: Dictionary, death_fraction: float) -> int:
	# how close the raid got: the DPS margin (the enrage race) centered at 0.5
	# and dragged down by how much of the raid died. A bounded flavor/learning
	# proxy, not a precise HP model — feeds encounter_progress in M3-004.
	var margin_norm := clampf(float(dps_check["margin"]) / 40.0, -0.5, 0.5)
	var reached := (0.5 + margin_norm) * (1.0 - death_fraction)
	return clampi(roundi(reached * 100.0), 1, 99)


# --- combat-log + death bookkeeping ------------------------------------------


static func _emit(
	state: Dictionary,
	event: Dictionary,
	phase: Dictionary,
	target: Dictionary,
	roll_result: String,
	outcome: String,
	log_line: String
) -> void:
	state["sequence"] = int(state["sequence"]) + 1
	(
		state["events"]
		. append(
			{
				"sequence_no": int(state["sequence"]),
				"encounter_event_slug": str(event.get("slug", "")),
				"phase_order": int(phase["phase_order"]),
				"target_avatar_id": int(target.get("avatar_id", 0)),
				"roll_result": roll_result,
				"outcome": outcome,
				"log_line": log_line,
			}
		)
	)


static func _kill(state: Dictionary, target: Dictionary) -> void:
	var avatar_id := int(target["avatar_id"])
	if state["dead_set"].has(avatar_id):
		return
	state["dead_set"][avatar_id] = str(target["handle"])
	state["deaths"].append(avatar_id)
	state["deaths_this_phase"].append(avatar_id)


static func _revive(state: Dictionary, avatar_id: int) -> void:
	if not state["dead_set"].has(avatar_id):
		return
	state["dead_set"].erase(avatar_id)
	state["deaths"].erase(avatar_id)
	state["deaths_this_phase"].erase(avatar_id)


static func _handle_for(state: Dictionary, avatar_id: int) -> String:
	return str(state["dead_set"].get(avatar_id, "raider #%d" % avatar_id))


static func _render(event: Dictionary, target: Dictionary, extra: Dictionary) -> String:
	var line := str(event.get("log_template", "{name} is hit."))
	line = line.replace("{name}", str(target.get("handle", "a raider")))
	line = line.replace("{target}", str(extra.get("target", target.get("handle", "a raider"))))
	return line


# --- helpers ------------------------------------------------------------------


static func _sorted_phases(phases: Array) -> Array:
	var sorted := phases.duplicate()
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["phase_order"]) < int(b["phase_order"])
	)
	return sorted


static func _phase_events(events: Array, phase_order: int) -> Array:
	var matched: Array = []
	for event: Dictionary in events:
		if int(event["phase_order"]) == phase_order:
			matched.append(event)
	matched.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return str(a["slug"]) < str(b["slug"])
	)
	return matched


static func _tune(tuning: Dictionary, key: String) -> float:
	return float(tuning.get(key, DEFAULTS[key]))
