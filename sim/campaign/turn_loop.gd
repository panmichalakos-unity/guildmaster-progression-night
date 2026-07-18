class_name TurnLoop
extends RefCounted

## The weekly turn loop (M5-002). FM-style "continue": advance from where the cursor
## sits to the next scheduled event, ticking recovery across the empty days in
## between, and stop ON the event (raid / dungeon / rest / social) for the player to
## resolve. When a week runs out of events, roll to the next — until the season's
## last week, where the loop stops for grading (M9).
##
## Progression lives entirely in the save (GAME_STATE cursor + CALENDAR_EVENT
## status) — no UI-only state owns it, and no wall clock. Deterministic given the DB.
##
##   advance(db, rng)   -> {kind, ...}   one "continue" step
##   complete_event(db, event_id)        the player finished the current event
##
## advance() result kinds:
##   event           stopped on an event now in_progress {event, empty_days_ticked}
##   blocked         an event is still in_progress — finish it first {event}
##   week_rolled     the week's events are done; a new week was built {week_number, week_id}
##   season_complete the final week is done; grading is next (M9) {}

const RAID_PHASES := {"raid": true, "dungeon": true}


## One "continue" step. See the result kinds above.
static func advance(db: Variant, _rng: RngStream = null) -> Dictionary:
	var state := GameState.read(db)
	if state.is_empty():
		return {"kind": "error", "detail": "no campaign"}
	# the season is played out — grading (M9) owns what happens next. Without this
	# guard every further "continue" re-ticked the final week's tail-day recovery,
	# silently melting the very snapshot season grading will read (M5-005 review).
	if str(state["phase"]) == "grade":
		return {"kind": "season_complete", "empty_days_ticked": []}
	var week_id := int(state["week_id"])
	var current_day := int(state["current_day"])
	var recovery := int(Tuning.section("calendar").get("empty_day_fatigue_recovery", 4))

	# genesis leaves week 1 un-snapshotted; whoever steps first seeds it (idempotent)
	WeekState.ensure(db, week_id)

	# you cannot advance past an event you have not resolved
	var pending := Calendar.pending_events(db, week_id)
	for event: Dictionary in pending:
		if str(event["status"]) == "in_progress":
			return {"kind": "blocked", "event": event}

	# the next thing to stop on is the earliest still-scheduled event this week
	if not pending.is_empty():
		var event: Dictionary = pending[0]
		var event_day := int(event["day"])
		var ticked := _tick_empty_days(db, week_id, current_day + 1, event_day - 1, recovery)
		_set_event_status(db, int(event["event_id"]), "in_progress")
		var phase := "raid" if RAID_PHASES.has(str(event["event_type"])) else "plan"
		_move_cursor(db, event_day, phase)
		event["status"] = "in_progress"
		return {"kind": "event", "event": event, "empty_days_ticked": ticked}

	# no events left this week — tick the tail of the week, then roll or end the season
	var tail := _tick_empty_days(db, week_id, current_day + 1, 7, recovery)
	return _roll_week(db, state, tail)


## The player finished the current event; free the loop to advance again. Also flips
## the phase out of 'raid' so the next advance is clean.
static func complete_event(db: Variant, event_id: int, status: String = "completed") -> bool:
	if not _set_event_status(db, event_id, status):
		return false
	db.query("UPDATE game_state SET phase = 'plan' WHERE game_id = 1;")
	return true


# --- internals ----------------------------------------------------------------


## Ticks recovery for every day in [from_day, to_day] that has no scheduled event,
## and returns the list of days actually ticked (empty days), for the log.
static func _tick_empty_days(
	db: Variant, week_id: int, from_day: int, to_day: int, recovery: int
) -> Array:
	var ticked: Array[int] = []
	for day in range(maxi(1, from_day), to_day + 1):
		db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM calendar_event WHERE week_id = ? AND day = ?;",
			[week_id, day]
		)
		if int(db.query_result[0]["n"]) == 0:
			WeekState.tick_recovery(db, week_id, recovery)
			ticked.append(day)
	return ticked


static func _set_event_status(db: Variant, event_id: int, status: String) -> bool:
	return db.query_with_bindings(
		"UPDATE calendar_event SET status = ? WHERE event_id = ?;", [status, event_id]
	)


static func _move_cursor(db: Variant, day: int, phase: String) -> void:
	db.query_with_bindings(
		"UPDATE game_state SET current_day = ?, phase = ? WHERE game_id = 1;", [day, phase]
	)


## Roll to the next week, or end the season if this was its last week. The season
## length is a property of the expansion (Season = Tier).
static func _roll_week(db: Variant, state: Dictionary, tail_ticked: Array) -> Dictionary:
	var week_id := int(state["week_id"])
	var season_id := int(state["season_id"])
	db.query_with_bindings("SELECT week_number FROM week WHERE week_id = ?;", [week_id])
	var week_number := int(db.query_result[0]["week_number"])

	db.query_with_bindings(
		"SELECT season_length_weeks FROM expansion WHERE expansion_id = ?;",
		[int(state["expansion_id"])]
	)
	var season_length := int(db.query_result[0]["season_length_weeks"])

	if week_number >= season_length:
		# the tier is played out — grading, sacking and Season 2 are M9
		db.query("UPDATE game_state SET phase = 'grade' WHERE game_id = 1;")
		return {"kind": "season_complete", "empty_days_ticked": tail_ticked}

	# create next week, carry state forward, lay out its default calendar
	if not db.query_with_bindings(
		"INSERT INTO week (season_id, week_number) VALUES (?, ?);", [season_id, week_number + 1]
	):
		return {"kind": "error", "detail": "week insert failed: %s" % db.error_message}
	db.query("SELECT last_insert_rowid() AS id;")
	var new_week_id := int(db.query_result[0]["id"])

	WeekState.ensure(db, new_week_id, week_id)
	if Calendar.build_default_week(db, new_week_id, season_id) < 0:
		return {"kind": "error", "detail": "could not build the next week's calendar"}

	db.query_with_bindings(
		"UPDATE game_state SET week_id = ?, current_day = 0, phase = 'plan' WHERE game_id = 1;",
		[new_week_id]
	)
	return {
		"kind": "week_rolled",
		"week_number": week_number + 1,
		"week_id": new_week_id,
		"empty_days_ticked": tail_ticked,
	}
