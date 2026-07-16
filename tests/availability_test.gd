extends GdUnitTestSuite

## M5-003 — availability rolls + planning-time raid decisions. Proves availability is
## deterministic and reasoned, the manning check flags undermanning, the readiness
## preview grades each boss from gear, and the four decisions mutate the event.

const SEED := 12345


func _campaign() -> Dictionary:
	var handle := Genesis.new_in_memory({"seed": SEED})
	assert_dict(handle).is_not_empty()
	return handle


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	if db.query_result.is_empty():
		return null
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]


func _roll(db: Variant, event_id: int) -> Dictionary:
	return Availability.roll_for_event(
		db, event_id, RngStream.derive(SEED, "availability").substream(str(event_id))
	)


# --- the pure roll: window gate + reasons -------------------------------------


func test_the_window_gate_excludes_out_of_window_raiders() -> void:
	# a Shift Worker is free afternoon/late but NOT evening — a structural exclusion,
	# decided before any dice
	var life := {
		"display_name": "Shift Worker",
		"availability_window": "afternoon,late",
		"volatility_mod": 25
	}
	var result := Availability.roll(
		"evening", "Bryndar", {"volatility": 50}, life, RngStream.derive(1, "x")
	)
	assert_bool(bool(result["available"])).is_false()
	assert_str(str(result["reason"])).contains("not free in the evening slot")


func test_an_in_window_steady_raider_can_make_it() -> void:
	# Single: free every slot, low volatility -> clears the show-rate comfortably
	var life := {
		"display_name": "Single",
		"availability_window": "afternoon,evening,late",
		"volatility_mod": -10
	}
	# force a passing roll: a stream whose first randf is small enough
	var made_it := false
	for seed_i in 8:
		var r := Availability.roll(
			"evening", "Ryn", {"volatility": 20}, life, RngStream.derive(seed_i, "x")
		)
		if bool(r["available"]):
			made_it = true
	(
		assert_bool(made_it)
		. override_failure_message(
			"a steady, in-window raider never became available across 8 rolls"
		)
		. is_true()
	)


# --- the batch roll: determinism, reasons, trials -----------------------------


func test_availability_is_deterministic_per_seed_and_event() -> void:
	var a := _campaign()
	var b := _campaign()
	var event := int(a["event_id"])
	_roll(a["db"], event)
	_roll(b["db"], event)
	assert_array(_availability_digest(a["db"], event)).is_equal(
		_availability_digest(b["db"], event)
	)
	a["db"].close_db()
	b["db"].close_db()


func test_every_unavailable_row_carries_a_reason() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	_roll(db, int(c["event_id"]))
	db.query(
		(
			"SELECT COUNT(*) AS n FROM event_availability"
			+ " WHERE available = 0 AND (reason IS NULL OR reason = '');"
		)
	)
	(
		assert_int(int(db.query_result[0]["n"]))
		. override_failure_message(
			"some unavailable raiders have no reason — the digest cannot explain them"
		)
		. is_equal(0)
	)
	db.close_db()


func test_trials_are_rollable() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	# make one member a trial — trials remain lineup-eligible (recruitment doc)
	var trial_id := int(
		_scalar(db, "SELECT player_id FROM guild_membership ORDER BY player_id LIMIT 1")
	)
	db.query_with_bindings(
		"UPDATE guild_membership SET status = 'trial' WHERE player_id = ?;", [trial_id]
	)
	_roll(db, int(c["event_id"]))
	(
		assert_int(
			int(
				_scalar(
					db, "SELECT COUNT(*) FROM event_availability WHERE player_id = %d" % trial_id
				)
			)
		)
		. override_failure_message("a trial got no availability roll")
		. is_equal(1)
	)
	db.close_db()


# --- manning ------------------------------------------------------------------


func test_manning_reports_the_available_pool() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	_roll(db, int(c["event_id"]))
	var manning := PrepDecisions.manning(db, int(c["event_id"]))
	assert_int(int(manning["minimum"])).is_equal(20)
	# available must match the rows actually marked available
	var counted := int(_scalar(db, "SELECT COUNT(*) FROM event_availability WHERE available = 1"))
	assert_int(int(manning["available"])).is_equal(counted)
	# short is exactly "fewer than 20 OR a required role missing"
	var roles_missing: Array = manning["roles_missing"]
	var short_expected: bool = int(manning["available"]) < 20 or not roles_missing.is_empty()
	assert_bool(bool(manning["short"])).is_equal(short_expected)
	db.close_db()


# --- readiness preview --------------------------------------------------------


func test_readiness_grades_run_from_ready_to_heavily() -> void:
	# a fresh-guild gear multiplier (~x1.0): Ready on the entry boss, Heavily on the last
	assert_str(PrepDecisions.grade_for(1.0, 1.0)).is_equal(PrepDecisions.GRADE_READY)
	assert_str(PrepDecisions.grade_for(1.0, 1.08)).is_equal(PrepDecisions.GRADE_TIGHT)
	assert_str(PrepDecisions.grade_for(1.0, 1.28)).is_equal(PrepDecisions.GRADE_UNDERGEARED)
	assert_str(PrepDecisions.grade_for(1.0, 1.42)).is_equal(PrepDecisions.GRADE_HEAVILY)


func test_the_preview_grades_every_boss_and_finds_the_gearable_front() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var lineup := PullInputLoader.auto_lineup(db)
	var preview := PrepDecisions.readiness_preview(db, lineup, int(c["season_id"]))
	assert_int(preview.size()).is_equal(4)  # the Emberdeep's four bosses
	# a fresh guild can gear the front (Krogg) but not the end boss (Cinderlords)
	assert_str(str(preview[0]["grade"])).is_equal(PrepDecisions.GRADE_READY)
	assert_str(str(preview[3]["grade"])).is_equal(PrepDecisions.GRADE_HEAVILY)
	# the downshift target is exactly the gearable (Ready/Tight) front
	var subset := PrepDecisions.gearable_subset(db, lineup, int(c["season_id"]))
	assert_bool(subset.has("gatewarden_krogg")).is_true()
	assert_bool(subset.has("cinderlords")).is_false()
	db.close_db()


# --- the four decisions -------------------------------------------------------


func test_cancel_stalls_the_night() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	assert_bool(PrepDecisions.cancel(db, int(c["event_id"]))).is_true()
	(
		assert_str(
			str(
				_scalar(
					db, "SELECT status FROM calendar_event WHERE event_id = %d" % int(c["event_id"])
				)
			)
		)
		. is_equal("cancelled")
	)
	db.close_db()


func test_convert_turns_the_raid_into_a_dungeon() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event := int(c["event_id"])
	assert_bool(PrepDecisions.convert_to_dungeon(db, event)).is_true()
	db.query_with_bindings(
		"SELECT event_type, raid_id FROM calendar_event WHERE event_id = ?;", [event]
	)
	var row: Dictionary = db.query_result[0]
	assert_str(str(row["event_type"])).is_equal("dungeon")
	assert_object(row["raid_id"]).is_null()
	db.close_db()


func test_downshift_records_the_boss_subset() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event := int(c["event_id"])
	(
		assert_bool(PrepDecisions.downshift(db, event, ["gatewarden_krogg", "forgemaster_vell"]))
		. is_true()
	)
	(
		assert_str(
			str(
				_scalar(
					db, "SELECT target_boss_subset FROM calendar_event WHERE event_id = %d" % event
				)
			)
		)
		. is_equal("gatewarden_krogg,forgemaster_vell")
	)
	# the raid stays a raid — downshift is not convert
	(
		assert_str(
			str(_scalar(db, "SELECT event_type FROM calendar_event WHERE event_id = %d" % event))
		)
		. is_equal("raid")
	)
	db.close_db()


func test_run_short_is_a_valid_proceed_with_no_mutation() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event := int(c["event_id"])
	var before := str(_scalar(db, "SELECT status FROM calendar_event WHERE event_id = %d" % event))
	assert_bool(PrepDecisions.run_short(db, event)).is_true()
	# proceeding undermanned changes nothing structural — the lineup just fields fewer
	(
		assert_str(
			str(_scalar(db, "SELECT status FROM calendar_event WHERE event_id = %d" % event))
		)
		. is_equal(before)
	)
	db.close_db()


## Hardening from the M5-003 review: re-rolling an event must not fail on the PK, and
## must leave the DB consistent with what it returns.
func test_rolling_an_event_twice_is_safe_and_consistent() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event := int(c["event_id"])
	var first := _roll(db, event)
	var second := _roll(db, event)  # must not blow up on the (event_id, player_id) PK
	assert_int(int(second["available"])).is_equal(int(first["available"]))
	# the summary matches the rows actually on disk
	var on_disk := int(_scalar(db, "SELECT COUNT(*) FROM event_availability WHERE available = 1"))
	assert_int(int(second["available"])).is_equal(on_disk)
	db.close_db()


## Hardening: plan-time decisions must refuse on a raid that is no longer 'scheduled',
## rather than silently rewriting a night already in progress or completed.
func test_decisions_refuse_on_a_non_scheduled_event() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event := int(c["event_id"])
	db.query_with_bindings(
		"UPDATE calendar_event SET status = 'completed' WHERE event_id = ?;", [event]
	)
	assert_bool(PrepDecisions.cancel(db, event)).is_false()
	assert_bool(PrepDecisions.convert_to_dungeon(db, event)).is_false()
	assert_bool(PrepDecisions.downshift(db, event, ["gatewarden_krogg"])).is_false()
	# the completed raid was not rewritten
	(
		assert_str(
			str(_scalar(db, "SELECT event_type FROM calendar_event WHERE event_id = %d" % event))
		)
		. is_equal("raid")
	)
	db.close_db()


func _availability_digest(db: Variant, event_id: int) -> Array:
	db.query_with_bindings(
		(
			"SELECT player_id, available, reason FROM event_availability"
			+ " WHERE event_id = ? ORDER BY player_id;"
		),
		[event_id]
	)
	return db.query_result.duplicate()
