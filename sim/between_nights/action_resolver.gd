class_name ActionResolver
extends RefCounted

## The between-nights action resolver (M5-004) — the five weekly lanes as
## deterministic, legible resolution. A light version of the raid resolver: roll the
## relevant attributes against a lane difficulty -> a bounded output -> write EXISTING
## model fields. Never a zero-outcome week ("skill dominates, luck flavors").
##
##   Gearing      dungeon_run       -> Avatar.marks
##   Development  drill             -> the player's weakest skill facet (ceiling-gated)
##                spec_test         -> Avatar.familiarity
##   Supply       farm_mats         -> GUILD_TREASURY.mats            (+ ledger)
##                buy_consumables   -> gold -> GUILD_STOCKPILE        (+ ledger)
##                convert_mats      -> mats -> GUILD_STOCKPILE        (+ ledger)
##   People       one_on_one        -> morale + a loyalty nudge (one raider)
##                social_night      -> broad small morale + relationship-lite
##   Rest         rest_week         -> fatigue recovery across the roster
##
## Actions are ACTION_TYPE seed rows (content as data); WEEK_ACTION stores every
## resolved output as the audit row, stamped with `decided_by` (the involvement
## contract, ADR-0033). The weekly time budget makes the pillar literal: time is
## scarce — you cannot do everything.
##
## Pure core: resolve(action, participants, tuning, rng, params) -> outcome.
## The persist step applies the writes and never invents state.

const DEFAULTS := {
	"weekly_time_budget": 5,
	"variance_band": 0.15,
	"quality_spread": 60.0,
	"skill_growth_cap": 4,
	"mats_per_consumable": 8,
	"loyalty_nudge_max": 3,
}

## Skill facets a drill can raise; it targets the player's weakest.
const FACETS := ["execution", "awareness", "consistency"]

## The tier gear ceiling (ilvl 31 = x1.64 BiS) — normalizes gear into the 0-100
## trait scale for rolls. See guildmaster-encounter-contracts.md §0.
const TIER_BIS_ILVL := 31.0


## The pure roll. `action` is an ACTION_TYPE row; `participants` carry whatever
## fields the action's roll_inputs name (player traits, plus `item_level` /
## `time_budget_hrs` for the normalized inputs). Returns:
##   {quality: 0..1, output_type, output_qty, outcome: String}
## Deterministic given (action, participants, tuning, rng). Actions with no
## roll_inputs (purchases, rest) resolve at quality 0.5 — parameter-driven, not lucky.
static func resolve(
	action: Dictionary,
	participants: Array,
	tuning: Dictionary,
	rng: RngStream,
	params: Dictionary = {}
) -> Dictionary:
	var lane := str(action["lane"])
	# godot-sqlite returns empty seed cells as SQL NULL with the key PRESENT, so
	# Dictionary.get's default never fires and str(null) is "<null>" — coerce here
	# or a no-roll action would roll against a phantom "<null>" input
	var inputs := _text(action, "roll_inputs").split(",", false)
	var quality := 0.5
	if not inputs.is_empty() and not participants.is_empty():
		var difficulty := float(_difficulty(tuning).get(lane, 50))
		var spread := float(tuning.get("quality_spread", DEFAULTS["quality_spread"]))
		var band := float(tuning.get("variance_band", DEFAULTS["variance_band"]))
		var avg := _avg_inputs(participants, inputs)
		# skill dominates, luck flavors: margin moves quality, the band adds spice
		quality = clampf(0.5 + (avg - difficulty) / spread + rng.randf_range(-band, band), 0.0, 1.0)

	var qty := int(params.get("qty", 0))
	var range_band := _range(action)
	if not range_band.is_empty():
		# bounded, and the floor is above zero — no feel-bad weeks
		qty = roundi(lerpf(float(range_band[0]), float(range_band[1]), quality))

	return {
		"quality": quality,
		"output_type": str(action.get("output_type", "")),
		"output_qty": qty,
		"outcome": _outcome_text(quality),
	}


## Resolve an action AND apply its writes. The one entry point callers use.
##   target_ref  what the action aims at (a player_id for drill/1:1, a consumable
##               slug for buy/convert, "" for roster-wide actions)
##   player_ids  who participates ([] = every current member/trial)
##   params      {qty} for purchases/conversions
## Returns {ok, action_id?, output_type?, output_qty?, outcome?, error?}.
static func resolve_and_persist(
	db: Variant,
	guild_id: int,
	week_id: int,
	action_slug: String,
	target_ref: String,
	player_ids: Array,
	rng: RngStream,
	params: Dictionary = {},
	decided_by: String = "player"
) -> Dictionary:
	var action := _action_type(db, action_slug)
	if action.is_empty():
		return {"ok": false, "error": "unknown action '%s'" % action_slug}
	var tuning := Tuning.section("action")

	# time is scarce: the weekly budget is a hard wall, not a suggestion
	var budget := int(tuning.get("weekly_time_budget", DEFAULTS["weekly_time_budget"]))
	if _time_spent(db, guild_id, week_id) >= budget:
		return {"ok": false, "error": "the week's %d action slots are spent" % budget}

	# refuse repeats BEFORE any state is written — otherwise the UNIQUE constraint
	# would fire after the lane writes applied, mutating state with no audit row
	db.query_with_bindings(
		(
			"SELECT COUNT(*) AS n FROM week_action"
			+ " WHERE guild_id = ? AND week_id = ? AND action_type_id = ? AND target_ref = ?;"
		),
		[guild_id, week_id, int(action["action_type_id"]), target_ref]
	)
	if int(db.query_result[0]["n"]) > 0:
		return {
			"ok": false, "error": "'%s' already done this week for '%s'" % [action_slug, target_ref]
		}

	# purchases/conversions are parameter-driven: a missing or non-positive qty is a
	# caller bug, refused up front — never silently defaulted (the audit row must
	# record exactly what was applied)
	if _text(action, "output_range").is_empty() and str(action["lane"]) == "supply":
		if int(params.get("qty", 0)) < 1:
			return {"ok": false, "error": "'%s' needs a positive qty" % action_slug}

	var participants := _participants(db, guild_id, player_ids)
	if participants.is_empty():
		return {"ok": false, "error": "no participants for '%s'" % action_slug}

	var result := resolve(action, participants, tuning, rng, params)

	# ATOMIC: the lane writes, the ledger and the audit row land together or not at
	# all — state must never mutate without its WEEK_ACTION row (review finding).
	db.query("BEGIN TRANSACTION;")
	var apply_error := _apply(
		db, guild_id, week_id, action, target_ref, participants, result, tuning, rng
	)
	if not apply_error.is_empty():
		db.query("ROLLBACK;")
		return {"ok": false, "error": apply_error}

	# the audit row — one WEEK_ACTION per resolved action, stamped with who decided
	if not (
		db
		. query_with_bindings(
			(
				"INSERT INTO week_action (guild_id, week_id, action_type_id, lane, target_ref,"
				+ " time_cost, output_type, output_qty, outcome, decided_by)"
				+ " VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?);"
			),
			[
				guild_id,
				week_id,
				int(action["action_type_id"]),
				str(action["lane"]),
				target_ref,
				result["output_type"],
				int(result["output_qty"]),
				str(result["outcome"]),
				decided_by,
			]
		)
	):
		# a failed audit insert aborts the WHOLE action — never mutate state silently
		db.query("ROLLBACK;")
		return {
			"ok": false,
			"error": "could not record '%s' for '%s' — nothing applied" % [action_slug, target_ref]
		}
	db.query("SELECT last_insert_rowid() AS id;")
	var action_id := int(db.query_result[0]["id"])
	db.query("COMMIT;")

	return {
		"ok": true,
		"action_id": action_id,
		"output_type": result["output_type"],
		"output_qty": int(result["output_qty"]),
		"quality": float(result["quality"]),
		"outcome": str(result["outcome"]),
	}


## Actions already taken this week — the budget check and the planning UI read this.
static func _time_spent(db: Variant, guild_id: int, week_id: int) -> int:
	(
		db
		. query_with_bindings(
			"SELECT COALESCE(SUM(time_cost), 0) AS n FROM week_action WHERE guild_id = ? AND week_id = ?;",
			[guild_id, week_id]
		)
	)
	return int(db.query_result[0]["n"])


## Public wrapper for planners: remaining slots this week.
static func slots_remaining(db: Variant, guild_id: int, week_id: int) -> int:
	var budget := int(
		Tuning.section("action").get("weekly_time_budget", DEFAULTS["weekly_time_budget"])
	)
	return maxi(0, budget - _time_spent(db, guild_id, week_id))


# --- applying the lanes ---------------------------------------------------------


static func _apply(
	db: Variant,
	guild_id: int,
	week_id: int,
	action: Dictionary,
	target_ref: String,
	participants: Array,
	result: Dictionary,
	tuning: Dictionary,
	rng: RngStream
) -> String:
	var qty := int(result["output_qty"])
	match str(action["slug"]):
		"dungeon_run":
			# Marks per runner. (The doc's "chance at gear" + minor skill XP defer to
			# M6-005, which owns equip-on-award and the Marks vendor.)
			for p: Dictionary in participants:
				db.query_with_bindings(
					"UPDATE avatar SET marks = marks + ? WHERE avatar_id = ?;",
					[qty, int(p["avatar_id"])]
				)
			return ""
		"drill":
			return _apply_drill(db, participants, qty, tuning)
		"spec_test":
			for p: Dictionary in participants:
				(
					db
					. query_with_bindings(
						"UPDATE avatar SET familiarity = MIN(100, familiarity + ?) WHERE avatar_id = ?;",
						[qty, int(p["avatar_id"])]
					)
				)
			return ""
		"farm_mats":
			db.query_with_bindings(
				"UPDATE guild_treasury SET mats = mats + ? WHERE guild_id = ?;", [qty, guild_id]
			)
			if not _ledger(db, guild_id, week_id, "farming", "mats", qty):
				return "ledger write failed — action aborted"
			return ""
		"buy_consumables":
			# qty was validated >= 1 up front and IS result.output_qty — the audit row
			# always records exactly what was applied (review finding)
			return _apply_buy(db, guild_id, week_id, target_ref, qty)
		"convert_mats":
			return _apply_convert(db, guild_id, week_id, target_ref, qty, tuning)
		"one_on_one":
			return _apply_one_on_one(db, week_id, participants, qty, result, tuning)
		"social_night":
			WeekState.ensure(db, week_id)
			_update_week_state_for(db, week_id, participants, "morale = MIN(100, morale + ?)", qty)
			_apply_relationship_lite(db, participants, rng)
			return ""
		"rest_week":
			WeekState.ensure(db, week_id)
			_update_week_state_for(db, week_id, participants, "fatigue = MAX(0, fatigue - ?)", qty)
			return ""
	return "no apply step for action '%s'" % action["slug"]


## Drill: raise each trainee's WEAKEST facet — ceiling-gated by potential, scaled by
## growth_rate, capped per week. At the ceiling the gain is honestly 0 (documented:
## you can't grind anyone into a god), and the outcome text says so.
static func _apply_drill(db: Variant, participants: Array, qty: int, tuning: Dictionary) -> String:
	var cap := int(tuning.get("skill_growth_cap", DEFAULTS["skill_growth_cap"]))
	for p: Dictionary in participants:
		var weakest := FACETS[0]
		for facet in FACETS:
			if int(p[facet]) < int(p[weakest]):
				weakest = facet
		var headroom := maxi(0, int(p["potential"]) - int(p[weakest]))
		var gain := clampi(roundi(qty * int(p["growth_rate"]) / 50.0), 0, mini(cap, headroom))
		if gain > 0:
			db.query_with_bindings(
				"UPDATE player SET %s = %s + ? WHERE player_id = ?;" % [weakest, weakest],
				[gain, int(p["player_id"])]
			)
	return ""


static func _apply_buy(
	db: Variant, guild_id: int, week_id: int, consumable_slug: String, qty: int
) -> String:
	db.query_with_bindings(
		"SELECT consumable_id, cost FROM consumable WHERE slug = ?;", [consumable_slug]
	)
	if db.query_result.is_empty():
		return "unknown consumable '%s'" % consumable_slug
	var consumable_id := int(db.query_result[0]["consumable_id"])
	var cost := int(db.query_result[0]["cost"]) * qty

	db.query_with_bindings("SELECT gold FROM guild_treasury WHERE guild_id = ?;", [guild_id])
	if db.query_result.is_empty():
		return "guild %d has no treasury" % guild_id
	if int(db.query_result[0]["gold"]) < cost:
		return "not enough gold: %d needed" % cost

	db.query_with_bindings(
		"UPDATE guild_treasury SET gold = gold - ? WHERE guild_id = ?;", [cost, guild_id]
	)
	_upsert_stockpile(db, guild_id, consumable_id, qty)
	if not _ledger(db, guild_id, week_id, "purchase", "gold", -cost):
		return "ledger write failed — action aborted"
	return ""


static func _apply_convert(
	db: Variant, guild_id: int, week_id: int, consumable_slug: String, qty: int, tuning: Dictionary
) -> String:
	db.query_with_bindings(
		"SELECT consumable_id FROM consumable WHERE slug = ?;", [consumable_slug]
	)
	if db.query_result.is_empty():
		return "unknown consumable '%s'" % consumable_slug
	var consumable_id := int(db.query_result[0]["consumable_id"])
	var mats_needed := qty * int(tuning.get("mats_per_consumable", DEFAULTS["mats_per_consumable"]))

	db.query_with_bindings("SELECT mats FROM guild_treasury WHERE guild_id = ?;", [guild_id])
	if db.query_result.is_empty():
		return "guild %d has no treasury" % guild_id
	if int(db.query_result[0]["mats"]) < mats_needed:
		return "not enough mats: %d needed" % mats_needed

	db.query_with_bindings(
		"UPDATE guild_treasury SET mats = mats - ? WHERE guild_id = ?;", [mats_needed, guild_id]
	)
	_upsert_stockpile(db, guild_id, consumable_id, qty)
	if not _ledger(db, guild_id, week_id, "conversion", "mats", -mats_needed):
		return "ledger write failed — action aborted"
	return ""


static func _apply_one_on_one(
	db: Variant, week_id: int, participants: Array, qty: int, result: Dictionary, tuning: Dictionary
) -> String:
	WeekState.ensure(db, week_id)
	var nudge_max := int(tuning.get("loyalty_nudge_max", DEFAULTS["loyalty_nudge_max"]))
	var nudge := maxi(1, roundi(float(result["quality"]) * nudge_max))
	for p: Dictionary in participants:
		db.query_with_bindings(
			(
				"UPDATE player_week_state SET morale = MIN(100, morale + ?)"
				+ " WHERE week_id = ? AND player_id = ?;"
			),
			[qty, week_id, int(p["player_id"])]
		)
		(
			db
			. query_with_bindings(
				"UPDATE player SET loyalty_current = MIN(100, loyalty_current + ?) WHERE player_id = ?;",
				[nudge, int(p["player_id"])]
			)
		)
	return ""


## Relationship-lite (the doc's "chemistry bump"): a social night warms a few seeded
## pairs by +1 sentiment. Deliberately tiny — real social depth is M10.
static func _apply_relationship_lite(db: Variant, participants: Array, rng: RngStream) -> void:
	if participants.size() < 2:
		return
	var pair_count := mini(3, participants.size() / 2)
	for i in pair_count:
		var a: Dictionary = participants[rng.randi_range(0, participants.size() - 1)]
		var b: Dictionary = participants[rng.randi_range(0, participants.size() - 1)]
		var from_id := int(a["player_id"])
		var to_id := int(b["player_id"])
		if from_id == to_id:
			continue
		db.query_with_bindings(
			(
				"INSERT INTO relationship (player_id_from, player_id_to, sentiment, origin)"
				+ " VALUES (?, ?, 1, 'social_night')"
				+ " ON CONFLICT(player_id_from, player_id_to)"
				+ " DO UPDATE SET sentiment = sentiment + 1;"
			),
			[from_id, to_id]
		)


# --- helpers ----------------------------------------------------------------------


## A roster-scoped PLAYER_WEEK_STATE update — the whole-week UPDATE hit every
## snapshotted player, including non-members, once prospects exist (review finding).
static func _update_week_state_for(
	db: Variant, week_id: int, participants: Array, set_clause: String, value: int
) -> void:
	var ids: Array = participants.map(func(p): return int(p["player_id"]))
	var placeholders := ", ".join(ids.map(func(_i): return "?"))
	var bindings: Array = [value, week_id]
	bindings.append_array(ids)
	db.query_with_bindings(
		(
			"UPDATE player_week_state SET %s WHERE week_id = ? AND player_id IN (%s);"
			% [set_clause, placeholders]
		),
		bindings
	)


## Every treasury move gets its audit row, or the whole action rolls back — the
## caller runs inside the transaction, so returning false aborts everything.
static func _ledger(
	db: Variant, guild_id: int, week_id: int, txn_type: String, resource: String, amount: int
) -> bool:
	return db.query_with_bindings(
		(
			"INSERT INTO treasury_ledger (guild_id, week_id, txn_type, resource_type, amount)"
			+ " VALUES (?, ?, ?, ?, ?);"
		),
		[guild_id, week_id, txn_type, resource, amount]
	)


static func _upsert_stockpile(db: Variant, guild_id: int, consumable_id: int, qty: int) -> void:
	db.query_with_bindings(
		(
			"INSERT INTO guild_stockpile (guild_id, consumable_id, quantity) VALUES (?, ?, ?)"
			+ " ON CONFLICT(guild_id, consumable_id) DO UPDATE SET quantity = quantity + ?;"
		),
		[guild_id, consumable_id, qty, qty]
	)


static func _action_type(db: Variant, slug: String) -> Dictionary:
	db.query_with_bindings("SELECT * FROM action_type WHERE slug = ?;", [slug])
	return {} if db.query_result.is_empty() else db.query_result[0].duplicate()


## Participants joined to their active avatar — one row carrying every field a
## roll_input can name. Scoped to THIS guild's current members/trials (review
## finding: without the guild filter, a roster-wide action would mutate every
## guild's members the moment a second guild has membership rows).
## `player_ids` empty = every current member/trial of the guild.
static func _participants(db: Variant, guild_id: int, player_ids: Array) -> Array:
	var filter := ""
	var bindings: Array = [guild_id]
	if not player_ids.is_empty():
		filter = " AND p.player_id IN (%s)" % ", ".join(player_ids.map(func(_p): return "?"))
		bindings.append_array(player_ids)
	db.query_with_bindings(
		(
			"SELECT p.player_id, p.handle, p.execution, p.awareness, p.consistency,"
			+ " p.potential, p.growth_rate, p.coachability, p.influence, p.volatility,"
			+ " p.time_budget_hrs, a.avatar_id, a.item_level, a.familiarity"
			+ " FROM guild_membership gm"
			+ " JOIN player p ON p.player_id = gm.player_id"
			+ " JOIN avatar a ON a.player_id = p.player_id AND a.is_active = 1"
			+ " WHERE gm.guild_id = ? AND gm.status IN ('member', 'trial')%s" % filter
			+ " ORDER BY p.player_id;"
		),
		bindings
	)
	return db.query_result.duplicate()


## Normalized roll inputs, all on the 0-100 trait scale:
##   gear -> item_level against the tier BiS ceiling; time -> hours (20h = 100);
##   anything else reads the participant column of that name.
static func _avg_inputs(participants: Array, inputs: PackedStringArray) -> float:
	var total := 0.0
	var count := 0
	for p: Dictionary in participants:
		for input_name in inputs:
			match input_name:
				"gear":
					total += float(p["item_level"]) * (100.0 / TIER_BIS_ILVL)
				"time":
					total += float(p["time_budget_hrs"]) * 5.0
				_:
					total += float(p.get(input_name, 50))
			count += 1
	return total / maxf(1.0, float(count))


static func _difficulty(tuning: Dictionary) -> Dictionary:
	var difficulty: Variant = tuning.get("difficulty", {})
	return difficulty if difficulty is Dictionary else {}


## A seed TEXT column as a plain string — SQL NULL (an empty CSV cell) becomes "".
static func _text(row: Dictionary, key: String) -> String:
	var raw: Variant = row.get(key)
	return str(raw) if raw != null else ""


static func _range(action: Dictionary) -> Array:
	var raw: Variant = action.get("output_range")
	if raw == null or str(raw).is_empty():
		return []
	var parts := str(raw).split("-", false)
	if parts.size() != 2:
		return []
	return [int(parts[0]), int(parts[1])]


static func _outcome_text(quality: float) -> String:
	if quality >= 0.8:
		return "an excellent week's work"
	if quality >= 0.55:
		return "a solid week's work"
	if quality >= 0.3:
		return "a modest week's work"
	return "a poor week — but not a wasted one"
