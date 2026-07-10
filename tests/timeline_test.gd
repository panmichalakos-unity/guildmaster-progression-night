extends GdUnitTestSuite

## M3-003: phase timeline + event firing — determinism, per-fixture outcomes,
## data-driven selectors, cascade/save/assigned-duty behaviors, legible log.


func _run(input: Dictionary, seed_value: int = SimFixture.TEST_SEED) -> Dictionary:
	return Timeline.run(input, RngStream.derive(seed_value, "pull"))


func _outcome_rate(input: Dictionary, want: String, runs: int = 80) -> float:
	var hits := 0
	for i in runs:
		if str(_run(input, 5000 + i)["outcome"]) == want:
			hits += 1
	return float(hits) / runs


func _mini(participants: Array, events: Array, phases: Array = []) -> Dictionary:
	var input := PullContracts.make_input()
	input["encounter"] = {
		"slug": "mini", "dps_check": 30, "healing_check": 30, "difficulty": 30, "phase_count": 1
	}
	input["phases"] = (
		phases
		if not phases.is_empty()
		else [{"slug": "mini_p1", "phase_order": 1, "entry_condition": ""}]
	)
	input["participants"] = participants
	input["events"] = events
	input["tuning"] = {"event_scale": 15}
	return input


func _raider(id: int, role: String, overrides: Dictionary = {}) -> Dictionary:
	var p: Dictionary = PullFixtures.clean_kill()["participants"][0].duplicate(true)
	p["avatar_id"] = id
	p["player_id"] = id
	p["handle"] = "%s_%d" % [role, id]
	p["role_slug"] = role
	p["uncrittable"] = 1 if role == "tank" else 0
	p["assignments"] = [{"assignment_type": "tank", "target": "main"}] if role == "tank" else []
	for key in overrides:
		p[key] = overrides[key]
	return p


func _event(
	slug: String, category: String, selector: String, attr: String, severity: int
) -> Dictionary:
	return {
		"slug": slug,
		"phase_order": 1,
		"event_type_slug": slug,
		"trigger": "t",
		"target_selector": selector,
		"roll_attribute": attr,
		"effect_category": category,
		"log_template": "{name} meets it.",
		"severity": severity,
		"weight": 100,
	}


# --- determinism --------------------------------------------------------------


func test_same_seed_identical_timeline() -> void:
	var a := _run(PullFixtures.mechanic_failure())
	var b := _run(PullFixtures.mechanic_failure())
	assert_str(str(a["outcome"])).is_equal(str(b["outcome"]))
	assert_str(str(a["wipe_reason"])).is_equal(str(b["wipe_reason"]))
	assert_that(a["events"]).is_equal(b["events"])
	assert_that(a["deaths"]).is_equal(b["deaths"])


func test_different_seed_can_diverge() -> void:
	# a near-margin fixture should not be identical across all seeds
	var outcomes := {}
	for i in 40:
		var r := _run(PullFixtures.healing_pressure(), 700 + i)
		outcomes[str(r["outcome"])] = true
	# at least the event rolls differ even if outcome is stable
	assert_that(_run(PullFixtures.healing_pressure(), 1)["events"]).is_not_equal(
		_run(PullFixtures.healing_pressure(), 2)["events"]
	)


# --- per-fixture outcomes (the doc's difficulty-via-margin) -------------------


func test_clean_kill_fixture_kills() -> void:
	assert_float(_outcome_rate(PullFixtures.clean_kill(), "kill")).is_greater(0.85)
	var r := _run(PullFixtures.clean_kill())
	assert_str(str(r["outcome"])).is_equal("kill")
	assert_str(str(r["wipe_reason"])).is_empty()
	assert_int(int(r["progress_pct"])).is_equal(100)


func test_dps_pressure_fixture_wipes_on_dps() -> void:
	assert_float(_outcome_rate(PullFixtures.dps_pressure(), "wipe")).is_greater(0.85)


func test_tank_pressure_fixture_wipes_on_the_gate() -> void:
	assert_float(_outcome_rate(PullFixtures.tank_pressure(), "wipe")).is_greater(0.8)
	# across seeds, tank failures should dominate the reason
	var tank_reasons := 0
	for i in 40:
		var r := _run(PullFixtures.tank_pressure(), 900 + i)
		if str(r["outcome"]) == "wipe" and str(r["wipe_reason"]).begins_with("tank_survival"):
			tank_reasons += 1
	assert_int(tank_reasons).is_greater(15)


func test_mechanic_failure_fixture_wipes_with_deaths() -> void:
	assert_float(_outcome_rate(PullFixtures.mechanic_failure(), "wipe")).is_greater(0.85)
	var r := _run(PullFixtures.mechanic_failure())
	assert_int(r["deaths"].size()).is_greater(0)  # avoidable events took bodies


func test_healing_pressure_fixture_wipes() -> void:
	assert_float(_outcome_rate(PullFixtures.healing_pressure(), "wipe")).is_greater(0.8)


# --- data-driven target selectors --------------------------------------------


func test_selector_routes_damage_to_the_named_role() -> void:
	var participants := [
		_raider(1, "tank"),
		_raider(2, "healer"),
		_raider(3, "melee"),
		_raider(4, "melee"),
		_raider(5, "ranged", {"awareness": 5}),
		_raider(6, "ranged", {"awareness": 5}),
	]
	# a ranged-punisher avoidable at brutal severity -> a ranged raider dies
	var input := _mini(participants, [_event("ranged_fire", "death", "ranged", "awareness", 95)])
	var r := _run(input)
	assert_int(r["deaths"].size()).is_greater(0)
	var dead_id: int = r["deaths"][0]
	var dead_role := ""
	for p: Dictionary in participants:
		if int(p["avatar_id"]) == dead_id:
			dead_role = str(p["role_slug"])
	assert_str(dead_role).is_equal("ranged")


func test_assigned_duty_failure_cascades_a_death() -> void:
	# a weak assignee vs a brutal duty window -> the missed cast kills a raider.
	# the weak melee holds the interrupt duty; the tank is busy tanking (no duty).
	var participants := [
		_raider(1, "tank", {"assignments": []}),
		_raider(2, "healer"),
		_raider(
			3,
			"melee",
			{
				"execution": 5,
				"role_proficiency": 5,
				"assignments": [{"assignment_type": "interrupt", "target": "adds"}],
			}
		),
		_raider(4, "ranged"),
	]
	var input := _mini(
		participants, [_event("interrupt", "duty_check", "assigned", "execution", 95)]
	)
	var r := _run(input)
	assert_int(r["deaths"].size()).is_greater(0)
	var has_duty_fail := false
	for event: Dictionary in r["events"]:
		if str(event["outcome"]) == "duty_fail":
			has_duty_fail = true
			assert_bool(str(event["log_line"]).contains("falls")).is_true()
	assert_bool(has_duty_fail).is_true()


func test_cascade_death_only_bites_after_a_prior_death() -> void:
	var participants := [
		_raider(1, "melee", {"awareness": 5}),
		_raider(2, "melee", {"awareness": 5}),
		_raider(3, "healer"),
	]
	# lone cascade, nobody dead yet -> the raid steadies (no death)
	var lone := _mini(participants, [_event("z_cascade", "death", "random", "", 60)])
	var r_lone := _run(lone)
	assert_int(r_lone["deaths"].size()).is_equal(0)
	assert_bool(str(r_lone["events"][0]["outcome"]) == "steadied").is_true()
	# an avoidable first (slug 'a_' sorts before 'z_'), THEN cascade can bite
	var chain := _mini(
		participants,
		[
			_event("a_avoidable", "death", "melee", "awareness", 95),
			_event("z_cascade", "death", "random", "", 55),
		]
	)
	var r_chain := _run(chain, 4242)
	assert_int(r_chain["deaths"].size()).is_greater_equal(1)


func test_clutch_save_cancels_a_death() -> void:
	var participants := [
		_raider(1, "melee", {"awareness": 5}),
		_raider(2, "healer", {"consistency": 95}),
		_raider(3, "tank"),
	]
	# avoidable kills the melee, then the healer's clutch (slug 'b_') saves them
	var input := _mini(
		participants,
		[
			_event("a_avoidable", "death", "melee", "awareness", 95),
			_event("b_clutch", "save", "healer", "consistency", 10),
		]
	)
	var r := _run(input)
	var saved := false
	for event: Dictionary in r["events"]:
		if str(event["outcome"]) == "save":
			saved = true
	assert_bool(saved).is_true()
	assert_int(r["deaths"].size()).is_equal(0)  # the death was reversed


func test_cooldown_surge_helps_the_dps_check() -> void:
	# a handled cooldown adds DPS surge; a fumbled one adds nothing
	var participants := [_raider(1, "tank"), _raider(2, "ranged", {"execution": 90})]
	var handled := _mini(participants, [_event("cd", "surge", "assigned", "execution", 1)])
	var fumbled := _mini(participants, [_event("cd", "surge", "assigned", "execution", 999)])
	assert_float(float(_run(handled)["dps_surge"])).is_greater(0.0)
	assert_float(float(_run(fumbled)["dps_surge"])).is_equal(0.0)


# --- combat log legibility ----------------------------------------------------


func test_combat_log_is_well_formed_and_named() -> void:
	var r := _run(PullFixtures.mechanic_failure())
	var seen := {}
	for event: Dictionary in r["events"]:
		var sequence := int(event["sequence_no"])
		(
			assert_bool(seen.has(sequence))
			. override_failure_message("duplicate sequence_no %d" % sequence)
			. is_false()
		)
		seen[sequence] = true
		assert_str(str(event["log_line"])).is_not_empty()
		assert_bool(event.has("target_avatar_id")).is_true()
		assert_bool(event.has("roll_result")).is_true()


func test_wipe_reason_always_names_a_check() -> void:
	for fixture: Dictionary in [
		PullFixtures.dps_pressure(),
		PullFixtures.tank_pressure(),
		PullFixtures.mechanic_failure(),
		PullFixtures.healing_pressure(),
	]:
		var r := _run(fixture)
		if str(r["outcome"]) == "wipe":
			var reason := str(r["wipe_reason"])
			assert_str(reason).is_not_empty()
			(
				assert_bool(reason.contains(":"))
				. override_failure_message("wipe_reason not legible: %s" % reason)
				. is_true()
			)


func test_no_boss_specific_code_engine_runs_any_seed_shape() -> void:
	# the same engine resolves a novel encounter defined purely by rows
	var participants := [_raider(1, "tank"), _raider(2, "healer"), _raider(3, "ranged")]
	var input := _mini(
		participants,
		[
			_event("beat", "tension", "random", "consistency", 40),
			_event("swap", "tank_check", "tank", "awareness", 40),
		]
	)
	var r := _run(input)
	assert_array(PullContracts.CHECK_KINDS).contains([str(r["checks"][0]["check"])])
	assert_bool(str(r["outcome"]) in ["kill", "wipe"]).is_true()
