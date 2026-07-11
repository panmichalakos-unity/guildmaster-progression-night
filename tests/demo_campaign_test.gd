extends GdUnitTestSuite

## M4-001: the demo campaign builder + theme — the slice's data entry point.
## Proves the WHOLE slice loop headless: build night -> lineup -> resolve ->
## persist, so the UI screens (M4-002..004) only ever render, never compute.


func test_build_returns_a_playable_night() -> void:
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	assert_bool(campaign.is_empty()).is_false()
	var db: Variant = campaign["db"]
	db.query("SELECT COUNT(*) AS n FROM avatar WHERE is_active = 1;")
	assert_int(int(db.query_result[0]["n"])).is_equal(28)
	db.query("SELECT display_name, is_player_guild FROM guild;")
	assert_int(int(db.query_result[0]["is_player_guild"])).is_equal(1)
	assert_str(str(db.query_result[0]["display_name"])).is_equal(DemoCampaign.DEMO_GUILD_NAME)
	db.query("SELECT event_type, status FROM calendar_event;")
	assert_str(str(db.query_result[0]["event_type"])).is_equal("raid")
	assert_int(int(campaign["guild_id"])).is_greater(0)
	assert_int(int(campaign["event_id"])).is_greater(0)
	db.close_db()


func test_same_seed_builds_the_same_night() -> void:
	var a := DemoCampaign.build(SimFixture.TEST_SEED)
	var b := DemoCampaign.build(SimFixture.TEST_SEED)
	var text_a := RosterReport.to_text(RosterReport.build(a["db"]))
	var text_b := RosterReport.to_text(RosterReport.build(b["db"]))
	assert_str(text_a).is_equal(text_b)
	a["db"].close_db()
	b["db"].close_db()


func test_slice_loop_resolves_and_persists_end_to_end() -> void:
	# the full raid-night loop the M4 screens will render, with zero UI
	var campaign := DemoCampaign.build(SimFixture.TEST_SEED)
	var db: Variant = campaign["db"]
	var lineup := PullInputLoader.auto_lineup(db)
	var input := PullInputLoader.build(
		db, "gatewarden_krogg", lineup, {"guild_id": int(campaign["guild_id"])}
	)
	assert_array(PullContracts.validate_input(input)).is_empty()
	var result := PullResolver.resolve(input, RngStream.derive(int(campaign["seed"]), "pull"))
	assert_array(PullContracts.validate_result(result)).is_empty()
	var pull_id := PullResolver.persist(
		db, int(campaign["guild_id"]), int(campaign["event_id"]), 1, result
	)
	assert_int(pull_id).is_greater(0)
	db.query("SELECT COUNT(*) AS n FROM pull_event WHERE pull_id = %d;" % pull_id)
	assert_int(int(db.query_result[0]["n"])).is_greater(0)
	db.close_db()


func test_theme_builder_returns_a_usable_theme() -> void:
	var theme := ThemeBuilder.build()
	assert_object(theme).is_not_null()
	assert_int(theme.default_font_size).is_equal(ThemeBuilder.FONT_SIZE)
	assert_bool(theme.has_stylebox("panel", "PanelContainer")).is_true()
	assert_bool(theme.has_stylebox("normal", "Button")).is_true()
	assert_bool(theme.has_color("font_color", "Label")).is_true()
