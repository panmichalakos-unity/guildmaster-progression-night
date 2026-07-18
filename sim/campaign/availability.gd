class_name Availability
extends RefCounted

## Who can raid tonight (M5-003). Availability is rolled per raider per event and
## written to EVENT_AVAILABILITY, so the raid-prep lineup is drawn from who actually
## showed. Deterministic given the campaign seed + event.
##
## Two gates, and the reason says which:
##   1. WINDOW — a structural fact of the raider's life: a Working Parent is only free
##      in the evening slot, so a 'late' raid simply excludes them. No roll.
##   2. VOLATILITY — the fog. Even inside their window, real life intervenes; a spiky
##      raider (high volatility, worsened by a demanding life situation) no-shows more
##      often. This is the roll, and it is why you keep a deep bench.
##
## Reasons are plain-language (MI-008): the digest and prep screen show them as-is.

## Retuned 2026-07-18 (ADR-0039, Panos-approved): the old 0.9/0.004 pair meant an
## in-window raider showed only ~65% of nights — every single week ran short. Now
## ~86% mean show: evenings land ~19-22 of 28, short weeks still happen but are
## events, not the baseline.
const DEFAULTS := {"base_rate": 0.97, "volatility_scale": 0.002}
## Statuses that can be fielded — trials raid too (recruitment/raid-prep docs).
const RAIDABLE_STATUSES := ["member", "trial"]


## The pure roll for one raider against one event slot. `player` needs `volatility`;
## `life` needs `display_name`, `availability_window` (CSV of slots), `volatility_mod`.
## Returns {available: bool, reason: String} — reason is "" when available.
static func roll(
	event_slot: String, handle: String, player: Dictionary, life: Dictionary, rng: RngStream
) -> Dictionary:
	# 1. window — a structural exclusion, not a roll. A LEFT JOIN miss (a player with
	# no life situation — RosterGen always assigns one, but the join tolerates it)
	# leaves the window null; coerce to empty and treat as "free in every slot" rather
	# than emitting a "<null>" reason and benching them forever.
	var window_raw: Variant = life.get("availability_window")
	var window_str := str(window_raw) if window_raw != null else ""
	var window := window_str.split(",", false)
	if not window.is_empty() and not window.has(event_slot):
		return {
			"available": false,
			"reason":
			(
				"%s is not free in the %s slot (%s)"
				% [handle, event_slot, life.get("display_name", "life situation")]
			),
		}

	# 2. volatility — the fog. A steadier raider clears base_rate comfortably; a spiky
	# one, or one whose life situation is demanding, dips below it and no-shows.
	var tuning := Tuning.section("availability")
	var base := float(tuning.get("base_rate", DEFAULTS["base_rate"]))
	var scale := float(tuning.get("volatility_scale", DEFAULTS["volatility_scale"]))
	var effective_vol := clampi(
		int(player["volatility"]) + int(life.get("volatility_mod", 0)), 0, 100
	)
	var show_rate := base - effective_vol * scale
	if rng.randf() < show_rate:
		return {"available": true, "reason": ""}
	return {"available": false, "reason": "%s could not make it this week" % handle}


## Rolls availability for every raidable member/trial against `event_id`, writing
## one EVENT_AVAILABILITY row each. `rng` is the campaign's event-scoped stream; each
## raider gets a per-player substream so the result is stable and order-independent.
## Returns {available, unavailable, reasons: [String]}.
static func roll_for_event(db: Variant, event_id: int, rng: RngStream) -> Dictionary:
	db.query_with_bindings("SELECT time_slot FROM calendar_event WHERE event_id = ?;", [event_id])
	if db.query_result.is_empty():
		push_error("Availability: no event %d" % event_id)
		return {}
	var event_slot := str(db.query_result[0]["time_slot"])

	# re-runnable: clear any prior roll for this event first, so a re-plan writes a
	# fresh, consistent set instead of silently failing on the (event_id, player_id)
	# primary key and leaving the returned summary out of step with the DB.
	db.query_with_bindings("DELETE FROM event_availability WHERE event_id = ?;", [event_id])

	var roster := _raidable_roster(db)
	var available := 0
	var reasons: Array[String] = []
	for raider: Dictionary in roster:
		var player_id := int(raider["player_id"])
		# the joined row carries both the PLAYER and LIFE_SITUATION fields roll() needs,
		# so it is passed as both arguments
		var result := roll(
			event_slot, str(raider["handle"]), raider, raider, rng.substream(str(player_id))
		)
		var is_available := 1 if bool(result["available"]) else 0
		available += is_available
		if not bool(result["available"]):
			reasons.append(str(result["reason"]))
		db.query_with_bindings(
			(
				"INSERT INTO event_availability (event_id, player_id, available, reason)"
				+ " VALUES (?, ?, ?, ?);"
			),
			[event_id, player_id, is_available, result["reason"] if not is_available else null]
		)
	return {"available": available, "unavailable": roster.size() - available, "reasons": reasons}


## The available roster for an event: player_id + handle + role, for the prep screen.
static func available_for_event(db: Variant, event_id: int) -> Array:
	db.query_with_bindings(
		(
			"SELECT ea.player_id, p.handle FROM event_availability ea"
			+ " JOIN player p ON p.player_id = ea.player_id"
			+ " WHERE ea.event_id = ? AND ea.available = 1 ORDER BY p.player_id;"
		),
		[event_id]
	)
	return db.query_result.duplicate()


## Every raidable member/trial, joined to their life situation. One row per raider
## carrying both PLAYER (volatility) and LIFE_SITUATION (window, volatility_mod) fields.
static func _raidable_roster(db: Variant) -> Array:
	var placeholders := ", ".join(RAIDABLE_STATUSES.map(func(_s): return "?"))
	db.query_with_bindings(
		(
			"SELECT p.player_id, p.handle, p.volatility,"
			+ " ls.display_name, ls.availability_window, ls.volatility_mod"
			+ " FROM guild_membership gm"
			+ " JOIN player p ON p.player_id = gm.player_id"
			+ " LEFT JOIN life_situation ls ON ls.life_situation_id = p.life_situation_id"
			+ " WHERE gm.status IN (%s) ORDER BY p.player_id;" % placeholders
		),
		RAIDABLE_STATUSES
	)
	return db.query_result.duplicate()
