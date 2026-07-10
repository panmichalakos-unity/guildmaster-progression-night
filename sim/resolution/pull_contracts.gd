class_name PullContracts
extends RefCounted

## Pull resolver API boundary (M3-001). Contracts only — the math lands in
## M3-002 (lanes/checks), M3-003 (timeline/events), M3-004 (ratings/state).
##
## THE ONE SIGNATURE every M3 task implements against and M4 consumes:
##
##     PullResolver.resolve(input: Dictionary, rng: RngStream) -> Dictionary
##
## `input` is a PullInput (validate_input), the result is a PullResult
## (validate_result). Both are plain Dictionaries: pure data, no DB, no
## scene tree — callers load/persist them (genesis, harness, M4 UI).
## Output keys are named after the data-model facts they map to:
## PULL, PULL_PARTICIPANT, PULL_EVENT, GUILD_ENCOUNTER_PROGRESS.
##
## Resolution doc trace (docs/guildmaster-resolution.md):
##   stage 1 contribution     <- participants[] skill/gear/state fields
##   stage 2 lane aggregation <- role_slug + the healing-demand coupling inputs
##   stage 3 checks           <- encounter dps_check/healing_check + result.checks[]
##   stage 4 timeline         <- phases[]/events[] -> result.events[] (PULL_EVENT)
##   stage 5 state writes     <- result.participants[] ratings + state_deltas

const OUTCOMES := ["kill", "wipe"]
const ROLES := ["tank", "healer", "melee", "ranged"]
const TARGET_SELECTORS := ["tank", "healer", "melee", "ranged", "random", "assigned"]
const CHECK_KINDS := ["dps", "healing", "tank", "mechanic", "assigned_duty"]

## PullInput required keys (see _INPUT_SPEC for nesting):
##   encounter:  slug, dps_check, healing_check, difficulty, phase_count
##   phases:     [{slug, phase_order, entry_condition}]
##   events:     [{slug, phase_order, event_type_slug, trigger,
##                 target_selector (already COALESCEd placement->type),
##                 roll_attribute, effect_category, log_template,
##                 severity, weight}]
##   participants: one per NON-BENCHED lineup member:
##               {avatar_id, player_id, handle, role_slug, spec_slug,
##                spec_difficulty, gear_score, item_level, familiarity,
##                hit_capped, uncrittable, execution, awareness, consistency,
##                role_proficiency, morale, fatigue, form,
##                assignments: [{assignment_type, target}],
##                consumables: [{slug, tier}]}
##   encounter_progress: {progress, attempt_count, best_attempt_pct}
##   attempt_number: int (>=1)
##   tuning: the resolution section of tuning.json

const _PARTICIPANT_INT_FIELDS: Array[String] = [
	"avatar_id",
	"player_id",
	"spec_difficulty",
	"gear_score",
	"item_level",
	"familiarity",
	"execution",
	"awareness",
	"consistency",
	"role_proficiency",
	"morale",
	"fatigue",
	"form",
]


## Empty-but-valid input skeleton; fixtures/loaders fill it in.
static func make_input() -> Dictionary:
	return {
		"encounter":
		{"slug": "", "dps_check": 0, "healing_check": 0, "difficulty": 0, "phase_count": 1},
		"phases": [],
		"events": [],
		"participants": [],
		"encounter_progress": {"progress": 0, "attempt_count": 0, "best_attempt_pct": 0},
		"attempt_number": 1,
		"tuning": {},
	}


## Validates a PullInput. Returns [] when valid, else human-readable errors.
static func validate_input(input: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in [
		"encounter",
		"phases",
		"events",
		"participants",
		"encounter_progress",
		"attempt_number",
		"tuning"
	]:
		if not input.has(key):
			errors.append("input missing key '%s'" % key)
	if not errors.is_empty():
		return errors

	var encounter: Dictionary = input["encounter"]
	for key in ["slug", "dps_check", "healing_check", "difficulty", "phase_count"]:
		if not encounter.has(key):
			errors.append("encounter missing '%s'" % key)
	if str(encounter.get("slug", "")).is_empty():
		errors.append("encounter.slug is empty")

	if input["participants"].is_empty():
		errors.append("participants is empty — a pull needs a lineup")
	var seen_avatars := {}
	for p: Dictionary in input["participants"]:
		var who := str(p.get("handle", "?"))
		for field in _PARTICIPANT_INT_FIELDS:
			if not p.has(field):
				errors.append("participant %s missing '%s'" % [who, field])
		if str(p.get("role_slug", "")) not in ROLES:
			errors.append("participant %s has bad role_slug '%s'" % [who, p.get("role_slug")])
		if not p.has("assignments") or not p.has("consumables"):
			errors.append("participant %s missing assignments/consumables arrays" % who)
		if not p.has("hit_capped") or not p.has("uncrittable"):
			errors.append("participant %s missing cap flags" % who)
		if seen_avatars.has(p.get("avatar_id")):
			errors.append("duplicate avatar_id %s in participants" % p.get("avatar_id"))
		seen_avatars[p.get("avatar_id")] = true

	var phase_orders := {}
	for phase: Dictionary in input["phases"]:
		phase_orders[int(phase.get("phase_order", -1))] = true
	for event: Dictionary in input["events"]:
		if not phase_orders.has(int(event.get("phase_order", -1))):
			errors.append(
				(
					"event '%s' references phase_order %s with no phase row"
					% [event.get("slug", "?"), event.get("phase_order")]
				)
			)
		if str(event.get("target_selector", "")) not in TARGET_SELECTORS:
			errors.append(
				(
					"event '%s' has bad target_selector '%s'"
					% [event.get("slug", "?"), event.get("target_selector")]
				)
			)
	if int(input["attempt_number"]) < 1:
		errors.append("attempt_number must be >= 1")
	return errors


## PullResult required shape (maps 1:1 onto the fact tables):
##   pull:        {outcome: kill|wipe, wipe_reason: String ("" on kill —
##                 names check AND culprit on wipe), duration_sec,
##                 attempt_number, boss_hp_pct_at_end}
##   participants:[{avatar_id, player_id, role_assigned, assignment_target,
##                 raw_contribution, performance_rating 1..10, died: bool}]
##   events:      [{sequence_no (1..N unique), encounter_event_slug ("" for
##                 engine-emitted beats), phase_order, target_avatar_id (0 =
##                 raid-wide), roll_result, outcome, log_line}]
##   checks:      [{check: CHECK_KINDS, margin: float, passed: bool,
##                 detail: String}]  — the legible-failure surface; the
##                 why-view (M7-005) and wipe_reason derive from it
##   state_deltas:{encounter_progress: {progress, attempt_count,
##                 best_attempt_pct}, participants: [{player_id,
##                 morale_delta, fatigue_delta, form_delta}]}
##   drops_loot:  bool (kill only; item selection is the loot system's job)
static func make_result() -> Dictionary:
	return {
		"pull":
		{
			"outcome": "wipe",
			"wipe_reason": "",
			"duration_sec": 0,
			"attempt_number": 1,
			"boss_hp_pct_at_end": 100,
		},
		"participants": [],
		"events": [],
		"checks": [],
		"state_deltas":
		{
			"encounter_progress": {"progress": 0, "attempt_count": 0, "best_attempt_pct": 0},
			"participants": [],
		},
		"drops_loot": false,
	}


## Validates a PullResult. Returns [] when valid, else human-readable errors.
static func validate_result(result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in ["pull", "participants", "events", "checks", "state_deltas", "drops_loot"]:
		if not result.has(key):
			errors.append("result missing key '%s'" % key)
	if not errors.is_empty():
		return errors

	var pull: Dictionary = result["pull"]
	var outcome := str(pull.get("outcome", ""))
	if outcome not in OUTCOMES:
		errors.append("pull.outcome '%s' not in %s" % [outcome, OUTCOMES])
	if outcome == "wipe" and str(pull.get("wipe_reason", "")).is_empty():
		errors.append("wipe without wipe_reason — legible failure is the engine")
	if outcome == "kill" and not str(pull.get("wipe_reason", "")).is_empty():
		errors.append("kill must not carry a wipe_reason")
	if outcome == "kill" and not bool(result["drops_loot"]):
		errors.append("kill must set drops_loot")

	for p: Dictionary in result["participants"]:
		var rating := int(p.get("performance_rating", 0))
		if rating < 1 or rating > 10:
			errors.append(
				(
					"participant %s performance_rating %d out of 1..10"
					% [p.get("avatar_id", "?"), rating]
				)
			)
		for field in ["avatar_id", "player_id", "role_assigned", "raw_contribution", "died"]:
			if not p.has(field):
				errors.append("result participant missing '%s'" % field)

	var seen_sequence := {}
	for event: Dictionary in result["events"]:
		var sequence := int(event.get("sequence_no", -1))
		if seen_sequence.has(sequence):
			errors.append("duplicate event sequence_no %d" % sequence)
		seen_sequence[sequence] = true
		if str(event.get("log_line", "")).is_empty():
			errors.append("event %d has no log_line — the feed is the show" % sequence)

	for check: Dictionary in result["checks"]:
		if str(check.get("check", "")) not in CHECK_KINDS:
			errors.append("unknown check kind '%s'" % check.get("check"))

	var deltas: Dictionary = result["state_deltas"]
	if not deltas.has("encounter_progress") or not deltas.has("participants"):
		errors.append("state_deltas needs encounter_progress + participants")
	return errors
