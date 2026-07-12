extends GdUnitTestSuite

## MI-006 — the performance-rating contract, locked before ratings become loot
## EVIDENCE in M6's Council.
##
## THE GOVERNING PRINCIPLE: a rating measures how well a raider fulfilled their role
## and their assignments RELATIVE TO THE KIT AND GEAR AVAILABLE TO THEM — never raw
## output. If a rating just re-reported gear score, loot would become a feedback loop
## that eats itself: the best-geared raider "earns" the loot that keeps him best-geared.
##
## The five scenarios below are the ones the ticket names. They are the contract.
##
## See docs/guildmaster-rating.md.

const TUNING := {"rating_spread": 12.0, "reference_realization": 0.65}


## A participant + their contribution entry, dialled to a chosen ratio of what
## their gear SHOULD produce. `ceiling` is the gear; `realized` is what they did
## with it, as a multiple of the reference (0.65 of ceiling = a plain 50-skill).
func _raider(avatar_id: int, role: String, ceiling: float, realized: float) -> Dictionary:
	return {
		"participant": {"avatar_id": avatar_id, "player_id": avatar_id, "role_slug": role},
		"contribution":
		{
			"avatar_id": avatar_id,
			"role_slug": role,
			"ceiling": ceiling,
			"contribution": ceiling * 0.65 * realized,
		},
	}


func _event(target: int, outcome: String) -> Dictionary:
	return {"target_avatar_id": target, "outcome": outcome, "log_line": "-"}


func _rate(raiders: Array, events: Array, dead: Array = []) -> Array[Dictionary]:
	var participants: Array = []
	var contributions: Array = []
	for r: Dictionary in raiders:
		participants.append(r["participant"])
		contributions.append(r["contribution"])
	var dead_set := {}
	for avatar_id in dead:
		dead_set[int(avatar_id)] = true
	return RatingEngine.rate(participants, contributions, events, dead_set, TUNING)


func _rating(rows: Array, avatar_id: int) -> int:
	for row: Dictionary in rows:
		if int(row["avatar_id"]) == avatar_id:
			return int(row["performance_rating"])
	fail("no rating for avatar %d" % avatar_id)
	return 0


## Lowercased: the summary is sentence-cased for display, and these assertions are
## about CONTENT, not capitalisation.
func _summary(rows: Array, avatar_id: int) -> String:
	for row: Dictionary in rows:
		if int(row["avatar_id"]) == avatar_id:
			return str(row["rating_summary"]).to_lower()
	return ""


# --- the five validation scenarios (from the ticket) ---------------------------


## 1. A highly geared tank who simply meets expectations → a middling ~6.
##    Big gear is not an achievement. Using it is.
func test_a_well_geared_tank_who_meets_expectations_is_average() -> void:
	var rows := _rate([_raider(1, "tank", 200.0, 1.0)], [])
	assert_int(_rating(rows, 1)).is_between(5, 7)
	assert_str(_summary(rows, 1)).contains("about what their gear should produce")


## 2. An UNDERGEARED healer who lands two clutch saves → 8-9.
##    The whole point: you can be poor and brilliant, and the number says so.
func test_an_undergeared_healer_with_two_clutch_saves_rates_highly() -> void:
	# poor kit, ORDINARY output for it — the two saves are what he is being rated on
	var rows := _rate(
		[_raider(2, "healer", 60.0, 1.0)],
		[_event(2, Timeline.OUTCOME_SAVE), _event(2, Timeline.OUTCOME_SAVE)]
	)
	(
		assert_int(_rating(rows, 2))
		. override_failure_message(
			"an undergeared healer who saved two lives must be able to top the table"
		)
		. is_between(8, 9)
	)
	assert_str(_summary(rows, 2)).contains("clutch save")


## 3. A highly geared DPS who dies early to avoidable damage → 2-4.
##    Raw output cannot buy your way out of standing in the fire.
func test_a_geared_dps_who_dies_to_avoidable_damage_rates_badly() -> void:
	var rows := _rate([_raider(3, "melee", 200.0, 0.85)], [_event(3, Timeline.OUTCOME_DEATH)], [3])
	assert_int(_rating(rows, 3)).is_between(2, 4)
	assert_str(_summary(rows, 3)).contains("died to damage they could have avoided")


## 4. A mid-geared DPS performing strongly who lands a critical interrupt → 8-9.
func test_a_mid_geared_dps_who_nails_their_duty_rates_highly() -> void:
	var rows := _rate(
		[_raider(4, "ranged", 120.0, 1.2)],
		[_event(4, Timeline.OUTCOME_DUTY_OK), _event(4, Timeline.OUTCOME_SURGE)]
	)
	assert_int(_rating(rows, 4)).is_between(8, 9)
	assert_str(_summary(rows, 4)).contains("assigned job")


## 5. A LOW-OUTPUT raider who completes a uniquely hard assignment — their
##    assignment contribution must be VISIBLE, not buried under the output score.
func test_a_low_output_raider_gets_credit_for_the_job_they_did() -> void:
	var rows := _rate([_raider(5, "melee", 100.0, 0.8)], [_event(5, Timeline.OUTCOME_DUTY_OK)])
	var summary := _summary(rows, 5)
	assert_str(summary).contains("below what their gear should produce")
	(
		assert_str(summary)
		. override_failure_message(
			"the assignment they completed is invisible — the breakdown only talks about output"
		)
		. contains("handled their assigned job cleanly")
	)
	# and it demonstrably lifted the number
	var without := _rate([_raider(5, "melee", 100.0, 0.8)], [])
	assert_float(float(_rating(rows, 5))).is_greater_equal(float(_rating(without, 5)))


# --- the three questions the ticket demands answers to -------------------------


## Q: Can an undergeared player earn a 9 by overperforming?  A: YES — by design.
func test_an_undergeared_raider_can_outrank_a_geared_one() -> void:
	var rows := _rate(
		[
			_raider(6, "melee", 60.0, 1.35),  # poor kit, playing out of his skin
			_raider(7, "melee", 220.0, 0.85),  # decked out, coasting
		],
		[]
	)
	(
		assert_int(_rating(rows, 6))
		. override_failure_message(
			"a raider in rags who outplays his gear must be able to beat a coasting BiS raider"
		)
		. is_greater(_rating(rows, 7))
	)


## Q: Can a highly geared player rate poorly despite high RAW output?  A: YES.
## Raw contribution is the highest in the raid; the rating is not.
func test_raw_output_does_not_buy_a_good_rating() -> void:
	var rows := _rate([_raider(8, "ranged", 300.0, 0.7), _raider(9, "ranged", 80.0, 1.3)], [])
	var geared := {}
	var scrappy := {}
	for row: Dictionary in rows:
		if int(row["avatar_id"]) == 8:
			geared = row
		if int(row["avatar_id"]) == 9:
			scrappy = row
	# the geared raider genuinely puts out MORE damage...
	assert_int(int(geared["raw_contribution"])).is_greater(int(scrappy["raw_contribution"]))
	# ...and still rates worse, because he is not using what he was given
	(
		assert_int(int(geared["performance_rating"]))
		. override_failure_message(
			"raw output bought a good rating — loot would become a feedback loop that eats itself"
		)
		. is_less(int(scrappy["performance_rating"]))
	)


## Q: Can a duty failure be double-counted through event + death + rating?  A: NO.
## The failure is charged ONCE, to the assignee. The raider it kills takes no rating
## hit at all — and, crucially, keeps their own contribution, so dying does not
## quietly collapse their output score on top of everything else.
func test_a_failure_is_charged_exactly_once_and_only_to_its_author() -> void:
	var assignee := _raider(10, "ranged", 120.0, 1.0)
	var victim := _raider(11, "melee", 120.0, 1.0)
	var control := _rate([assignee, victim], [])

	# the assignee drops the duty; the victim dies for it (the timeline kills the
	# victim but targets the EVENT at the assignee — Timeline._resolve_duty)
	var rows := _rate([assignee, victim], [_event(10, Timeline.OUTCOME_DUTY_FAIL)], [11])

	# the assignee pays, once: exactly the duty_fail delta
	var charged := _rating(control, 10) - _rating(rows, 10)
	(
		assert_int(charged)
		. override_failure_message(
			"the assignee was charged %d, not the single -2 for the duty they dropped" % charged
		)
		. is_equal(2)
	)

	# the victim pays NOTHING — they authored none of it
	(
		assert_int(_rating(rows, 11))
		. override_failure_message(
			"the raider who was KILLED by somebody else's mistake lost rating for it"
		)
		. is_equal(_rating(control, 11))
	)


## Dying does not secretly cost you twice. A dead raider keeps their own
## contribution — death removes them from the LANE SUMS, never from their own ratio.
func test_death_costs_the_event_delta_and_nothing_more() -> void:
	var raider := _raider(12, "melee", 150.0, 1.0)
	var alive := _rate([raider], [])
	var fallen := _rate([raider], [_event(12, Timeline.OUTCOME_DEATH)], [12])
	(
		assert_int(_rating(alive, 12) - _rating(fallen, 12))
		. override_failure_message(
			"a death cost more than its -2: the output score was collapsed as well"
		)
		. is_equal(2)
	)


# --- the breakdown -------------------------------------------------------------


## Every rating must be explicable. A number nobody can argue with is not evidence.
func test_every_rating_carries_a_breakdown() -> void:
	var rows := _rate([_raider(13, "healer", 100.0, 1.0)], [])
	for row: Dictionary in rows:
		assert_array(row["rating_factors"]).is_not_empty()
		assert_str(str(row["rating_summary"])).is_not_empty()
		# the output judgement is always there, whatever else happened
		assert_str(str(row["rating_factors"][0]["code"])).is_equal("output")


## The deaths a raider did NOT author are shown anyway — explicitly saying "not
## their fault", so a guildmaster reading a corpse beside a number does not draw
## the obvious wrong conclusion (the scapegoat trap, ADR-0028).
func test_a_blameless_death_is_shown_and_says_so() -> void:
	var rows := _rate(
		[_raider(14, "tank", 150.0, 1.0)], [_event(14, Timeline.OUTCOME_TANK_OVERWHELMED)], [14]
	)
	var summary := _summary(rows, 14)
	assert_str(summary).contains("not out-played")
	# and it cost him nothing
	var unharmed := _rate([_raider(14, "tank", 150.0, 1.0)], [])
	assert_int(_rating(rows, 14)).is_equal(_rating(unharmed, 14))
