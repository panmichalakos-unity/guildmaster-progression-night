class_name Inbox
extends RefCounted

## The decision inbox (M5-005) — the FM-style single queue for everything that
## needs the Guildmaster's attention (campaign doc: "a lightweight INBOX_ITEM view
## over existing queues — not heavy new structure"). PURELY DERIVED: build() only
## reads, and an item clears when the queue behind it resolves (the lineup gets
## set, the loot gets awarded, the night gets finished). No dismissal state exists
## until a screen needs one.
##
##   Inbox.build(db, week_id) -> Array[Dictionary]
##
## Item shape: {kind, priority, title, detail, ref}. Kinds by source queue:
##   blocked_event        a night still in progress — the loop will not advance
##   manning_short        availability says the raid cannot field 20 (decision)
##   lineup_pending       a scheduled raid has no persisted lineup yet
##   availability_pending a scheduled raid whose availability is still unrolled
##   unawarded_loot       LOOT_DROP rows nobody has awarded (M6 owns the panel)
##   application          prospects in PROSPECT_ASSESSMENT (M8 owns recruitment)
##   objective            the season mandate, ungraded (M9 issues these)
##
## Titles follow the terminology doc: consequence first, then the action.

const PRIORITY_URGENT := 1
const PRIORITY_DECISION := 2
const PRIORITY_NOTICE := 3


## The full queue for the week, urgent first; deterministic order throughout.
static func build(db: Variant, week_id: int) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	_blocked_events(db, week_id, items)
	_raid_prep(db, week_id, items)
	_unawarded_loot(db, items)
	_applications(db, items)
	_mandate(db, week_id, items)
	items.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["priority"]) != int(b["priority"]):
				return int(a["priority"]) < int(b["priority"])
			if str(a["kind"]) != str(b["kind"]):
				return str(a["kind"]) < str(b["kind"])
			return str(a["title"]) < str(b["title"])
	)
	return items


## Count per kind, for smokes and the digest's one-line summary.
static func counts(items: Array[Dictionary]) -> Dictionary:
	var out := {}
	for item: Dictionary in items:
		var kind := str(item["kind"])
		out[kind] = int(out.get(kind, 0)) + 1
	return out


# --- the queues ---------------------------------------------------------------


static func _blocked_events(db: Variant, week_id: int, items: Array[Dictionary]) -> void:
	db.query_with_bindings(
		(
			"SELECT event_id, event_type, day FROM calendar_event"
			+ " WHERE week_id = ? AND status = 'in_progress' ORDER BY day, event_id;"
		),
		[week_id]
	)
	for row in db.query_result:
		(
			items
			. append(
				{
					"kind": "blocked_event",
					"priority": PRIORITY_URGENT,
					"title":
					(
						"The week cannot advance — a %s on day %d is still unresolved."
						% [str(row["event_type"]), int(row["day"])]
					),
					"detail": "Finish the night (or call it) to keep the calendar moving.",
					"ref": {"event_id": int(row["event_id"])},
				}
			)
		)


static func _raid_prep(db: Variant, week_id: int, items: Array[Dictionary]) -> void:
	db.query_with_bindings(
		(
			"SELECT event_id, day FROM calendar_event"
			+ " WHERE week_id = ? AND event_type = 'raid' AND status = 'scheduled'"
			+ " ORDER BY day, event_id;"
		),
		[week_id]
	)
	for row in db.query_result.duplicate():
		var event_id := int(row["event_id"])
		var day := int(row["day"])

		db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM raid_lineup WHERE event_id = ? AND is_benched = 0;",
			[event_id]
		)
		if int(db.query_result[0]["n"]) == 0:
			(
				items
				. append(
					{
						"kind": "lineup_pending",
						"priority": PRIORITY_DECISION,
						"title": "The raid on day %d has no lineup yet." % day,
						"detail": "Pick your 20 and set assignments before the night.",
						"ref": {"event_id": event_id},
					}
				)
			)

		db.query_with_bindings(
			"SELECT COUNT(*) AS n FROM event_availability WHERE event_id = ?;", [event_id]
		)
		if int(db.query_result[0]["n"]) == 0:
			(
				items
				. append(
					{
						"kind": "availability_pending",
						"priority": PRIORITY_DECISION,
						"title": "Nobody has confirmed for the raid on day %d." % day,
						"detail": "Roll the week's availability to see who can make it.",
						"ref": {"event_id": event_id},
					}
				)
			)
			continue

		var manning := PrepDecisions.manning(db, event_id)
		if bool(manning["short"]):
			var missing: Array = manning["roles_missing"]
			# the consequence line must state what is actually wrong: a headcount
			# shortage and a role hole are different problems ("Only 24 of the 20
			# you need" was an arithmetic falsehood — M5-005 review)
			var title := ""
			if int(manning["available"]) < int(manning["minimum"]):
				title = (
					"Only %d of the %d you need can raid on day %d."
					% [int(manning["available"]), int(manning["minimum"]), day]
				)
			else:
				title = (
					"You can field %d on day %d, but nobody available covers: %s."
					% [int(manning["available"]), day, ", ".join(missing)]
				)
			var missing_note := "" if missing.is_empty() else " Missing: %s." % ", ".join(missing)
			(
				items
				. append(
					{
						"kind": "manning_short",
						"priority": PRIORITY_URGENT,
						"title": title,
						"detail":
						(
							"Decide the night: run short, downshift to the gearable"
							+ " bosses, convert to a dungeon, or cancel.%s" % missing_note
						),
						"ref": {"event_id": event_id},
					}
				)
			)


static func _unawarded_loot(db: Variant, items: Array[Dictionary]) -> void:
	db.query(
		(
			"SELECT ld.drop_id, li.display_name FROM loot_drop ld"
			+ " JOIN loot_item li ON li.item_id = ld.item_id"
			+ " WHERE ld.awarded_to_player_id IS NULL ORDER BY ld.drop_id;"
		)
	)
	for row in db.query_result:
		(
			items
			. append(
				{
					"kind": "unawarded_loot",
					"priority": PRIORITY_DECISION,
					"title": "%s is sitting unawarded." % str(row["display_name"]),
					"detail":
					(
						"Every week it sits, someone wonders why. Award it —"
						+ " the claims panel arrives with M6."
					),
					"ref": {"drop_id": int(row["drop_id"])},
				}
			)
		)


static func _applications(db: Variant, items: Array[Dictionary]) -> void:
	db.query(
		(
			"SELECT DISTINCT pa.player_id, p.handle FROM prospect_assessment pa"
			+ " JOIN player p ON p.player_id = pa.player_id"
			+ " JOIN guild g ON g.guild_id = pa.guild_id AND g.is_player_guild = 1"
			+ " LEFT JOIN guild_membership gm ON gm.player_id = pa.player_id"
			+ " AND gm.guild_id = pa.guild_id"
			+ " WHERE gm.player_id IS NULL ORDER BY pa.player_id;"
		)
	)
	for row in db.query_result:
		(
			items
			. append(
				{
					"kind": "application",
					"priority": PRIORITY_NOTICE,
					"title": "%s wants to join." % str(row["handle"]),
					"detail":
					(
						"What you see is an estimate, not the truth — scouting and"
						+ " trials arrive with M8."
					),
					"ref": {"player_id": int(row["player_id"])},
				}
			)
		)


static func _mandate(db: Variant, week_id: int, items: Array[Dictionary]) -> void:
	db.query_with_bindings("SELECT season_id FROM week WHERE week_id = ?;", [week_id])
	if db.query_result.is_empty():
		return
	var season_id := int(db.query_result[0]["season_id"])
	db.query_with_bindings(
		(
			"SELECT so.objective_id, so.target, so.priority, so.is_personal_ambition,"
			+ " ot.display_name FROM season_objective so"
			+ " JOIN objective_type ot ON ot.objective_type_id = so.objective_type_id"
			+ " WHERE so.season_id = ? AND so.result IS NULL"
			+ " ORDER BY so.priority, so.objective_id;"
		),
		[season_id]
	)
	for row in db.query_result:
		var ambition := int(row["is_personal_ambition"]) == 1
		(
			items
			. append(
				{
					"kind": "objective",
					"priority": PRIORITY_NOTICE,
					"title":
					(
						"%s: %s"
						% [
							"Your own ambition" if ambition else "The guild's mandate",
							str(row["display_name"]),
						]
					),
					"detail": "Target: %s. Graded at season's end." % str(row["target"]),
					"ref": {"objective_id": int(row["objective_id"])},
				}
			)
		)
