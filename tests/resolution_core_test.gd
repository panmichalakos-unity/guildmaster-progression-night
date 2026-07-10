extends GdUnitTestSuite

## M3-002: contribution lanes + margin/sigmoid checks — determinism,
## overgeared/undergeared behavior, near-margin variance, the couplings.


func _lanes(input: Dictionary, seed_value: int = SimFixture.TEST_SEED) -> Dictionary:
	return Contribution.lanes(
		input["participants"], input["tuning"], RngStream.derive(seed_value, "contribution")
	)


func _checks(input: Dictionary, seed_value: int = SimFixture.TEST_SEED) -> Array[Dictionary]:
	var lane_data := _lanes(input, seed_value)
	return PullChecks.resolve(input, lane_data, RngStream.derive(seed_value, "checks"))


func _pass_rate(input: Dictionary, kind: String, runs: int = 60) -> float:
	var passes := 0
	for i in runs:
		for check: Dictionary in _checks(input, 1000 + i):
			if str(check["check"]) == kind and bool(check["passed"]):
				passes += 1
	return float(passes) / runs


func test_same_seed_identical_lanes_and_checks() -> void:
	var input: Dictionary = PullFixtures.clean_kill()
	var lanes_a := _lanes(input)
	var lanes_b := _lanes(input)
	assert_float(float(lanes_a["dps"])).is_equal(float(lanes_b["dps"]))
	assert_float(float(lanes_a["hps"])).is_equal(float(lanes_b["hps"]))
	assert_that(_checks(input)).is_equal(_checks(input))


func test_different_seed_diverges() -> void:
	var input: Dictionary = PullFixtures.dps_pressure()
	assert_float(float(_lanes(input, 1)["dps"])).is_not_equal(float(_lanes(input, 2)["dps"]))


func test_overgeared_roster_passes_decisively() -> void:
	# clean_kill: gear 260 vs demands 20 — the saturated + margin zone
	for check: Dictionary in _checks(PullFixtures.clean_kill()):
		if str(check["check"]) in ["dps", "healing"]:
			(
				assert_float(float(check["margin"]))
				. override_failure_message("expected saturated margin, got %s" % check["detail"])
				. is_greater(15.0)
			)
	assert_float(_pass_rate(PullFixtures.clean_kill(), "dps")).is_greater(0.9)


func test_undergeared_roster_fails_the_dps_wall() -> void:
	# dps_pressure: demand 85 vs gear-130 roster — decisive wipe territory
	var checks := _checks(PullFixtures.dps_pressure())
	var dps_check := checks[0]
	assert_str(str(dps_check["check"])).is_equal("dps")
	assert_float(float(dps_check["margin"])).is_less(-10.0)
	assert_float(_pass_rate(PullFixtures.dps_pressure(), "dps")).is_less(0.15)


func test_near_margin_is_the_coinflip_zone() -> void:
	# construct margin ~ 0: soft check probability must sit mid-band and
	# outcomes must actually vary across seeds
	var input: Dictionary = PullFixtures.clean_kill()
	assert_float(PullChecks.pass_probability(0.0, "healing", input["tuning"])).is_equal(0.5)
	var rate := _pass_rate(_tuned_to_margin_zero(input), "healing", 80)
	assert_float(rate).is_between(0.25, 0.75)


func test_hard_checks_use_the_steeper_curve() -> void:
	var tuning: Dictionary = PullFixtures.clean_kill()["tuning"]
	# same negative margin: the cliff punishes harder than the slope
	var soft := PullChecks.pass_probability(-15.0, "healing", tuning)
	var hard := PullChecks.pass_probability(-15.0, "tank", tuning)
	assert_float(hard).is_less(soft)
	# and saturates faster on the upside
	assert_float(PullChecks.pass_probability(20.0, "tank", tuning)).is_greater(0.8)


func test_healing_demand_couples_to_awareness() -> void:
	# the sloppy raid strains its healers: lower awareness -> higher demand
	var sloppy: Dictionary = PullFixtures.healing_pressure()
	var tidy: Dictionary = PullFixtures.healing_pressure()
	for p: Dictionary in sloppy["participants"]:
		p["awareness"] = 25
	for p: Dictionary in tidy["participants"]:
		p["awareness"] = 70
	var sloppy_demand: float = Contribution.demands(sloppy, _lanes(sloppy))["healing"]
	var tidy_demand: float = Contribution.demands(tidy, _lanes(tidy))["healing"]
	assert_float(sloppy_demand).is_greater(tidy_demand)
	assert_float(tidy_demand).is_greater_equal(float(tidy["encounter"]["healing_check"]))


func test_uncrittable_gate_is_near_binary() -> void:
	# tank_pressure ships a NOT-uncrittable main tank -> gate penalty applies
	var gated := _checks(PullFixtures.tank_pressure())
	var tank_gated: Dictionary = gated[2]
	assert_str(str(tank_gated["check"])).is_equal("tank")
	assert_bool(str(tank_gated["detail"]).contains("NOT uncrittable")).is_true()
	# fix the gear gate -> margin recovers by exactly the penalty
	var fixed: Dictionary = PullFixtures.tank_pressure()
	for p: Dictionary in fixed["participants"]:
		if str(p["role_slug"]) == "tank":
			p["uncrittable"] = 1
	var tank_fixed: Dictionary = _checks(fixed)[2]
	assert_float(float(tank_fixed["margin"]) - float(tank_gated["margin"])).is_equal_approx(
		25.0, 0.001
	)
	assert_float(_pass_rate(PullFixtures.tank_pressure(), "tank")).is_less(0.2)


func test_spec_difficulty_bites_only_low_skill() -> void:
	var novice := _fixture_participant(
		{"execution": 25, "role_proficiency": 25, "familiarity": 25, "spec_difficulty": 75}
	)
	var novice_easy := _fixture_participant(
		{"execution": 25, "role_proficiency": 25, "familiarity": 25, "spec_difficulty": 40}
	)
	var master := _fixture_participant(
		{"execution": 90, "role_proficiency": 90, "familiarity": 90, "spec_difficulty": 75}
	)
	var master_easy := _fixture_participant(
		{"execution": 90, "role_proficiency": 90, "familiarity": 90, "spec_difficulty": 40}
	)
	var tuning := {}
	var rng := SimFixture.rng("spec_bite")
	var novice_hard_r: float = Contribution.compute(novice, tuning, rng)["realization"]
	var novice_easy_r: float = Contribution.compute(novice_easy, tuning, rng)["realization"]
	var master_hard_r: float = Contribution.compute(master, tuning, rng)["realization"]
	var master_easy_r: float = Contribution.compute(master_easy, tuning, rng)["realization"]
	assert_float(novice_easy_r - novice_hard_r).is_greater(0.05)  # bites the novice
	assert_float(master_easy_r - master_hard_r).is_equal(0.0)  # the master shrugs


func test_consistency_sets_variance_width() -> void:
	var steady := _fixture_participant({"consistency": 90})
	var spiky := _fixture_participant({"consistency": 20})
	var tuning := {}
	assert_float(_spread(steady, tuning)).is_less(_spread(spiky, tuning))


func test_situational_mods_stay_clamped() -> void:
	var wrecked := _fixture_participant({"morale": 5, "fatigue": 95, "form": 5, "consumables": []})
	var flying := _fixture_participant(
		{
			"morale": 95,
			"fatigue": 0,
			"form": 95,
			"consumables": [{"slug": "emberflask", "tier": "premium"}]
		}
	)
	var rng := SimFixture.rng("clamp")
	var low: float = Contribution.compute(wrecked, {}, rng)["situational"]
	var high: float = Contribution.compute(flying, {}, rng)["situational"]
	assert_float(low).is_greater_equal(0.7)
	assert_float(high).is_less_equal(1.3)
	assert_float(high).is_greater(low)


func test_every_check_names_numbers_for_legibility() -> void:
	for check: Dictionary in _checks(PullFixtures.healing_pressure()):
		assert_bool(str(check["detail"]).contains("margin")).is_true()
	# lane checks name their weakest link
	var dps_detail := str(_checks(PullFixtures.dps_pressure())[0]["detail"])
	assert_bool(dps_detail.contains("weakest:")).is_true()


# --- helpers -------------------------------------------------------------------


func _fixture_participant(overrides: Dictionary) -> Dictionary:
	var p: Dictionary = PullFixtures.clean_kill()["participants"][0].duplicate(true)
	for key in overrides:
		p[key] = overrides[key]
	return p


func _spread(participant: Dictionary, tuning: Dictionary) -> float:
	var lowest := 999.0
	var highest := -999.0
	for i in 200:
		var rng := RngStream.derive(i, "spread")
		var roll: float = Contribution.compute(participant, tuning, rng)["variance_roll"]
		lowest = minf(lowest, roll)
		highest = maxf(highest, roll)
	return highest - lowest


func _tuned_to_margin_zero(input: Dictionary) -> Dictionary:
	# pull the healing demand up to the roster's actual average HPS output
	var probe := Contribution.lanes(input["participants"], input["tuning"], SimFixture.rng("probe"))
	input["encounter"]["healing_check"] = float(probe["hps"])
	for p: Dictionary in input["participants"]:
		p["awareness"] = 55  # neutralize the coupling for a clean margin-zero
	return input
