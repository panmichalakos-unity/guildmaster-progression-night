extends GdUnitTestSuite

## M4-003/004: night orchestrator + post-night report.


func test_encounter_slugs_are_emberdeep_boss_order() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var slugs := NightRunner.encounter_slugs(campaign["db"], int(campaign["event_id"]))
	assert_int(slugs.size()).is_equal(4)
	assert_str(slugs[0]).is_equal("gatewarden_krogg")
	campaign["db"].close_db()


func test_resolve_pull_persists_events() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	var prep := RaidPrep.build(db, int(campaign["event_id"]))
	var step := (
		NightRunner
		. resolve_pull(
			db,
			int(campaign["seed"]),
			int(campaign["guild_id"]),
			int(campaign["event_id"]),
			{
				"lineup_ids": prep["lineup_ids"],
				"assignments": prep["assignments"],
				"consumable_tier": "basic",
			},
			"gatewarden_krogg",
			1
		)
	)
	assert_bool(bool(step["ok"])).is_true()
	assert_int(int(step["pull_id"])).is_greater(0)
	assert_array(step["result"]["events"]).is_not_empty()
	assert_str(str(step["result"]["events"][0]["log_line"])).is_not_empty()
	db.close_db()


func test_same_seed_same_pull_outcome() -> void:
	var a := _one_krogg_pull(SimFixture.TEST_SEED)
	var b := _one_krogg_pull(SimFixture.TEST_SEED)
	assert_str(a["outcome"]).is_equal(b["outcome"])
	assert_str(a["wipe_reason"]).is_equal(b["wipe_reason"])
	assert_int(a["event_count"]).is_equal(b["event_count"])


func test_run_night_builds_report() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	var prep := RaidPrep.build(db, int(campaign["event_id"]))
	var night := (
		NightRunner
		. run_night(
			db,
			int(campaign["seed"]),
			int(campaign["guild_id"]),
			int(campaign["event_id"]),
			{
				"lineup_ids": prep["lineup_ids"],
				"assignments": prep["assignments"],
				"consumable_tier": "basic",
			}
		)
	)
	assert_bool(bool(night["ok"])).is_true()
	assert_int(night["pulls"].size()).is_greater_equal(4)
	var report: Dictionary = night["report"]
	assert_int(int(report["pull_count"])).is_equal(night["pulls"].size())
	assert_int(report["bosses"].size()).is_equal(4)
	assert_array(report["ratings"]).is_not_empty()
	assert_str(str(report["summary_line"])).is_not_empty()
	db.close_db()


func _one_krogg_pull(seed_value: int) -> Dictionary:
	var campaign := DemoCampaign.build(seed_value)
	var db: Variant = campaign["db"]
	var prep := RaidPrep.build(db, int(campaign["event_id"]))
	var step := (
		NightRunner
		. resolve_pull(
			db,
			seed_value,
			int(campaign["guild_id"]),
			int(campaign["event_id"]),
			{
				"lineup_ids": prep["lineup_ids"],
				"assignments": prep["assignments"],
				"consumable_tier": "basic",
			},
			"gatewarden_krogg",
			1
		)
	)
	var pull: Dictionary = step["result"]["pull"]
	var out := {
		"outcome": str(pull["outcome"]),
		"wipe_reason": str(pull["wipe_reason"]),
		"event_count": step["result"]["events"].size(),
	}
	db.close_db()
	return out
