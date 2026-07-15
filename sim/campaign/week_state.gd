class_name WeekState
extends RefCounted

## PLAYER_WEEK_STATE — the volatile per-player snapshot for a week (conventions:
## states live in snapshots, not on the entity). Morale / fatigue / form.
##
## The turn loop (M5-002) ticks fatigue recovery across empty days here. Snapshots
## are created lazily so genesis stays untouched: whoever first needs the week's
## state calls `ensure`, which carries the prior week's values forward (or seeds
## defaults for the very first week). Deterministic — a flat recovery, no rng yet
## (the signature keeps room for variance later).

const DEFAULT_MORALE := 50
const DEFAULT_FATIGUE := 0
const DEFAULT_FORM := 50


## Guarantees a PLAYER_WEEK_STATE row for every active player in `week_id`. If
## `prior_week_id` is given, morale/fatigue/form carry forward from it; otherwise
## defaults seed the first week. Idempotent — a no-op if the week is already snapshotted.
static func ensure(db: Variant, week_id: int, prior_week_id: int = 0) -> void:
	db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM player_week_state WHERE week_id = ?;", [week_id]
	)
	if int(db.query_result[0]["n"]) > 0:
		return

	if prior_week_id > 0:
		# carry the prior week's state forward — the campaign's state is continuous
		db.query_with_bindings(
			(
				"INSERT INTO player_week_state (player_id, week_id, morale, fatigue, form)"
				+ " SELECT player_id, ?, morale, fatigue, form FROM player_week_state"
				+ " WHERE week_id = ?;"
			),
			[week_id, prior_week_id]
		)
		return

	# first snapshot: neutral defaults for every active player
	db.query_with_bindings(
		(
			"INSERT INTO player_week_state (player_id, week_id, morale, fatigue, form)"
			+ " SELECT player_id, ?, ?, ?, ? FROM player;"
		),
		[week_id, DEFAULT_MORALE, DEFAULT_FATIGUE, DEFAULT_FORM]
	)


## An empty day sheds `recovery` fatigue from every raider (clamped at 0). Returns the
## number of rows touched — the caller logs this so the tick is inspectable.
static func tick_recovery(db: Variant, week_id: int, recovery: int) -> int:
	db.query_with_bindings(
		(
			"UPDATE player_week_state SET fatigue = MAX(0, fatigue - ?)"
			+ " WHERE week_id = ? AND fatigue > 0;"
		),
		[recovery, week_id]
	)
	db.query_with_bindings(
		"SELECT COUNT(*) AS n FROM player_week_state WHERE week_id = ?;", [week_id]
	)
	return int(db.query_result[0]["n"])


## Read a week's snapshot (all rows), for smokes / tests / the digest.
static func read(db: Variant, week_id: int) -> Array:
	db.query_with_bindings(
		(
			"SELECT player_id, morale, fatigue, form FROM player_week_state"
			+ " WHERE week_id = ? ORDER BY player_id;"
		),
		[week_id]
	)
	return db.query_result.duplicate()
