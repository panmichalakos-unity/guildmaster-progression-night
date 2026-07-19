extends GdUnitTestSuite

## M5-007 — the bench has a cost. Consecutive benchings of AVAILABLE raiders
## charge morale (into the new week's snapshot) and current loyalty, scaled by
## ego, at week roll. The digest reports exactly what the roll applied — one
## shared function, so they cannot disagree. Deterministic throughout.

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


## Two completed, lineup-recorded raids in week 1, benching everyone outside the
## auto-lineup twice. Returns the fielded lineup.
func _two_sat_out_nights(c: Dictionary) -> Array[int]:
	var db: Variant = c["db"]
	var raid_id := int(_scalar(db, "SELECT raid_id FROM raid ORDER BY raid_id LIMIT 1"))
	var second := Calendar.schedule(db, int(c["week_id"]), 5, "evening", "raid", raid_id)
	var full := PullInputLoader.auto_lineup(db)
	for event_id in [int(c["event_id"]), second]:
		assert_bool(RaidPrep.persist_lineup(db, event_id, full)).is_true()
		db.query_with_bindings(
			"UPDATE calendar_event SET status = 'completed' WHERE event_id = ?;", [event_id]
		)
	return full


## Drive the turn loop to the week roll (the two raids are already completed, so
## it stops only on the rest night). Returns the new week's id.
func _roll_the_week(db: Variant) -> int:
	var guard := 0
	while guard < 8:
		guard += 1
		var advanced := TurnLoop.advance(db)
		var kind := str(advanced["kind"])
		if kind == "event":
			TurnLoop.complete_event(db, int(advanced["event"]["event_id"]))
		elif kind == "week_rolled":
			return int(advanced["week_id"])
		else:
			fail("unexpected advance kind '%s'" % kind)
			return -1
	fail("the week never rolled")
	return -1


func test_the_week_roll_charges_exactly_what_assess_prices() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_one := int(c["week_id"])
	var lineup := _two_sat_out_nights(c)

	var priced := BenchCost.assess(db, week_one)
	assert_array(priced).is_not_empty()
	var loyalty_before := {}
	for row: Dictionary in priced:
		loyalty_before[int(row["player_id"])] = int(
			_scalar(
				db,
				"SELECT loyalty_current FROM player WHERE player_id = %d" % int(row["player_id"])
			)
		)

	var week_two := _roll_the_week(db)
	assert_int(week_two).is_greater(0)

	for row: Dictionary in priced:
		var player_id := int(row["player_id"])
		var morale := int(
			_scalar(
				db,
				(
					"SELECT morale FROM player_week_state WHERE week_id = %d AND player_id = %d"
					% [week_two, player_id]
				)
			)
		)
		(
			assert_int(morale)
			. override_failure_message(
				(
					"%s (streak %d) should open the week at 50 - %d morale"
					% [row["handle"], int(row["streak"]), int(row["morale_ding"])]
				)
			)
			. is_equal(50 - int(row["morale_ding"]))
		)
		var loyalty := int(
			_scalar(db, "SELECT loyalty_current FROM player WHERE player_id = %d" % player_id)
		)
		assert_int(loyalty).is_equal(int(loyalty_before[player_id]) - int(row["loyalty_ding"]))

	# a fielded raider pays nothing, in either currency
	var fielded_player := int(
		_scalar(db, "SELECT player_id FROM avatar WHERE avatar_id = %d" % int(lineup[0]))
	)
	(
		assert_int(
			int(
				_scalar(
					db,
					(
						"SELECT morale FROM player_week_state WHERE week_id = %d AND player_id = %d"
						% [week_two, fielded_player]
					)
				)
			)
		)
		. is_equal(50)
	)
	db.close_db()


func test_one_sit_is_free_and_the_unavailable_are_never_charged() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_one := int(c["week_id"])
	# mark one roster player unavailable for the night, then field the auto-lineup:
	# they get NO lineup row (attendance vs participation) on the ONLY completed raid
	Availability.roll_for_event(db, int(c["event_id"]), RngStream.derive(SEED, "availability"))
	db.query_with_bindings(
		"UPDATE event_availability SET available = 1, reason = '' WHERE event_id = ?;",
		[int(c["event_id"])]
	)
	var full := PullInputLoader.auto_lineup(db)
	var absent := int(
		_scalar(
			db,
			(
				(
					"SELECT a.player_id FROM avatar a WHERE a.is_active = 1"
					+ " AND a.avatar_id NOT IN (%s) ORDER BY a.avatar_id LIMIT 1"
				)
				% ", ".join(full.map(func(i): return str(i)))
			)
		)
	)
	db.query_with_bindings(
		(
			"UPDATE event_availability SET available = 0, reason = 'test'"
			+ " WHERE event_id = ? AND player_id = ?;"
		),
		[int(c["event_id"]), absent]
	)
	assert_bool(RaidPrep.persist_lineup(db, int(c["event_id"]), full)).is_true()
	db.query_with_bindings(
		"UPDATE calendar_event SET status = 'completed' WHERE event_id = ?;", [int(c["event_id"])]
	)

	# every streak is exactly 1 (one completed night) — nobody is priced, and the
	# unavailable raider does not even hold a streak
	assert_array(BenchCost.assess(db, week_one)).is_empty()
	for row: Dictionary in BenchCost.streaks(db, week_one):
		assert_int(int(row["player_id"])).is_not_equal(absent)
	db.close_db()


func test_ego_scales_the_price_of_the_same_streak() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_one := int(c["week_id"])
	_two_sat_out_nights(c)

	var priced := BenchCost.assess(db, week_one)
	assert_bool(priced.size() >= 2).is_true()
	var diva := int(priced[0]["player_id"])
	var stoic := int(priced[1]["player_id"])
	db.query_with_bindings("UPDATE player SET ego = 90 WHERE player_id = ?;", [diva])
	db.query_with_bindings("UPDATE player SET ego = 10 WHERE player_id = ?;", [stoic])

	var by_player := {}
	for row: Dictionary in BenchCost.assess(db, week_one):
		by_player[int(row["player_id"])] = row
	# streak 2: morale 2*2*(0.5 + ego/100) -> 6 for ego 90, 2 for ego 10
	assert_int(int(by_player[diva]["morale_ding"])).is_equal(6)
	assert_int(int(by_player[stoic]["morale_ding"])).is_equal(2)
	assert_int(int(by_player[diva]["loyalty_ding"])).is_greater(
		int(by_player[stoic]["loyalty_ding"])
	)
	db.close_db()


func test_the_digest_reports_the_same_numbers_the_roll_applies() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_one := int(c["week_id"])
	_two_sat_out_nights(c)
	_roll_the_week(db)

	var digest_costs: Array = Digest.build(db, week_one)["roster"]["bench_costs"]
	var assessed := BenchCost.assess(db, week_one)
	assert_str(str(digest_costs)).is_equal(str(assessed))
	assert_array(digest_costs).is_not_empty()
	# and the rendered line carries the price, not a placeholder
	var text := "\n".join(Digest.lines(Digest.build(db, week_one)))
	assert_str(text).contains("morale -")
	assert_str(text).not_contains("TODO: bench")
	db.close_db()


## Hardening from the M5-007 review: the charge is MARGINAL. A week in which the
## streak did not grow (no lineup-recorded raids) charges NOTHING — the same two
## sat-out nights used to be re-priced at every subsequent roll, forever.
func test_a_frozen_streak_is_never_charged_twice() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	_two_sat_out_nights(c)
	var week_two := _roll_the_week(db)

	# week 2's raid completes with NO lineup record — the streak freezes
	var guard := 0
	while guard < 8:
		guard += 1
		var advanced := TurnLoop.advance(db)
		if str(advanced["kind"]) == "event":
			TurnLoop.complete_event(db, int(advanced["event"]["event_id"]))
		elif str(advanced["kind"]) == "week_rolled":
			break

	# the roll out of week 2 assessed nothing, and week 3 opens uncharged
	assert_array(BenchCost.assess(db, week_two)).is_empty()
	var week_three := int(GameState.read(db)["week_id"])
	var benched := BenchCost.streaks(db, week_two)
	assert_array(benched).is_not_empty()
	var player_id := int(benched[0]["player_id"])
	var opening := int(
		_scalar(
			db,
			(
				"SELECT morale FROM player_week_state WHERE week_id = %d AND player_id = %d"
				% [week_three, player_id]
			)
		)
	)
	var prior := int(
		_scalar(
			db,
			(
				"SELECT morale FROM player_week_state WHERE week_id = %d AND player_id = %d"
				% [week_two, player_id]
			)
		)
	)
	(
		assert_int(opening)
		. override_failure_message("a frozen streak was charged again on the next roll")
		. is_equal(prior)
	)
	db.close_db()


## Hardening from the M5-007 review: an unavailable night (no lineup row for the
## raider) SKIPS — it neither counts nor breaks. One availability miss must not
## reset a perpetual bencher's tab.
func test_an_unavailable_night_does_not_reset_the_streak() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_id := int(c["week_id"])
	var raid_id := int(_scalar(db, "SELECT raid_id FROM raid ORDER BY raid_id LIMIT 1"))
	var second := Calendar.schedule(db, week_id, 4, "evening", "raid", raid_id)
	var third := Calendar.schedule(db, week_id, 5, "evening", "raid", raid_id)
	var full := PullInputLoader.auto_lineup(db)
	for event_id in [int(c["event_id"]), second, third]:
		assert_bool(RaidPrep.persist_lineup(db, event_id, full)).is_true()
		db.query_with_bindings(
			"UPDATE calendar_event SET status = 'completed' WHERE event_id = ?;", [event_id]
		)

	# pick a twice-benched raider and erase their MIDDLE night's row — the shape
	# persist_lineup writes for a raider whose availability roll said no
	var streaks_before := BenchCost.streaks(db, week_id)
	assert_array(streaks_before).is_not_empty()
	var avatar_id := int(streaks_before[0]["avatar_id"])
	assert_int(int(streaks_before[0]["streak"])).is_equal(3)
	db.query_with_bindings(
		"DELETE FROM raid_lineup WHERE event_id = ? AND avatar_id = ?;", [second, avatar_id]
	)

	for row: Dictionary in BenchCost.streaks(db, week_id):
		if int(row["avatar_id"]) != avatar_id:
			continue
		(
			assert_int(int(row["streak"]))
			. override_failure_message("the unavailable night reset the streak instead of skipping")
			. is_equal(2)
		)
	db.close_db()
