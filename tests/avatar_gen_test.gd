extends GdUnitTestSuite

## M2-003: avatar/class/spec/gear assignment — coverage, determinism, gear math.

const ROSTER_SIZE := 28

var _db: Variant


func before() -> void:
	_db = SimFixture.new_campaign_db()
	assert_object(_db).is_not_null()
	var players := RosterGen.generate_from_db(
		_db, ROSTER_SIZE, RngStream.derive(SimFixture.TEST_SEED, "roster_gen")
	)
	assert_int(RosterGen.persist(_db, players).size()).is_equal(ROSTER_SIZE)


func after() -> void:
	_db.close_db()


func _player_rows() -> Array:
	_db.query("SELECT player_id, growth_rate, execution FROM player ORDER BY player_id;")
	return _db.query_result.duplicate()


func _avatars(seed_value: int = SimFixture.TEST_SEED) -> Array[Dictionary]:
	return AvatarGen.generate(_db, _player_rows(), RngStream.derive(seed_value, "avatar_gen"))


func test_same_seed_identical_assignments() -> void:
	assert_array(_avatars()).is_equal(_avatars())


func test_different_seed_diverges() -> void:
	assert_array(_avatars(1)).is_not_equal(_avatars(2))


func test_one_avatar_per_player_with_role_coverage() -> void:
	var avatars := _avatars()
	assert_int(avatars.size()).is_equal(ROSTER_SIZE)
	var by_role := {"tank": 0, "healer": 0, "melee": 0, "ranged": 0}
	var player_ids := {}
	for avatar in avatars:
		by_role[str(avatar["role_slug"])] += 1
		player_ids[int(avatar["player_id"])] = true
	assert_int(player_ids.size()).is_equal(ROSTER_SIZE)
	# tuning targets: 4/7/8/9 — and always enough for a 20-lineup (2t/5h/13d)
	assert_int(by_role["tank"]).is_equal(4)
	assert_int(by_role["healer"]).is_equal(7)
	assert_int(by_role["melee"]).is_equal(8)
	assert_int(by_role["ranged"]).is_equal(9)
	assert_bool(by_role["tank"] >= 2 and by_role["healer"] >= 5).is_true()
	assert_bool(by_role["melee"] + by_role["ranged"] >= 13).is_true()


func test_specs_come_from_seed_rows_and_class_matches() -> void:
	for avatar in _avatars():
		_db.query_with_bindings(
			"SELECT class_id, role_id FROM spec WHERE spec_id = ?;", [avatar["spec_id"]]
		)
		assert_int(_db.query_result.size()).is_equal(1)
		var spec: Dictionary = _db.query_result[0]
		assert_int(int(avatar["class_id"])).is_equal(int(spec["class_id"]))
		assert_int(int(avatar["role_id"])).is_equal(int(spec["role_id"]))


func test_gear_score_is_exact_sum_of_slot_levels() -> void:
	for avatar in _avatars():
		var items: Array = avatar["items"]
		assert_int(items.size()).is_equal(7)
		var slot_ids := {}
		var level_sum := 0
		for item: Dictionary in items:
			slot_ids[int(item["slot_id"])] = true
			level_sum += int(item["item_level"])
		assert_int(slot_ids.size()).is_equal(7)  # one item per slot, all 7 slots
		assert_int(int(avatar["gear_score"])).is_equal(level_sum)
		assert_int(int(avatar["item_level"])).is_equal(int(round(level_sum / 7.0)))


func test_caps_derive_from_gear() -> void:
	var caps_by_spec := _defense_caps()
	for avatar in _avatars():
		var avg := int(avatar["item_level"])
		assert_int(int(avatar["hit_capped"])).is_equal(1 if avg >= 20 else 0)
		var cap := int(caps_by_spec[int(avatar["spec_id"])])
		var immune := str(avatar["role_slug"]) == "tank" and cap > 0 and avg >= cap
		assert_int(int(avatar["uncrittable"])).is_equal(1 if immune else 0)
		if int(avatar["uncrittable"]) == 1:
			assert_str(str(avatar["role_slug"])).is_equal("tank")


## ADR-0025 — the whole point of a per-spec defense cap: a BETTER-geared tank can
## still be crittable while a WORSE-geared one is crit-immune. Without this the
## best-geared tank was always the immune one (gear_score is just the sum of the
## same slot item levels), so the tank gate could never be a player decision.
func test_defense_cap_is_per_spec_not_a_gear_threshold() -> void:
	var hide_tank := AvatarGen.derive_caps(24, "tank", 27)
	var plated_tank := AvatarGen.derive_caps(21, "tank", 20)
	assert_int(int(hide_tank["uncrittable"])).is_equal(0)
	assert_int(int(plated_tank["uncrittable"])).is_equal(1)
	# and the cap never applies to a spec that cannot tank
	assert_int(int(AvatarGen.derive_caps(40, "melee", 0)["uncrittable"])).is_equal(0)
	assert_int(int(AvatarGen.derive_caps(40, "tank", 0)["uncrittable"])).is_equal(0)


func _defense_caps() -> Dictionary:
	_db.query("SELECT spec_id, defense_cap_ilvl FROM spec;")
	var by_spec := {}
	for row in _db.query_result:
		by_spec[int(row["spec_id"])] = int(row["defense_cap_ilvl"])
	return by_spec


func test_proficiencies_anchor_on_assigned_role() -> void:
	for avatar in _avatars():
		var rows: Array = avatar["role_proficiencies"]
		assert_int(rows.size()).is_equal(4)
		var assigned_value := 0
		var best_value := 0
		for prof: Dictionary in rows:
			var value := int(prof["proficiency"])
			best_value = maxi(best_value, value)
			if int(prof["role_id"]) == int(avatar["role_id"]):
				assigned_value = value
		assert_int(assigned_value).is_equal(best_value)
		var familiarity := int(avatar["familiarity"])
		assert_bool(familiarity >= 10 and familiarity <= 90).is_true()


func test_persist_roundtrip_with_fk_integrity() -> void:
	var ids := AvatarGen.persist(_db, _avatars())
	assert_int(ids.size()).is_equal(ROSTER_SIZE)
	_db.query("SELECT COUNT(*) AS n FROM avatar WHERE is_active = 1;")
	assert_int(int(_db.query_result[0]["n"])).is_equal(ROSTER_SIZE)
	_db.query("SELECT COUNT(*) AS n FROM avatar_item;")
	assert_int(int(_db.query_result[0]["n"])).is_equal(ROSTER_SIZE * 7)
	_db.query("SELECT COUNT(*) AS n FROM player_role_proficiency;")
	assert_int(int(_db.query_result[0]["n"])).is_equal(ROSTER_SIZE * 4)
	_db.query("PRAGMA foreign_key_check;")
	assert_int(_db.query_result.size()).is_equal(0)
	# persisted gear_score still matches the stored equipped set
	_db.query(
		(
			"SELECT COUNT(*) AS n FROM avatar a WHERE a.gear_score != "
			+ "(SELECT SUM(ai.item_level) FROM avatar_item ai WHERE ai.avatar_id = a.avatar_id);"
		)
	)
	assert_int(int(_db.query_result[0]["n"])).is_equal(0)
