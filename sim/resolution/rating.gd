class_name RatingEngine
extends RefCounted

## Performance ratings (M3-004 / M3c). FM-style 1-10, RELATIVE to what a
## raider's gear+role should produce — a 6.2, not "43k". Powers Loot MVP,
## morale deltas, and the post-night report.
##
##   expected = ceiling x reference realization (a plain 50-skill raider)
##   ratio    = actual contribution / expected
##   rating   = clamp(round(5.5 + (ratio - 1) x spread + event deltas), 1, 10)
##
## Event deltas read the combat log (by target_avatar_id), so the night's
## STORY moves the number: dying to an avoidable drags it, a clutch save or
## clean duty lifts it. `raw_contribution` is kept alongside for the log.

const DEFAULTS := {
	"rating_spread": 12.0,
	"reference_realization": 0.65,  # skill-50 raider: 0.35 + 0.5 * 0.6
}

## combat-log outcome -> rating delta for the event's target
const _EVENT_DELTAS := {
	"death": -2.0,
	"tank_death": -2.0,
	"duty_fail": -2.0,
	"save": 1.5,
	"duty_ok": 0.5,
	"surge": 0.5,
	"survived": 0.5,
}


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
	var deltas := _event_deltas(events)
	var by_avatar := {}
	for entry: Dictionary in contributions:
		by_avatar[int(entry["avatar_id"])] = entry

	var rows: Array[Dictionary] = []
	for participant: Dictionary in participants:
		var avatar_id := int(participant["avatar_id"])
		var entry: Dictionary = by_avatar.get(avatar_id, {})
		var contribution := float(entry.get("contribution", 0.0))
		var ceiling := float(entry.get("ceiling", 1.0))
		var expected := maxf(0.001, ceiling * _tune(tuning, "reference_realization"))
		var ratio := contribution / expected
		var raw_rating := (
			5.5 + (ratio - 1.0) * _tune(tuning, "rating_spread") + float(deltas.get(avatar_id, 0.0))
		)
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
				}
			)
		)
	return rows


static func _event_deltas(events: Array) -> Dictionary:
	var deltas := {}
	for event: Dictionary in events:
		var delta := float(_EVENT_DELTAS.get(str(event.get("outcome", "")), 0.0))
		if delta == 0.0:
			continue
		var target := int(event.get("target_avatar_id", 0))
		if target == 0:
			continue
		deltas[target] = float(deltas.get(target, 0.0)) + delta
	return deltas


static func _first_assignment(participant: Dictionary) -> String:
	var assignments: Array = participant.get("assignments", [])
	if assignments.is_empty():
		return ""
	return str(assignments[0].get("target", ""))


static func _tune(tuning: Dictionary, key: String) -> float:
	return float(tuning.get(key, DEFAULTS[key]))
