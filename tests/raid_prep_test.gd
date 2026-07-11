extends GdUnitTestSuite

## M4-002: RaidPrep read model — lineup/bench, warnings, assignments.


func test_auto_lineup_is_ready_with_coverage_and_assignments() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	var report := RaidPrep.build(db, int(campaign["event_id"]))
	assert_bool(bool(report["ready"])).is_true()
	assert_int(report["lineup"].size()).is_equal(20)
	assert_int(report["bench"].size()).is_equal(8)
	assert_int(int(report["coverage"]["tank"])).is_greater_equal(2)
	assert_int(int(report["coverage"]["healer"])).is_greater_equal(5)
	assert_array(report["assignment_summary"]).is_not_empty()
	assert_bool(report["assignments"].is_empty()).is_false()
	db.close_db()


func test_toggle_moves_between_lineup_and_bench() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	var report := RaidPrep.build(db, int(campaign["event_id"]))
	var lineup: Array[int] = []
	for avatar_id in report["lineup_ids"]:
		lineup.append(int(avatar_id))
	var benched := int(lineup[0])
	var after_bench := RaidPrep.toggle(lineup, benched)
	assert_int(after_bench.size()).is_equal(19)
	assert_bool(benched in after_bench).is_false()
	var bench_id := int(report["bench"][0]["avatar_id"])
	var after_add := RaidPrep.toggle(after_bench, bench_id)
	assert_int(after_add.size()).is_equal(20)
	assert_bool(bench_id in after_add).is_true()
	db.close_db()


func test_warnings_flag_thin_healer_comp() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	# build a deliberately thin healer lineup: 2 tanks + 2 healers + 16 dps
	var lineup: Array[int] = []
	for role_count: Array in [["tank", 2], ["healer", 2], ["melee", 8], ["ranged", 8]]:
		db.query_with_bindings(
			(
				"SELECT a.avatar_id FROM avatar a"
				+ " JOIN spec s ON s.spec_id = a.spec_id"
				+ " JOIN role r ON r.role_id = s.role_id"
				+ " WHERE r.slug = ? AND a.is_active = 1"
				+ " ORDER BY a.gear_score DESC LIMIT ?;"
			),
			[role_count[0], role_count[1]]
		)
		for row in db.query_result:
			lineup.append(int(row["avatar_id"]))
	var report := RaidPrep.build(db, int(campaign["event_id"]), lineup)
	var texts: Array[String] = []
	for warning: Dictionary in report["warnings"]:
		texts.append(str(warning["text"]))
	var joined := " | ".join(texts)
	assert_bool(joined.contains("healer")).is_true()
	db.close_db()


func test_prep_assignments_flow_into_pull_input() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	var report := RaidPrep.build(db, int(campaign["event_id"]))
	var lineup: Array[int] = []
	for avatar_id in report["lineup_ids"]:
		lineup.append(int(avatar_id))
	var input := (
		PullInputLoader
		. build(
			db,
			"gatewarden_krogg",
			lineup,
			{
				"guild_id": int(campaign["guild_id"]),
				"assignments": report["assignments"],
				"consumable_tier": "basic",
			}
		)
	)
	assert_array(PullContracts.validate_input(input)).is_empty()
	var assigned := 0
	for participant: Dictionary in input["participants"]:
		if not participant["assignments"].is_empty():
			assigned += 1
	assert_int(assigned).is_greater(0)
	db.close_db()
