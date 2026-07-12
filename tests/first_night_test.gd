extends GdUnitTestSuite

## MI-003 — the Night One contract. This suite guards the fun gate: the first
## session must hand the player a losing lineup, TELL them why, and reward the one
## legible fix with a kill in a handful of pulls. If any assertion here fails, the
## game's opening no longer teaches — that is a release blocker, not a tuning nit.
##
## See docs/guildmaster-first-session.md.

const BOSS := "gatewarden_krogg"
const PULLS := 120
## A guild that has not fixed its tank should be walled, not merely unlucky.
const MAX_UNFIXED_WIN_RATE := 8.0
## After the fix: the progression band — earned, but not a grind (contracts doc).
const MIN_PULLS_TO_KILL := 2.0
const MAX_PULLS_TO_KILL := 9.0
## Seeds are guilds. The arc must hold for every guild, not just the demo's.
const GUILD_SEEDS: Array[int] = [133742, 1, 42, 777, 90210, 2024, 55, 8, 314, 2718]


func test_default_lineup_fields_a_crittable_main_tank() -> void:
	for guild_seed in GUILD_SEEDS:
		var campaign := DemoCampaign.build(guild_seed)
		assert_dict(campaign).is_not_empty()
		var main_tank := _main_tank(campaign, PullInputLoader.auto_lineup(campaign["db"]))

		# the flaw is present, and it is the tank the scenario authored
		assert_int(int(main_tank["avatar_id"])).is_equal(int(campaign["scenario"]["incumbent_id"]))
		assert_int(int(main_tank["uncrittable"])).is_equal(0)
		_close(campaign)


func test_prep_warns_before_the_player_pulls() -> void:
	for guild_seed in GUILD_SEEDS:
		var campaign := DemoCampaign.build(guild_seed)
		var prep := RaidPrep.build(
			campaign["db"], int(campaign["event_id"]), PullInputLoader.auto_lineup(campaign["db"])
		)
		# match the STRUCTURED term, not the prose: MI-008 rewrote this warning into
		# plain language, and a test that sniffs for the jargon would have blocked
		# the very fix that makes the sentence readable.
		var warned := false
		for warning: Dictionary in prep["warnings"]:
			if str(warning.get("term", "")) == "uncrittable":
				warned = true
		(
			assert_bool(warned)
			. override_failure_message(
				"seed %d: prep does not warn about the crittable main tank" % guild_seed
			)
			. is_true()
		)
		_close(campaign)


func test_unfixed_lineup_is_a_wall_that_names_the_tank() -> void:
	for guild_seed in GUILD_SEEDS:
		var campaign := DemoCampaign.build(guild_seed)
		var measured := _measure(campaign["db"], PullInputLoader.auto_lineup(campaign["db"]))

		(
			assert_float(measured["win_rate"])
			. override_failure_message(
				(
					"seed %d: unfixed wins %.1f%% — it must be a wall"
					% [guild_seed, measured["win_rate"]]
				)
			)
			. is_less_equal(MAX_UNFIXED_WIN_RATE)
		)
		# legible failure: the wipe blames the tank, not the dice
		assert_str(str(measured["top_reason"])).is_equal("tank_survival")
		_close(campaign)


func test_benching_the_star_tank_promotes_a_crit_immune_one() -> void:
	for guild_seed in GUILD_SEEDS:
		var campaign := DemoCampaign.build(guild_seed)
		var main_tank := _main_tank(campaign, _fixed_lineup(campaign))
		(
			assert_int(int(main_tank["uncrittable"]))
			. override_failure_message(
				"seed %d: the fix does not promote a crit-immune tank" % guild_seed
			)
			. is_equal(1)
		)
		_close(campaign)


func test_the_one_fix_turns_the_wall_into_a_kill() -> void:
	for guild_seed in GUILD_SEEDS:
		var campaign := DemoCampaign.build(guild_seed)
		var measured := _measure(campaign["db"], _fixed_lineup(campaign))
		var pulls_to_kill := (
			999.0 if measured["win_rate"] < 1.0 else 100.0 / float(measured["win_rate"])
		)
		(
			assert_float(pulls_to_kill)
			. override_failure_message(
				(
					"seed %d: after the fix the kill takes ~%.1f pulls (want %.0f-%.0f)"
					% [guild_seed, pulls_to_kill, MIN_PULLS_TO_KILL, MAX_PULLS_TO_KILL]
				)
			)
			. is_between(MIN_PULLS_TO_KILL, MAX_PULLS_TO_KILL)
		)
		_close(campaign)


func test_night_one_is_deterministic() -> void:
	var first := DemoCampaign.build(133742)
	var second := DemoCampaign.build(133742)
	assert_dict(first["scenario"]).is_equal(second["scenario"])
	assert_array(PullInputLoader.auto_lineup(first["db"])).is_equal(
		PullInputLoader.auto_lineup(second["db"])
	)
	assert_float(_measure(first["db"], _fixed_lineup(first))["win_rate"]).is_equal(
		_measure(second["db"], _fixed_lineup(second))["win_rate"]
	)
	_close(first)
	_close(second)


# --- helpers ------------------------------------------------------------------


## The fix a player performs in the prep screen: bench the star tank, then fill
## the slot from the bench with the best tank left.
func _fixed_lineup(campaign: Dictionary) -> Array[int]:
	var db: Variant = campaign["db"]
	var incumbent_id := int(campaign["scenario"]["incumbent_id"])
	var fixed := RaidPrep.toggle(PullInputLoader.auto_lineup(db), incumbent_id)
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
func _main_tank(campaign: Dictionary, lineup: Array[int]) -> Dictionary:
	var prep := RaidPrep.build(campaign["db"], int(campaign["event_id"]), lineup)
	var best := {}
	for row: Dictionary in prep["lineup"]:
		if str(row["role_slug"]) != "tank":
			continue
		if best.is_empty() or int(row["gear_score"]) > int(best["gear_score"]):
			best = row
	return best


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


func _close(campaign: Dictionary) -> void:
	campaign["db"].close_db()
