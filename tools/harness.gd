extends SceneTree

## Balance harness (M3-005, rebuilt by MI-009).
##
##   godot --headless -s tools/harness.gd -- --pulls 200
##   godot --headless -s tools/harness.gd -- --pulls 200 --assert-contracts
##   godot --headless -s tools/harness.gd -- --probes
##   godot --headless -s tools/harness.gd -- --pulls 100 --csv user://pulls.csv
##
## THE HARNESS THAT SHIPPED AN UNPLAYABLE GAME. The old version asserted ONE
## global win-rate band on boss 1 and passed green while bosses 2-4 sat at a 0%
## win rate — it swept gear to x3.0, so it was validating a fantasy roster the
## player can never assemble. Two failures of principle, both now closed:
##
##   1. PER-BOSS CONTRACTS. Every boss is asserted against ITS OWN contract
##      (data/seeds/encounter_contract.csv, the machine-readable half of
##      docs/guildmaster-encounter-contracts.md): the progression band at the
##      gear it is FOR, the farm band at full tier BiS, monotonicity in gear,
##      and its dominant failure. A boss that only works on gear the player
##      cannot reach is a FAILING boss.
##
##   2. PREP LEVERAGE. Gear was the only thing the harness ever varied — so it
##      could not tell whether raid prep was TACTICS or ADMINISTRATION. The
##      probes hold seed, roster and gear fixed and vary ONE decision at a time.
##      A prep control that moves nothing, anywhere, is broken or should be cut,
##      and the harness now says so out loud.
##
## Contracts are asserted against a PREPARED raid (crit-immune main tank, duties
## on the best hands). Otherwise the numbers measure the roster lottery rather
## than the boss — the harness roster happens to roll a capped tank, and that is
## luck, not a test.
##
## Exits 0 on PASS, 1 on FAIL.

# The REALISTIC in-tier gear band (MI-001): 7 slots, starting ilvl 18.9, every
# Tier-1 drop ilvl 31 -> full BiS is x1.64. Anything above is unreachable content.
const GEAR_SWEEP: Array[float] = [0.85, 1.0, 1.12, 1.28, 1.42, 1.55, 1.64]
const DEFAULT_PULLS := 150
const PROBE_PULLS := 200
const BASE_SEED := 424242
const MONOTONE_SLACK := 0.06  # sampling noise allowance between adjacent steps
## A prep lever that never moves any boss by more than this is not a decision.
const DEAD_LEVER_PP := 3.0

var _failures: PackedStringArray = []
var _warnings: PackedStringArray = []


func _init() -> void:
	var args := _parse_args()
	var pulls := int(args.get("pulls", DEFAULT_PULLS))

	var db: Variant = Migrator.open_db(":memory:")
	if db == null or not Migrator.migrate(db).ok or not SeedLoader.load_seeds(db).ok:
		printerr("HARNESS FAIL: could not build campaign DB")
		quit(1)
		return
	RosterGen.persist(db, RosterGen.generate_from_db(db, 28, RngStream.derive(BASE_SEED, "roster")))
	AvatarGen.generate_and_persist(db, RngStream.derive(BASE_SEED, "avatar_gen"))

	var roster := _roster(db)
	var prepared := _prepared(roster)
	if prepared["lineup"].is_empty():
		printerr("HARNESS FAIL: could not field a prepared raid from the generated roster")
		quit(1)
		return

	var contracts := _contracts(db)
	if args.has("probes"):
		_run_probes(db, roster, contracts, int(args.get("pulls", PROBE_PULLS)))
	else:
		_run_sweep(db, prepared, contracts, pulls, args)

	db.close_db()
	for warning in _warnings:
		print("  warn: %s" % warning)
	if _failures.is_empty():
		print("HARNESS: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("HARNESS FAIL: %s" % failure)
		quit(1)


# --- the gear sweep + per-boss contracts ---------------------------------------


func _run_sweep(
	db: Variant, prepared: Dictionary, contracts: Dictionary, pulls: int, args: Dictionary
) -> void:
	print("== balance harness: %d pulls x %d gear steps per boss ==" % [pulls, GEAR_SWEEP.size()])
	var csv_lines: PackedStringArray = []
	csv_lines.append(
		"boss,boss_order,gear_mult,seed,outcome,wipe_reason,duration_sec,deaths,mean_rating"
	)

	db.query("SELECT slug, boss_order FROM encounter ORDER BY boss_order;")
	var encounters: Array = db.query_result.duplicate()

	var matrix := {}
	for encounter: Dictionary in encounters:
		var boss := str(encounter["slug"])
		matrix[boss] = []
		for mult in GEAR_SWEEP:
			matrix[boss].append(
				_cell(db, boss, prepared, mult, pulls, csv_lines, int(encounter["boss_order"]))
			)

	_print_sweep(matrix, contracts)
	if args.has("csv"):
		_write_csv(str(args["csv"]), csv_lines)
	if args.has("assert_contracts"):
		_assert_contracts(matrix, contracts)


## One (boss, gear) cell: N seeded pulls with the PREPARED raid.
func _cell(
	db: Variant,
	boss: String,
	prepared: Dictionary,
	mult: float,
	pulls: int,
	csv_lines: PackedStringArray,
	boss_order: int
) -> Dictionary:
	var measured := _measure(
		db,
		boss,
		prepared["lineup"],
		{
			"gear_multiplier": mult,
			"assignments": prepared["assignments"],
			"consumable_tier": "basic",
		},
		pulls,
		csv_lines,
		boss_order
	)
	measured["mult"] = mult
	return measured


func _measure(
	db: Variant,
	boss: String,
	lineup: Array[int],
	overrides: Dictionary,
	pulls: int,
	csv_lines: PackedStringArray = [],
	boss_order: int = 0
) -> Dictionary:
	var input := PullInputLoader.build(db, boss, lineup, overrides)
	var kills := 0
	var reasons := {}
	for i in pulls:
		var seed_value := BASE_SEED + i
		var stream := "harness/%s/%.2f" % [boss, float(overrides.get("gear_multiplier", 1.0))]
		var result := PullResolver.resolve(input, RngStream.derive(seed_value, stream))
		var outcome := str(result["pull"]["outcome"])
		var reason := str(result["pull"]["wipe_reason"]).get_slice(":", 0)
		if outcome == "kill":
			kills += 1
		else:
			reasons[reason] = int(reasons.get(reason, 0)) + 1
		if csv_lines.is_empty():
			continue
		var deaths := 0
		var rating_total := 0
		for row: Dictionary in result["participants"]:
			if bool(row["died"]):
				deaths += 1
			rating_total += int(row["performance_rating"])
		(
			csv_lines
			. append(
				(
					"%s,%d,%.2f,%d,%s,%s,%d,%d,%.2f"
					% [
						boss,
						boss_order,
						float(overrides.get("gear_multiplier", 1.0)),
						seed_value,
						outcome,
						reason,
						int(result["pull"]["duration_sec"]),
						deaths,
						float(rating_total) / result["participants"].size(),
					]
				)
			)
		)
	return {
		"win_rate": float(kills) / pulls,
		"top_reason": _top(reasons),
	}


## THE CONTRACT ASSERTS. Each boss against its own row, never one global band.
func _assert_contracts(matrix: Dictionary, contracts: Dictionary) -> void:
	print("\n== per-boss contracts (docs/guildmaster-encounter-contracts.md) ==")
	print(
		(
			"%-18s %-10s %-16s %-14s %s"
			% ["BOSS", "AT GEAR", "PROGRESSION", "FARM @x1.64", "DOMINANT FAILURE"]
		)
	)
	for boss in matrix:
		if not contracts.has(boss):
			_failures.append("%s has no contract row — retuning without a contract is a bug" % boss)
			continue
		var contract: Dictionary = contracts[boss]
		var at_gear := _at(matrix[boss], float(contract["expected_gear"]))
		var at_farm := _at(matrix[boss], float(contract["farm_gear"]))
		var win := float(at_gear["win_rate"])
		var farm := float(at_farm["win_rate"])
		var lo := float(contract["win_lo"])
		var hi := float(contract["win_hi"])
		var farm_min := float(contract["farm_win_min"])
		var dominant := str(at_gear["top_reason"])

		var progression_ok := win >= lo and win <= hi
		var farm_ok := farm >= farm_min
		var identity_ok := dominant == str(contract["dominant_failure"])
		print(
			(
				"%-18s %-10s %5.0f%% %-9s %5.0f%% %-7s %s %s"
				% [
					boss,
					"x%.2f" % float(contract["expected_gear"]),
					win * 100.0,
					"[%.0f-%.0f]%s" % [lo * 100, hi * 100, "" if progression_ok else " X"],
					farm * 100.0,
					">=%.0f%%%s" % [farm_min * 100, "" if farm_ok else " X"],
					dominant,
					"" if identity_ok else "(want %s) X" % contract["dominant_failure"],
				]
			)
		)

		if not progression_ok:
			_failures.append(
				(
					"%s wins %.0f%% at its own gear (x%.2f) — contract is %.0f-%.0f%%"
					% [boss, win * 100, float(contract["expected_gear"]), lo * 100, hi * 100]
				)
			)
		if not farm_ok:
			_failures.append(
				(
					"%s only reaches %.0f%% at full tier BiS — farm content must not waste a night"
					% [boss, farm * 100]
				)
			)
		if not identity_ok:
			_failures.append(
				(
					"%s dies to '%s', not its authored '%s' — the fight is not what it says it is"
					% [boss, dominant, contract["dominant_failure"]]
				)
			)

	# gearing up must always help, on every boss
	for boss in matrix:
		var previous := -1.0
		for cell: Dictionary in matrix[boss]:
			var rate := float(cell["win_rate"])
			if rate < previous - MONOTONE_SLACK:
				_failures.append(
					(
						"%s: win rate fell %.2f -> %.2f at x%.2f — gearing up must help"
						% [boss, previous, rate, float(cell["mult"])]
					)
				)
			previous = maxf(previous, rate)


# --- prep-leverage probes ------------------------------------------------------


## Does raid prep DECIDE anything? Same seed, same roster, same gear — vary ONE
## decision. If a lever moves nothing on any boss, it is administration, not
## tactics, and it should be fixed or cut.
func _run_probes(db: Variant, roster: Dictionary, contracts: Dictionary, pulls: int) -> void:
	print("== prep-leverage probes: %d pulls per cell, gear + roster held fixed ==" % pulls)
	print("   each cell = win-rate delta (percentage points) from making the RIGHT call\n")

	db.query("SELECT slug FROM encounter ORDER BY boss_order;")
	var bosses: Array = db.query_result.duplicate()

	var levers := _levers(roster)
	var header := "%-14s" % "LEVER"
	for boss: Dictionary in bosses:
		header += " %14s" % str(boss["slug"]).substr(0, 14)
	print(header)

	var best_by_lever := {}
	var worst_by_lever := {}
	for lever_name in levers:
		var lever: Dictionary = levers[lever_name]
		var line := "%-14s" % lever_name
		var best := -999.0
		var worst := 999.0
		for boss: Dictionary in bosses:
			var slug := str(boss["slug"])
			var gear := float(contracts[slug]["expected_gear"]) if contracts.has(slug) else 1.0
			var strong := _measure(
				db, slug, lever["strong"]["lineup"], _over(lever["strong"], gear), pulls
			)
			var weak := _measure(
				db, slug, lever["weak"]["lineup"], _over(lever["weak"], gear), pulls
			)
			var delta := (float(strong["win_rate"]) - float(weak["win_rate"])) * 100.0
			best = maxf(best, delta)
			worst = minf(worst, delta)
			line += " %13s" % ("%+.1f" % delta)
			_note_signature(slug, lever_name, delta, contracts)
		best_by_lever[lever_name] = best
		worst_by_lever[lever_name] = worst
		print(line)

	print("")
	for lever_name in best_by_lever:
		var best := float(best_by_lever[lever_name])
		var worst := float(worst_by_lever[lever_name])
		# A lever is allowed to COST you on a fight it is not for — stacking healers
		# into a DPS race should hurt, and an opportunity cost is what makes a comp
		# a decision rather than a checklist. What a lever may never do is fail on
		# its OWN boss (asserted below, per contract).
		#
		# What it must do is matter SOMEWHERE. A control that moves nothing on any
		# boss is administration, not tactics.
		#
		# Note the direction: never compare |delta|. The first version of this
		# harness took absf() here and cheerfully reported "healers: a real
		# decision, 17pp" — while the right call was making the raid WORSE on every
		# single boss, including the one built around healing.
		if best < DEAD_LEVER_PP:
			_failures.append(
				(
					(
						"prep lever '%s' moves no boss by more than %.1fpp — it is administration,"
						+ " not tactics. Fix it or cut it."
					)
					% [lever_name, DEAD_LEVER_PP]
				)
			)
		else:
			var cost := (
				"" if worst >= -DEAD_LEVER_PP else "  (costs %+.1fpp where it is wrong)" % worst
			)
			print("  ok: '%s' is a real decision (up to %+.1fpp)%s" % [lever_name, best, cost])

	# a boss's SIGNATURE lever must actually be its biggest lever — that is what
	# gives the fight an identity the player can read and act on
	for slug in contracts:
		var contract: Dictionary = contracts[slug]
		var lever := str(contract["signature_lever"])
		var want := float(contract["signature_min_delta"])
		var got := float(contract.get("_measured_signature", 0.0))
		if got < want:
			_failures.append(
				(
					(
						"%s's signature lever '%s' moves it only %.1fpp (contract wants >=%.1fpp)"
						+ " — the fight has no identity the player can act on"
					)
					% [slug, lever, got, want]
				)
			)
		else:
			print("  ok: %s answers to '%s' (%+.1fpp)" % [slug, lever, got])


func _note_signature(slug: String, lever: String, delta: float, contracts: Dictionary) -> void:
	if not contracts.has(slug):
		return
	var contract: Dictionary = contracts[slug]
	if str(contract["signature_lever"]) == lever:
		contract["_measured_signature"] = delta


func _over(variant: Dictionary, gear: float) -> Dictionary:
	return {
		"gear_multiplier": gear,
		"assignments": variant["assignments"],
		"consumable_tier": str(variant.get("consumable_tier", "basic")),
	}


## The five decision axes (MI-009). Each is a STRONG and a WEAK call at identical
## roster power — the delta between them is what raid prep is worth.
func _levers(roster: Dictionary) -> Dictionary:
	return {
		"tank_cap":
		{
			"strong": _lineup(roster, {}),  # crit-immune main tank
			"weak": _lineup(roster, {"crittable_tank": true}),
		},
		"duties":
		{
			"strong": _lineup(roster, {}),  # duties on the best Execution
			"weak": _lineup(roster, {"worst_duties": true}),
		},
		"healers":
		{
			"strong": _lineup(roster, {"healers": 7, "melee": 5, "ranged": 6}),
			"weak": _lineup(roster, {"healers": 3, "melee": 7, "ranged": 8}),
		},
		"range_comp":
		{
			"strong": _lineup(roster, {"melee": 2, "ranged": 11}),
			"weak": _lineup(roster, {"melee": 11, "ranged": 2}),
		},
		"consumables":
		{
			"strong": _lineup(roster, {"consumable_tier": "premium"}),
			"weak": _lineup(roster, {"consumable_tier": ""}),
		},
	}


# --- roster / lineup construction ----------------------------------------------


func _roster(db: Variant) -> Dictionary:
	db.query(
		(
			"SELECT a.avatar_id, r.slug AS role_slug, a.gear_score, a.uncrittable, p.execution"
			+ " FROM avatar a"
			+ " JOIN player p ON p.player_id = a.player_id"
			+ " JOIN spec s ON s.spec_id = a.spec_id"
			+ " JOIN role r ON r.role_id = s.role_id"
			+ " WHERE a.is_active = 1"
			+ " ORDER BY a.gear_score DESC, a.avatar_id;"
		)
	)
	var by_role := {"tank": [], "healer": [], "melee": [], "ranged": []}
	for row in db.query_result:
		by_role[str(row["role_slug"])].append(row.duplicate())
	return by_role


## A lineup + its assignments. Defaults to the PREPARED raid: a crit-immune main
## tank and the duties on the best hands available. `opts` degrades it one axis at
## a time, which is exactly what a probe needs.
func _lineup(roster: Dictionary, opts: Dictionary) -> Dictionary:
	var tanks: Array = roster["tank"].duplicate()
	if bool(opts.get("crittable_tank", false)):
		# the guildmaster who fields his best-geared tank without checking the cap
		tanks.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if int(a["uncrittable"]) != int(b["uncrittable"]):
					return int(a["uncrittable"]) < int(b["uncrittable"])
				return int(a["gear_score"]) > int(b["gear_score"])
		)
	else:
		tanks.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if int(a["uncrittable"]) != int(b["uncrittable"]):
					return int(a["uncrittable"]) > int(b["uncrittable"])
				return int(a["gear_score"]) > int(b["gear_score"])
		)

	var counts := {
		"tank": 2,
		"healer": int(opts.get("healers", 5)),
		"melee": int(opts.get("melee", 6)),
		"ranged": int(opts.get("ranged", 7)),
	}
	var lineup: Array[int] = []
	var picked := {"tank": [], "healer": [], "melee": [], "ranged": []}
	for role in ["tank", "healer", "melee", "ranged"]:
		var pool: Array = tanks if role == "tank" else roster[role]
		for i in mini(int(counts[role]), pool.size()):
			lineup.append(int(pool[i]["avatar_id"]))
			picked[role].append(pool[i])

	return {
		"lineup": lineup,
		"assignments": _assignments(picked, bool(opts.get("worst_duties", false))),
		"consumable_tier": str(opts.get("consumable_tier", "basic")),
	}


## Main tank first (the lineup's tanks are already ordered by cap then gear), then
## the duty windows — to the best Execution in the raid, or the worst if the probe
## is asking what a bad call costs.
func _assignments(picked: Dictionary, worst: bool) -> Dictionary:
	var by_avatar := {}
	var tanks: Array = picked["tank"]
	if not tanks.is_empty():
		by_avatar[int(tanks[0]["avatar_id"])] = [{"assignment_type": "tank", "target": "main"}]
	if tanks.size() > 1:
		by_avatar[int(tanks[1]["avatar_id"])] = [{"assignment_type": "tank", "target": "off"}]

	var candidates: Array = []
	for role in ["melee", "ranged", "healer"]:
		candidates.append_array(picked[role])
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				int(a["execution"]) < int(b["execution"])
				if worst
				else int(a["execution"]) > int(b["execution"])
			)
	)
	for i in mini(3, candidates.size()):
		by_avatar[int(candidates[i]["avatar_id"])] = [
			{"assignment_type": "interrupt", "target": "adds"}
		]
	if candidates.size() > 3:
		by_avatar[int(candidates[3]["avatar_id"])] = [
			{"assignment_type": "cooldown", "target": "lust"}
		]
	return by_avatar


func _prepared(roster: Dictionary) -> Dictionary:
	return _lineup(roster, {})


func _contracts(db: Variant) -> Dictionary:
	db.query(
		(
			"SELECT e.slug, ec.expected_gear, ec.win_lo, ec.win_hi, ec.farm_gear,"
			+ " ec.farm_win_min, ec.dominant_failure, ec.signature_lever, ec.signature_min_delta"
			+ " FROM encounter_contract ec"
			+ " JOIN encounter e ON e.encounter_id = ec.encounter_id;"
		)
	)
	var out := {}
	for row in db.query_result:
		out[str(row["slug"])] = row.duplicate()
	return out


# --- reporting -----------------------------------------------------------------


## The summary reports each boss at the gear IT IS FOR, not at a fixed x1.00.
## Reading identity off the fresh-guild column is how the eye gets lied to: the
## Slagbeast is contracted at x1.28 and dies there to `tank_survival`, but at x1.00
## — gear it was never meant to be fought at — it reads `dps_enrage`, which looks
## like a mistuned boss and is not. Judge a fight where the fight lives.
func _print_sweep(matrix: Dictionary, contracts: Dictionary) -> void:
	var header := "%-18s" % "BOSS"
	for mult in GEAR_SWEEP:
		header += " %7s" % ("x%.2f" % mult)
	print(header + "   AT ITS OWN GEAR: win / dominant failure")
	for boss in matrix:
		var line := "%-18s" % boss
		var expected := float(contracts[boss]["expected_gear"]) if contracts.has(boss) else 1.0
		var at_gear := {}
		for cell: Dictionary in matrix[boss]:
			line += " %6.0f%%" % (float(cell["win_rate"]) * 100.0)
			if is_equal_approx(float(cell["mult"]), expected):
				at_gear = cell
		if at_gear.is_empty():
			print(line + "   (no contract row)")
			continue
		print(
			(
				"%s   x%.2f: %.0f%% / %s"
				% [line, expected, float(at_gear["win_rate"]) * 100.0, at_gear["top_reason"]]
			)
		)


func _at(cells: Array, mult: float) -> Dictionary:
	var best: Dictionary = cells[0]
	for cell: Dictionary in cells:
		if absf(float(cell["mult"]) - mult) < absf(float(best["mult"]) - mult):
			best = cell
	return best


func _top(reasons: Dictionary) -> String:
	var best := ""
	var best_count := 0
	for key in reasons:
		if int(reasons[key]) > best_count:
			best = str(key)
			best_count = int(reasons[key])
	return best if not best.is_empty() else "-"


func _write_csv(path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("cannot write CSV to %s" % path)
		return
	file.store_string("\n".join(lines) + "\n")
	print("  csv: %d pull rows -> %s" % [lines.size() - 1, path])


func _parse_args() -> Dictionary:
	var out := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--pulls":
				out["pulls"] = int(args[i + 1])
				i += 2
			"--assert-contracts":
				out["assert_contracts"] = true
				i += 1
			"--probes":
				out["probes"] = true
				i += 1
			"--csv":
				out["csv"] = args[i + 1]
				i += 2
			_:
				i += 1
	return out
