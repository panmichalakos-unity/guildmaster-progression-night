extends SceneTree

## MI-003 — Night One smoke. Proves the first session actually teaches:
##
##   1. The DEFAULT lineup the game hands you fields a crittable main tank.
##   2. The prep screen SAYS SO before you pull.
##   3. Pulling anyway is a brick wall, and the wipe names `tank_survival`.
##   4. Benching the star tank promotes a crit-immune one.
##   5. That single fix turns the wall into a kill in a handful of pulls.
##
## This is the fun-gate arc — diagnose -> adjust -> succeed — and it is the one
## thing that must never regress. Exits 1 if any link in the chain breaks.
##
##   godot --headless -s tools/smoke/first_night_smoke.gd -- --seed 133742

const PULLS := 150
const BOSS := "gatewarden_krogg"
## The fixed lineup must kill inside the progression band (3-8 pulls, with a
## little slack for a lucky guild). See docs/guildmaster-encounter-contracts.md.
const MIN_PULLS_TO_KILL := 2.0
const MAX_PULLS_TO_KILL := 9.0
## Before the fix it should be a wall, not merely "hard".
const MAX_UNFIXED_WIN_RATE := 8.0

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_arg()
	print("FIRST NIGHT SMOKE: seed=%d" % seed_value)

	var campaign := DemoCampaign.build(seed_value)
	if campaign.is_empty():
		printerr("FIRST NIGHT SMOKE: campaign build failed")
		quit(1)
		return
	var db: Variant = campaign["db"]
	var scenario: Dictionary = campaign["scenario"]
	var event_id := int(campaign["event_id"])

	# 1. the default lineup the player is handed
	var default_lineup := PullInputLoader.auto_lineup(db)
	var prep := RaidPrep.build(db, event_id, default_lineup)
	var main_tank := _main_tank(prep["lineup"])
	print(
		(
			"  default main tank: %s (%s) — %s"
			% [
				main_tank.get("handle", "?"),
				scenario["incumbent_spec"],
				"crit-immune" if int(main_tank.get("uncrittable", 0)) == 1 else "CRITTABLE",
			]
		)
	)
	if int(main_tank.get("avatar_id", -1)) != int(scenario["incumbent_id"]):
		_fail("the default lineup does not field the incumbent as main tank")
	if int(main_tank.get("uncrittable", 1)) != 0:
		_fail("the default main tank is already crit-immune — there is no lesson")

	# 2. the prep screen warns BEFORE the player pulls
	var warned := false
	for warning: Dictionary in prep["warnings"]:
		if str(warning.get("term", "")) == "uncrittable":
			warned = true
			print("  prep warning: %s" % warning["text"])
	if not warned:
		_fail("prep gives no crit-immunity warning — the failure is not legible")

	# 3. pulling anyway is a wall, and it says why
	var unfixed := _measure(db, default_lineup)
	print(
		(
			"  as handed to you:   %5.1f%% win   (top wipe: %s)"
			% [unfixed["win_rate"], unfixed["top_reason"]]
		)
	)
	if unfixed["win_rate"] > MAX_UNFIXED_WIN_RATE:
		_fail("the unfixed lineup wins %.1f%% — it should be a wall" % unfixed["win_rate"])
	if str(unfixed["top_reason"]) != "tank_survival":
		_fail("wipes blame '%s', not the tank — the cause is not legible" % unfixed["top_reason"])

	# 4. + 5. bench the star tank; a crit-immune tank takes over; the wall falls
	var fixed := _bench_incumbent(db, default_lineup, int(scenario["incumbent_id"]))
	var fixed_prep := RaidPrep.build(db, event_id, fixed)
	var new_main := _main_tank(fixed_prep["lineup"])
	print(
		(
			"  bench %s -> main tank is now %s (%s)"
			% [scenario["incumbent_handle"], new_main.get("handle", "?"), scenario["fix_spec"]]
		)
	)
	if int(new_main.get("uncrittable", 0)) != 1:
		_fail("benching the incumbent did not promote a crit-immune tank — the fix does not work")

	var fixed_result := _measure(db, fixed)
	var pulls_to_kill := (
		999.0 if fixed_result["win_rate"] < 1.0 else 100.0 / float(fixed_result["win_rate"])
	)
	print(
		(
			"  after the one fix:  %5.1f%% win   -> a kill in ~%.1f pulls"
			% [fixed_result["win_rate"], pulls_to_kill]
		)
	)
	if pulls_to_kill < MIN_PULLS_TO_KILL:
		_fail("the fixed lineup kills in %.1f pulls — too easy to feel earned" % pulls_to_kill)
	if pulls_to_kill > MAX_PULLS_TO_KILL:
		_fail("the fixed lineup needs %.1f pulls — the fix does not pay off" % pulls_to_kill)

	db.close_db()
	if _failures.is_empty():
		print("FIRST NIGHT SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("FIRST NIGHT SMOKE FAIL: %s" % failure)
		quit(1)


## Win rate + dominant wipe reason over PULLS seeded pulls.
func _measure(db: Variant, lineup: Array[int]) -> Dictionary:
	var kills := 0
	var reasons := {}
	for i in PULLS:
		var input := PullInputLoader.build(db, BOSS, lineup)
		var result := PullResolver.resolve(input, RngStream.derive(4400 + i, "first_night"))
		if str(result["pull"]["outcome"]) == "kill":
			kills += 1
		else:
			var key := str(result["pull"]["wipe_reason"]).get_slice(":", 0)
			reasons[key] = int(reasons.get(key, 0)) + 1
	var top := "-"
	var best := 0
	for key in reasons:
		if int(reasons[key]) > best:
			top = str(key)
			best = int(reasons[key])
	return {"win_rate": 100.0 * kills / PULLS, "top_reason": top}


## The fix a player would actually perform in the prep screen: bench the star
## tank, then fill the empty slot from the bench with the best tank left.
func _bench_incumbent(db: Variant, lineup: Array[int], incumbent_id: int) -> Array[int]:
	var fixed := RaidPrep.toggle(lineup, incumbent_id)
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
		if avatar_id != incumbent_id and avatar_id not in fixed:
			return RaidPrep.toggle(fixed, avatar_id)
	return fixed


## RaidPrep derives the main tank as the best-geared tank in the lineup.
func _main_tank(lineup_rows: Array) -> Dictionary:
	var best := {}
	for row: Dictionary in lineup_rows:
		if str(row["role_slug"]) != "tank":
			continue
		if best.is_empty() or int(row["gear_score"]) > int(best["gear_score"]):
			best = row
	return best


func _fail(message: String) -> void:
	_failures.append(message)


func _seed_arg() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 133742
