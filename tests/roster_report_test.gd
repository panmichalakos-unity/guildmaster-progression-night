extends GdUnitTestSuite

## M2-004: roster report read model + whole-chain cross-DB determinism.

const ROSTER_SIZE := 28


func _full_chain_db(seed_value: int) -> Variant:
	var db: Variant = SimFixture.new_campaign_db()
	assert_object(db).is_not_null()
	var players := RosterGen.generate_from_db(
		db, ROSTER_SIZE, RngStream.derive(seed_value, "roster_gen")
	)
	assert_int(RosterGen.persist(db, players).size()).is_equal(ROSTER_SIZE)
	var avatar_ids := AvatarGen.generate_and_persist(db, RngStream.derive(seed_value, "avatar_gen"))
	assert_int(avatar_ids.size()).is_equal(ROSTER_SIZE)
	return db


func test_report_shape_and_coverage() -> void:
	var db: Variant = _full_chain_db(SimFixture.TEST_SEED)
	var report := RosterReport.build(db)
	assert_int(report["players"].size()).is_equal(ROSTER_SIZE)
	var coverage: Dictionary = report["coverage"]
	assert_int(int(coverage["tank"])).is_equal(4)
	assert_int(int(coverage["healer"])).is_equal(7)
	assert_int(int(coverage["melee"])).is_equal(8)
	assert_int(int(coverage["ranged"])).is_equal(9)
	# 4/7/8/9 always satisfies the 20-lineup minima -> no role issues possible
	for issue: String in report["issues"]:
		(
			assert_bool(issue.contains("lineup"))
			. override_failure_message("unexpected role issue on a full roster: %s" % issue)
			. is_false()
		)
	# all 8 utilities are reported (count may legitimately be 0 for a seed)
	assert_int(report["utilities"].size()).is_equal(8)
	db.close_db()


func test_to_text_renders_every_player_and_summary() -> void:
	var db: Variant = _full_chain_db(SimFixture.TEST_SEED)
	var report := RosterReport.build(db)
	var text := RosterReport.to_text(report)
	for p: Dictionary in report["players"]:
		(
			assert_bool(text.contains(str(p["handle"])))
			. override_failure_message("handle %s missing from rendered report" % p["handle"])
			. is_true()
		)
	assert_bool(text.contains("coverage: 4 tank / 7 healer / 8 melee / 9 ranged")).is_true()
	assert_bool(text.contains("roster fingerprint:")).is_true()
	db.close_db()


func test_whole_chain_is_deterministic_across_fresh_dbs() -> void:
	var db_a: Variant = _full_chain_db(SimFixture.TEST_SEED)
	var db_b: Variant = _full_chain_db(SimFixture.TEST_SEED)
	var text_a := RosterReport.to_text(RosterReport.build(db_a))
	var text_b := RosterReport.to_text(RosterReport.build(db_b))
	assert_str(text_a).is_equal(text_b)
	db_a.close_db()
	db_b.close_db()


func test_different_seed_changes_the_roster() -> void:
	var db_a: Variant = _full_chain_db(SimFixture.TEST_SEED)
	var db_b: Variant = _full_chain_db(SimFixture.TEST_SEED + 1)
	var text_a := RosterReport.to_text(RosterReport.build(db_a))
	var text_b := RosterReport.to_text(RosterReport.build(db_b))
	assert_str(text_a).is_not_equal(text_b)
	db_a.close_db()
	db_b.close_db()
