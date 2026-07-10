extends GdUnitTestSuite

## M3-001: resolver contract + fixture validation.


func test_all_fixtures_validate_clean() -> void:
	var fixtures := PullFixtures.all()
	assert_int(fixtures.size()).is_equal(5)
	for name in fixtures:
		var errors := PullContracts.validate_input(fixtures[name])
		(
			assert_array(errors)
			. override_failure_message("fixture '%s' invalid: %s" % [name, errors])
			. is_empty()
		)


func test_fixture_shapes_encode_their_scenarios() -> void:
	# clean_kill: overgeared vs low demands
	var kill: Dictionary = PullFixtures.clean_kill()
	assert_int(int(kill["participants"][0]["gear_score"])).is_greater(200)
	assert_int(int(kill["encounter"]["dps_check"])).is_less_equal(30)
	assert_int(kill["participants"].size()).is_equal(20)
	# mechanic_failure: low awareness, high-severity avoidable events, 2 phases
	var mech: Dictionary = PullFixtures.mechanic_failure()
	assert_int(int(mech["participants"][0]["awareness"])).is_less(30)
	assert_int(mech["phases"].size()).is_equal(2)
	# dps_pressure: demand far above the clean-kill band
	var dps: Dictionary = PullFixtures.dps_pressure()
	assert_int(int(dps["encounter"]["dps_check"])).is_greater_equal(85)
	# healing_pressure: thin healer lane (3, not 5)
	var heal: Dictionary = PullFixtures.healing_pressure()
	var healers := 0
	for p: Dictionary in heal["participants"]:
		if str(p["role_slug"]) == "healer":
			healers += 1
	assert_int(healers).is_equal(3)
	assert_int(heal["participants"].size()).is_equal(20)
	# tank_pressure: no uncrittable tank (the gear gate)
	var tank: Dictionary = PullFixtures.tank_pressure()
	for p: Dictionary in tank["participants"]:
		if str(p["role_slug"]) == "tank":
			assert_int(int(p["uncrittable"])).is_equal(0)


func test_input_validator_catches_broken_inputs() -> void:
	# empty lineup
	var input := PullContracts.make_input()
	input["encounter"]["slug"] = "x"
	assert_array(PullContracts.validate_input(input)).is_not_empty()
	# bad role
	var bad_role: Dictionary = PullFixtures.clean_kill()
	bad_role["participants"][0]["role_slug"] = "bard"
	(
		assert_bool("\n".join(PullContracts.validate_input(bad_role)).contains("bad role_slug"))
		. is_true()
	)
	# event pointing at a phase that does not exist
	var orphan_event: Dictionary = PullFixtures.clean_kill()
	orphan_event["events"][0]["phase_order"] = 9
	(
		assert_bool("\n".join(PullContracts.validate_input(orphan_event)).contains("no phase row"))
		. is_true()
	)
	# duplicate avatar in the lineup
	var duped: Dictionary = PullFixtures.clean_kill()
	duped["participants"][1]["avatar_id"] = duped["participants"][0]["avatar_id"]
	(
		assert_bool("\n".join(PullContracts.validate_input(duped)).contains("duplicate avatar_id"))
		. is_true()
	)
	# bad selector
	var bad_selector: Dictionary = PullFixtures.clean_kill()
	bad_selector["events"][0]["target_selector"] = "pets"
	(
		assert_bool(
			"\n".join(PullContracts.validate_input(bad_selector)).contains("target_selector")
		)
		. is_true()
	)


func test_result_validator_enforces_legible_failure() -> void:
	var result := PullContracts.make_result()
	# a bare wipe with no reason must fail — legibility is the engine
	result["pull"]["outcome"] = "wipe"
	result["pull"]["wipe_reason"] = ""
	assert_bool("\n".join(PullContracts.validate_result(result)).contains("wipe_reason")).is_true()
	# a named wipe passes
	result["pull"]["wipe_reason"] = "healing_sustain: tank_1 died with heals dry"
	assert_array(PullContracts.validate_result(result)).is_empty()
	# a kill must not carry a reason and must drop loot
	result["pull"]["outcome"] = "kill"
	assert_bool(PullContracts.validate_result(result).size() >= 2).is_true()
	result["pull"]["wipe_reason"] = ""
	result["drops_loot"] = true
	assert_array(PullContracts.validate_result(result)).is_empty()


func test_result_validator_checks_participant_and_event_shapes() -> void:
	var result := PullContracts.make_result()
	result["pull"]["wipe_reason"] = "dps_enrage: raid 12% short"
	result["participants"] = [
		{
			"avatar_id": 1,
			"player_id": 1,
			"role_assigned": "tank",
			"assignment_target": "main",
			"raw_contribution": 900,
			"performance_rating": 11,
			"died": false,
		}
	]
	assert_bool("\n".join(PullContracts.validate_result(result)).contains("out of 1..10")).is_true()
	result["participants"][0]["performance_rating"] = 7
	result["events"] = [
		{
			"sequence_no": 1,
			"encounter_event_slug": "",
			"phase_order": 1,
			"target_avatar_id": 1,
			"roll_result": "pass",
			"outcome": "survived",
			"log_line": "tank_1 takes the swap."
		},
		{
			"sequence_no": 1,
			"encounter_event_slug": "",
			"phase_order": 1,
			"target_avatar_id": 0,
			"roll_result": "",
			"outcome": "",
			"log_line": "The raid steadies."
		},
	]
	(
		assert_bool(
			"\n".join(PullContracts.validate_result(result)).contains("duplicate event sequence_no")
		)
		. is_true()
	)
	result["events"][1]["sequence_no"] = 2
	assert_array(PullContracts.validate_result(result)).is_empty()


func test_check_kinds_match_resolution_doc() -> void:
	assert_array(PullContracts.CHECK_KINDS).contains(
		["dps", "healing", "tank", "mechanic", "assigned_duty"]
	)
	var result := PullContracts.make_result()
	result["pull"]["wipe_reason"] = "tank_survival: gate check failed"
	result["checks"] = [{"check": "resistance", "margin": 0.0, "passed": false, "detail": ""}]
	(
		assert_bool("\n".join(PullContracts.validate_result(result)).contains("unknown check kind"))
		. is_true()
	)
