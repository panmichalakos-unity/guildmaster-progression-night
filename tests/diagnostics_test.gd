extends GdUnitTestSuite

## MI-005 — the diagnostic contract, and the anti-scapegoat rules that hold it up.
##
## "Every wipe names a culprit" is half a pillar. Failures here are COUPLED, so one
## dominant check is not one root cause and certainly not one guilty person. These
## tests exist because that principle is trivially easy to regress: somebody adds a
## death outcome, forgets the rating table, and the game quietly starts teaching the
## player to bench the victim of a systemic failure.
##
## See docs/guildmaster-diagnostics.md.

const BOSS := "gatewarden_krogg"


func _wipe(attempt: int = 1, gear: float = 1.0) -> Dictionary:
	var campaign := DemoCampaign.build(133742)
	var db: Variant = campaign["db"]
	var result := PullResolver.resolve(
		PullInputLoader.build(db, BOSS, PullInputLoader.auto_lineup(db), {"gear_multiplier": gear}),
		RngStream.derive(4400 + attempt, "diagnostics")
	)
	db.close_db()
	return result


# --- the hierarchy ------------------------------------------------------------


func test_a_wipe_produces_the_full_hierarchy() -> void:
	var result := _wipe()
	assert_str(str(result["pull"]["outcome"])).is_equal("wipe")
	var diagnosis: Dictionary = result["pull"]["diagnosis"]

	for key in [
		"primary_cause",
		"primary_cause_label",
		"headline",
		"contributing_factors",
		"key_moment",
		"recommendation",
		"detail",
	]:
		(
			assert_bool(diagnosis.has(key))
			. override_failure_message("diagnosis is missing '%s'" % key)
			. is_true()
		)
	assert_str(str(diagnosis["primary_cause_label"])).is_not_empty()
	assert_str(str(diagnosis["headline"])).is_not_empty()
	assert_str(str(diagnosis["recommendation"])).is_not_empty()


func test_a_kill_has_no_diagnosis_to_give() -> void:
	for attempt in range(1, 12):
		var result := _wipe(attempt, 1.64)
		if str(result["pull"]["outcome"]) == "kill":
			assert_dict(result["pull"]["diagnosis"]).is_empty()
			return
	fail("no kill produced at full tier gear — cannot check the kill path")


## The primary cause is a CHECK, and only the three gates that can end a pull
## (MI-002) may ever be one. Healing and mechanic are pressure: they are
## contributing factors, never the headline.
func test_the_primary_cause_is_always_one_of_the_three_gates() -> void:
	for attempt in range(1, 10):
		var result := _wipe(attempt)
		if str(result["pull"]["outcome"]) != "wipe":
			continue
		var cause := str(result["pull"]["diagnosis"]["primary_cause"])
		(
			assert_array(Diagnosis.CAUSE_LABELS.keys())
			. override_failure_message("'%s' is not a gate that may end a pull" % cause)
			. contains([cause])
		)


# --- the anti-scapegoat rules -------------------------------------------------


## THE RULE. A raider may be named as the key moment ONLY for an event they
## authored: a duty they were assigned and dropped, or damage they were rolled
## against and ate. Never for the raid running out of healing, and never for the
## guildmaster's decision to field an uncapped tank.
func test_only_authored_failures_can_name_a_person() -> void:
	assert_array(Diagnosis.ATTRIBUTABLE_OUTCOMES).is_equal(["duty_fail", "death"])
	for outcome in [
		Timeline.OUTCOME_TANK_OVERWHELMED,
		Timeline.OUTCOME_CASCADE_DEATH,
		Timeline.OUTCOME_TANK_DEATH,
	]:
		(
			assert_array(Diagnosis.ATTRIBUTABLE_OUTCOMES)
			. override_failure_message(
				"'%s' is not the raider's doing — it must never name them" % outcome
			)
			. not_contains([outcome])
		)


## The tank gate is the guildmaster's decision, not the tank's mistake. If this
## ever costs him rating, the game starts teaching the player to bench the man
## they failed to gear.
func test_being_out_damaged_costs_the_tank_nothing() -> void:
	assert_float(RatingEngine.delta_for(Timeline.OUTCOME_TANK_OVERWHELMED)).is_equal(0.0)


## A raider caught by the raid's healing running dry rolled nothing he controlled.
func test_a_cascade_death_costs_its_victim_nothing() -> void:
	assert_float(RatingEngine.delta_for(Timeline.OUTCOME_CASCADE_DEATH)).is_equal(0.0)


## ...but standing in the fire, and dropping a duty you were handed, still do.
## The point is not that nothing is ever anyone's fault.
func test_authored_failures_still_cost_rating() -> void:
	assert_float(RatingEngine.delta_for(Timeline.OUTCOME_DEATH)).is_less(0.0)
	assert_float(RatingEngine.delta_for(Timeline.OUTCOME_DUTY_FAIL)).is_less(0.0)


## The bug MI-004 surfaced: a tank_survival wipe left the tank standing and the
## report showed "0 deaths" on a wipe whose stated cause was the tank dying.
func test_a_tank_survival_wipe_actually_puts_the_tank_on_the_floor() -> void:
	var checked := 0
	for attempt in range(1, 10):
		var result := _wipe(attempt)
		var pull: Dictionary = result["pull"]
		if str(pull["outcome"]) != "wipe":
			continue
		if str(pull["diagnosis"]["primary_cause"]) != "tank_survival":
			continue
		checked += 1
		var deaths := 0
		for participant: Dictionary in result["participants"]:
			if bool(participant["died"]):
				deaths += 1
		(
			assert_int(deaths)
			. override_failure_message("the wipe blames tank survival but nobody is on the floor")
			. is_greater(0)
		)
	(
		assert_int(checked)
		. override_failure_message(
			"no tank_survival wipe produced — the fixture is not exercising the gate"
		)
		. is_greater(0)
	)


## And he is not punished for it — a tank who dies in every single wipe must not
## sink to the bottom of the ratings table for a readiness gap he does not own.
func test_the_out_damaged_tank_does_not_sink_to_the_bottom() -> void:
	var campaign := DemoCampaign.build(133742)
	var db: Variant = campaign["db"]
	var prep := RaidPrep.build(db, int(campaign["event_id"]))
	var night := NightRunner.run_night(
		db, 133742, int(campaign["guild_id"]), int(campaign["event_id"]), prep
	)
	var report: Dictionary = night["report"]
	var incumbent := int(campaign["scenario"]["incumbent_id"])

	var tank := {}
	var worst := 99.0
	for row: Dictionary in report["ratings"]:
		worst = minf(worst, float(row["avg_rating"]))
		if int(row["avatar_id"]) == incumbent:
			tank = row
	assert_dict(tank).is_not_empty()
	# he falls in essentially every pull...
	assert_int(int(tank["deaths"])).is_greater(0)
	# ...and is still not the worst-rated raider in the guild
	(
		assert_float(float(tank["avg_rating"]))
		. override_failure_message(
			(
				"the out-damaged tank rated %.1f, the guild's worst — he is being scapegoated"
				% float(tank["avg_rating"])
			)
		)
		. is_greater(worst)
	)
	db.close_db()


# --- recurrence ---------------------------------------------------------------


## `wipe_reason` embeds margins and probabilities ("margin -18.6, p=0.07"), so it
## is unique per pull. Tallying it meant every count came out as 1 and recurrence
## — the sentence that tells a player they are stuck on ONE wall — could never
## appear. The report groups on the PRIMARY CAUSE.
func test_recurrence_groups_wipes_by_cause_not_by_the_numeric_string() -> void:
	var campaign := DemoCampaign.build(133742)
	var db: Variant = campaign["db"]
	var prep := RaidPrep.build(db, int(campaign["event_id"]))
	var night := NightRunner.run_night(
		db, 133742, int(campaign["guild_id"]), int(campaign["event_id"]), prep
	)
	var report: Dictionary = night["report"]

	assert_array(report["top_wipe_reasons"]).is_not_empty()
	var top: Dictionary = report["top_wipe_reasons"][0]
	(
		assert_int(int(top["count"]))
		. override_failure_message(
			"wipes are not grouping — every cause counted once, so recurrence is invisible"
		)
		. is_greater(1)
	)
	assert_str(str(top["label"])).is_not_empty()

	var said_it := false
	for boss: Dictionary in report["bosses"]:
		if not str(boss["recurrence"]).is_empty():
			said_it = true
			assert_str(str(boss["recurrence"])).contains("wipes here")
	(
		assert_bool(said_it)
		. override_failure_message(
			"a night of repeated wipes on the same wall never surfaced recurrence"
		)
		. is_true()
	)
	db.close_db()
