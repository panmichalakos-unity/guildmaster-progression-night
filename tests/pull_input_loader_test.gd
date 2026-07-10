extends GdUnitTestSuite

## M3-005: PullInputLoader — real DB rows into contract-valid resolver inputs.

var _db: Variant


func before() -> void:
	_db = SimFixture.new_campaign_db()
	assert_object(_db).is_not_null()
	var players := RosterGen.generate_from_db(
		_db, 28, RngStream.derive(SimFixture.TEST_SEED, "roster_gen")
	)
	assert_int(RosterGen.persist(_db, players).size()).is_equal(28)
	(
		assert_int(
			(
				AvatarGen
				. generate_and_persist(_db, RngStream.derive(SimFixture.TEST_SEED, "avatar_gen"))
				. size()
			)
		)
		. is_equal(28)
	)


func after() -> void:
	_db.close_db()


func test_auto_lineup_fields_a_valid_twenty() -> void:
	var lineup := PullInputLoader.auto_lineup(_db)
	assert_int(lineup.size()).is_equal(20)
	assert_int(lineup.size()).is_equal(_unique(lineup).size())


func test_build_produces_contract_valid_input_for_every_boss() -> void:
	var lineup := PullInputLoader.auto_lineup(_db)
	for boss in ["gatewarden_krogg", "forgemaster_vell", "slagbeast", "cinderlords"]:
		var input := PullInputLoader.build(_db, boss, lineup)
		var errors := PullContracts.validate_input(input)
		(
			assert_array(errors)
			. override_failure_message("loader input for '%s' invalid: %s" % [boss, errors])
			. is_empty()
		)
		assert_int(input["participants"].size()).is_equal(20)
		assert_bool(input["events"].size() > 0).is_true()
		# tuning came from tuning.json and carries the consumables block
		assert_bool(input["tuning"].has("sigmoid_scale")).is_true()
		assert_bool(input["tuning"].has("consumables")).is_true()


func test_selector_coalesce_applies_the_range_profile_override() -> void:
	var lineup := PullInputLoader.auto_lineup(_db)
	# Vell's storm placements override the avoidable_death type to RANGED
	var vell := PullInputLoader.build(_db, "forgemaster_vell", lineup)
	var storm_selector := ""
	for event: Dictionary in vell["events"]:
		if str(event["slug"]) == "vell_p2_storm_ranged":
			storm_selector = str(event["target_selector"])
	assert_str(storm_selector).is_equal("ranged")
	# Krogg's tank_swap inherits the TYPE default (tank) — no override
	var krogg := PullInputLoader.build(_db, "gatewarden_krogg", lineup)
	var swap_selector := ""
	for event: Dictionary in krogg["events"]:
		if str(event["slug"]) == "krogg_p1_tank_swap":
			swap_selector = str(event["target_selector"])
	assert_str(swap_selector).is_equal("tank")


func test_gear_multiplier_scales_the_lineup() -> void:
	var lineup := PullInputLoader.auto_lineup(_db)
	var base := PullInputLoader.build(_db, "gatewarden_krogg", lineup)
	var doubled := PullInputLoader.build(_db, "gatewarden_krogg", lineup, {"gear_multiplier": 2.0})
	var base_gs := int(base["participants"][0]["gear_score"])
	assert_int(int(doubled["participants"][0]["gear_score"])).is_equal(base_gs * 2)


func test_exactly_one_main_tank_assignment() -> void:
	var lineup := PullInputLoader.auto_lineup(_db)
	var input := PullInputLoader.build(_db, "slagbeast", lineup)
	var main_tanks := 0
	for p: Dictionary in input["participants"]:
		for assignment: Dictionary in p["assignments"]:
			if str(assignment["target"]) == "main":
				main_tanks += 1
				assert_str(str(p["role_slug"])).is_equal("tank")
	assert_int(main_tanks).is_equal(1)


func test_encounter_progress_reads_the_learning_table() -> void:
	var lineup := PullInputLoader.auto_lineup(_db)
	_db.query("INSERT INTO guild (display_name, is_player_guild) VALUES ('G', 1);")
	_db.query(
		(
			"INSERT INTO guild_encounter_progress (guild_id, encounter_id, progress,"
			+ " attempt_count, best_attempt_pct) VALUES (1, 1, 40, 7, 22);"
		)
	)
	var input := PullInputLoader.build(_db, "gatewarden_krogg", lineup, {"guild_id": 1})
	assert_int(int(input["encounter_progress"]["progress"])).is_equal(40)
	assert_int(int(input["encounter_progress"]["attempt_count"])).is_equal(7)
	# and the resolver consumes it end-to-end without complaint
	var result := PullResolver.resolve(input, SimFixture.rng("loader_e2e"))
	assert_array(PullContracts.validate_result(result)).is_empty()
	assert_int(int(result["state_deltas"]["encounter_progress"]["attempt_count"])).is_equal(8)


func _unique(values: Array) -> Dictionary:
	var seen := {}
	for value in values:
		seen[value] = true
	return seen
