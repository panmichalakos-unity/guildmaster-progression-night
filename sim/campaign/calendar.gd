class_name Calendar
extends RefCounted

## The weekly calendar (M5-002). Places CALENDAR_EVENT rows on days + time slots and
## reads a week back in chronological order. Time is data, never a wall clock.
##
## v1 default week: one raid night and one rest night; the other five days are empty
## and the turn loop ticks recovery across them. Days/slots are tuning-driven
## (`calendar.raid_day` / `rest_day`), never hardcoded gameplay numbers.

## Slots run afternoon -> evening -> late within a day; this ranks them for ordering.
const SLOT_ORDER := {"afternoon": 0, "evening": 1, "late": 2}


## Inserts one event and returns its id (or -1 on failure). `raid_id` is required for
## event_type 'raid' and ignored otherwise.
static func schedule(
	db: Variant, week_id: int, day: int, time_slot: String, event_type: String, raid_id: int = 0
) -> int:
	var raid_ref: Variant = raid_id if event_type == "raid" and raid_id > 0 else null
	if not db.query_with_bindings(
		(
			"INSERT INTO calendar_event (week_id, raid_id, day, time_slot, event_type)"
			+ " VALUES (?, ?, ?, ?, ?);"
		),
		[week_id, raid_ref, day, time_slot, event_type]
	):
		push_error("Calendar: schedule failed: %s" % db.error_message)
		return -1
	db.query("SELECT last_insert_rowid() AS id;")
	return int(db.query_result[0]["id"])


## Lays out the standard week for `week_id` in `season_id`: the season's raid on the
## tuned raid day (evening) and a rest night on the tuned rest day. Returns the raid
## event id, or -1 if the season has no raid to schedule.
static func build_default_week(db: Variant, week_id: int, season_id: int) -> int:
	var cal: Dictionary = Tuning.section("calendar")
	var raid_day := int(cal.get("raid_day", 3))
	var rest_day := int(cal.get("rest_day", 6))

	db.query_with_bindings(
		"SELECT raid_id FROM raid WHERE season_id = ? ORDER BY raid_id LIMIT 1;", [season_id]
	)
	if db.query_result.is_empty():
		push_error("Calendar: season %d has no raid to schedule" % season_id)
		return -1
	var raid_id := int(db.query_result[0]["raid_id"])

	var raid_event := schedule(db, week_id, raid_day, "evening", "raid", raid_id)
	if raid_event < 0:
		return -1
	# a scheduled rest night — the loop STOPS on it (unlike an empty day, which just
	# ticks). Non-fatal if it collides with the raid slot; the raid is what matters.
	schedule(db, week_id, rest_day, "evening", "rest")
	return raid_event


## The week's events that still need resolving, in chronological (day, slot) order.
static func pending_events(db: Variant, week_id: int) -> Array:
	db.query_with_bindings(
		(
			"SELECT event_id, day, time_slot, event_type, status, raid_id FROM calendar_event"
			+ " WHERE week_id = ? AND status IN ('scheduled', 'in_progress')"
			+ " ORDER BY day, CASE time_slot"
			+ " WHEN 'afternoon' THEN 0 WHEN 'evening' THEN 1 ELSE 2 END;"
		),
		[week_id]
	)
	return db.query_result.duplicate()
