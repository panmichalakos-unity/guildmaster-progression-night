class_name BenchCost
extends RefCounted

## The bench has a cost (M5-007). Consecutive benchings of raiders who were
## AVAILABLE to play ding morale and current loyalty, scaled by ego — the
## raid-prep doc's promise, previously an explicit digest placeholder.
##
## One module owns the whole thing so the applier and the digest can never
## disagree:
##   streaks(db, week_id, week_offset=0) -> [{player_id, avatar_id, handle, ego, streak}]
##   assess(db, week_id)  -> the priced MARGINAL charge the roll out of week_id applies
##   apply(db, streak_week_id, charge_week_id) -> the assess rows it applied
##
## Streak semantics (per raider, walking completed lineup-recorded raids in this
## week's season, newest first): a benched night counts; a FIELDED night breaks;
## a night with no row for the raider (they were unavailable — persist_lineup
## writes none) neither counts nor breaks — it is skipped. ADR-0038 locked the
## event-level no-record case; ADR-0042 locks this per-raider reading: one
## availability miss must not reset a perpetual bencher's tab.
##
## The charge is MARGINAL (M5-007 review): each week roll charges the price of
## the streak as of the played week MINUS the price as of the week before, so
## every benched night is priced exactly once, a frozen streak (no lineup-
## recorded raids this week) charges nothing, and there is no compounding.
## Deterministic — no rng; the digest recomputes exactly what the roll applied.
##
## Recompute honesty (its expiry conditions): assess() prices with CURRENT ego,
## membership and bench tuning. Nothing in the sim mutates those today, so the
## digest's rebuilt numbers equal the applied ones. The day ego drift (M10),
## attrition (M8) or live tuning edits land, the charge needs a persisted audit
## row — do not silently outlive this assumption. A season's FINAL week is never
## charged (there is no next snapshot); grading (M9) owns that aftermath, and
## streaks are season-scoped so nothing leaks into the next tier.

## Ego scaling: a ding is halved for the egoless and 1.5x for the prima donna.
## The SHAPE is fixed here (0.5 + ego/100); the per-night magnitudes are tuning.
const EGO_SCALE_BASE := 0.5


## Bench streaks anchored `week_offset` weeks before `week_id`'s week (0 = as of
## that week). The offset is how assess() sees the streak the PREVIOUS roll saw.
static func streaks(db: Variant, week_id: int, week_offset: int = 0) -> Array[Dictionary]:
	db.query_with_bindings(
		(
			"SELECT ce.event_id FROM calendar_event ce"
			+ " JOIN week w ON w.week_id = ce.week_id"
			+ " JOIN week cur ON cur.week_id = ?"
			+ " WHERE ce.event_type = 'raid' AND ce.status = 'completed'"
			+ " AND w.season_id = cur.season_id AND w.week_number <= cur.week_number - ?"
			+ " AND EXISTS (SELECT 1 FROM raid_lineup rl WHERE rl.event_id = ce.event_id)"
			+ " ORDER BY w.week_number DESC, ce.day DESC, ce.event_id DESC;"
		),
		[week_id, week_offset]
	)
	var event_ids: Array[int] = []
	for row in db.query_result:
		event_ids.append(int(row["event_id"]))
	if event_ids.is_empty():
		return []

	db.query(
		(
			"SELECT a.avatar_id, p.player_id, p.handle, p.ego FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " JOIN guild_membership gm ON gm.player_id = p.player_id"
			+ " JOIN guild g ON g.guild_id = gm.guild_id AND g.is_player_guild = 1"
			+ " WHERE a.is_active = 1 AND gm.status IN ('member', 'trial')"
			+ " ORDER BY a.avatar_id;"
		)
	)
	var out: Array[Dictionary] = []
	for member in db.query_result.duplicate():
		var streak := 0
		for event_id in event_ids:
			db.query_with_bindings(
				"SELECT is_benched FROM raid_lineup WHERE event_id = ? AND avatar_id = ?;",
				[event_id, int(member["avatar_id"])]
			)
			if db.query_result.is_empty():
				# they were unavailable that night — it neither counts nor breaks
				continue
			if int(db.query_result[0]["is_benched"]) == 0:
				break
			streak += 1
		if streak > 0:
			(
				out
				. append(
					{
						"player_id": int(member["player_id"]),
						"avatar_id": int(member["avatar_id"]),
						"handle": str(member["handle"]),
						"ego": int(member["ego"]),
						"streak": streak,
					}
				)
			)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["streak"]) != int(b["streak"]):
				return int(a["streak"]) > int(b["streak"])
			return str(a["handle"]) < str(b["handle"])
	)
	return out


## What the roll out of `week_id` charges: the marginal price of each streak over
## what the previous roll already charged. Empty when nothing new accrued.
static func assess(db: Variant, week_id: int) -> Array[Dictionary]:
	var tuning := Tuning.section("bench")
	var streak_min := int(tuning.get("streak_min", 2))
	var morale_per := int(tuning.get("morale_per_night", 2))
	var loyalty_per := int(tuning.get("loyalty_per_night", 1))

	var prior := {}
	for row in streaks(db, week_id, 1):
		prior[int(row["player_id"])] = int(row["streak"])

	var priced: Array[Dictionary] = []
	for row in streaks(db, week_id):
		var ego := int(row["ego"])
		var now := _price(int(row["streak"]), ego, streak_min, morale_per, loyalty_per)
		var before := _price(
			int(prior.get(int(row["player_id"]), 0)), ego, streak_min, morale_per, loyalty_per
		)
		var morale_ding := maxi(0, int(now["morale"]) - int(before["morale"]))
		var loyalty_ding := maxi(0, int(now["loyalty"]) - int(before["loyalty"]))
		if morale_ding == 0 and loyalty_ding == 0:
			continue
		var charged := row.duplicate()
		charged["morale_ding"] = morale_ding
		charged["loyalty_ding"] = loyalty_ding
		priced.append(charged)
	return priced


## Charge the assessed dings: morale into `charge_week_id`'s snapshot (the new
## week arrives with the mood already soured), loyalty into the player's current
## loyalty (baseline stays put — conventions doc). Returns what it applied.
static func apply(db: Variant, streak_week_id: int, charge_week_id: int) -> Array[Dictionary]:
	var charged := assess(db, streak_week_id)
	for row: Dictionary in charged:
		db.query_with_bindings(
			(
				"UPDATE player_week_state SET morale = MAX(0, morale - ?)"
				+ " WHERE week_id = ? AND player_id = ?;"
			),
			[int(row["morale_ding"]), charge_week_id, int(row["player_id"])]
		)
		db.query_with_bindings(
			(
				"UPDATE player SET loyalty_current = MAX(0, loyalty_current - ?)"
				+ " WHERE player_id = ?;"
			),
			[int(row["loyalty_ding"]), int(row["player_id"])]
		)
	return charged


## The full price of a streak. Below the threshold it is free; past it, every
## night is priced, ego-scaled, floored at 1 ONLY when the knob is actually on —
## an explicit 0 in tuning turns that currency off entirely.
static func _price(
	streak: int, ego: int, streak_min: int, morale_per: int, loyalty_per: int
) -> Dictionary:
	if streak < streak_min:
		return {"morale": 0, "loyalty": 0}
	var scale := EGO_SCALE_BASE + float(ego) / 100.0
	return {
		"morale": 0 if morale_per <= 0 else maxi(1, roundi(morale_per * streak * scale)),
		"loyalty": 0 if loyalty_per <= 0 else maxi(1, roundi(loyalty_per * streak * scale)),
	}
