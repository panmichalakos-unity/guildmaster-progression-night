extends GdUnitTestSuite

## M5-005 — the decision inbox and the weekly digest. Both are DERIVED read models
## over persisted audit/state tables: items clear when the queue behind them
## resolves, digests rebuild identically from the save alone, and later systems
## (M6 loot, M8 recruitment, M9 objectives) appear as explicit placeholders.

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


func _find(items: Array, kind: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item["kind"]) == kind:
			return item
	return {}


func _roll_availability(c: Dictionary) -> void:
	Availability.roll_for_event(c["db"], int(c["event_id"]), RngStream.derive(SEED, "availability"))


func _play_the_night(c: Dictionary) -> Dictionary:
	var db: Variant = c["db"]
	var lineup := PullInputLoader.auto_lineup(db)
	assert_bool(RaidPrep.persist_lineup(db, int(c["event_id"]), lineup)).is_true()
	var night := NightRunner.run_night(
		db,
		SEED,
		int(c["guild_id"]),
		int(c["event_id"]),
		{"lineup_ids": lineup, "assignments": {}, "consumable_tier": "basic"}
	)
	assert_bool(bool(night.get("ok", false))).is_true()
	TurnLoop.complete_event(db, int(c["event_id"]))
	return night


# --- inbox: items appear from real queues and clear when the queue resolves ----


func test_the_inbox_flags_the_unset_lineup() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var item := _find(Inbox.build(db, int(c["week_id"])), "lineup_pending")
	assert_dict(item).is_not_empty()
	assert_int(int(item["ref"]["event_id"])).is_equal(int(c["event_id"]))

	RaidPrep.persist_lineup(db, int(c["event_id"]), PullInputLoader.auto_lineup(db))
	assert_dict(_find(Inbox.build(db, int(c["week_id"])), "lineup_pending")).is_empty()
	db.close_db()


func test_the_inbox_flags_an_unrolled_availability() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	assert_dict(_find(Inbox.build(db, int(c["week_id"])), "availability_pending")).is_not_empty()
	_roll_availability(c)
	assert_dict(_find(Inbox.build(db, int(c["week_id"])), "availability_pending")).is_empty()
	db.close_db()


func test_the_inbox_escalates_a_night_that_cannot_field_twenty() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	_roll_availability(c)
	db.query_with_bindings(
		"UPDATE event_availability SET available = 0, reason = 'test' WHERE event_id = ?;",
		[int(c["event_id"])]
	)
	var item := _find(Inbox.build(db, int(c["week_id"])), "manning_short")
	assert_dict(item).is_not_empty()
	assert_int(int(item["priority"])).is_equal(Inbox.PRIORITY_URGENT)
	# consequence first, action in the detail (terminology doc)
	assert_str(str(item["detail"])).contains("run short")
	db.close_db()


func test_the_inbox_flags_a_blocked_night() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	db.query_with_bindings(
		"UPDATE calendar_event SET status = 'in_progress' WHERE event_id = ?;", [int(c["event_id"])]
	)
	var item := _find(Inbox.build(db, int(c["week_id"])), "blocked_event")
	assert_dict(item).is_not_empty()
	assert_int(int(item["priority"])).is_equal(Inbox.PRIORITY_URGENT)
	db.close_db()


func test_the_inbox_surfaces_unawarded_loot_until_awarded() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var encounter_id := int(_scalar(db, "SELECT encounter_id FROM encounter LIMIT 1"))
	var item_id := int(_scalar(db, "SELECT item_id FROM loot_item LIMIT 1"))
	db.query_with_bindings(
		(
			"INSERT INTO pull (event_id, encounter_id, attempt_number, outcome)"
			+ " VALUES (?, ?, 1, 'kill');"
		),
		[int(c["event_id"]), encounter_id]
	)
	var pull_id := int(_scalar(db, "SELECT last_insert_rowid()"))
	db.query_with_bindings(
		"INSERT INTO loot_drop (pull_id, item_id, loot_method) VALUES (?, ?, 'council');",
		[pull_id, item_id]
	)
	assert_dict(_find(Inbox.build(db, int(c["week_id"])), "unawarded_loot")).is_not_empty()

	var player_id := int(_scalar(db, "SELECT player_id FROM guild_membership LIMIT 1"))
	db.query_with_bindings(
		"UPDATE loot_drop SET awarded_to_player_id = ? WHERE pull_id = ?;", [player_id, pull_id]
	)
	assert_dict(_find(Inbox.build(db, int(c["week_id"])), "unawarded_loot")).is_empty()
	db.close_db()


func test_the_inbox_surfaces_an_application() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	db.query("INSERT INTO player (handle) VALUES ('Newcomer');")
	var prospect_id := int(_scalar(db, "SELECT last_insert_rowid()"))
	db.query_with_bindings(
		(
			"INSERT INTO prospect_assessment (guild_id, player_id, attribute, estimate)"
			+ " VALUES (?, ?, 'execution', 60);"
		),
		[int(c["guild_id"]), prospect_id]
	)
	var item := _find(Inbox.build(db, int(c["week_id"])), "application")
	assert_dict(item).is_not_empty()
	assert_str(str(item["title"])).contains("Newcomer")
	db.close_db()


func test_the_inbox_carries_the_mandate() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	db.query(
		(
			"INSERT INTO objective_type (slug, display_name, reads_from)"
			+ " VALUES ('progression', 'Clear the tier', 'guild_encounter_progress');"
		)
	)
	var type_id := int(_scalar(db, "SELECT last_insert_rowid()"))
	db.query_with_bindings(
		(
			"INSERT INTO season_objective (season_id, objective_type_id, target, priority)"
			+ " VALUES (?, ?, 'all 4 bosses', 1);"
		),
		[int(c["season_id"]), type_id]
	)
	var item := _find(Inbox.build(db, int(c["week_id"])), "objective")
	assert_dict(item).is_not_empty()
	assert_str(str(item["title"])).contains("mandate")
	db.close_db()


# --- digest: built from the save alone -----------------------------------------


func test_the_digest_reports_a_played_night() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	_play_the_night(c)
	var digest := Digest.build(db, int(c["week_id"]))

	var raids: Array = digest["raids"]
	assert_int(raids.size()).is_equal(1)
	var raid: Dictionary = raids[0]
	var on_disk := int(_scalar(db, "SELECT COUNT(*) FROM pull"))
	assert_int(int(raid["pulls"])).is_equal(on_disk)
	assert_int(int(raid["kills"]) + int(raid["wipes"])).is_equal(on_disk)

	var ratings: Array = digest["ratings"]
	assert_array(ratings).is_not_empty()
	for row: Dictionary in ratings:
		assert_float(float(row["avg_rating"])).is_between(1.0, 10.0)

	var progression: Dictionary = digest["progression"]
	assert_int(int(progression["bosses_total"])).is_equal(4)
	var downed := int(
		_scalar(db, "SELECT COUNT(*) FROM guild_encounter_progress WHERE first_kill_at IS NOT NULL")
	)
	assert_int(int(progression["bosses_down"])).is_equal(downed)
	db.close_db()


func test_the_digest_speaks_remaining_health_never_progress() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var encounter_id := int(
		_scalar(db, "SELECT encounter_id FROM encounter ORDER BY boss_order LIMIT 1")
	)
	db.query_with_bindings(
		(
			"INSERT INTO pull (event_id, encounter_id, attempt_number, outcome, wipe_reason)"
			+ " VALUES (?, ?, 1, 'wipe', 'tank_survival: margin -12');"
		),
		[int(c["event_id"]), encounter_id]
	)
	db.query_with_bindings(
		(
			"INSERT INTO guild_encounter_progress (guild_id, encounter_id, progress,"
			+ " attempt_count, best_attempt_pct) VALUES (?, ?, 40, 1, 40);"
		),
		[int(c["guild_id"]), encounter_id]
	)
	TurnLoop.complete_event(db, int(c["event_id"]))

	var digest := Digest.build(db, int(c["week_id"]))
	var raid: Dictionary = digest["raids"][0]
	var boss: Dictionary = raid["bosses"][0]
	# best_attempt_pct stored 40% PROGRESS; the player must hear 60% REMAINING
	assert_int(int(boss["closest_remaining_pct"])).is_equal(60)
	var text := "\n".join(Digest.lines(digest))
	assert_str(text).contains("boss at 60% health")
	assert_str(text).not_contains("40%")
	db.close_db()


func test_bench_streaks_surface_after_two_sits() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_id := int(c["week_id"])
	var raid_id := int(_scalar(db, "SELECT raid_id FROM raid LIMIT 1"))
	var second_event := Calendar.schedule(db, week_id, 5, "evening", "raid", raid_id)

	# a lineup that benches the same two raiders both nights
	var full := PullInputLoader.auto_lineup(db)
	var benched_handle := str(
		_scalar(
			db,
			(
				(
					"SELECT p.handle FROM avatar a JOIN player p ON p.player_id = a.player_id"
					+ " WHERE a.avatar_id NOT IN (%s) AND a.is_active = 1"
					+ " ORDER BY a.avatar_id LIMIT 1"
				)
				% ", ".join(full.map(func(i): return str(i)))
			)
		)
	)
	for event_id in [int(c["event_id"]), second_event]:
		assert_bool(RaidPrep.persist_lineup(db, event_id, full)).is_true()
		db.query_with_bindings(
			"UPDATE calendar_event SET status = 'completed' WHERE event_id = ?;", [event_id]
		)

	var roster: Dictionary = Digest.build(db, week_id)["roster"]
	var costs: Array = roster["bench_costs"]
	assert_array(costs).is_not_empty()
	var found := {}
	for row: Dictionary in costs:
		found[str(row["handle"])] = row
	assert_bool(found.has(benched_handle)).is_true()
	assert_int(int(found[benched_handle]["streak"])).is_equal(2)
	# the cost half is real now (M5-007): the digest prices the streak
	assert_int(int(found[benched_handle]["morale_ding"])).is_greater(0)
	assert_int(int(found[benched_handle]["loyalty_ding"])).is_greater(0)

	# a fielded raider never appears in the bench record
	var fielded_handle := str(
		_scalar(
			db,
			(
				(
					"SELECT p.handle FROM avatar a JOIN player p ON p.player_id = a.player_id"
					+ " WHERE a.avatar_id = %d"
				)
				% int(full[0])
			)
		)
	)
	assert_bool(found.has(fielded_handle)).is_false()
	db.close_db()


func test_the_digest_sums_the_week_ledger() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var week_id := int(c["week_id"])
	var party := [int(_scalar(db, "SELECT player_id FROM guild_membership LIMIT 1"))]
	var farmed := ActionResolver.resolve_and_persist(
		db, int(c["guild_id"]), week_id, "farm_mats", "mats", party, RngStream.derive(SEED, "farm")
	)
	assert_bool(bool(farmed["ok"])).is_true()

	var economy: Dictionary = Digest.build(db, week_id)["economy"]
	assert_int(int(economy["mats_delta"])).is_equal(int(farmed["output_qty"]))
	assert_int(int(economy["mats"])).is_equal(int(farmed["output_qty"]))

	var actions: Array = Digest.build(db, week_id)["actions"]
	assert_int(actions.size()).is_equal(1)
	assert_str(str(actions[0]["slug"])).is_equal("farm_mats")
	assert_str(str(actions[0]["decided_by"])).is_equal("player")
	db.close_db()


func test_the_digest_is_deterministic() -> void:
	var digests: Array[String] = []
	for run in 2:
		var c := _campaign()
		var db: Variant = c["db"]
		_roll_availability(c)
		ActionResolver.resolve_and_persist(
			db,
			int(c["guild_id"]),
			int(c["week_id"]),
			"farm_mats",
			"mats",
			[int(_scalar(db, "SELECT player_id FROM guild_membership LIMIT 1"))],
			RngStream.derive(SEED, "farm")
		)
		var digest := Digest.build(db, int(c["week_id"]))
		digests.append("\n".join(Digest.lines(digest)) + "|" + str(digest))
		db.close_db()
	assert_str(digests[1]).is_equal(digests[0])


func test_missing_systems_are_explicit_placeholders() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var digest := Digest.build(db, int(c["week_id"]))
	assert_str(str(digest["objectives"]["todo"])).contains("M9")
	assert_str(str(digest["applicants"]["todo"])).contains("M8")

	# a kill with no LOOT_DROP rows must say M6 owns it, not pretend loot happened
	var encounter_id := int(_scalar(db, "SELECT encounter_id FROM encounter LIMIT 1"))
	db.query_with_bindings(
		(
			"INSERT INTO pull (event_id, encounter_id, attempt_number, outcome)"
			+ " VALUES (?, ?, 1, 'kill');"
		),
		[int(c["event_id"]), encounter_id]
	)
	TurnLoop.complete_event(db, int(c["event_id"]))
	var loot: Dictionary = Digest.build(db, int(c["week_id"]))["loot"]
	assert_int(int(loot["awarded"])).is_equal(0)
	assert_str(str(loot["todo"])).contains("M6")
	db.close_db()


# --- lineup persistence (the bench record's source) ----------------------------


func test_persist_lineup_records_fielded_and_benched_and_replaces() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event_id := int(c["event_id"])
	var lineup := PullInputLoader.auto_lineup(db)
	assert_bool(RaidPrep.persist_lineup(db, event_id, lineup)).is_true()

	var actives := int(
		_scalar(
			db,
			(
				"SELECT COUNT(*) FROM avatar a"
				+ " JOIN guild_membership gm ON gm.player_id = a.player_id"
				+ " WHERE a.is_active = 1 AND gm.status IN ('member', 'trial')"
			)
		)
	)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM raid_lineup"))).is_equal(actives)
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM raid_lineup WHERE is_benched = 0"))).is_equal(
		lineup.size()
	)

	# re-persisting replaces the plan instead of failing on the primary key
	assert_bool(RaidPrep.persist_lineup(db, event_id, lineup)).is_true()
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM raid_lineup"))).is_equal(actives)

	# an empty lineup is refused outright
	assert_bool(RaidPrep.persist_lineup(db, event_id, [] as Array[int])).is_false()
	db.close_db()


func test_auto_lineup_respects_an_availability_pool() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	db.query("SELECT player_id FROM guild_membership ORDER BY player_id LIMIT 10;")
	var pool: Array = db.query_result.duplicate().map(func(r): return int(r["player_id"]))
	var lineup := PullInputLoader.auto_lineup(db, pool)
	assert_array(lineup).is_not_empty()
	for avatar_id in lineup:
		var owner := int(
			_scalar(db, "SELECT player_id FROM avatar WHERE avatar_id = %d" % int(avatar_id))
		)
		assert_bool(pool.has(owner)).is_true()
	db.close_db()


# --- hardening from the M5-005 review ------------------------------------------


## A role-only shortage (20+ can come, but no tank) must not print the arithmetic
## falsehood "Only 24 of the 20 you need can raid."
func test_a_role_only_shortage_never_misstates_the_headcount() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	_roll_availability(c)
	db.query_with_bindings(
		"UPDATE event_availability SET available = 1, reason = '' WHERE event_id = ?;",
		[int(c["event_id"])]
	)
	db.query_with_bindings(
		(
			"UPDATE event_availability SET available = 0, reason = 'test'"
			+ " WHERE event_id = ? AND player_id IN ("
			+ " SELECT a.player_id FROM avatar a"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE r.slug = 'tank' AND a.is_active = 1);"
		),
		[int(c["event_id"])]
	)
	var item := _find(Inbox.build(db, int(c["week_id"])), "manning_short")
	assert_dict(item).is_not_empty()
	assert_str(str(item["title"])).contains("nobody available covers")
	assert_str(str(item["title"])).not_contains("Only")
	db.close_db()


## The "week isn't wasted" decision (convert to dungeon, M5-003) must still show
## in the digest — dropping the event implied the slot was wasted.
func test_a_converted_night_still_appears_in_the_digest() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	assert_bool(PrepDecisions.convert_to_dungeon(db, int(c["event_id"]))).is_true()
	db.query_with_bindings(
		"UPDATE calendar_event SET status = 'completed' WHERE event_id = ?;", [int(c["event_id"])]
	)
	var digest := Digest.build(db, int(c["week_id"]))
	var raids: Array = digest["raids"]
	assert_int(raids.size()).is_equal(1)
	assert_str(str(raids[0]["event_type"])).is_equal("dungeon")
	var text := "\n".join(Digest.lines(digest))
	assert_str(text).contains("converted")
	assert_str(text).not_contains("No raid was played")
	db.close_db()


## A played night's lineup record is history, not a plan — rewriting it would hand
## raiders who actually played a bench streak.
func test_persist_lineup_never_rewrites_a_played_night() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var lineup := PullInputLoader.auto_lineup(db)
	assert_bool(RaidPrep.persist_lineup(db, int(c["event_id"]), lineup)).is_true()
	TurnLoop.complete_event(db, int(c["event_id"]))
	var fielded_before := int(_scalar(db, "SELECT COUNT(*) FROM raid_lineup WHERE is_benched = 0"))
	assert_bool(RaidPrep.persist_lineup(db, int(c["event_id"]), lineup.slice(0, 10))).is_false()
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM raid_lineup WHERE is_benched = 0"))).is_equal(
		fielded_before
	)
	db.close_db()


## The fielded side guards the same invariant as the bench side: a raider whose
## availability roll said "can't make it" cannot be recorded as having played.
func test_persist_lineup_refuses_a_raider_who_cannot_come() -> void:
	var c := _campaign()
	var db: Variant = c["db"]
	var event_id := int(c["event_id"])
	_roll_availability(c)
	db.query_with_bindings(
		"SELECT player_id FROM event_availability WHERE event_id = ? AND available = 1;", [event_id]
	)
	var pool: Array = db.query_result.duplicate().map(func(r): return int(r["player_id"]))
	var lineup := PullInputLoader.auto_lineup(db, pool)
	assert_array(lineup).is_not_empty()
	var owner := int(
		_scalar(db, "SELECT player_id FROM avatar WHERE avatar_id = %d" % int(lineup[0]))
	)
	db.query_with_bindings(
		(
			"UPDATE event_availability SET available = 0, reason = 'test'"
			+ " WHERE event_id = ? AND player_id = ?;"
		),
		[event_id, owner]
	)
	assert_bool(RaidPrep.persist_lineup(db, event_id, lineup)).is_false()
	assert_int(int(_scalar(db, "SELECT COUNT(*) FROM raid_lineup"))).is_equal(0)

	# and with the raider available again, the same lineup persists fine
	db.query_with_bindings(
		(
			"UPDATE event_availability SET available = 1, reason = ''"
			+ " WHERE event_id = ? AND player_id = ?;"
		),
		[event_id, owner]
	)
	assert_bool(RaidPrep.persist_lineup(db, event_id, lineup)).is_true()
	db.close_db()
