extends GdUnitTestSuite

## M5-001 — guild genesis: the save root, config, and the shared new-game / rebuild
## flow. Proves the campaign is fully created, deterministic per seed, expresses
## Season = Tier, and reuses cleanly for post-sack rebuilds.
##
## The Night One contract that genesis must ALSO satisfy is covered by
## first_night_test.gd (repointed at the genesis path).

const SEED := 12345


func _campaign(config: Dictionary = {}) -> Dictionary:
	if not config.has("seed"):
		config["seed"] = SEED
	var handle := Genesis.new_in_memory(config)
	assert_dict(handle).override_failure_message("genesis returned nothing").is_not_empty()
	return handle


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	if db.query_result.is_empty():
		return null
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]


# --- the campaign is fully created --------------------------------------------


func test_genesis_creates_the_whole_save_root() -> void:
	var c := _campaign()
	var db: Variant = c["db"]

	# the singleton save root + config
	assert_dict(GameState.read(db)).is_not_empty()
	assert_dict(GameConfig.read(db)).is_not_empty()
	# the player guild, its config, its treasury
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM guild WHERE is_player_guild = 1"))).is_equal(1)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM guild_config"))).is_equal(1)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM guild_treasury"))).is_equal(1)
	# a full starting roster, all seated as members
	var roster := int(Tuning.section("genesis").get("roster_size", 28))
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM player"))).is_equal(roster)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM guild_membership WHERE status = 'member'"))).is_equal(
		roster
	)
	# a raid night scheduled for the opening
	assert_int(int(c["event_id"])).is_greater(0)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM calendar_event WHERE event_type = 'raid'"))).is_equal(
		1
	)
	db.close_db()


func test_the_save_root_anchors_at_tier_one() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var state := GameState.read(db)
	# Season = Tier (I-03): a campaign starts at the FIRST season by tier_order
	var first_tier := int(
		_scalar(db, "SELECT tier_order FROM season WHERE season_id = %d" % int(state["season_id"]))
	)
	assert_int(first_tier).override_failure_message(
		"genesis did not anchor at Tier 1 — it started at tier_order %d" % first_tier
	).is_equal(1)
	assert_str(str(state["phase"])).is_equal("plan")
	assert_int(int(state["rng_seed"])).is_equal(SEED)
	db.close_db()


# --- involvement contract (MI-007 / ADR-0033) ---------------------------------


func test_every_involvement_domain_starts_on_the_chosen_preset() -> void:
	# picking "Hands-Off" at genesis writes 'instant' into all six domains
	var c := _campaign({"involvement_default": "instant"})
	var db: Variant = c["db"]
	for domain in GameConfig.DOMAINS:
		assert_str(GameConfig.involvement_for(db, domain)).override_failure_message(
			"domain '%s' did not inherit the 'instant' preset" % domain
		).is_equal("instant")
	db.close_db()


func test_the_audit_column_exists_and_defaults_to_player() -> void:
	# the decided_by column must exist on the fact tables (migration 0004), so the
	# Phase-B screens never need a migration to record who authored a decision
	var c := _campaign()
	var db: Variant = c["db"]
	for table in ["raid_lineup", "raid_assignment", "week_action", "loot_drop"]:
		db.query("SELECT COUNT(*) AS n FROM pragma_table_info('%s') WHERE name = 'decided_by'" % table)
		assert_int(int(db.query_result[0]["n"])).override_failure_message(
			"table '%s' has no decided_by column" % table
		).is_equal(1)
	db.close_db()


# --- determinism --------------------------------------------------------------


func test_same_seed_same_starting_campaign() -> void:
	var a := _campaign()
	var b := _campaign()
	# the roster is the load-bearing random part; compare it in full
	var roster_a := _roster_digest(a["db"])
	var roster_b := _roster_digest(b["db"])
	assert_array(roster_a).is_equal(roster_b)
	# and the curated scenario is identical
	assert_dict(a["scenario"]).is_equal(b["scenario"])
	a["db"].close_db()
	b["db"].close_db()


func test_different_seed_diverges() -> void:
	var a := _campaign({"seed": 111})
	var b := _campaign({"seed": 222})
	assert_array(_roster_digest(a["db"])).is_not_equal(_roster_digest(b["db"]))
	a["db"].close_db()
	b["db"].close_db()


func _roster_digest(db: Variant) -> Array:
	db.query(
		(
			"SELECT p.handle, a.spec_id, a.gear_score, a.uncrittable FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id ORDER BY a.avatar_id;"
		)
	)
	return db.query_result.duplicate()


# --- the rebuild path (M9-004 reuse) ------------------------------------------


func test_rebuild_starts_poorer_than_a_fresh_guild() -> void:
	var fresh := _campaign()
	var rebuild := _campaign({"seed": SEED, "is_rebuild": true})
	var fresh_rep := int(_scalar(fresh["db"], "SELECT reputation FROM guild WHERE is_player_guild = 1"))
	var rebuild_rep := int(
		_scalar(rebuild["db"], "SELECT reputation FROM guild WHERE is_player_guild = 1")
	)
	var fresh_gold := int(_scalar(fresh["db"], "SELECT gold FROM guild_treasury"))
	var rebuild_gold := int(_scalar(rebuild["db"], "SELECT gold FROM guild_treasury"))

	assert_int(rebuild_rep).override_failure_message(
		"a rebuild (%d rep) did not start below a fresh guild (%d rep)" % [rebuild_rep, fresh_rep]
	).is_less(fresh_rep)
	assert_int(rebuild_gold).is_less(fresh_gold)
	fresh["db"].close_db()
	rebuild["db"].close_db()


func test_explicit_overrides_win() -> void:
	var c := _campaign({"reputation_override": 7, "gold_override": 3})
	var db: Variant = c["db"]
	assert_int(int(_scalar(db, "SELECT reputation FROM guild WHERE is_player_guild = 1"))).is_equal(7)
	assert_int(int(_scalar(db, "SELECT gold FROM guild_treasury"))).is_equal(3)
	db.close_db()
