class_name Diagnosis
extends RefCounted

## Resolution stage 4b (MI-005) — THE DIAGNOSTIC HIERARCHY.
##
## "Every wipe names a culprit" is half a pillar. Raid failures in this engine are
## deliberately COUPLED: low awareness -> avoidable damage -> healing strain ->
## the tank drops -> collapse. So one dominant check is NOT one root cause, and it
## is certainly not one guilty person. A UI that points at a name teaches the
## player to bench their lowest-rated raider instead of fixing the system — which
## is the opposite of the game we are building.
##
## So the engine answers five questions, in this order, and never collapses them
## into one sentence:
##
##   1. PRIMARY CAUSE          which gate failed          ("Tank survival")
##   2. CONTRIBUTING FACTORS   what made it fatal         (the coupling)
##   3. KEY MOMENT             a person — ONLY when a specific event is
##                             directly attributable to them. Usually: nobody.
##   4. RECOMMENDATION         the lever the player should actually pull
##   5. RECURRENCE             is this the same wall as last time? (NightReport)
##
## `wipe_reason` survives as INTERNAL shorthand — the precise numeric string for
## logs, tests and the balance lab. It is never the player-facing diagnosis.
##
## Pure: (input, checks, state, verdict) -> Dictionary. No DB, no scene tree.
## Contract: docs/guildmaster-diagnostics.md.

## Player-facing names for the three gates that can end a pull (MI-002).
const CAUSE_LABELS := {
	"tank_survival": "Tank survival",
	"raid_collapse": "Raid collapse",
	"dps_enrage": "Enrage — not enough damage",
}

## A person may be named ONLY for an event they actually authored: a duty they
## were assigned and dropped, or damage they were rolled against and ate. A tank
## who dies because he was never crit-immune authored nothing — that is the
## guildmaster's lineup, and naming him for it is the scapegoat trap.
const ATTRIBUTABLE_OUTCOMES := ["duty_fail", "death"]


## Builds the structured diagnosis for a finished pull.
## `verdict` is Timeline._verdict's output; `checks` the stage-3 checks.
static func build(
	input: Dictionary, checks: Array, state: Dictionary, verdict: Dictionary
) -> Dictionary:
	if str(verdict["outcome"]) == "kill":
		return {}

	var cause := str(verdict["wipe_reason"]).get_slice(":", 0)
	var factors: Array[String] = verdict["contributing_factors"]
	var by_kind := {}
	for check: Dictionary in checks:
		by_kind[str(check["check"])] = check

	return {
		"primary_cause": cause,
		"primary_cause_label": str(CAUSE_LABELS.get(cause, cause)),
		"headline": _headline(cause, input, state),
		"contributing_factors": factors,
		"key_moment": _key_moment(input, state),
		"recommendation": _recommendation(cause, input, state, by_kind),
		# internal shorthand — the numbers, for the log and the balance lab
		"detail": str(verdict["wipe_reason"]),
	}


## One sentence, in plain language, about the SYSTEM — never about a person.
static func _headline(cause: String, input: Dictionary, state: Dictionary) -> String:
	var main_tank := Contribution.find_main_tank(input["participants"])
	match cause:
		"tank_survival":
			if not main_tank.is_empty() and int(main_tank.get("uncrittable", 0)) == 0:
				return (
					"Your main tank could be hit by a critical strike, so the boss's damage was"
					+ " never survivable — no amount of healing would have saved him"
					+ " (not uncrittable)."
				)
			return "The boss out-damaged what the tank and the healing on them could absorb."
		"raid_collapse":
			return (
				"The raid ran out of bodies — %d down, and the survivors could not carry it."
				% state["deaths"].size()
			)
		"dps_enrage":
			return (
				"The boss outlasted you: its damage became unsurvivable while it still had"
				+ " health left. Your raid simply did not hit hard enough (enrage)."
			)
		_:
			return "The raid could not meet the fight's demands."


## The one place a person may be named — and only when they authored the event.
## Returns {} when nobody is fairly nameable, which is the COMMON case and must
## stay comfortable: a wipe with no key moment is a systems problem, and the
## report says exactly that rather than reaching for a scapegoat.
static func _key_moment(input: Dictionary, state: Dictionary) -> Dictionary:
	var best := {}
	for event: Dictionary in state["events"]:
		if str(event["outcome"]) not in ATTRIBUTABLE_OUTCOMES:
			continue
		if int(event.get("target_avatar_id", 0)) <= 0:
			continue
		# the earliest attributable failure is the one that started the cascade
		if best.is_empty() or int(event["sequence_no"]) < int(best["sequence_no"]):
			best = event
	if best.is_empty():
		return {}
	return {
		"avatar_id": int(best["target_avatar_id"]),
		"handle": _handle_for(input, int(best["target_avatar_id"])),
		"sequence_no": int(best["sequence_no"]),
		"log_line": str(best["log_line"]),
		"outcome": str(best["outcome"]),
	}


## The lever the player should actually pull. Ordered by what is BINDING: the
## contributing factors are read first, because the primary cause is often only
## the thing that broke — not the thing that was wrong.
static func _recommendation(
	cause: String, input: Dictionary, state: Dictionary, by_kind: Dictionary
) -> String:
	var main_tank := Contribution.find_main_tank(input["participants"])
	var tank_uncapped := not main_tank.is_empty() and int(main_tank.get("uncrittable", 0)) == 0

	# the readiness gate dwarfs every other lever — say so before anything else
	if cause == "tank_survival" and tank_uncapped:
		return (
			"Field a main tank who cannot be critically hit. Check the bench: that tank is the"
			+ " right call even when their gear score is lower (uncrittable)."
		)
	if int(state["assigned_failures"]) > 0:
		return (
			"Reassign the dropped duty to a raider with higher Execution — unchecked casts"
			+ " are feeding the damage that is killing you."
		)
	match cause:
		"tank_survival":
			return (
				"Put more healing on the tank, or field a better-geared one. The tank is being"
				+ " out-damaged, not out-played."
			)
		"raid_collapse":
			if by_kind.has("healing") and not bool(by_kind["healing"]["passed"]):
				return (
					"Bring another healer. The healing lane cannot cover the damage this fight"
					+ " puts out, and every body you lose makes the next one likelier."
				)
			return (
				"Cut the avoidable damage: field higher-Awareness raiders, or trim the roles"
				+ " this boss punishes."
			)
		"dps_enrage":
			return (
				"You need more damage: upgrade gear, swap in higher-output raiders, or spend"
				+ " premium consumables."
			)
		_:
			return "Review the lineup against the fight's demands."


static func _handle_for(input: Dictionary, avatar_id: int) -> String:
	for participant: Dictionary in input["participants"]:
		if int(participant["avatar_id"]) == avatar_id:
			return str(participant["handle"])
	return "avatar %d" % avatar_id
