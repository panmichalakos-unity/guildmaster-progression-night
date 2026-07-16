extends SceneTree

## M5-003 availability + prep-decisions smoke. Rolls who can make the week-1 raid,
## prints the manning check and the per-boss readiness preview, then rebuilds and
## diffs the availability for determinism.
##
##   godot --headless -s tools/smoke/availability_smoke.gd -- --seed 12345
##
## Exits 0 on PASS, 1 on FAIL.

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_arg()
	print("AVAILABILITY SMOKE: seed=%d" % seed_value)

	var digest_a := _run(seed_value)
	if digest_a.is_empty():
		printerr("AVAILABILITY SMOKE FAIL: produced nothing")
		quit(1)
		return
	print(digest_a)

	if _run(seed_value) != digest_a:
		_failures.append("non-deterministic: same seed produced different availability")

	if _failures.is_empty():
		print("AVAILABILITY SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("AVAILABILITY SMOKE FAIL: %s" % failure)
		quit(1)


func _run(seed_value: int) -> String:
	var handle := Genesis.new_in_memory({"seed": seed_value})
	if handle.is_empty():
		return ""
	var db: Variant = handle["db"]
	var event_id := int(handle["event_id"])
	var season_id := int(handle["season_id"])
	var lines: PackedStringArray = []

	var rolled := Availability.roll_for_event(
		db, event_id, RngStream.derive(seed_value, "availability").substream(str(event_id))
	)
	lines.append(
		(
			"who can raid: %d available, %d out"
			% [int(rolled["available"]), int(rolled["unavailable"])]
		)
	)
	# show the first few reasons (window vs volatility) — plain language
	var shown := 0
	for reason: String in rolled["reasons"]:
		lines.append("  out: %s" % reason)
		shown += 1
		if shown >= 4:
			break

	var manning := PrepDecisions.manning(db, event_id)
	(
		lines
		. append(
			(
				"manning: %d/%d  short=%s  roles_missing=%s"
				% [
					int(manning["available"]),
					int(manning["minimum"]),
					manning["short"],
					str(manning["roles_missing"]),
				]
			)
		)
	)

	lines.append("readiness (auto-lineup vs the tier):")
	var lineup := PullInputLoader.auto_lineup(db)
	for boss: Dictionary in PrepDecisions.readiness_preview(db, lineup, season_id):
		lines.append(
			"  %-18s x%.2f  %s" % [boss["boss_name"], boss["expected_gear"], boss["label"]]
		)
	lines.append(
		(
			"gearable subset (downshift target): %s"
			% str(PrepDecisions.gearable_subset(db, lineup, season_id))
		)
	)

	db.close_db()
	return "\n".join(lines)


func _seed_arg() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 12345
