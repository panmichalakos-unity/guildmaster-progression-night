extends SceneTree

## M5-002 turn-loop smoke. Creates a campaign and drives the weekly "continue" loop
## for a few weeks — auto-completing each event (the smoke does not play raids) —
## printing every empty-day tick, event stop and week roll. Then rebuilds and diffs
## for determinism.
##
##   godot --headless -s tools/smoke/turn_loop_smoke.gd -- --seed 12345
##
## Exits 0 on PASS, 1 on FAIL.

const MAX_STEPS := 30

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_arg()
	print("TURN LOOP SMOKE: seed=%d" % seed_value)

	var transcript_a := _run(seed_value)
	if transcript_a.is_empty():
		printerr("TURN LOOP SMOKE FAIL: loop produced nothing")
		quit(1)
		return
	print(transcript_a)

	if _run(seed_value) != transcript_a:
		_failures.append("non-deterministic: same seed produced two different transcripts")

	if _failures.is_empty():
		print("TURN LOOP SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("TURN LOOP SMOKE FAIL: %s" % failure)
		quit(1)


func _run(seed_value: int) -> String:
	var handle := Genesis.new_in_memory({"seed": seed_value})
	if handle.is_empty():
		return ""
	var db: Variant = handle["db"]
	var lines: PackedStringArray = []

	for _step in MAX_STEPS:
		var result := TurnLoop.advance(db, RngStream.derive(seed_value, "turn"))
		match str(result["kind"]):
			"event":
				var e: Dictionary = result["event"]
				(
					lines
					. append(
						(
							"week %d day %d: %s (%s)  [ticked empty days %s]"
							% [
								_week_number(db),
								int(e["day"]),
								str(e["event_type"]).to_upper(),
								e["time_slot"],
								str(result["empty_days_ticked"]),
							]
						)
					)
				)
				# the smoke does not play raids — just complete and continue
				TurnLoop.complete_event(db, int(e["event_id"]))
			"week_rolled":
				lines.append(
					(
						"-- week rolled to %d  [tail ticks %s] --"
						% [int(result["week_number"]), str(result["empty_days_ticked"])]
					)
				)
			"season_complete":
				lines.append("== season complete (grading is M9) ==")
				break
			_:
				lines.append("!! unexpected: %s" % str(result))
				break

	db.close_db()
	return "\n".join(lines)


func _week_number(db: Variant) -> int:
	var state := GameState.read(db)
	db.query_with_bindings(
		"SELECT week_number FROM week WHERE week_id = ?;", [int(state["week_id"])]
	)
	return int(db.query_result[0]["week_number"])


func _seed_arg() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 12345
