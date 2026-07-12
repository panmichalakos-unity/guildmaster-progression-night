class_name RatingEngine
extends RefCounted

## Performance ratings (M3-004 / M3c; CONTRACT LOCKED by MI-006).
##
## THE GOVERNING PRINCIPLE — a rating measures how well a raider fulfilled their
## ROLE AND THEIR ASSIGNMENTS, relative to the kit, gear and situation available
## to them. It is NOT raw output. A 6.2, never "43k".
##
##   expected = ceiling x reference realization (a plain 50-skill raider)
##   ratio    = actual contribution / expected          <- vs THEIR OWN ceiling
##   rating   = clamp(round(5.5 + (ratio - 1) x spread + event deltas), 1, 10)
##
## Because `expected` is derived from the raider's OWN gear, the number is
## automatically fair across roles and across gear levels: an undergeared healer
## who plays out of their skin outranks a decked-out DPS coasting at 80% of what
## his gear should produce. That is the whole point — this rating is loot
## EVIDENCE (M6 Council), and evidence that just re-reported gear score would make
## loot a feedback loop that eats itself.
##
## Event deltas read the combat log (by target_avatar_id), so the night's STORY
## moves the number: dying to something you could have avoided drags it; a clutch
## save or a clean duty lifts it.
##
## NO DOUBLE-COUNTING (MI-006, verified by test). One failure is charged exactly
## once, to whoever authored it:
##   * a dead raider keeps their own `contribution` (death removes them from the
##     LANE SUMS, never from their own ratio) — so dying costs the event delta and
##     nothing more;
##   * a missed duty is charged to the ASSIGNEE, and the raider it kills takes no
##     rating hit at all (the event targets the assignee, not the victim).
##
## Every rating carries a plain-language BREAKDOWN (`rating_factors`), because a
## number nobody can explain makes loot feel arbitrary — see docs/guildmaster-rating.md.

const DEFAULTS := {
	"rating_spread": 12.0,
	"reference_realization": 0.65,  # skill-50 raider: 0.35 + 0.5 * 0.6
}

## How the raider's OUTPUT reads, given what their gear should have produced.
## Ordered worst -> best; the first band whose ceiling the ratio clears wins.
const OUTPUT_BANDS := [
	[0.75, "well below what their gear should produce"],
	[0.95, "below what their gear should produce"],
	[1.05, "about what their gear should produce"],
	[1.25, "strong output for the gear they have"],
	[999.0, "far above what their gear should produce"],
]

## The order a NIGHT reads in: what they DID first, what it COST second, and the
## deaths that were never theirs last. A summary that opens with a raider's
## failures is an indictment, not an explanation — before this, the MVP's line came
## out as "3 avoidable death(s)" and nothing else, which says the exact opposite of
## what his 7.4 says.
const NIGHT_ORDER: Array[String] = [
	"save",
	"duty_ok",
	"surge",
	"survived",
	"duty_fail",
	"death",
	"tank_death",
	"tank_overwhelmed",
	"cascade_death",
]

## combat-log outcome -> rating delta, keyed on Timeline's OUTCOME_* constants
## (never raw strings — a rename there must break HERE at parse time, ADR-0021)
static var _outcome_deltas := {
	Timeline.OUTCOME_DEATH: -2.0,
	Timeline.OUTCOME_TANK_DEATH: -2.0,
	Timeline.OUTCOME_DUTY_FAIL: -2.0,
	Timeline.OUTCOME_SAVE: 1.5,
	Timeline.OUTCOME_DUTY_OK: 0.5,
	Timeline.OUTCOME_SURGE: 0.5,
	Timeline.OUTCOME_SURVIVED: 0.5,
	# MI-005 — DELIBERATELY ZERO, both of them. A tank who is out-damaged (almost
	# always for want of the crit-immune cap) and a raider caught by the raid's
	# healing running dry rolled nothing they controlled and authored nothing: the
	# guildmaster fielded the lineup. Docking them would teach the player to bench
	# the casualty instead of fixing the system — the exact scapegoat trap this
	# ticket exists to close. They die in the log; they do not take the blame.
	Timeline.OUTCOME_TANK_OVERWHELMED: 0.0,
	Timeline.OUTCOME_CASCADE_DEATH: 0.0,
}

## MI-006 — what each combat-log outcome MEANS, in the player's language (MI-008:
## consequence in plain words, no naked jargon). A rating nobody can explain makes
## loot feel arbitrary, and the Council is the flagship system that rests on it.
## %d is the number of times it happened.
static var _outcome_labels := {
	Timeline.OUTCOME_DEATH: "died to damage they could have avoided (x%d)",
	Timeline.OUTCOME_TANK_DEATH: "was caught by a critical strike while tanking (x%d)",
	Timeline.OUTCOME_DUTY_FAIL: "dropped an assigned job (x%d)",
	Timeline.OUTCOME_DUTY_OK: "handled their assigned job cleanly (x%d)",
	Timeline.OUTCOME_SAVE: "pulled off a clutch save (x%d)",
	Timeline.OUTCOME_SURGE: "nailed the cooldown window (x%d)",
	Timeline.OUTCOME_SURVIVED: "survived a moment that should have killed them (x%d)",
	# zero-delta, but SHOWN anyway: the report must say out loud that this death
	# was not their fault, or the player reads a corpse and a low number and draws
	# the obvious wrong conclusion (the scapegoat trap, ADR-0028).
	Timeline.OUTCOME_TANK_OVERWHELMED: "was out-damaged, not out-played — no fault of his (x%d)",
	Timeline.OUTCOME_CASCADE_DEATH: "fell when the healing ran dry — not their doing (x%d)",
}

## MI-006 — the same facts at NIGHT grain. A rating is atomic per pull; the report
## shows the mean across the night, so it must explain the mean. The per-pull output
## VERDICT does not sum ("about what their gear should produce, eight times" tells a
## guildmaster nothing) — but the ratio behind it does, and `output_label()` says so
## in one phrase up front.
static var _night_labels := {
	Timeline.OUTCOME_DEATH: "%d avoidable death(s)",
	Timeline.OUTCOME_TANK_DEATH: "%d critical-strike death(s) while tanking",
	Timeline.OUTCOME_DUTY_FAIL: "dropped %d assigned job(s)",
	Timeline.OUTCOME_DUTY_OK: "handled %d assigned job(s) cleanly",
	Timeline.OUTCOME_SAVE: "%d clutch save(s)",
	Timeline.OUTCOME_SURGE: "%d cooldown window(s) nailed",
	Timeline.OUTCOME_SURVIVED: "%d near-death survival(s)",
	Timeline.OUTCOME_TANK_OVERWHELMED: "fell %d time(s) out-damaged — not his doing",
	Timeline.OUTCOME_CASCADE_DEATH: "fell %d time(s) when the healing ran dry — not their doing",
}


## Night-grain phrasing for a factor code; "" for codes with no night meaning.
static func night_label(code: String) -> String:
	return str(_night_labels.get(code, ""))


## How a raider's OUTPUT read across the whole night. The per-pull verdict does
## not sum, but the mean RATIO does — and without it a strong raider's summary is
## all debits and no credits.
static func output_label(mean_ratio: float) -> String:
	return "consistently %s" % _output_label(mean_ratio)


## Ratings for every participant. `contributions` = Contribution.lanes()
## entries; `events` = the timeline's combat log; `dead_set` = avatar_id keys.
## Returns Array of contract participant rows (PULL_PARTICIPANT shape).
static func rate(
	participants: Array,
	contributions: Array,
	events: Array,
	dead_set: Dictionary,
	tuning: Dictionary
) -> Array[Dictionary]:
	var tallies := _event_tallies(events)
	var by_avatar := {}
	for entry: Dictionary in contributions:
		by_avatar[int(entry["avatar_id"])] = entry

	var rows: Array[Dictionary] = []
	for participant: Dictionary in participants:
		var avatar_id := int(participant["avatar_id"])
		var entry: Dictionary = by_avatar.get(avatar_id, {})
		# NOTE: a dead raider keeps their OWN contribution here. Death removes them
		# from the lane SUMS (Contribution.lanes `exclude`), never from their own
		# ratio — otherwise a death would be charged twice: once as the event delta,
		# and again as a collapsed output score. MI-006: one failure, one charge.
		var contribution := float(entry.get("contribution", 0.0))
		var ceiling := float(entry.get("ceiling", 1.0))
		var expected := maxf(0.001, ceiling * _tune(tuning, "reference_realization"))
		var ratio := contribution / expected

		var tally: Dictionary = tallies.get(avatar_id, {})
		var factors := _factors(ratio, tally, tuning)
		var event_delta := 0.0
		for factor: Dictionary in factors:
			if str(factor["code"]) != "output":
				event_delta += float(factor["delta"])
		var raw_rating := 5.5 + (ratio - 1.0) * _tune(tuning, "rating_spread") + event_delta

		(
			rows
			. append(
				{
					"avatar_id": avatar_id,
					"player_id": int(participant["player_id"]),
					"role_assigned": str(participant["role_slug"]),
					"assignment_target": _first_assignment(participant),
					"raw_contribution": roundi(contribution * 10.0),  # x10 keeps a decimal in an int fact
					"performance_rating": clampi(roundi(raw_rating), 1, 10),
					"died": dead_set.has(avatar_id),
					# MI-006 — WHY they got that number. Loot Council (M6) uses ratings
					# as evidence; evidence nobody can explain is just a vibe.
					"rating_factors": factors,
					"rating_summary": summarise(factors),
				}
			)
		)
	return rows


## The breakdown behind one rating: the output judgement first (always present),
## then everything the night actually did — good and bad, including the deaths
## that were NOT the raider's fault, which are shown precisely so the player does
## not read a corpse next to a number and blame the wrong person.
static func _factors(ratio: float, tally: Dictionary, tuning: Dictionary) -> Array[Dictionary]:
	var factors: Array[Dictionary] = []
	(
		factors
		. append(
			{
				"code": "output",
				"label": _output_label(ratio),
				"delta": (ratio - 1.0) * _tune(tuning, "rating_spread"),
				# the raw ratio survives so the night report can AVERAGE it. Without
				# this the report can only tally a raider's failures, never their
				# competence — and the MVP's summary reads as an indictment.
				"value": ratio,
			}
		)
	)
	for outcome: String in _outcome_labels:
		if not tally.has(outcome):
			continue
		var count := int(tally[outcome])
		(
			factors
			. append(
				{
					"code": outcome,
					"label": str(_outcome_labels[outcome]) % count,
					"delta": delta_for(outcome) * count,
				}
			)
		)
	return factors


## One line a guildmaster can read at a glance — and, crucially, argue with.
static func summarise(factors: Array) -> String:
	var parts: Array[String] = []
	for factor: Dictionary in factors:
		parts.append(str(factor["label"]))
	if parts.is_empty():
		return ""
	var text := "; ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1) + "."


static func _output_label(ratio: float) -> String:
	for band: Array in OUTPUT_BANDS:
		if ratio < float(band[0]):
			return str(band[1])
	return str(OUTPUT_BANDS[OUTPUT_BANDS.size() - 1][1])


## What a combat-log outcome does to the raider it happened TO. Public so the
## anti-scapegoat rules are assertable: a failure a raider did not author must
## cost them exactly nothing, and a test says so (MI-005).
static func delta_for(event_outcome: String) -> float:
	return float(_outcome_deltas.get(event_outcome, 0.0))


## {avatar_id: {outcome: count}} over the combat log. Counts, not just a summed
## delta: the breakdown has to be able to say "died twice", and the zero-delta
## outcomes (the deaths that were not the raider's fault) have to survive the trip
## so the report can say so out loud.
static func _event_tallies(events: Array) -> Dictionary:
	var tallies := {}
	for event: Dictionary in events:
		var outcome := str(event.get("outcome", ""))
		if not _outcome_labels.has(outcome):
			continue
		var target := int(event.get("target_avatar_id", 0))
		if target == 0:
			continue
		if not tallies.has(target):
			tallies[target] = {}
		var tally: Dictionary = tallies[target]
		tally[outcome] = int(tally.get(outcome, 0)) + 1
	return tallies


static func _first_assignment(participant: Dictionary) -> String:
	var assignments: Array = participant.get("assignments", [])
	if assignments.is_empty():
		return ""
	return str(assignments[0].get("target", ""))


static func _tune(tuning: Dictionary, key: String) -> float:
	return float(tuning.get(key, DEFAULTS[key]))
