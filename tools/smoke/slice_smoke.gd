extends SceneTree

## Phase-A vertical-slice smoke (M4-005). Headless: demo campaign → prep →
## full Emberdeep night → report. Exit 0 on success.
##
##   godot --headless -s tools/smoke/slice_smoke.gd -- --seed 133742
##
## MI-003: this plays the night as a COMPETENT guildmaster — it reads the raid-prep
## warning and benches the crittable main tank before pulling. That fix is the whole
## Night One lesson (docs/guildmaster-first-session.md); a player who ignores it
## wipes all night by design, which is what `first_night_smoke.gd` measures. The
## slice therefore asserts a KILL: a green slice with zero kills is precisely the
## failure this project's intervention existed to stop.


func _init() -> void:
	var seed_value := _parse_seed()
	print("SLICE SMOKE: seed=%d" % seed_value)

	var a := _run_night(seed_value)
	if not bool(a["ok"]):
		_fail(str(a["error"]))
	var report: Dictionary = a["report"]
	print(
		(
			"  pulls=%d kills=%d wipes=%d"
			% [int(report["pull_count"]), int(report["kills"]), int(report["wipes"])]
		)
	)
	print("  %s" % report["summary_line"])
	if int(report["pull_count"]) < 4:
		_fail("expected at least one pull per boss")
	if int(report["kills"]) < 1:
		_fail("a prepared raid killed nothing all night — the slice is not playable")
	if report["ratings"].is_empty():
		_fail("report missing ratings")
	if report["bosses"].size() != 4:
		_fail("expected 4 bosses in report")

	var b := _run_night(seed_value)
	if not bool(b["ok"]):
		_fail("determinism rebuild failed: %s" % b["error"])
	var out_a := str(a["pulls"][0]["result"]["pull"]["outcome"])
	var out_b := str(b["pulls"][0]["result"]["pull"]["outcome"])
	var wipe_a := str(a["pulls"][0]["result"]["pull"]["wipe_reason"])
	var wipe_b := str(b["pulls"][0]["result"]["pull"]["wipe_reason"])
	if out_a != out_b or wipe_a != wipe_b:
		_fail("determinism break on first pull: %s/%s vs %s/%s" % [out_a, wipe_a, out_b, wipe_b])
	if int(a["report"]["pull_count"]) != int(b["report"]["pull_count"]):
		_fail("determinism break on pull_count")

	print("SLICE SMOKE: PASS")
	quit(0)


func _run_night(seed_value: int) -> Dictionary:
	var campaign := DemoCampaign.build(seed_value)
	if campaign.is_empty():
		return {"ok": false, "error": "DemoCampaign.build failed"}
	var db: Variant = campaign["db"]
	var event_id := int(campaign["event_id"])
	# read the prep warning and act on it, like a guildmaster would
	var lineup := _fix_the_tank(db, int(campaign["scenario"]["incumbent_id"]))
	var prep_report := RaidPrep.build(db, event_id, lineup)
	if not bool(prep_report["ready"]):
		db.close_db()
		return {"ok": false, "error": "prep lineup not ready"}
	var night := (
		NightRunner
		. run_night(
			db,
			seed_value,
			int(campaign["guild_id"]),
			int(campaign["event_id"]),
			{
				"lineup_ids": prep_report["lineup_ids"],
				"assignments": prep_report["assignments"],
				"consumable_tier": "basic",
			}
		)
	)
	db.close_db()
	return night


## The Night One fix: bench the crittable star tank the default lineup fields,
## and call up the best tank left on the bench.
func _fix_the_tank(db: Variant, incumbent_id: int) -> Array[int]:
	var lineup := RaidPrep.toggle(PullInputLoader.auto_lineup(db), incumbent_id)
	db.query(
		(
			"SELECT a.avatar_id FROM avatar a"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE r.slug = 'tank' AND a.is_active = 1"
			+ " ORDER BY a.gear_score DESC, a.avatar_id;"
		)
	)
	for row in db.query_result:
		var avatar_id := int(row["avatar_id"])
		if avatar_id != incumbent_id and avatar_id not in lineup:
			return RaidPrep.toggle(lineup, avatar_id)
	return lineup


func _parse_seed() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return SimFixture.TEST_SEED


func _fail(message: String) -> void:
	printerr("SLICE SMOKE: FAIL — %s" % message)
	quit(1)
