extends GdUnitTestSuite

## M1-004: Phase-A seed coverage gates, engine-side. Runs the REAL pipeline
## (migrate + load data/seeds) — the same path guild genesis will use — and
## asserts the locked content contract from docs/guildmaster-content-and-dod.md.

const MigratorScript := preload("res://sim/db/migrator.gd")
const SeedLoaderScript := preload("res://sim/db/seed_loader.gd")

var _db: Variant


func before() -> void:
	_db = MigratorScript.open_db(":memory:")
	assert_object(_db).is_not_null()
	assert_bool(MigratorScript.migrate(_db).ok).is_true()
	var loaded: Dictionary = SeedLoaderScript.load_seeds(_db)
	(
		assert_bool(loaded.ok)
		. override_failure_message("seed load failed: %s (%s)" % [loaded.error, loaded.failed_file])
		. is_true()
	)


func after() -> void:
	_db.close_db()


func _count(sql: String) -> int:
	_db.query(sql)
	return int(_db.query_result[0]["n"])


func test_class_and_spec_matrix() -> void:
	assert_int(_count("SELECT COUNT(*) AS n FROM class")).is_equal(6)
	assert_int(_count("SELECT COUNT(*) AS n FROM spec")).is_equal(18)
	for role_expect: Array in [["tank", 3], ["healer", 4], ["melee", 5], ["ranged", 6]]:
		var n := _count(
			(
				"SELECT COUNT(*) AS n FROM spec s JOIN role r ON r.role_id = s.role_id "
				+ "WHERE r.slug = '%s'" % role_expect[0]
			)
		)
		(
			assert_int(n)
			. override_failure_message(
				"expected %d %s specs, got %d" % [role_expect[1], role_expect[0], n]
			)
			. is_equal(int(role_expect[1]))
		)


func test_one_raid_with_phase_a_encounters() -> void:
	assert_int(_count("SELECT COUNT(*) AS n FROM raid")).is_equal(1)
	var bosses := _count("SELECT COUNT(*) AS n FROM encounter")
	(
		assert_bool(bosses >= 3 and bosses <= 6)
		. override_failure_message(
			"Phase A wants 3-4 encounters (tier completes in Phase B); got %d" % bosses
		)
		. is_true()
	)
	assert_int(_count("SELECT COUNT(*) AS n FROM event_type")).is_greater_equal(7)


func test_every_encounter_has_phases_events_and_loot() -> void:
	(
		assert_int(
			_count(
				(
					"SELECT COUNT(*) AS n FROM encounter e WHERE NOT EXISTS "
					+ "(SELECT 1 FROM encounter_phase p WHERE p.encounter_id = e.encounter_id)"
				)
			)
		)
		. is_equal(0)
	)
	(
		assert_int(
			_count(
				(
					"SELECT COUNT(*) AS n FROM encounter e WHERE NOT EXISTS "
					+ "(SELECT 1 FROM encounter_event ev WHERE ev.encounter_id = e.encounter_id)"
				)
			)
		)
		. is_equal(0)
	)
	(
		assert_int(
			_count(
				(
					"SELECT COUNT(*) AS n FROM encounter e WHERE "
					+ "(SELECT COUNT(*) FROM loot_item li WHERE li.encounter_id = e.encounter_id) < 3"
				)
			)
		)
		. is_equal(0)
	)


func test_range_profiles_present_for_comp_warnings() -> void:
	var melee := _count(
		(
			"SELECT COUNT(*) AS n FROM encounter_event ee JOIN event_type et "
			+ "ON et.event_type_id = ee.event_type_id "
			+ "WHERE COALESCE(ee.target_selector, et.target_selector) = 'melee'"
		)
	)
	var ranged := _count(
		(
			"SELECT COUNT(*) AS n FROM encounter_event ee JOIN event_type et "
			+ "ON et.event_type_id = ee.event_type_id "
			+ "WHERE COALESCE(ee.target_selector, et.target_selector) = 'ranged'"
		)
	)
	assert_int(melee).is_greater_equal(1)
	assert_int(ranged).is_greater_equal(1)


func test_comp_puzzle_utilities_resolvable() -> void:
	# the comp check's key joins must answer: "do we have a battle-rez tonight?"
	var rez_providers := _count(
		(
			"SELECT COUNT(*) AS n FROM spec_utility su "
			+ "JOIN raid_utility u ON u.utility_id = su.utility_id WHERE u.slug = 'rekindle'"
		)
	)
	assert_int(rez_providers).is_greater_equal(1)
	var surge_providers := _count(
		(
			"SELECT COUNT(*) AS n FROM spec_utility su "
			+ "JOIN raid_utility u ON u.utility_id = su.utility_id WHERE u.slug = 'stormsurge'"
		)
	)
	assert_int(surge_providers).is_greater_equal(1)


func test_consumable_plan_support() -> void:
	(
		assert_int(_count("SELECT COUNT(*) AS n FROM consumable WHERE tier = 'premium'"))
		. is_greater_equal(1)
	)
	(
		assert_int(_count("SELECT COUNT(*) AS n FROM consumable WHERE tier = 'basic'"))
		. is_greater_equal(1)
	)


func test_marks_vendor_covers_all_seven_slots() -> void:
	(
		assert_int(
			_count("SELECT COUNT(DISTINCT slot_id) AS n FROM loot_item WHERE marks_cost > 0")
		)
		. is_equal(7)
	)
