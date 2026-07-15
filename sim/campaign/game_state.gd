class_name GameState
extends RefCounted

## GAME_STATE — the campaign save root (M5-001). The singleton row (`game_id = 1`)
## that anchors WHERE the campaign is: which expansion/season/week, which phase, and
## the `rng_seed` that makes the whole campaign reproducible (the determinism pillar).
##
## M5-001 owns CREATE + READ. Advancing the phase and generating weeks is the turn
## loop (M5-002); this service deliberately stops short of that so genesis can stand
## alone.
##
## Season = Tier (I-03): a campaign starts at the FIRST season by `tier_order`, so it
## begins at Tier 1 today and will still begin at Tier 1 when MC-001 adds Tier 2 as
## the second season. Genesis never fabricates a season that has no raid content.

const PHASES := ["plan", "raid", "resolve", "grade"]


## Creates the save-root row anchored to the first playable season and its week 1.
## `seed` drives every random draw in the campaign. Returns
## {season_id, expansion_id, week_id} on success, or {} on failure.
static func create(db: Variant, seed_value: int) -> Dictionary:
	# the first season by tier order — Tier 1 today; still Tier 1 when Tier 2 lands
	db.query(
		"SELECT season_id, expansion_id FROM season ORDER BY tier_order, season_id LIMIT 1;"
	)
	if db.query_result.is_empty():
		push_error("GameState: no seasons seeded — cannot anchor a campaign")
		return {}
	var season_id := int(db.query_result[0]["season_id"])
	var expansion_id := int(db.query_result[0]["expansion_id"])

	# week 1 of that season (weeks are runtime rows, not seed data)
	if not db.query_with_bindings(
		"INSERT INTO week (season_id, week_number) VALUES (?, 1);", [season_id]
	):
		push_error("GameState: week insert failed: %s" % db.error_message)
		return {}
	db.query("SELECT last_insert_rowid() AS id;")
	var week_id := int(db.query_result[0]["id"])

	if not db.query_with_bindings(
		(
			"INSERT INTO game_state (game_id, expansion_id, season_id, week_id, phase, rng_seed)"
			+ " VALUES (1, ?, ?, ?, 'plan', ?);"
		),
		[expansion_id, season_id, week_id, seed_value]
	):
		push_error("GameState: game_state insert failed: %s" % db.error_message)
		return {}

	return {"season_id": season_id, "expansion_id": expansion_id, "week_id": week_id}


## The save-root row as a plain dictionary (or {} if the campaign is not created).
static func read(db: Variant) -> Dictionary:
	db.query("SELECT * FROM game_state WHERE game_id = 1;")
	return {} if db.query_result.is_empty() else db.query_result[0].duplicate()
