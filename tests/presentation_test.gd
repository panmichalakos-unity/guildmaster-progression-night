extends GdUnitTestSuite

## MI-004 — the presentation contract, where it is testable in the pure sim.
##
## The combat log is a thin renderer, so the things that make the show WORK are
## engine facts: every event can be weighted, and every pull ends with a beat that
## says how it ended. Styling is not testable headless; these two are, and they are
## the ones that were actually broken.
##
## See docs/guildmaster-presentation.md.

const BOSS := "gatewarden_krogg"


func test_notability_tiers_are_the_documented_four() -> void:
	assert_array(PullContracts.NOTABILITY).is_equal(["routine", "notable", "critical", "decisive"])


func test_the_pull_turning_is_decisive() -> void:
	# a tank death IS the wipe; the fight's own closing beat is the climax
	assert_str(PullContracts.notability_for(Timeline.OUTCOME_TANK_DEATH)).is_equal("decisive")
	assert_str(PullContracts.notability_for(Timeline.OUTCOME_BOSS_DOWN)).is_equal("decisive")
	assert_str(PullContracts.notability_for(Timeline.OUTCOME_WIPE_CALL)).is_equal("decisive")


func test_consequence_is_critical_and_texture_recedes() -> void:
	for outcome in [Timeline.OUTCOME_DEATH, Timeline.OUTCOME_DUTY_FAIL, Timeline.OUTCOME_SAVE]:
		assert_str(PullContracts.notability_for(outcome)).is_equal("critical")
	for outcome in [Timeline.OUTCOME_SURVIVED, Timeline.OUTCOME_SURGE]:
		assert_str(PullContracts.notability_for(outcome)).is_equal("notable")
	# a clean duty and an unrecognised beat are texture — they must not cry wolf
	assert_str(PullContracts.notability_for(Timeline.OUTCOME_DUTY_OK)).is_equal("routine")
	assert_str(PullContracts.notability_for("a_new_event_type_nobody_tiered")).is_equal("routine")


## The bug this ticket found: the verdict was computed AFTER the timeline and never
## written into the log, so a tank-gate wipe read as a few forgettable lines and
## then a verdict from nowhere. Every pull must now SAY how it ended.
func test_every_pull_ends_with_a_decisive_closing_beat() -> void:
	for attempt in range(1, 9):
		var campaign := DemoCampaign.build(133742)
		var db: Variant = campaign["db"]
		var result := PullResolver.resolve(
			PullInputLoader.build(db, BOSS, PullInputLoader.auto_lineup(db)),
			RngStream.derive(4400 + attempt, "presentation")
		)
		var events: Array = result["events"]
		assert_array(events).is_not_empty()

		var last: Dictionary = events[events.size() - 1]
		var outcome := str(result["pull"]["outcome"])
		var expected := (
			Timeline.OUTCOME_BOSS_DOWN if outcome == "kill" else Timeline.OUTCOME_WIPE_CALL
		)
		(
			assert_str(str(last["outcome"]))
			. override_failure_message("a %s did not close the log with its own beat" % outcome)
			. is_equal(expected)
		)
		assert_str(PullContracts.notability_for(str(last["outcome"]))).is_equal("decisive")
		assert_str(str(last["log_line"])).is_not_empty()
		db.close_db()


func test_the_closing_beat_names_the_boss_on_a_kill() -> void:
	var campaign := DemoCampaign.build(133742)
	var db: Variant = campaign["db"]
	# a heavily out-geared raid one-shots it, so this reliably reaches a kill
	var result := PullResolver.resolve(
		PullInputLoader.build(db, BOSS, PullInputLoader.auto_lineup(db), {"gear_multiplier": 1.64}),
		RngStream.derive(11, "presentation_kill")
	)
	if str(result["pull"]["outcome"]) != "kill":
		db.close_db()
		return
	var events: Array = result["events"]
	var last: Dictionary = events[events.size() - 1]
	assert_str(str(last["log_line"])).contains("Gatewarden Krogg")
	assert_str(str(last["log_line"])).contains("KILL")
	db.close_db()


## Phase banners cannot be titled from `phase_order` alone — a bare "PHASE 2" is
## not a beat the player feels. The runner hands the screen the phase rows.
func test_the_runner_hands_the_screen_named_phases() -> void:
	var campaign := DemoCampaign.build(133742)
	var db: Variant = campaign["db"]
	var prep := RaidPrep.build(db, int(campaign["event_id"]))
	var step := (
		NightRunner
		. resolve_pull(
			db,
			133742,
			int(campaign["guild_id"]),
			int(campaign["event_id"]),
			prep,
			BOSS,
			1,
		)
	)
	assert_bool(bool(step["ok"])).is_true()
	assert_array(step["phases"]).is_not_empty()
	for phase: Dictionary in step["phases"]:
		assert_str(str(phase["display_name"])).is_not_empty()
	db.close_db()
