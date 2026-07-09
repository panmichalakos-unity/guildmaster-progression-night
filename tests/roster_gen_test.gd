extends GdUnitTestSuite

## M2-002: roster generation — determinism, correlation, believability, persistence.

const ROSTER_SIZE := 28

var _db: Variant
var _presets: Array = []


func before() -> void:
	_db = SimFixture.new_campaign_db()
	assert_object(_db).is_not_null()
	_db.query("SELECT * FROM life_situation;")
	_presets = _db.query_result.duplicate()
	assert_int(_presets.size()).is_equal(6)


func after() -> void:
	_db.close_db()


func _roster(seed_value: int = SimFixture.TEST_SEED, count: int = ROSTER_SIZE) -> Array[Dictionary]:
	return RosterGen.generate(_presets, count, RngStream.derive(seed_value, "roster_gen"))


func test_same_seed_identical_roster() -> void:
	assert_array(_roster()).is_equal(_roster())


func test_different_seed_diverges() -> void:
	assert_array(_roster(1)).is_not_equal(_roster(2))


func test_roster_size_and_required_fields() -> void:
	var players := _roster()
	assert_int(players.size()).is_equal(ROSTER_SIZE)
	for player in players:
		for field in [
			"handle",
			"life_situation_id",
			"execution",
			"awareness",
			"consistency",
			"potential",
			"growth_rate",
			"ego",
			"loyalty_baseline",
			"loyalty_current",
			"volatility",
			"coachability",
			"influence",
			"time_budget_hrs",
			"schedule_volatility",
			"burnout_sensitivity",
			"attendance_reliability",
		]:
			(
				assert_bool(player.has(field))
				. override_failure_message("player missing field '%s'" % field)
				. is_true()
			)


func test_traits_within_bounds() -> void:
	for player in _roster():
		for field in [
			"execution",
			"awareness",
			"consistency",
			"potential",
			"growth_rate",
			"ego",
			"loyalty_baseline",
			"volatility",
			"coachability",
			"influence",
			"schedule_volatility",
			"burnout_sensitivity",
			"attendance_reliability",
		]:
			var v := int(player[field])
			(
				assert_bool(v >= 5 and v <= 95)
				. override_failure_message("%s=%d out of 5..95" % [field, v])
				. is_true()
			)
		var hrs := int(player["time_budget_hrs"])
		assert_bool(hrs >= 4 and hrs <= 16).is_true()


func test_loyalty_current_starts_at_baseline() -> void:
	for player in _roster():
		assert_int(int(player["loyalty_current"])).is_equal(int(player["loyalty_baseline"]))


func test_handles_unique_and_presets_diverse() -> void:
	var players := _roster()
	var handles := {}
	var presets_used := {}
	for player in players:
		handles[str(player["handle"]).to_lower()] = true
		presets_used[int(player["life_situation_id"])] = true
	assert_int(handles.size()).is_equal(ROSTER_SIZE)
	assert_int(presets_used.size()).is_greater_equal(4)


func test_roster_has_texture_not_grey_goo() -> void:
	var players := _roster()
	var best := 0
	var worst := 100
	var total := 0.0
	for player in players:
		var e := int(player["execution"])
		best = maxi(best, e)
		worst = mini(worst, e)
		total += e
	var mean := total / players.size()
	var variance := 0.0
	for player in players:
		variance += pow(int(player["execution"]) - mean, 2)
	var stddev := sqrt(variance / players.size())
	assert_int(best).override_failure_message("no star: best execution %d" % best).is_greater_equal(
		65
	)
	(
		assert_int(worst)
		. override_failure_message("no fringe: worst execution %d" % worst)
		. is_less_equal(45)
	)
	assert_float(stddev).override_failure_message("flat roster: stddev %f" % stddev).is_greater(8.0)


func test_correlated_traits_not_independent() -> void:
	# talent drives both execution and awareness -> must correlate positively
	# across a large sample; youth (potential) anti-correlates with experience
	# proxies like influence. Sample 300 for stability.
	var players := _roster(SimFixture.TEST_SEED, 300)
	var exec_aware := _pearson(players, "execution", "awareness")
	(
		assert_float(exec_aware)
		. override_failure_message("execution/awareness correlation too weak: %f" % exec_aware)
		. is_greater(0.25)
	)
	var consist_loyal := _pearson(players, "consistency", "loyalty_baseline")
	(
		assert_float(consist_loyal)
		. override_failure_message("consistency/loyalty correlation too weak: %f" % consist_loyal)
		. is_greater(0.15)
	)
	var growth_influence := _pearson(players, "growth_rate", "influence")
	(
		assert_float(growth_influence)
		. override_failure_message(
			"growth/influence should not strongly co-move: %f" % growth_influence
		)
		. is_less(0.5)
	)


func test_persist_roundtrip() -> void:
	var players := _roster()
	var ids := RosterGen.persist(_db, players)
	assert_int(ids.size()).is_equal(ROSTER_SIZE)
	_db.query("SELECT COUNT(*) AS n FROM player;")
	assert_int(int(_db.query_result[0]["n"])).is_equal(ROSTER_SIZE)
	_db.query_with_bindings(
		"SELECT handle, execution, loyalty_current FROM player WHERE player_id = ?;", [ids[0]]
	)
	var row: Dictionary = _db.query_result[0]
	assert_str(str(row["handle"])).is_equal(str(players[0]["handle"]))
	assert_int(int(row["execution"])).is_equal(int(players[0]["execution"]))
	# FK integrity: every player's life_situation resolves
	_db.query(
		(
			"SELECT COUNT(*) AS n FROM player p LEFT JOIN life_situation ls "
			+ "ON ls.life_situation_id = p.life_situation_id WHERE ls.life_situation_id IS NULL;"
		)
	)
	assert_int(int(_db.query_result[0]["n"])).is_equal(0)


func test_generate_from_db_matches_pure_generate() -> void:
	var via_db := RosterGen.generate_from_db(
		_db, ROSTER_SIZE, RngStream.derive(SimFixture.TEST_SEED, "roster_gen")
	)
	assert_array(via_db).is_equal(_roster())


func _pearson(players: Array[Dictionary], field_a: String, field_b: String) -> float:
	var n := players.size()
	var sum_a := 0.0
	var sum_b := 0.0
	for p in players:
		sum_a += int(p[field_a])
		sum_b += int(p[field_b])
	var mean_a := sum_a / n
	var mean_b := sum_b / n
	var cov := 0.0
	var var_a := 0.0
	var var_b := 0.0
	for p in players:
		var delta_a := int(p[field_a]) - mean_a
		var delta_b := int(p[field_b]) - mean_b
		cov += delta_a * delta_b
		var_a += delta_a * delta_a
		var_b += delta_b * delta_b
	if var_a == 0.0 or var_b == 0.0:
		return 0.0
	return cov / sqrt(var_a * var_b)
