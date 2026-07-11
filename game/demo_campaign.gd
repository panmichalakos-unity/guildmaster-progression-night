class_name DemoCampaign
extends RefCounted

## Vertical-slice demo campaign (M4-001), curated into Night One (MI-003).
## SLICE-ONLY scaffolding: builds a playable raid night from the REAL pipeline
## (migrate -> seeds -> roster -> avatars -> guild -> calendar event) in an
## in-memory DB. M5-001's guild genesis replaces this for the actual game;
## nothing here is hardcoded content — every row comes from seeds or generators.
##
## MI-003 — THE FIRST SESSION IS AUTHORED. A random roster does not reliably
## teach anything: measured across 10 seeds, none produced a tank corps where the
## player had a *decision* to make (either the best tank was already crit-immune
## and the game silently handed you the answer, or no tank could be capped at all
## and you were stuck). So Night One curates ONE thing — the tank corps — into the
## shape that makes Gatewarden Krogg's authored identity legible:
##
##   the best-geared tank is a hide-armoured bruiser who CANNOT be crit-immune,
##   sitting above a plated tank who IS.
##
## The game's own default lineup (auto_lineup) picks tanks greedily by gear_score,
## so it walks straight into the trap and fields the wrong main tank. That is the
## point: the default is a heuristic, not an answer. The prep screen already warns
## ("Main tank X is not uncrittable — spike-death risk"), the wipe already names
## `tank_survival`, and benching the star tank turns ~0% into ~38% — a kill in a
## few pulls. Diagnose -> adjust -> succeed, in the first ten minutes.
##
## See docs/guildmaster-first-session.md for the scenario contract.

const ROSTER_SIZE := 28
## Demo guild name from the naming bible's guild-name pools (not one of the
## eight ghost rivals).
const DEMO_GUILD_NAME := "Northern Accord"

## Night One's curated tank corps. The incumbent out-gears everyone and is still
## crittable (his spec's defense cap is far above this); the capped tank clears
## his own cap while sitting visibly BELOW the incumbent on gear score.
const INCUMBENT_ILVL := 24
const CAPPED_ILVL := 23
## The off-tank who steps up when the incumbent is benched: credible, and below
## the capped tank so the crit-immune one always takes over as main.
const RESERVE_ILVL := 22
const GEAR_SLOTS := 7


## Builds the demo night. Returns {} on failure, else:
##   db          live in-memory campaign DB (caller owns closing)
##   seed        the master seed (reproducible night)
##   guild_id    the demo guild
##   event_id    tonight's calendar_event (raid)
##   guild_name  display name for the top bar
##   scenario    Night One's curated facts (see _curate_tank_corps)
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

	var scenario := _curate_tank_corps(db)
	if scenario.is_empty():
		return _fail(db, "could not curate the Night One tank corps")

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
		"scenario": scenario,
	}


## Night One's one authored fact. Reshapes ONLY the tank corps so that the default
## lineup fields a crittable main tank while a crit-immune one waits on the bench.
## Returns {incumbent_id, incumbent_handle, fix_id, fix_handle}, or {} if the
## roster is too small to express the scenario.
static func _curate_tank_corps(db: Variant) -> Dictionary:
	var tanks := _tanks(db)
	if tanks.size() < 3:
		return {}

	# The incumbent: a spec whose defense cap is out of reach at INCUMBENT_ILVL,
	# so no amount of Night One gear makes him crit-immune.
	# The fix: a spec that IS capped at CAPPED_ILVL — properly armoured, less loot.
	var incumbent := {}
	var fix := {}
	for tank: Dictionary in tanks:
		var cap := int(tank["defense_cap_ilvl"])
		if incumbent.is_empty() and cap > INCUMBENT_ILVL:
			incumbent = tank
		elif fix.is_empty() and cap > 0 and cap <= CAPPED_ILVL:
			fix = tank

	# Roster generation specs tanks at random, so a guild may field no hide tank
	# at all (or no plated one). Night One is authored, and an AVATAR is a
	# re-rollable character (modeling conventions) — so re-spec the tank we need
	# rather than let the scenario collapse into "no decision to make".
	if incumbent.is_empty():
		incumbent = _respec(db, _first_free(tanks, [fix]), _extreme_tank_spec(db, true))
	if fix.is_empty():
		fix = _respec(db, _first_free(tanks, [incumbent]), _extreme_tank_spec(db, false))
	if incumbent.is_empty() or fix.is_empty():
		return {}

	_set_gear(db, incumbent, INCUMBENT_ILVL)
	_set_gear(db, fix, CAPPED_ILVL)
	# The off-tank. Benching the incumbent costs the raid its best-geared body, so
	# the guild must own a credible third tank — otherwise the "fix" trades a
	# crit-immunity problem for a gear problem and the win rate barely moves.
	# Every later tank is only held down if they are crittable AND would out-gear
	# the capped one, which would promote a second crittable main tank and make
	# the fix quietly fail.
	var off_tank_set := false
	for tank: Dictionary in tanks:
		var avatar_id := int(tank["avatar_id"])
		if avatar_id == int(incumbent["avatar_id"]) or avatar_id == int(fix["avatar_id"]):
			continue
		var ilvl := int(tank["item_level"])
		if not off_tank_set:
			_set_gear(db, tank, RESERVE_ILVL)
			off_tank_set = true
		elif ilvl >= CAPPED_ILVL and ilvl < int(tank["defense_cap_ilvl"]):
			_set_gear(db, tank, RESERVE_ILVL)

	return {
		"incumbent_id": int(incumbent["avatar_id"]),
		"incumbent_handle": str(incumbent["handle"]),
		"incumbent_spec": str(incumbent["spec_name"]),
		"fix_id": int(fix["avatar_id"]),
		"fix_handle": str(fix["handle"]),
		"fix_spec": str(fix["spec_name"]),
	}


## The tanking spec with the highest (`hardest` = true) or lowest defense cap —
## read from the seed rows, never hardcoded (content as data).
static func _extreme_tank_spec(db: Variant, hardest: bool) -> Dictionary:
	db.query(
		(
			"SELECT s.spec_id, s.class_id, s.defense_cap_ilvl, s.display_name AS spec_name"
			+ " FROM spec s JOIN role r ON r.role_id = s.role_id"
			+ " WHERE r.slug = 'tank' AND s.defense_cap_ilvl > 0"
			+ " ORDER BY s.defense_cap_ilvl %s LIMIT 1;" % ("DESC" if hardest else "ASC")
		)
	)
	return {} if db.query_result.is_empty() else db.query_result[0].duplicate()


## The best-geared tank that is not already spoken for by the scenario.
static func _first_free(tanks: Array, taken: Array) -> Dictionary:
	for tank: Dictionary in tanks:
		var claimed := false
		for other: Dictionary in taken:
			if not other.is_empty() and int(other["avatar_id"]) == int(tank["avatar_id"]):
				claimed = true
		if not claimed:
			return tank
	return {}


## Re-rolls `tank` onto `spec` (AVATAR is re-rollable; the PLAYER is untouched).
## Returns the tank row with its new spec facts, ready for _set_gear.
static func _respec(db: Variant, tank: Dictionary, spec: Dictionary) -> Dictionary:
	if tank.is_empty() or spec.is_empty():
		return {}
	db.query_with_bindings(
		"UPDATE avatar SET spec_id = ?, class_id = ? WHERE avatar_id = ?;",
		[int(spec["spec_id"]), int(spec["class_id"]), int(tank["avatar_id"])]
	)
	var respecced := tank.duplicate()
	respecced["defense_cap_ilvl"] = int(spec["defense_cap_ilvl"])
	respecced["spec_name"] = str(spec["spec_name"])
	return respecced


## Re-gears an avatar to a flat `ilvl` across all 7 slots and recomputes the
## derived columns through THE shared rules — gear_score stays the SUM of the
## equipped slots (gear doc) and caps stay derived, never hand-set.
static func _set_gear(db: Variant, tank: Dictionary, ilvl: int) -> void:
	var avatar_id := int(tank["avatar_id"])
	db.query_with_bindings(
		"UPDATE avatar_item SET item_level = ? WHERE avatar_id = ?;", [ilvl, avatar_id]
	)
	var caps := AvatarGen.derive_caps(ilvl, "tank", int(tank["defense_cap_ilvl"]))
	db.query_with_bindings(
		(
			"UPDATE avatar SET item_level = ?, gear_score = ?, hit_capped = ?, uncrittable = ?"
			+ " WHERE avatar_id = ?;"
		),
		[ilvl, ilvl * GEAR_SLOTS, caps["hit_capped"], caps["uncrittable"], avatar_id]
	)


static func _tanks(db: Variant) -> Array:
	db.query(
		(
			"SELECT a.avatar_id, a.item_level, p.handle, s.defense_cap_ilvl,"
			+ " s.display_name AS spec_name"
			+ " FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE r.slug = 'tank' AND a.is_active = 1"
			+ " ORDER BY a.gear_score DESC, a.avatar_id;"
		)
	)
	return db.query_result.duplicate()


static func _fail(db: Variant, message: String) -> Dictionary:
	push_error("DemoCampaign: %s" % message)
	db.close_db()
	return {}
