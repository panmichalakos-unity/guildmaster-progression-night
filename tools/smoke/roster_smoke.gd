extends SceneTree

## M2-004 roster inspection harness.
## Usage: godot --headless -s tools/smoke/roster_smoke.gd [-- --seed 12345]
##
## Builds a full campaign roster in :memory: (migrate -> seeds -> players ->
## avatars), prints the readable RosterReport, then proves cross-DB
## determinism by rebuilding the whole chain in a second fresh DB and
## comparing fingerprints. Exits 0 on PASS, 1 on FAIL.

const DEFAULT_SEED := 133742
const ROSTER_SIZE := 28

var _failures: PackedStringArray = []


func _init() -> void:
	var seed_value := _seed_from_args()
	print("== roster inspection (seed %d) ==" % seed_value)
	var first_text := _build_roster_text(seed_value)
	if first_text.is_empty():
		printerr("ROSTER SMOKE FAIL: could not build roster")
		quit(1)
		return
	print(first_text)

	# determinism: a completely fresh DB + same seed must render identically
	var second_text := _build_roster_text(seed_value)
	if first_text == second_text:
		print("  ok: rerun in a fresh DB renders identically (deterministic)")
	else:
		_failures.append("same-seed rerun produced a different roster")

	var other_text := _build_roster_text(seed_value + 1)
	if first_text != other_text:
		print("  ok: different seed produces a different roster")
	else:
		_failures.append("seed %d and %d produced identical rosters" % [seed_value, seed_value + 1])

	if _failures.is_empty():
		print("ROSTER SMOKE: PASS")
		quit(0)
	else:
		for failure in _failures:
			printerr("ROSTER SMOKE FAIL: %s" % failure)
		quit(1)


func _seed_from_args() -> int:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return DEFAULT_SEED


func _build_roster_text(seed_value: int) -> String:
	var db: Variant = Migrator.open_db(":memory:")
	if db == null or not Migrator.migrate(db).ok or not SeedLoader.load_seeds(db).ok:
		return ""
	var players := RosterGen.generate_from_db(
		db, ROSTER_SIZE, RngStream.derive(seed_value, "roster_gen")
	)
	if RosterGen.persist(db, players).is_empty():
		db.close_db()
		return ""
	if AvatarGen.generate_and_persist(db, RngStream.derive(seed_value, "avatar_gen")).is_empty():
		db.close_db()
		return ""
	var text := RosterReport.to_text(RosterReport.build(db))
	db.close_db()
	return text
