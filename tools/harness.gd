extends SceneTree

## M3-005 batch balance harness — the cheapest insurance against a broken feel.
## Usage:
##   godot --headless -s tools/harness.gd -- --pulls 200
##   godot --headless -s tools/harness.gd -- --pulls 200 --assert-winrate 0.6 0.8
##   godot --headless -s tools/harness.gd -- --pulls 100 --csv user://pulls.csv
##
## Builds a REAL campaign (migrate -> seeds -> 28-roster -> auto-lineup), then
## sweeps every seeded encounter across gear multipliers, running N seeded
## pulls per cell. Reports win rates + top wipe reasons + mean ratings, and
## optionally dumps one CSV row per pull for the balance lab (DuckDB/pandas).
##
## --assert-winrate LO HI enforces the difficulty-via-margin contract:
##   1. REACHABLE: some gear step on boss 1 lands inside [LO, HI] — matched
##      progression content sits in the target band.
##   2. MONOTONE(gear): win rate never falls as gear rises (per boss, small
##      sampling slack) — gearing up always helps.
##   3. SPREAD: undergeared is decisive (<= 0.25 at the lowest step) and
##      overgeared saturates (>= 0.9 at the highest) on boss 1 — the sigmoid
##      spans one-shot to brick wall.
## Exits 0 on PASS, 1 on FAIL.

# 0.8 = fresh-roster undergear; 1.25-1.75 = the tier's own drops; 3.0 = next-tier
# gear on an entry boss ("over-geared vs low tier -> one-shot", the doc's spread).
# Dense in the transition region so the 60-80% band cannot fall between steps.
const GEAR_SWEEP: Array[float] = [0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 3.0]
const DEFAULT_PULLS := 150
const BASE_SEED := 424242
const MONOTONE_SLACK := 0.06  # sampling noise allowance between adjacent steps

var _failures: PackedStringArray = []


func _init() -> void:
	var args := _parse_args()
	var pulls := int(args.get("pulls", DEFAULT_PULLS))
	print("== balance harness: %d pulls x %d gear steps per boss ==" % [pulls, GEAR_SWEEP.size()])

	var db: Variant = Migrator.open_db(":memory:")
	if db == null or not Migrator.migrate(db).ok or not SeedLoader.load_seeds(db).ok:
		printerr("HARNESS FAIL: could not build campaign DB")
		quit(1)
		return
	var players := RosterGen.generate_from_db(db, 28, RngStream.derive(BASE_SEED, "roster_gen"))
	RosterGen.persist(db, players)
	AvatarGen.generate_and_persist(db, RngStream.derive(BASE_SEED, "avatar_gen"))
	var lineup := PullInputLoader.auto_lineup(db)

	db.query("SELECT slug, boss_order FROM encounter ORDER BY boss_order;")
	var encounters: Array = db.query_result.duplicate()

	var csv_lines: PackedStringArray = []
	csv_lines.append(
		"boss,boss_order,gear_mult,seed,outcome,wipe_reason,duration_sec,deaths,mean_rating"
	)
	var matrix := {}  # boss_slug -> Array[{mult, win_rate, top_reason}]

	for encounter: Dictionary in encounters:
		var boss := str(encounter["slug"])
		matrix[boss] = []
		for mult in GEAR_SWEEP:
			var cell := _run_cell(
				db, boss, lineup, mult, pulls, csv_lines, int(encounter["boss_order"])
			)
			matrix[boss].append(cell)

	_print_report(matrix)
	if args.has("csv"):
		_write_csv(str(args["csv"]), csv_lines)
	if args.has("assert_lo"):
		_assert_band(matrix, encounters, float(args["assert_lo"]), float(args["assert_hi"]))

	db.close_db()
	if _failures.is_empty():
		print("HARNESS: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("HARNESS FAIL: %s" % failure)
		quit(1)


func _run_cell(
	db: Variant,
	boss: String,
	lineup: Array[int],
	mult: float,
	pulls: int,
	csv_lines: PackedStringArray,
	boss_order: int
) -> Dictionary:
	var input := PullInputLoader.build(db, boss, lineup, {"gear_multiplier": mult})
	var kills := 0
	var reasons := {}
	for i in pulls:
		var seed_value := BASE_SEED + i
		var result := PullResolver.resolve(
			input, RngStream.derive(seed_value, "harness/%s/%.2f" % [boss, mult])
		)
		var outcome := str(result["pull"]["outcome"])
		var reason := str(result["pull"]["wipe_reason"])
		if outcome == "kill":
			kills += 1
		else:
			var key := reason.get_slice(":", 0)
			reasons[key] = int(reasons.get(key, 0)) + 1
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
						mult,
						seed_value,
						outcome,
						reason.get_slice(":", 0),
						int(result["pull"]["duration_sec"]),
						deaths,
						float(rating_total) / result["participants"].size(),
					]
				)
			)
		)
	return {
		"mult": mult,
		"win_rate": float(kills) / pulls,
		"top_reason": _top_reason(reasons),
	}


func _top_reason(reasons: Dictionary) -> String:
	var best := ""
	var best_count := 0
	for key in reasons:
		if int(reasons[key]) > best_count:
			best = str(key)
			best_count = int(reasons[key])
	return best if not best.is_empty() else "-"


func _print_report(matrix: Dictionary) -> void:
	var header := "%-18s" % "BOSS"
	for mult in GEAR_SWEEP:
		header += " %7s" % ("x%.2f" % mult)
	print(header + "   top wipe reason (at x1.00)")
	for boss in matrix:
		var line := "%-18s" % boss
		var at_par_reason := "-"
		for cell: Dictionary in matrix[boss]:
			line += " %6.0f%%" % (float(cell["win_rate"]) * 100.0)
			if is_equal_approx(float(cell["mult"]), 1.0):
				at_par_reason = str(cell["top_reason"])
		print(line + "   " + at_par_reason)


func _assert_band(matrix: Dictionary, encounters: Array, lo: float, hi: float) -> void:
	var first_boss := str(encounters[0]["slug"])
	var first_cells: Array = matrix[first_boss]

	# 1. REACHABLE: some gear step lands in the band on boss 1
	var reachable := false
	for cell: Dictionary in first_cells:
		if float(cell["win_rate"]) >= lo and float(cell["win_rate"]) <= hi:
			reachable = true
	if reachable:
		print("  ok: win-rate band [%.2f, %.2f] reachable on %s" % [lo, hi, first_boss])
	else:
		_failures.append("no gear step lands in [%.2f, %.2f] on %s" % [lo, hi, first_boss])

	# 2. MONOTONE(gear) per boss, with sampling slack
	for boss in matrix:
		var previous := -1.0
		for cell: Dictionary in matrix[boss]:
			var rate := float(cell["win_rate"])
			if rate < previous - MONOTONE_SLACK:
				_failures.append(
					(
						"%s: win rate fell from %.2f to %.2f at x%.2f — gearing up must help"
						% [boss, previous, rate, float(cell["mult"])]
					)
				)
			previous = maxf(previous, rate)
	if _failures.is_empty():
		print("  ok: win rates monotone in gear (slack %.2f)" % MONOTONE_SLACK)

	# 3. SPREAD on boss 1: decisive lows, saturated highs
	var lowest := float(first_cells[0]["win_rate"])
	var highest := float(first_cells[first_cells.size() - 1]["win_rate"])
	if lowest <= 0.25:
		print("  ok: undergeared is decisive (%.0f%% at x%.2f)" % [lowest * 100, GEAR_SWEEP[0]])
	else:
		_failures.append("undergeared should wipe: %.2f at x%.2f" % [lowest, GEAR_SWEEP[0]])
	if highest >= 0.9:
		print(
			(
				"  ok: overgeared saturates (%.0f%% at x%.2f)"
				% [highest * 100, GEAR_SWEEP[GEAR_SWEEP.size() - 1]]
			)
		)
	else:
		_failures.append(
			(
				"overgeared should one-shot: %.2f at x%.2f"
				% [highest, GEAR_SWEEP[GEAR_SWEEP.size() - 1]]
			)
		)


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
			"--assert-winrate":
				out["assert_lo"] = float(args[i + 1])
				out["assert_hi"] = float(args[i + 2])
				i += 3
			"--csv":
				out["csv"] = args[i + 1]
				i += 2
			_:
				i += 1
	return out
