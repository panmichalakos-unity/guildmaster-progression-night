class_name DemoCampaign
extends RefCounted

## Vertical-slice demo campaign (M4-001). SLICE-ONLY scaffolding: builds a
## playable raid night from the REAL pipeline (migrate -> seeds -> roster ->
## avatars -> guild -> calendar event) in an in-memory DB. M5-001's guild
## genesis replaces this for the actual game; nothing here is hardcoded
## content — every row comes from seeds or generators.

const ROSTER_SIZE := 28
## Demo guild name from the naming bible's guild-name pools (not one of the
## eight ghost rivals).
const DEMO_GUILD_NAME := "Northern Accord"


## Builds the demo night. Returns {} on failure, else:
##   db          live in-memory campaign DB (caller owns closing)
##   seed        the master seed (reproducible night)
##   guild_id    the demo guild
##   event_id    tonight's calendar_event (raid)
##   guild_name  display name for the top bar
static func build(seed_value: int) -> Dictionary:
	var db: Variant = Migrator.open_db(":memory:")
	if db == null or not Migrator.migrate(db).ok or not SeedLoader.load_seeds(db).ok:
		push_error("DemoCampaign: could not build campaign DB")
		return {}
	var players := RosterGen.generate_from_db(
		db, ROSTER_SIZE, RngStream.derive(seed_value, "roster_gen")
	)
	if RosterGen.persist(db, players).is_empty():
		return _fail(db, "roster persist failed")
	if AvatarGen.generate_and_persist(db, RngStream.derive(seed_value, "avatar_gen")).is_empty():
		return _fail(db, "avatar persist failed")

	if not db.query_with_bindings(
		"INSERT INTO guild (display_name, is_player_guild) VALUES (?, 1);", [DEMO_GUILD_NAME]
	):
		return _fail(db, db.error_message)
	db.query("SELECT last_insert_rowid() AS id;")
	var guild_id := int(db.query_result[0]["id"])

	# tonight: week 1, raid night on day 3, evening slot (schema enums)
	db.query("INSERT INTO week (season_id, week_number) VALUES (1, 1);")
	if not db.query(
		(
			"INSERT INTO calendar_event (week_id, raid_id, day, time_slot, event_type)"
			+ " VALUES (1, 1, 3, 'evening', 'raid');"
		)
	):
		return _fail(db, db.error_message)
	db.query("SELECT last_insert_rowid() AS id;")
	var event_id := int(db.query_result[0]["id"])

	return {
		"db": db,
		"seed": seed_value,
		"guild_id": guild_id,
		"event_id": event_id,
		"guild_name": DEMO_GUILD_NAME,
	}


static func _fail(db: Variant, message: String) -> Dictionary:
	push_error("DemoCampaign: %s" % message)
	db.close_db()
	return {}
