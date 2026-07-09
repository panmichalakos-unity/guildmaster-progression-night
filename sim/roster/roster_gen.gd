class_name RosterGen
extends RefCounted

## PLAYER roster generation (M2-002). Pure: (presets, count, rng) -> players.
##
## Anti-grey-goo design (ADR-0013): traits are NOT independent dice. Each
## person is derived from four latent factors plus bounded noise:
##   * talent      — stratified into star/core/fringe tiers (tuning.json
##                   `roster` block) so EVERY roster has texture: a couple of
##                   aces, a solid middle, some projects.
##   * steadiness  — calm reliability; drives consistency/loyalty/coachability
##                   up, volatility/ego down.
##   * drive       — hunger; drives growth/influence/ego up, burns hotter.
##   * experience  — from the life preset (young_gun greener than veteran):
##                   raises current skill realization + influence + loyalty,
##                   lowers potential headroom, growth and coachability.
## Life presets also stamp availability windows and the volatility/burnout/
## loyalty modifiers (life_situation seed rows).
##
## PLAYER vs AVATAR boundary is strict: nothing class/spec/gear-shaped here
## (M2-003). Volatile state (morale/fatigue/form -> player_week_state) is not
## generated here either — snapshots begin with the campaign (M5).
##
## Derivation coefficients below are generator SHAPE (sim logic), symbolic
## like all tuning; distribution parameters live in tuning.json `roster`.

const _CLAMP_LO := 5
const _CLAMP_HI := 95


## Pure generation. `presets` = life_situation rows (each needs slug,
## life_situation_id, availability_window, volatility_mod, burnout_mod,
## loyalty_mod). Returns an Array of player Dictionaries keyed by the
## `player` table's column names (minus player_id).
static func generate(presets: Array, count: int, rng: RngStream) -> Array[Dictionary]:
	assert(not presets.is_empty(), "life presets required (seed life_situation.csv)")
	var tuning := Tuning.section("roster")
	var talent_tiers := _talent_tiers(count, tuning, rng.substream("tiers"))
	var trait_rng := rng.substream("traits")
	var name_rng := rng.substream("names")
	var preset_rng := rng.substream("presets")
	var taken_names := {}
	var players: Array[Dictionary] = []
	for i in count:
		var preset: Dictionary = _pick_preset(presets, tuning, preset_rng)
		players.append(
			_generate_player(
				float(talent_tiers[i]), preset, tuning, trait_rng, name_rng, taken_names
			)
		)
	return players


## Convenience: read presets from a migrated+seeded DB, then generate.
static func generate_from_db(db: Variant, count: int, rng: RngStream) -> Array[Dictionary]:
	db.query("SELECT * FROM life_situation;")
	var presets: Array = db.query_result.duplicate()
	return generate(presets, count, rng)


## Persists generated players. Returns the new player_ids (insert order).
static func persist(db: Variant, players: Array[Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	db.query("BEGIN TRANSACTION;")
	for player in players:
		var columns := player.keys()
		var placeholders := []
		var values := []
		for column in columns:
			placeholders.append("?")
			values.append(player[column])
		var sql := (
			"INSERT INTO player (%s) VALUES (%s);" % [", ".join(columns), ", ".join(placeholders)]
		)
		if not db.query_with_bindings(sql, values):
			push_error("RosterGen: persist failed: %s" % db.error_message)
			db.query("ROLLBACK;")
			return []
		db.query("SELECT last_insert_rowid() AS id;")
		ids.append(int(db.query_result[0]["id"]))
	db.query("COMMIT;")
	return ids


## Stratified talent values for `count` players, shuffled deterministically
## so roster order never sorts by quality.
static func _talent_tiers(count: int, tuning: Dictionary, rng: RngStream) -> Array[float]:
	var stars := maxi(1, roundi(count * float(tuning.get("stars_share", 0.15))))
	var fringe := maxi(1, roundi(count * float(tuning.get("fringe_share", 0.25))))
	var core := maxi(0, count - stars - fringe)
	var talents: Array[float] = []
	for params_count in [
		[tuning.get("talent_star", [75, 8]), stars],
		[tuning.get("talent_core", [52, 12]), core],
		[tuning.get("talent_fringe", [38, 10]), fringe],
	]:
		var params: Array = params_count[0]
		for _i in int(params_count[1]):
			talents.append(rng.randfn(float(params[0]), float(params[1])))
	rng.shuffle(talents)
	return talents


static func _pick_preset(presets: Array, tuning: Dictionary, rng: RngStream) -> Dictionary:
	var weights_by_slug: Dictionary = tuning.get("preset_weights", {})
	var weights := []
	for preset in presets:
		weights.append(float(weights_by_slug.get(str(preset["slug"]), 10)))
	return rng.weighted_pick(presets, weights)


static func _generate_player(
	talent: float,
	preset: Dictionary,
	tuning: Dictionary,
	rng: RngStream,
	name_rng: RngStream,
	taken_names: Dictionary
) -> Dictionary:
	var steadiness := rng.randfn(50.0, 15.0)
	var drive := rng.randfn(50.0, 15.0)
	var experience_map: Dictionary = tuning.get("experience_by_preset", {})
	var experience := clampf(
		float(experience_map.get(str(preset["slug"]), 50)) + rng.randfn(0.0, 10.0), 5.0, 95.0
	)
	var xp := experience / 100.0  # 0..1 seasoning factor
	var window := str(preset["availability_window"])
	var slots := window.split(",", false).size()
	var loyalty_baseline := _trait(
		steadiness * 0.5 + xp * 18.0 + float(preset["loyalty_mod"]) + rng.randfn(8.0, 8.0)
	)

	return {
		"handle": NameGen.generate(name_rng, taken_names),
		"life_situation_id": int(preset["life_situation_id"]),
		# skill facets: current ability realizes talent more with seasoning
		"execution": _trait(talent * (0.55 + 0.45 * xp) + rng.randfn(6.0, 7.0)),
		"awareness":
		_trait(talent * 0.5 * (0.6 + 0.4 * xp) + steadiness * 0.25 + rng.randfn(8.0, 7.0)),
		"consistency": _trait(steadiness * 0.6 + talent * 0.15 + xp * 12.0 + rng.randfn(5.0, 6.0)),
		# headroom: the young keep theirs, veterans have spent it
		"potential": _trait(talent * 0.8 + (1.0 - xp) * 28.0 + rng.randfn(0.0, 6.0)),
		"growth_rate": _trait(70.0 - experience * 0.45 + drive * 0.25 + rng.randfn(0.0, 7.0)),
		# psychology
		"ego": _trait(drive * 0.55 - steadiness * 0.25 + talent * 0.2 + rng.randfn(15.0, 9.0)),
		"loyalty_baseline": loyalty_baseline,
		"loyalty_current": loyalty_baseline,  # starts AT the anchor (conventions Shape A)
		"volatility":
		_trait(55.0 - steadiness * 0.45 + float(preset["volatility_mod"]) + rng.randfn(10.0, 8.0)),
		"coachability": _trait(steadiness * 0.35 + (1.0 - xp) * 32.0 + rng.randfn(12.0, 8.0)),
		"influence": _trait(drive * 0.4 + xp * 26.0 + talent * 0.1 + rng.randfn(5.0, 8.0)),
		# real-life knobs
		"time_budget_hrs": clampi(roundi(slots * 4.0 + rng.randfn(0.0, 2.0)), 4, 16),
		"schedule_volatility":
		_trait(45.0 + float(preset["volatility_mod"]) * 1.4 + rng.randfn(0.0, 8.0)),
		"burnout_sensitivity":
		_trait(42.0 + float(preset["burnout_mod"]) * 1.3 + drive * 0.18 + rng.randfn(0.0, 8.0)),
		"attendance_reliability":
		_trait(
			steadiness * 0.4 + 28.0 - float(preset["volatility_mod"]) * 0.9 + rng.randfn(8.0, 7.0)
		),
	}


static func _trait(value: float) -> int:
	return clampi(roundi(value), _CLAMP_LO, _CLAMP_HI)
