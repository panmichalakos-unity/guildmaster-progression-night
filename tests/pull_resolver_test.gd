extends GdUnitTestSuite

## M3-004: the assembled resolver — contract validity on every fixture,
## rating semantics, the gated learning arc, state deltas, persistence.


func _resolve(input: Dictionary, seed_value: int = SimFixture.TEST_SEED) -> Dictionary:
	return PullResolver.resolve(input, RngStream.derive(seed_value, "pull"))


## clean_kill roster with the DPS demand pinned just above its own output:
## wipes land with a SMALL blocking margin on a GATING check.
##
## MI-002: this used to pin the HEALING demand — but healing is now PRESSURE,
## not a kill-gate, so a healing shortfall no longer wipes the raid (it makes
## deaths deadlier instead). A near-margin *wipe* must therefore be built on a
## gating check (dps or tank). That the old fixture stopped producing wipes is
## the aggregation fix working as designed.
func _near_margin_fixture() -> Dictionary:
	var input: Dictionary = PullFixtures.clean_kill()
	for p: Dictionary in input["participants"]:
		p["awareness"] = 55  # keep the awareness->healing coupling neutral
	var probe := Contribution.lanes(input["participants"], input["tuning"], SimFixture.rng("probe"))
	input["encounter"]["dps_check"] = float(probe["dps"]) + 4.0
	return input


# --- contract validity ----------------------------------------------------------


func test_every_fixture_produces_a_contract_valid_result() -> void:
	var fixtures := PullFixtures.all()
	for fixture_name in fixtures:
		for seed_value in [1, SimFixture.TEST_SEED, 777]:
			var result := _resolve(fixtures[fixture_name], seed_value)
			var errors := PullContracts.validate_result(result)
			(
				assert_array(errors)
				. override_failure_message(
					"fixture '%s' seed %d invalid: %s" % [fixture_name, seed_value, errors]
				)
				. is_empty()
			)


func test_same_seed_identical_result() -> void:
	assert_that(_resolve(PullFixtures.healing_pressure())).is_equal(
		_resolve(PullFixtures.healing_pressure())
	)


func test_kill_report_shape() -> void:
	var result := _resolve(PullFixtures.clean_kill())
	assert_str(str(result["pull"]["outcome"])).is_equal("kill")
	assert_bool(bool(result["drops_loot"])).is_true()
	assert_int(int(result["pull"]["boss_hp_pct_at_end"])).is_equal(0)
	assert_int(int(result["state_deltas"]["encounter_progress"]["progress"])).is_equal(100)
	assert_int(result["participants"].size()).is_equal(20)


func test_wipe_report_names_reason_and_keeps_hp() -> void:
	var result := _resolve(PullFixtures.dps_pressure())
	assert_str(str(result["pull"]["outcome"])).is_equal("wipe")
	assert_bool(str(result["pull"]["wipe_reason"]).contains(":")).is_true()
	assert_bool(bool(result["drops_loot"])).is_false()
	assert_int(int(result["pull"]["boss_hp_pct_at_end"])).is_greater(0)


# --- ratings ---------------------------------------------------------------------


func test_ratings_are_relative_to_gear_not_absolute() -> void:
	# an on-par roster (skill ~ its gear) should center near 5-6, whether the
	# gear is starter or raid tier — the rating is vs EXPECTED, not raw output
	for fixture: Dictionary in [PullFixtures.clean_kill(), PullFixtures.dps_pressure()]:
		var total := 0.0
		var result := _resolve(fixture)
		for row: Dictionary in result["participants"]:
			total += int(row["performance_rating"])
			assert_int(int(row["performance_rating"])).is_between(1, 10)
			assert_bool(row.has("raw_contribution")).is_true()
		var mean: float = total / result["participants"].size()
		(
			assert_float(mean)
			. override_failure_message("mean rating %f should sit mid-band" % mean)
			. is_between(4.0, 7.5)
		)


func test_dying_to_avoidable_drags_the_rating() -> void:
	# across seeds, raiders who died average a worse rating than survivors
	var died_total := 0.0
	var died_count := 0
	var lived_total := 0.0
	var lived_count := 0
	for i in 30:
		var result := _resolve(PullFixtures.mechanic_failure(), 3000 + i)
		for row: Dictionary in result["participants"]:
			if bool(row["died"]):
				died_total += int(row["performance_rating"])
				died_count += 1
			else:
				lived_total += int(row["performance_rating"])
				lived_count += 1
	assert_int(died_count).is_greater(0)
	assert_float(died_total / died_count).is_less(lived_total / lived_count)


# --- the learning arc --------------------------------------------------------------


func test_learning_gains_are_gated_to_close_fights() -> void:
	# hopeless content (margin far beyond the band) earns ~nothing;
	# a near-margin fight earns real progress per attempt
	var hopeless: Dictionary = PullFixtures.dps_pressure()
	hopeless["encounter"]["dps_check"] = 200  # absurd wall
	var hopeless_gain := int(_resolve(hopeless)["state_deltas"]["encounter_progress"]["progress"])
	assert_int(hopeless_gain).is_less_equal(1)

	# a genuinely CLOSE fight: demand pinned just above the roster's actual
	# output, so wipes happen with a small blocking margin -> real learning
	var close := _near_margin_fixture()
	var wipes := 0
	for i in 40:
		var close_result := _resolve(close, 8000 + i)
		if str(close_result["pull"]["outcome"]) != "wipe":
			continue
		wipes += 1
		var gain := int(close_result["state_deltas"]["encounter_progress"]["progress"])
		(
			assert_int(gain)
			. override_failure_message(
				"near-margin wipe should teach: got %d (seed %d)" % [gain, 8000 + i]
			)
			. is_greater(0)
		)
	assert_int(wipes).override_failure_message("fixture never wiped — not near-margin").is_greater(
		0
	)


func test_progress_feeds_forward_into_better_pulls() -> void:
	# same seed, same roster, same boss: progress 90 must (a) raise the
	# contested margin (familiarity -> realization), (b) shed bodies to
	# avoidable damage no faster, (c) kill at least as often
	var fresh := _near_margin_fixture()
	var practiced := _near_margin_fixture()
	practiced["encounter_progress"] = {"progress": 90, "attempt_count": 12, "best_attempt_pct": 8}

	var fresh_margin := _contested_margin(_resolve(fresh))
	var practiced_margin := _contested_margin(_resolve(practiced))
	(
		assert_float(practiced_margin)
		. override_failure_message(
			"practice should lift the contested margin: %f -> %f" % [fresh_margin, practiced_margin]
		)
		. is_greater(fresh_margin)
	)

	var fresh_deaths := 0
	var practiced_deaths := 0
	var fresh_kills := 0
	var practiced_kills := 0
	for i in 60:
		var fresh_result := _resolve(fresh, 6000 + i)
		var practiced_result := _resolve(practiced, 6000 + i)
		fresh_deaths += fresh_result["participants"].filter(_died).size()
		practiced_deaths += practiced_result["participants"].filter(_died).size()
		if str(fresh_result["pull"]["outcome"]) == "kill":
			fresh_kills += 1
		if str(practiced_result["pull"]["outcome"]) == "kill":
			practiced_kills += 1
	assert_int(practiced_deaths).is_less_equal(fresh_deaths)
	(
		assert_int(practiced_kills)
		. override_failure_message(
			(
				"practice should not hurt: fresh %d vs practiced %d kills"
				% [fresh_kills, practiced_kills]
			)
		)
		. is_greater_equal(fresh_kills)
	)


func _died(row: Dictionary) -> bool:
	return bool(row["died"])


## The contested GATING margin in `_near_margin_fixture` — dps since MI-002.
func _contested_margin(result: Dictionary) -> float:
	for check: Dictionary in result["checks"]:
		if str(check["check"]) == "dps":
			return float(check["margin"])
	return 0.0


func test_attempt_count_and_best_pct_accumulate() -> void:
	var input: Dictionary = PullFixtures.dps_pressure()
	input["encounter_progress"] = {"progress": 10, "attempt_count": 4, "best_attempt_pct": 35}
	var progress: Dictionary = _resolve(input)["state_deltas"]["encounter_progress"]
	assert_int(int(progress["attempt_count"])).is_equal(5)
	assert_int(int(progress["best_attempt_pct"])).is_greater_equal(35)


# --- state deltas -------------------------------------------------------------------


func test_state_deltas_follow_the_night() -> void:
	var kill := _resolve(PullFixtures.clean_kill())
	for delta: Dictionary in kill["state_deltas"]["participants"]:
		assert_int(int(delta["morale_delta"])).is_greater(0)
		assert_int(int(delta["fatigue_delta"])).is_greater(0)
	var wipe := _resolve(PullFixtures.dps_pressure())
	var kill_fatigue := int(kill["state_deltas"]["participants"][0]["fatigue_delta"])
	for delta: Dictionary in wipe["state_deltas"]["participants"]:
		assert_int(int(delta["morale_delta"])).is_less(0)
		assert_int(int(delta["fatigue_delta"])).is_greater(kill_fatigue)  # wipes grind harder


# --- persistence ---------------------------------------------------------------------


func test_persist_writes_the_fact_tables() -> void:
	var db: Variant = SimFixture.new_campaign_db()
	assert_object(db).is_not_null()
	# real avatars so the pull facts' FKs resolve (fixture avatar_ids 1..20)
	var players := RosterGen.generate_from_db(db, 28, RngStream.derive(1, "roster_gen"))
	RosterGen.persist(db, players)
	AvatarGen.generate_and_persist(db, RngStream.derive(1, "avatar_gen"))
	# minimal campaign scaffolding: a guild, a week, a raid-night event
	db.query("INSERT INTO guild (display_name, is_player_guild) VALUES ('Test Guild', 1);")
	db.query("INSERT INTO week (season_id, week_number) VALUES (1, 1);")
	db.query(
		(
			"INSERT INTO calendar_event (week_id, raid_id, day, time_slot, event_type)"
			+ " VALUES (1, 1, 3, 'evening', 'raid');"
		)
	)
	var result := _resolve(PullFixtures.tank_pressure())
	var pull_id := PullResolver.persist(db, 1, 1, 1, result)
	assert_int(pull_id).is_greater(0)

	db.query("SELECT outcome, wipe_reason FROM pull WHERE pull_id = %d;" % pull_id)
	assert_str(str(db.query_result[0]["outcome"])).is_equal(str(result["pull"]["outcome"]))
	db.query("SELECT COUNT(*) AS n FROM pull_participant WHERE pull_id = %d;" % pull_id)
	assert_int(int(db.query_result[0]["n"])).is_equal(20)
	db.query("SELECT COUNT(*) AS n FROM pull_event WHERE pull_id = %d;" % pull_id)
	assert_int(int(db.query_result[0]["n"])).is_equal(result["events"].size())
	db.query("SELECT attempt_count FROM guild_encounter_progress WHERE guild_id = 1;")
	assert_int(int(db.query_result[0]["attempt_count"])).is_equal(1)
	db.query("PRAGMA foreign_key_check;")
	assert_int(db.query_result.size()).is_equal(0)

	# persist a second pull: progress row upserts, attempt_count climbs
	var again := _resolve(PullFixtures.tank_pressure(), 42)
	again["pull"]["attempt_number"] = 2  # unique per (event, encounter, attempt)
	again["state_deltas"]["encounter_progress"]["attempt_count"] = 2
	assert_int(PullResolver.persist(db, 1, 1, 1, again)).is_greater(pull_id)
	db.query("SELECT attempt_count, COUNT(*) AS rows FROM guild_encounter_progress;")
	assert_int(int(db.query_result[0]["attempt_count"])).is_equal(2)
	assert_int(int(db.query_result[0]["rows"])).is_equal(1)
	db.close_db()
