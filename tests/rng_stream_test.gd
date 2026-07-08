extends GdUnitTestSuite

## M2-001: determinism contract tests for RngStream + the SimFixture pattern.

const DRAWS := 200


func _int_sequence(stream: RngStream, n: int = DRAWS) -> Array[int]:
	var sequence: Array[int] = []
	for _i in n:
		sequence.append(stream.randi_range(0, 1000000))
	return sequence


func _float_sequence(stream: RngStream, n: int = DRAWS) -> Array[float]:
	var sequence: Array[float] = []
	for _i in n:
		sequence.append(stream.randf())
	return sequence


func test_same_seed_same_name_same_sequence() -> void:
	var a := RngStream.derive(SimFixture.TEST_SEED, "resolution")
	var b := RngStream.derive(SimFixture.TEST_SEED, "resolution")
	assert_array(_int_sequence(a)).is_equal(_int_sequence(b))
	# and float draws are bit-identical too
	var c := RngStream.derive(SimFixture.TEST_SEED, "resolution")
	var d := RngStream.derive(SimFixture.TEST_SEED, "resolution")
	assert_array(_float_sequence(c)).is_equal(_float_sequence(d))


func test_different_stream_names_diverge() -> void:
	var a := RngStream.derive(SimFixture.TEST_SEED, "roster_gen")
	var b := RngStream.derive(SimFixture.TEST_SEED, "resolution")
	assert_array(_int_sequence(a)).is_not_equal(_int_sequence(b))


func test_different_master_seeds_diverge() -> void:
	var a := RngStream.derive(1, "resolution")
	var b := RngStream.derive(2, "resolution")
	assert_array(_int_sequence(a)).is_not_equal(_int_sequence(b))


func test_substream_fork_does_not_disturb_parent() -> void:
	# parent A: draws with a substream fork + draws interleaved
	var parent_a := RngStream.derive(SimFixture.TEST_SEED, "roster_gen")
	var first_half_a := _int_sequence(parent_a, 50)
	var sub := parent_a.substream("traits")
	_int_sequence(sub, 50)  # consume the fork — must not advance the parent
	var second_half_a := _int_sequence(parent_a, 50)
	# parent B: same draws, no fork at all
	var parent_b := RngStream.derive(SimFixture.TEST_SEED, "roster_gen")
	var first_half_b := _int_sequence(parent_b, 50)
	var second_half_b := _int_sequence(parent_b, 50)
	assert_array(first_half_a).is_equal(first_half_b)
	assert_array(second_half_a).is_equal(second_half_b)


func test_substream_is_deterministic_and_path_tracked() -> void:
	var a := RngStream.derive(SimFixture.TEST_SEED, "roster_gen").substream("traits")
	var b := RngStream.derive(SimFixture.TEST_SEED, "roster_gen").substream("traits")
	assert_array(_int_sequence(a)).is_equal(_int_sequence(b))
	assert_str(a.stream_path).is_equal("roster_gen/traits")


func test_weighted_pick_deterministic_and_skips_zero_weights() -> void:
	var items := ["kill", "wipe", "never"]
	var weights := [70, 30, 0]
	var a := SimFixture.rng("events")
	var b := SimFixture.rng("events")
	var picks_a: Array[String] = []
	var picks_b: Array[String] = []
	for _i in DRAWS:
		picks_a.append(a.weighted_pick(items, weights))
		picks_b.append(b.weighted_pick(items, weights))
	assert_array(picks_a).is_equal(picks_b)
	assert_bool("never" in picks_a).is_false()
	assert_bool("kill" in picks_a and "wipe" in picks_a).is_true()


func test_weighted_pick_edge_cases() -> void:
	var stream := SimFixture.rng("events")
	assert_that(stream.weighted_pick([], [])).is_null()
	assert_that(stream.weighted_pick(["a"], [0])).is_null()
	assert_str(stream.weighted_pick(["only"], [5])).is_equal("only")


func test_shuffle_is_deterministic_permutation() -> void:
	var items_a := range(30)
	var items_b := range(30)
	SimFixture.rng("lineup").shuffle(items_a)
	SimFixture.rng("lineup").shuffle(items_b)
	assert_array(items_a).is_equal(items_b)
	var sorted_copy := items_a.duplicate()
	sorted_copy.sort()
	assert_array(sorted_copy).is_equal(range(30))  # still a permutation


func test_ranges_respect_bounds() -> void:
	var stream := SimFixture.rng("bounds")
	for _i in DRAWS:
		var v := stream.randi_range(3, 7)
		assert_bool(v >= 3 and v <= 7).is_true()
		var f := stream.randf_range(-1.5, 1.5)
		assert_bool(f >= -1.5 and f <= 1.5).is_true()


func test_draw_count_tracks_observability() -> void:
	var stream := SimFixture.rng("audit")
	assert_int(stream.draw_count).is_equal(0)
	stream.randf()
	stream.randi_range(0, 9)
	stream.pick([1, 2, 3])
	assert_int(stream.draw_count).is_equal(3)


func test_fixture_provides_seeded_campaign_db() -> void:
	var db: Variant = SimFixture.new_campaign_db()
	assert_object(db).is_not_null()
	db.query("SELECT COUNT(*) AS n FROM spec;")
	assert_int(int(db.query_result[0]["n"])).is_equal(18)
	db.close_db()
