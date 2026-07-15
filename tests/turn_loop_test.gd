extends GdUnitTestSuite

## M5-002 — the weekly calendar + turn loop. Proves "continue" stops on events,
## ticks empty days deterministically, rolls weeks, ends the season at its last week,
## and keeps ALL progression in the save (never UI-only state).

const SEED := 12345


func _campaign() -> Dictionary:
	var handle := Genesis.new_in_memory({"seed": SEED})
	assert_dict(handle).is_not_empty()
	return handle


# --- stopping on events -------------------------------------------------------


func test_advance_stops_on_the_week_one_raid() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var result := TurnLoop.advance(db)

	assert_str(str(result["kind"])).is_equal("event")
	assert_str(str(result["event"]["event_type"])).is_equal("raid")
	assert_int(int(result["event"]["day"])).is_equal(3)
	# the days before the raid were empty and got ticked
	assert_array(result["empty_days_ticked"]).is_equal([1, 2])
	# and the cursor + phase moved, persisted to the save
	var state := GameState.read(db)
	assert_int(int(state["current_day"])).is_equal(3)
	assert_str(str(state["phase"])).is_equal("raid")
	db.close_db()


func test_you_cannot_advance_past_an_unresolved_event() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	TurnLoop.advance(db)  # stop on the raid (now in_progress)
	var blocked := TurnLoop.advance(db)
	(
		assert_str(str(blocked["kind"]))
		. override_failure_message("the loop advanced past a raid that was never played")
		. is_equal("blocked")
	)
	db.close_db()


func test_completing_the_event_frees_the_loop_and_rolls_the_week() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var raid := TurnLoop.advance(db)
	assert_bool(TurnLoop.complete_event(db, int(raid["event"]["event_id"]))).is_true()

	# week 1 (genesis) has only the raid, so the next advance rolls the week
	var rolled := TurnLoop.advance(db)
	assert_str(str(rolled["kind"])).is_equal("week_rolled")
	assert_int(int(rolled["week_number"])).is_equal(2)

	# the new week has a freshly built default calendar (a raid + a rest night)
	var events := Calendar.pending_events(db, int(rolled["week_id"]))
	var types := {}
	for e: Dictionary in events:
		types[str(e["event_type"])] = true
	assert_bool(types.has("raid")).is_true()
	assert_bool(types.has("rest")).is_true()
	db.close_db()


# --- empty-day recovery -------------------------------------------------------


func test_empty_days_recover_fatigue_deterministically() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var state := GameState.read(db)
	var week_id := int(state["week_id"])
	WeekState.ensure(db, week_id)

	# put some fatigue on the roster so recovery has something to shed
	db.query_with_bindings(
		"UPDATE player_week_state SET fatigue = 10 WHERE week_id = ?;", [week_id]
	)
	var recovery := int(Tuning.section("calendar").get("empty_day_fatigue_recovery", 4))
	WeekState.tick_recovery(db, week_id, recovery)

	for row: Dictionary in WeekState.read(db, week_id):
		assert_int(int(row["fatigue"])).is_equal(10 - recovery)
	db.close_db()


func test_recovery_never_goes_below_zero() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_id := int(GameState.read(db)["week_id"])
	WeekState.ensure(db, week_id)
	# fatigue defaults to 0; ticking must not push it negative
	WeekState.tick_recovery(db, week_id, 4)
	for row: Dictionary in WeekState.read(db, week_id):
		assert_int(int(row["fatigue"])).is_equal(0)
	db.close_db()


# --- rolling and the season boundary ------------------------------------------


func test_the_season_ends_after_its_last_week() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var season_length := int(
		_scalar(db, "SELECT season_length_weeks FROM expansion WHERE expansion_id = 1")
	)

	var kind := ""
	var guard := 0
	while kind != "season_complete" and guard < season_length * 6:
		guard += 1
		var result := TurnLoop.advance(db)
		kind = str(result["kind"])
		if kind == "event":
			TurnLoop.complete_event(db, int(result["event"]["event_id"]))

	(
		assert_str(kind)
		. override_failure_message(
			"the season never completed within %d weeks of stepping" % season_length
		)
		. is_equal("season_complete")
	)
	# no week beyond the season length was created
	assert_int(int(_scalar(db, "SELECT MAX(week_number) FROM week"))).is_equal(season_length)
	assert_str(str(GameState.read(db)["phase"])).is_equal("grade")
	db.close_db()


# --- determinism + persistence ------------------------------------------------


func test_the_loop_is_deterministic() -> void:
	assert_str(_transcript()).is_equal(_transcript())


func test_progression_is_persisted_not_held_in_memory() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	TurnLoop.advance(db)
	# read GAME_STATE and the event status straight from the DB — nothing cached
	assert_int(int(GameState.read(db)["current_day"])).is_equal(3)
	(
		assert_int(
			int(_scalar(db, "SELECT COUNT(*) FROM calendar_event WHERE status = 'in_progress'"))
		)
		. is_equal(1)
	)
	db.close_db()


func _transcript() -> String:
	var c := _campaign()
	var db: Variant = c["db"]
	var lines: PackedStringArray = []
	for _step in 12:
		var result := TurnLoop.advance(db)
		lines.append(str(result["kind"]) + ":" + str(result.get("empty_days_ticked", [])))
		if str(result["kind"]) == "event":
			TurnLoop.complete_event(db, int(result["event"]["event_id"]))
		elif str(result["kind"]) == "season_complete":
			break
	db.close_db()
	return "\n".join(lines)


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	if db.query_result.is_empty():
		return null
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]
