class_name Genesis
extends RefCounted

## Guild genesis (M5-001) — the ONE flow that creates a new campaign, reused by both
## new-game and post-sack rebuild. The SQLite DB is the save; genesis fills a
## migrated+seeded DB with the save root, the player guild, and a starting roster.
##
## Pure over (db, config): same seed + same config = same starting campaign (the
## determinism pillar). Nothing here hardcodes content — the roster comes from the
## generators, the raid/season from seed rows.
##
## It carries the game's OPENING: FirstSession.curate() shapes the tank corps so the
## first raid night teaches diagnose -> fix -> succeed (MI-003). The curation lives
## in exactly one place (FirstSession) and genesis calls it for every campaign
## (ADR-0034) — a random roster mostly produces no decision at all.
##
## Config keys (all optional except handled defaults):
##   guild_name              display name (default from the naming-bible pool)
##   seed                    master seed; every draw derives from it (default 0)
##   difficulty              GAME_CONFIG (default 'standard')
##   involvement_default     GAME_CONFIG preset (default 'manual')
##   sack_risk_enabled       GAME_CONFIG (default true)
##   loot_culture            GUILD_CONFIG.active_loot_system (default 'council')
##   is_rebuild              post-sack rebuild: scale starting reputation/gold down
##   reputation_override     explicit starting reputation (else tuning/rebuild mult)
##   gold_override           explicit starting gold (else tuning/rebuild mult)

## A default guild name from the naming bible's guild pools (not one of the eight
## ghost rivals). The new-game UI will let the player name their own; this is the
## headless/default.
const DEFAULT_GUILD_NAME := "Northern Accord"


## Opens a fresh in-memory campaign, migrated + seeded, then runs genesis. The
## convenience path for headless smokes, tests and the slice UI. Caller owns closing
## the returned db. Returns {} on any failure.
static func new_in_memory(config: Dictionary = {}) -> Dictionary:
	var db: Variant = Migrator.open_db(":memory:")
	if db == null or not Migrator.migrate(db).ok or not SeedLoader.load_seeds(db).ok:
		push_error("Genesis: could not build campaign DB")
		return {}
	var handle := create_campaign(db, config)
	if handle.is_empty():
		db.close_db()
		return {}
	return handle


## Fills an already-migrated, already-seeded `db` with a new campaign. Returns the
## campaign handle, or {} on failure (the caller owns the db either way).
##
## Handle: {db, seed, guild_id, guild_name, event_id, scenario, season_id, week_id,
##          expansion_id} — a superset of the old slice handle, so existing callers
## keep working.
static func create_campaign(db: Variant, config: Dictionary = {}) -> Dictionary:
	var tuning: Dictionary = Tuning.section("genesis")
	var seed_value := int(config.get("seed", 0))
	var guild_name := str(config.get("guild_name", DEFAULT_GUILD_NAME))
	var roster_size := int(tuning.get("roster_size", 28))

	# 1. roster + avatars (reuse M2 — never a parallel setup path)
	var players := RosterGen.generate_from_db(
		db, roster_size, RngStream.derive(seed_value, "roster_gen")
	)
	if RosterGen.persist(db, players).is_empty():
		return _fail("roster persist failed")
	if AvatarGen.generate_and_persist(db, RngStream.derive(seed_value, "avatar_gen")).is_empty():
		return _fail("avatar persist failed")

	# 2. the game's opening — always curated (ADR-0034), in one place (FirstSession)
	var scenario := FirstSession.curate(db)
	if scenario.is_empty():
		return _fail("could not curate the Night One tank corps")

	# 3. the player guild + its starting standing
	var guild_id := _create_guild(db, guild_name, tuning, config)
	if guild_id < 0:
		return _fail("guild creation failed")

	# 4. the save root: GAME_STATE (anchored to Tier 1) + GAME_CONFIG
	var anchor := GameState.create(db, seed_value)
	if anchor.is_empty():
		return _fail("save-root creation failed")
	if not GameConfig.create(db, config):
		return _fail("game config creation failed")

	# 5. the starting roster's membership (one member row per generated player)
	if not _seat_roster(db, guild_id):
		return _fail("roster membership failed")

	# 6. schedule week 1's raid night, so the opening has somewhere to happen. The
	#    full weekly calendar is M5-002; genesis schedules only the first raid.
	var event_id := _schedule_first_raid(db, int(anchor["season_id"]), int(anchor["week_id"]))
	if event_id < 0:
		return _fail("could not schedule the first raid night")

	return {
		"db": db,
		"seed": seed_value,
		"guild_id": guild_id,
		"guild_name": guild_name,
		"event_id": event_id,
		"scenario": scenario,
		"season_id": int(anchor["season_id"]),
		"expansion_id": int(anchor["expansion_id"]),
		"week_id": int(anchor["week_id"]),
	}


## The player guild + GUILD_CONFIG (loot culture) + GUILD_TREASURY. Starting
## reputation/gold come from tuning, scaled down on a rebuild, or overridden outright.
static func _create_guild(
	db: Variant, guild_name: String, tuning: Dictionary, config: Dictionary
) -> int:
	var reputation := _starting_value(
		config, tuning, "reputation", "starting_reputation", "rebuild_reputation_mult", 40
	)
	var gold := _starting_value(config, tuning, "gold", "starting_gold", "rebuild_gold_mult", 500)

	if not db.query_with_bindings(
		"INSERT INTO guild (display_name, is_player_guild, reputation) VALUES (?, 1, ?);",
		[guild_name, reputation]
	):
		return -1
	db.query("SELECT last_insert_rowid() AS id;")
	var guild_id := int(db.query_result[0]["id"])

	var loot_culture := str(config.get("loot_culture", "council"))
	if not db.query_with_bindings(
		"INSERT INTO guild_config (guild_id, active_loot_system) VALUES (?, ?);",
		[guild_id, loot_culture]
	):
		return -1
	if not db.query_with_bindings(
		"INSERT INTO guild_treasury (guild_id, gold, mats) VALUES (?, ?, 0);", [guild_id, gold]
	):
		return -1
	return guild_id


## A starting reputation/gold value: explicit override wins; else the tuning base,
## scaled by the rebuild multiplier when this is a post-sack rebuild.
static func _starting_value(
	config: Dictionary,
	tuning: Dictionary,
	override_key: String,
	base_key: String,
	rebuild_mult_key: String,
	fallback: int
) -> int:
	if config.has("%s_override" % override_key):
		return int(config["%s_override" % override_key])
	var base := int(tuning.get(base_key, fallback))
	if bool(config.get("is_rebuild", false)):
		return int(round(base * float(tuning.get(rebuild_mult_key, 1.0))))
	return base


## Seat every generated player as a guild member. `joined_at` stays NULL (a runtime
## timestamp would break determinism, and the roster all joins "at genesis" anyway).
static func _seat_roster(db: Variant, guild_id: int) -> bool:
	return db.query_with_bindings(
		(
			"INSERT INTO guild_membership (guild_id, player_id, status)"
			+ " SELECT ?, player_id, 'member' FROM player ORDER BY player_id;"
		),
		[guild_id]
	)


## Schedule the season's raid on week 1 (day 3, evening — matching the slice). The
## raid belongs to the season, so Tier 1 gets The Emberdeep automatically.
static func _schedule_first_raid(db: Variant, season_id: int, week_id: int) -> int:
	db.query_with_bindings(
		"SELECT raid_id FROM raid WHERE season_id = ? ORDER BY raid_id LIMIT 1;", [season_id]
	)
	if db.query_result.is_empty():
		push_error("Genesis: season %d has no raid to schedule" % season_id)
		return -1
	var raid_id := int(db.query_result[0]["raid_id"])
	if not db.query_with_bindings(
		(
			"INSERT INTO calendar_event (week_id, raid_id, day, time_slot, event_type)"
			+ " VALUES (?, ?, 3, 'evening', 'raid');"
		),
		[week_id, raid_id]
	):
		return -1
	db.query("SELECT last_insert_rowid() AS id;")
	return int(db.query_result[0]["id"])


static func _fail(message: String) -> Dictionary:
	push_error("Genesis: %s" % message)
	return {}
