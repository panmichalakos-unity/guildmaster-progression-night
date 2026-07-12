extends GdUnitTestSuite

## The "closest yet" rule — a bug found in play (2026-07-12).
##
## The combat log reports the boss's REMAINING HEALTH, which is the bar the player
## watches. The engine thinks in `progress` (100 - hp). The two run in OPPOSITE
## directions, and the card was computing progress and then printing it under a
## health label:
##
##   the raid pushes the boss down to 40% health
##   -> progress = 60
##   -> the card says "Boss to 60%"          (reads as: left it at 60%. Wrong.)
##   -> "furthest yet" reports the HIGHEST number, so a guild's BEST attempt was
##      announced with its worst-sounding figure.
##
## An attempt is CLOSER when it leaves the boss on LESS health. That is the whole
## rule, it lives in one place, and this suite exists so it cannot invert again.


func test_a_lower_boss_health_is_a_closer_attempt() -> void:
	# pushed the boss to 12% — closer than the previous best of 40%
	assert_bool(CombatLogScreen.is_closer(12, 40)).is_true()


func test_a_higher_boss_health_is_not_closer() -> void:
	# left the boss at 70% when the guild has already had it to 40%
	assert_bool(CombatLogScreen.is_closer(70, 40)).is_false()


func test_matching_the_best_is_not_closer() -> void:
	assert_bool(CombatLogScreen.is_closer(40, 40)).is_false()


## The regression, stated as the engine states it: `boss_hp_pct_at_end` is what the
## screen must compare. Feeding it `progress` (100 - hp) inverts the whole thing.
func test_progress_and_remaining_health_run_in_opposite_directions() -> void:
	var better_attempt_hp := 15  # boss almost dead   -> progress 85
	var worse_attempt_hp := 65  # boss barely dented -> progress 35

	# the truth: the attempt that left LESS health is the better one
	assert_bool(CombatLogScreen.is_closer(better_attempt_hp, worse_attempt_hp)).is_true()

	# and the bug: comparing PROGRESS with the same "lower is better" test would
	# have called the better attempt worse. This is what shipped.
	var better_as_progress := 100 - better_attempt_hp
	var worse_as_progress := 100 - worse_attempt_hp
	(
		assert_bool(CombatLogScreen.is_closer(better_as_progress, worse_as_progress))
		. override_failure_message(
			"progress and remaining health are no longer inverses — the bug's premise changed"
		)
		. is_false()
	)


## A kill leaves the boss on 0% — it is, definitionally, the closest you can get.
func test_a_kill_is_the_closest_possible_attempt() -> void:
	assert_bool(CombatLogScreen.is_closer(0, 1)).is_true()
	assert_bool(CombatLogScreen.is_closer(0, 100)).is_true()
