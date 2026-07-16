extends GdUnitTestSuite

## M5-004 — the between-nights action resolver. Proves each lane writes its real
## fields, growth respects the ceiling, the weekly budget is a hard wall, refusals
## never half-apply, outputs are bounded above zero, and everything is deterministic.

const SEED := 12345


func _campaign() -> Dictionary:
	var handle := Genesis.new_in_memory({"seed": SEED})
	assert_dict(handle).is_not_empty()
	return handle


func _scalar(db: Variant, sql: String) -> Variant:
	db.query(sql)
	if db.query_result.is_empty():
		return null
	var row: Dictionary = db.query_result[0]
	return row[row.keys()[0]]


func _do(
	c: Dictionary, slug: String, target: String, players: Array, params: Dictionary = {}
) -> Dictionary:
	return ActionResolver.resolve_and_persist(
		c["db"],
		int(c["guild_id"]),
		int(c["week_id"]),
		slug,
		target,
		players,
		RngStream.derive(SEED, slug),
		params
	)


func _first_player(db: Variant) -> int:
	return int(_scalar(db, "SELECT player_id FROM guild_membership ORDER BY player_id LIMIT 1"))


# --- each lane writes its real fields -------------------------------------------


func test_gearing_awards_marks() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	var before := int(_scalar(db, "SELECT marks FROM avatar WHERE player_id = %d" % pid))
	var result := _do(c, "dungeon_run", "party", [pid])
	assert_bool(bool(result["ok"])).is_true()
	var after := int(_scalar(db, "SELECT marks FROM avatar WHERE player_id = %d" % pid))
	assert_int(after - before).is_equal(int(result["output_qty"]))
	assert_int(after - before).is_greater(0)
	db.close_db()


func test_development_raises_the_weakest_facet_and_familiarity() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	# pin the facets so the weakest is unambiguous and the ceiling is far away
	db.query_with_bindings(
		(
			"UPDATE player SET execution = 40, awareness = 60, consistency = 60,"
			+ " potential = 90, growth_rate = 50 WHERE player_id = ?;"
		),
		[pid]
	)
	var result := _do(c, "drill", str(pid), [pid])
	assert_bool(bool(result["ok"])).is_true()
	var execution := int(_scalar(db, "SELECT execution FROM player WHERE player_id = %d" % pid))
	assert_int(execution).override_failure_message("the weakest facet did not move").is_greater(40)
	# and the other facets did not move
	(
		assert_int(int(_scalar(db, "SELECT awareness FROM player WHERE player_id = %d" % pid)))
		. is_equal(60)
	)

	var fam_before := int(_scalar(db, "SELECT familiarity FROM avatar WHERE player_id = %d" % pid))
	var spec := _do(c, "spec_test", str(pid), [pid])
	assert_bool(bool(spec["ok"])).is_true()
	var fam_after := int(_scalar(db, "SELECT familiarity FROM avatar WHERE player_id = %d" % pid))
	assert_int(fam_after - fam_before).is_equal(int(spec["output_qty"]))
	db.close_db()


func test_growth_respects_the_potential_ceiling() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	# every facet AT potential: the drill must honestly produce zero facet gain
	db.query_with_bindings(
		(
			"UPDATE player SET execution = 70, awareness = 70, consistency = 70,"
			+ " potential = 70 WHERE player_id = ?;"
		),
		[pid]
	)
	var result := _do(c, "drill", str(pid), [pid])
	assert_bool(bool(result["ok"])).is_true()
	(
		assert_int(int(_scalar(db, "SELECT execution FROM player WHERE player_id = %d" % pid)))
		. is_equal(70)
	)
	db.close_db()


func test_supply_farms_buys_and_converts_with_a_ledger_trail() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)

	var farm := _do(c, "farm_mats", "mats", [pid])
	assert_bool(bool(farm["ok"])).is_true()
	assert_int(int(_scalar(db, "SELECT mats FROM guild_treasury"))).is_equal(
		int(farm["output_qty"])
	)

	var gold_before := int(_scalar(db, "SELECT gold FROM guild_treasury"))
	var buy := _do(c, "buy_consumables", "hearthstew", [pid], {"qty": 3})
	assert_bool(bool(buy["ok"])).is_true()
	var gold_after := int(_scalar(db, "SELECT gold FROM guild_treasury"))
	assert_int(gold_before - gold_after).is_equal(3 * 5)  # hearthstew costs 5
	(
		assert_int(
			int(
				_scalar(
					db,
					(
						"SELECT quantity FROM guild_stockpile gs JOIN consumable cn"
						+ " ON cn.consumable_id = gs.consumable_id WHERE cn.slug = 'hearthstew'"
					)
				)
			)
		)
		. is_equal(3)
	)

	# every supply mutation left an audit row
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM treasury_ledger"))).is_greater_equal(2)
	db.close_db()


func test_buying_without_gold_is_refused_and_nothing_moves() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	db.query("UPDATE guild_treasury SET gold = 2;")
	var buy := _do(c, "buy_consumables", "emberflask", [_first_player(db)], {"qty": 3})
	assert_bool(bool(buy["ok"])).is_false()
	assert_str(str(buy["error"])).contains("not enough gold")
	# nothing moved, nothing was audited
	assert_int(int(_scalar(db, "SELECT gold FROM guild_treasury"))).is_equal(2)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM week_action"))).is_equal(0)
	db.close_db()


func test_people_lifts_morale_and_nudges_loyalty() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	var loyalty_before := int(
		_scalar(db, "SELECT loyalty_current FROM player WHERE player_id = %d" % pid)
	)
	var result := _do(c, "one_on_one", str(pid), [pid])
	assert_bool(bool(result["ok"])).is_true()
	var morale := int(
		_scalar(
			db,
			(
				"SELECT morale FROM player_week_state WHERE player_id = %d AND week_id = %d"
				% [pid, int(c["week_id"])]
			)
		)
	)
	assert_int(morale).is_greater(50)  # the neutral default
	(
		assert_int(
			int(_scalar(db, "SELECT loyalty_current FROM player WHERE player_id = %d" % pid))
		)
		. is_greater(loyalty_before)
	)
	db.close_db()


func test_social_night_lifts_everyone_and_warms_a_few_pairs() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var result := _do(c, "social_night", "", [])
	assert_bool(bool(result["ok"])).is_true()
	# broad: every snapshot row moved above the neutral default
	(
		assert_int(
			int(
				_scalar(
					db,
					(
						"SELECT COUNT(*) FROM player_week_state WHERE week_id = %d AND morale <= 50"
						% int(c["week_id"])
					)
				)
			)
		)
		. is_equal(0)
	)
	# relationship-lite: at least one pair warmed
	(
		assert_int(
			int(_scalar(db, "SELECT COUNT(*) FROM relationship WHERE origin = 'social_night'"))
		)
		. is_greater(0)
	)
	db.close_db()


func test_rest_recovers_fatigue() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_id := int(c["week_id"])
	WeekState.ensure(db, week_id)
	db.query_with_bindings(
		"UPDATE player_week_state SET fatigue = 20 WHERE week_id = ?;", [week_id]
	)
	var result := _do(c, "rest_week", "", [])
	assert_bool(bool(result["ok"])).is_true()
	var avg := float(
		_scalar(db, "SELECT AVG(fatigue) FROM player_week_state WHERE week_id = %d" % week_id)
	)
	assert_float(avg).is_equal(20.0 - float(result["output_qty"]))
	db.close_db()


# --- hardening from the M5-004 review ---------------------------------------------


## A purchase with no qty (or a non-positive one) is a caller bug — refused up
## front, never silently defaulted.
func test_buy_without_a_positive_qty_is_refused() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	for params in [{}, {"qty": 0}, {"qty": -5}]:
		var buy := _do(c, "buy_consumables", "hearthstew", [pid], params)
		assert_bool(bool(buy["ok"])).is_false()
		assert_str(str(buy["error"])).contains("positive qty")
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM week_action"))).is_equal(0)
	db.close_db()


## The audit row records exactly what was applied — applied and audited quantities
## must be the same number.
func test_the_audit_row_records_exactly_what_was_applied() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var buy := _do(c, "buy_consumables", "hearthstew", [_first_player(db)], {"qty": 2})
	assert_bool(bool(buy["ok"])).is_true()
	var audited := int(_scalar(db, "SELECT output_qty FROM week_action"))
	var applied := int(_scalar(db, "SELECT quantity FROM guild_stockpile"))
	assert_int(audited).is_equal(2)
	assert_int(applied).is_equal(audited)
	db.close_db()


## Roster-wide actions touch THIS guild's current members only — a former member
## keeps their snapshot row, but your social night is not for them.
func test_roster_wide_actions_only_touch_current_members() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var former := _first_player(db)
	db.query_with_bindings(
		"UPDATE guild_membership SET status = 'former' WHERE player_id = ?;", [former]
	)
	WeekState.ensure(db, int(c["week_id"]))
	var result := _do(c, "social_night", "", [])
	assert_bool(bool(result["ok"])).is_true()
	# the former member's morale did not move off the neutral default
	(
		assert_int(
			int(
				_scalar(
					db,
					(
						"SELECT morale FROM player_week_state WHERE player_id = %d AND week_id = %d"
						% [former, int(c["week_id"])]
					)
				)
			)
		)
		. is_equal(50)
	)
	db.close_db()


## The transaction: if any write inside the action fails (here: the ledger insert's
## week FK on a bogus week), the WHOLE action rolls back — treasury untouched.
func test_a_failed_write_rolls_the_whole_action_back() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	var result := ActionResolver.resolve_and_persist(
		db, int(c["guild_id"]), 9999, "farm_mats", "mats", [pid], RngStream.derive(SEED, "tx")
	)
	assert_bool(bool(result["ok"])).is_false()
	# the treasury mutation inside the failed action was rolled back
	assert_int(int(_scalar(db, "SELECT mats FROM guild_treasury"))).is_equal(0)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM treasury_ledger"))).is_equal(0)
	db.close_db()


# --- the rules -------------------------------------------------------------------


func test_the_weekly_budget_is_a_hard_wall() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	var budget := int(Tuning.section("action").get("weekly_time_budget", 5))
	# spend the whole budget on distinct drill targets
	db.query("SELECT player_id FROM guild_membership ORDER BY player_id;")
	var ids: Array = db.query_result.duplicate().map(func(r): return int(r["player_id"]))
	for i in budget:
		var r := _do(c, "drill", str(ids[i]), [ids[i]])
		assert_bool(bool(r["ok"])).is_true()
	assert_int(ActionResolver.slots_remaining(db, int(c["guild_id"]), int(c["week_id"]))).is_equal(
		0
	)
	var over := _do(c, "rest_week", "", [])
	assert_bool(bool(over["ok"])).is_false()
	assert_str(str(over["error"])).contains("slots are spent")
	db.close_db()


## The ordering bug the first draft had: a duplicate must be refused BEFORE any lane
## write applies — a refusal that half-applies is worse than either outcome.
func test_a_duplicate_action_is_refused_without_touching_state() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	db.query_with_bindings(
		(
			"UPDATE player SET execution = 40, awareness = 60, consistency = 60, potential = 90"
			+ " WHERE player_id = ?;"
		),
		[pid]
	)
	assert_bool(bool(_do(c, "drill", str(pid), [pid])["ok"])).is_true()
	var facet_after_first := int(
		_scalar(db, "SELECT execution FROM player WHERE player_id = %d" % pid)
	)
	var repeat := _do(c, "drill", str(pid), [pid])
	assert_bool(bool(repeat["ok"])).is_false()
	assert_str(str(repeat["error"])).contains("already done this week")
	(
		assert_int(int(_scalar(db, "SELECT execution FROM player WHERE player_id = %d" % pid)))
		. is_equal(facet_after_first)
	)
	db.close_db()


func test_rolled_outputs_are_bounded_and_never_zero() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var action := {"lane": "gearing", "roll_inputs": "execution", "output_range": "8-16"}
	# sweep quality across many rng draws: output stays inside [8, 16], never zero
	for i in 40:
		var result := ActionResolver.resolve(
			action, [{"execution": 10 + i * 2}], Tuning.section("action"), RngStream.derive(i, "b")
		)
		assert_int(int(result["output_qty"])).is_between(8, 16)
	db.close_db()


func test_same_seed_same_week() -> void:
	assert_str(_week_digest()).is_equal(_week_digest())


func _week_digest() -> String:
	var c := _campaign()
	var db: Variant = c["db"]
	var pid := _first_player(db)
	var rng := RngStream.derive(SEED, "digest")
	var out: PackedStringArray = []
	for slug in ["dungeon_run", "drill", "farm_mats", "one_on_one", "rest_week"]:
		var r := ActionResolver.resolve_and_persist(
			db,
			int(c["guild_id"]),
			int(c["week_id"]),
			slug,
			str(pid),
			[pid] if slug != "rest_week" else [],
			rng.substream(slug)
		)
		out.append("%s:%s:%s" % [slug, r.get("output_qty", "x"), r.get("outcome", "")])
	db.close_db()
	return "\n".join(out)
