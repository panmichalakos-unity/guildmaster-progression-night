class_name PullResolver
extends RefCounted

## THE resolver (M3-004 / M3c) — implements the M3-001 contract signature:
##
##     PullResolver.resolve(input: Dictionary, rng: RngStream) -> Dictionary
##
## Assembles the full PullResult: Timeline.run (stages 1-4) -> ratings ->
## learning arc -> state deltas -> contract-valid output. Pure; persistence
## is the separate `persist()` below.
##
## LEARNING ARC (the emotional core): `encounter_progress` feeds FORWARD
## (progress bumps familiarity into skill_realization, and shaves event
## severity — fewer avoidable deaths on later attempts) and BACK (this pull's
## outcome updates progress; gains are GATED to hard fights: only margins
## near zero earn learning, farm content short-circuits to 100 on the kill).

const DEFAULTS := {
	"learning_gain_per_attempt": 6.0,
	"learning_gate_band": 30.0,
	"learning_familiarity_rate": 0.3,
	"fatigue_per_pull": 3.0,
	"wipe_extra_fatigue": 1.0,
	"kill_morale": 4.0,
	"wipe_morale": -2.0,
	"death_morale": -1.0,
	"save_morale": 2.0,
	"form_rate": 0.8,
}


## The one entry point. Deterministic given (input, rng).
static func resolve(input: Dictionary, rng: RngStream) -> Dictionary:
	var tuning: Dictionary = input["tuning"]
	var progress_before := float(input["encounter_progress"].get("progress", 0))

	# learning feeds FORWARD: seasoned attempts realize more of the kit
	var effective_input := input.duplicate()
	effective_input["participants"] = _with_learning(input["participants"], progress_before, tuning)

	var timeline := Timeline.run(effective_input, rng)
	var outcome := str(timeline["outcome"])

	var participant_rows := RatingEngine.rate(
		effective_input["participants"],
		timeline["lanes"]["contributions"],
		timeline["events"],
		_dead_set(timeline["deaths"]),
		tuning
	)

	var result := PullContracts.make_result()
	result["pull"] = {
		"outcome": outcome,
		"wipe_reason": str(timeline["wipe_reason"]),
		# MI-002/MI-005: the primary cause is `wipe_reason`; these are the
		# coupled conditions that made it fatal. The report shows both.
		"contributing_factors": timeline["contributing_factors"],
		"duration_sec": _duration(outcome, timeline),
		"attempt_number": int(input["attempt_number"]),
		"boss_hp_pct_at_end": 0 if outcome == "kill" else 100 - int(timeline["progress_pct"]),
	}
	result["participants"] = participant_rows
	result["events"] = timeline["events"]
	result["checks"] = _with_duty_check(timeline["checks"], timeline["events"])
	result["state_deltas"] = {
		"encounter_progress": _progress_delta(input, timeline, tuning),
		"participants": _participant_deltas(participant_rows, outcome, timeline, tuning),
	}
	result["drops_loot"] = outcome == "kill"
	return result


## Persists the fact rows for a resolved pull: pull + pull_participant +
## pull_event, and upserts guild_encounter_progress. State deltas
## (morale/fatigue/form) are RETURNED, not applied — the campaign layer (M5)
## owns player_week_state. Returns the new pull_id, or -1 on failure.
static func persist(
	db: Variant, guild_id: int, event_id: int, encounter_id: int, result: Dictionary
) -> int:
	var pull: Dictionary = result["pull"]
	db.query("BEGIN TRANSACTION;")
	if not (
		db
		. query_with_bindings(
			(
				"INSERT INTO pull (event_id, encounter_id, attempt_number, outcome,"
				+ " duration_sec, wipe_reason) VALUES (?, ?, ?, ?, ?, ?);"
			),
			[
				event_id,
				encounter_id,
				pull["attempt_number"],
				pull["outcome"],
				pull["duration_sec"],
				null if str(pull["wipe_reason"]).is_empty() else pull["wipe_reason"],
			]
		)
	):
		return _rollback(db, "pull insert: %s" % db.error_message)
	db.query("SELECT last_insert_rowid() AS id;")
	var pull_id := int(db.query_result[0]["id"])

	for row: Dictionary in result["participants"]:
		if not (
			db
			. query_with_bindings(
				(
					"INSERT INTO pull_participant (pull_id, avatar_id, role_assigned,"
					+ " assignment_target, raw_contribution, performance_rating)"
					+ " VALUES (?, ?, (SELECT role_id FROM role WHERE slug = ?), ?, ?, ?);"
				),
				[
					pull_id,
					row["avatar_id"],
					row["role_assigned"],
					row["assignment_target"],
					row["raw_contribution"],
					row["performance_rating"],
				]
			)
		):
			return _rollback(db, "pull_participant insert: %s" % db.error_message)

	for event: Dictionary in result["events"]:
		var target: Variant = (
			null if int(event["target_avatar_id"]) == 0 else event["target_avatar_id"]
		)
		if not (
			db
			. query_with_bindings(
				(
					"INSERT INTO pull_event (pull_id, phase_id, target_avatar_id,"
					+ " sequence_no, roll_result, outcome, log_line)"
					+ " VALUES (?, NULL, ?, ?, ?, ?, ?);"
				),
				[
					pull_id,
					target,
					event["sequence_no"],
					event["roll_result"],
					event["outcome"],
					event["log_line"],
				]
			)
		):
			return _rollback(db, "pull_event insert: %s" % db.error_message)

	var progress: Dictionary = result["state_deltas"]["encounter_progress"]
	var first_kill_at: Variant = null
	if str(result["pull"]["outcome"]) == "kill":
		# audit timestamp (like schema_migration.applied_at) — persist() is the
		# side-effect layer; the deterministic result never contains wall-clock
		first_kill_at = Time.get_datetime_string_from_system(true)
	if not (
		db
		. query_with_bindings(
			(
				"INSERT INTO guild_encounter_progress (guild_id, encounter_id, progress,"
				+ " attempt_count, best_attempt_pct, first_kill_at)"
				+ " VALUES (?, ?, ?, ?, ?, ?)"
				+ " ON CONFLICT(guild_id, encounter_id) DO UPDATE SET"
				+ " progress = excluded.progress, attempt_count = excluded.attempt_count,"
				+ " best_attempt_pct = excluded.best_attempt_pct,"
				+ " first_kill_at = COALESCE(guild_encounter_progress.first_kill_at,"
				+ " excluded.first_kill_at);"
			),
			[
				guild_id,
				encounter_id,
				progress["progress"],
				progress["attempt_count"],
				progress["best_attempt_pct"],
				first_kill_at,
			]
		)
	):
		return _rollback(db, "progress upsert: %s" % db.error_message)
	db.query("COMMIT;")
	return pull_id


# --- learning arc ---------------------------------------------------------------


## Progress bumps familiarity (skill_realization's 25% input) — attempts teach.
static func _with_learning(participants: Array, progress: float, tuning: Dictionary) -> Array:
	if progress <= 0.0:
		return participants
	var rate := _tune(tuning, "learning_familiarity_rate")
	var boosted := []
	for participant: Dictionary in participants:
		var copy: Dictionary = participant.duplicate(true)
		copy["familiarity"] = clampi(roundi(float(copy["familiarity"]) + progress * rate), 0, 95)
		boosted.append(copy)
	return boosted


## The pull's learning outcome. Kill -> 100. Wipe -> gain gated by how CLOSE
## the contested check was: |margin| at the gate band or beyond earns nothing
## (farm content and hopeless content both short-circuit), margin near zero
## earns full gain — the "8%... 3%... KILL" arc is reserved for earned fights.
static func _progress_delta(
	input: Dictionary, timeline: Dictionary, tuning: Dictionary
) -> Dictionary:
	var before: Dictionary = input["encounter_progress"]
	var attempt_count := int(before.get("attempt_count", 0)) + 1
	var best := maxi(int(before.get("best_attempt_pct", 0)), int(timeline["progress_pct"]))
	if str(timeline["outcome"]) == "kill":
		return {"progress": 100, "attempt_count": attempt_count, "best_attempt_pct": 100}

	var blocking_margin := _blocking_margin(timeline["checks"])
	var band := _tune(tuning, "learning_gate_band")
	var closeness := 1.0 - clampf(absf(blocking_margin) / band, 0.0, 1.0)
	var gain := _tune(tuning, "learning_gain_per_attempt") * closeness
	return {
		"progress": clampi(roundi(float(before.get("progress", 0)) + gain), 0, 99),
		"attempt_count": attempt_count,
		"best_attempt_pct": best,
	}


## The WALL: the worst failed margin. A fight is only "close" (learnable)
## when EVERY failing axis is nearly passing — one hopeless wall means the
## attempts teach nothing, however near the other checks were.
static func _blocking_margin(checks: Array) -> float:
	var worst := 0.0
	for check: Dictionary in checks:
		if not bool(check["passed"]):
			worst = maxf(worst, absf(float(check["margin"])))
	return worst


# --- state deltas -----------------------------------------------------------------


static func _participant_deltas(
	rows: Array[Dictionary], outcome: String, timeline: Dictionary, tuning: Dictionary
) -> Array[Dictionary]:
	var save_targets := {}
	for event: Dictionary in timeline["events"]:
		if str(event["outcome"]) == Timeline.OUTCOME_SAVE:
			save_targets[int(event["target_avatar_id"])] = true

	var deltas: Array[Dictionary] = []
	for row: Dictionary in rows:
		var morale := (
			_tune(tuning, "kill_morale") if outcome == "kill" else _tune(tuning, "wipe_morale")
		)
		if bool(row["died"]):
			morale += _tune(tuning, "death_morale")
		if save_targets.has(int(row["avatar_id"])):
			morale += _tune(tuning, "save_morale")
		var fatigue := _tune(tuning, "fatigue_per_pull")
		if outcome == "wipe":
			fatigue += _tune(tuning, "wipe_extra_fatigue")
		(
			deltas
			. append(
				{
					"player_id": int(row["player_id"]),
					"morale_delta": roundi(morale),
					"fatigue_delta": roundi(fatigue),
					"form_delta":
					roundi((float(row["performance_rating"]) - 5.5) * _tune(tuning, "form_rate")),
				}
			)
		)
	return deltas


# --- assembly helpers ---------------------------------------------------------------


## Synthesizes the assigned_duty check row from the night's duty events, so
## the checks[] surface covers the full doc catalogue when duties fired.
static func _with_duty_check(checks: Array, events: Array) -> Array:
	var successes := 0
	var failures := 0
	for event: Dictionary in events:
		match str(event.get("outcome", "")):
			Timeline.OUTCOME_DUTY_OK:
				successes += 1
			Timeline.OUTCOME_DUTY_FAIL:
				failures += 1
	if successes + failures == 0:
		return checks
	var combined := checks.duplicate()
	(
		combined
		. append(
			{
				"check": "assigned_duty",
				"margin": float((successes - failures) * 10),
				"passed": failures == 0,
				"detail": "duties: %d handled, %d missed" % [successes, failures],
			}
		)
	)
	return combined


## Symbolic but deterministic pull length: decisive kills are quick, long
## wipes are the ones that ALMOST happened.
static func _duration(outcome: String, timeline: Dictionary) -> int:
	if outcome == "kill":
		var dps_margin := 0.0
		for check: Dictionary in timeline["checks"]:
			if str(check["check"]) == "dps":
				dps_margin = float(check["margin"])
		return roundi(300.0 - clampf(dps_margin, 0.0, 60.0) * 2.0)
	return roundi(60.0 + float(timeline["progress_pct"]) * 2.2)


static func _dead_set(deaths: Array) -> Dictionary:
	var dead := {}
	for avatar_id in deaths:
		dead[int(avatar_id)] = true
	return dead


static func _rollback(db: Variant, message: String) -> int:
	push_error("PullResolver: persist failed: %s" % message)
	db.query("ROLLBACK;")
	return -1


static func _tune(tuning: Dictionary, key: String) -> float:
	return float(tuning.get(key, DEFAULTS[key]))
