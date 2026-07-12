extends GdUnitTestSuite

## MI-008 — the dual-language contract, enforced.
##
## A copy pass rots the moment somebody adds the next warning. These tests make the
## rule mechanical: a player who has never raided must be able to ACT on every
## warning without a glossary, and any MMO term the UI says must be one somebody
## has actually explained.
##
## See docs/guildmaster-terminology.md.

## Jargon a non-raider cannot be expected to parse. Using these is FINE — the game
## is an MMO management sim and the authenticity is the point — but never NAKED:
## the consequence and the fix must be in plain language first.
const JARGON: Array[String] = [
	"uncrittable",
	"crit-immune",
	"battle-rez",
	"rez",
	"dps",
	"hps",
	"enrage",
	"soak",
	"dispel",
	"interrupt",
	"haste burst",
	"comp",
	"spike-death",
	"add",
	"cc",
	"aggro",
	"threat",
	"proc",
	"bis",
]

## A warning that does not tell you what to DO is an observation, not a warning.
const ACTION_VERBS: Array[String] = [
	"field",
	"swap",
	"bring",
	"bench",
	"assign",
	"reassign",
	"spend",
	"upgrade",
	"cut",
	"check",
	"put",
	"reduce",
	"add",
]


func _prep(fix_the_tank: bool = false) -> Dictionary:
	var campaign := DemoCampaign.build(133742)
	var db: Variant = campaign["db"]
	var lineup := PullInputLoader.auto_lineup(db)
	if fix_the_tank:
		lineup = RaidPrep.toggle(lineup, int(campaign["scenario"]["incumbent_id"]))
	var report := RaidPrep.build(db, int(campaign["event_id"]), lineup)
	db.close_db()
	return report


# --- the glossary --------------------------------------------------------------


func test_the_glossary_loads_and_defines_the_load_bearing_terms() -> void:
	assert_dict(Glossary.terms()).is_not_empty()
	# the term the entire first session hangs on
	var uncrittable := Glossary.entry("uncrittable")
	assert_dict(uncrittable).is_not_empty()
	assert_str(str(uncrittable["plain"])).is_equal("cannot be critically hit")
	assert_str(str(uncrittable["detail"])).is_not_empty()


func test_every_glossary_entry_is_complete() -> void:
	for key: String in Glossary.terms():
		var entry := Glossary.entry(key)
		for field in ["term", "plain", "detail"]:
			(
				assert_str(str(entry.get(field, "")))
				. override_failure_message("glossary term '%s' has no '%s'" % [key, field])
				. is_not_empty()
			)
		# the plain phrase must not itself be jargon — that explains nothing
		(
			assert_str(str(entry["plain"]).to_lower())
			. override_failure_message("glossary term '%s' is 'explained' with more jargon" % key)
			. not_contains(key.to_lower())
		)


# --- the warnings --------------------------------------------------------------


## THE RULE. Every warning must be actionable by somebody who has never raided.
func test_every_warning_tells_the_player_what_to_do() -> void:
	for warning: Dictionary in _all_warnings():
		if str(warning["severity"]) == "ok":
			continue
		var text := str(warning["text"]).to_lower()
		var acted := false
		for verb in ACTION_VERBS:
			if text.contains(verb):
				acted = true
		(
			assert_bool(acted)
			. override_failure_message(
				(
					"this warning says what is wrong but not what to DO about it:\n    %s"
					% warning["text"]
				)
			)
			. is_true()
		)


## Jargon may appear — but never before the plain-language meaning, and never as
## the only way to understand the sentence. In practice: the term is parenthesised.
func test_no_warning_leads_with_jargon() -> void:
	for warning: Dictionary in _all_warnings():
		var text := str(warning["text"])
		for term in JARGON:
			var index := text.to_lower().find(term)
			if index < 0:
				continue
			# the term must be introduced in parentheses, after the plain meaning
			var before := text.substr(0, index)
			(
				assert_bool(before.contains("("))
				. override_failure_message(
					(
						(
							"'%s' appears NAKED (not parenthesised after a plain-language"
							+ " explanation) in:\n    %s"
						)
						% [term, text]
					)
				)
				. is_true()
			)


## A term the UI says that nobody has defined is a term the player cannot look up.
func test_every_term_a_warning_tags_is_in_the_glossary() -> void:
	var tagged := 0
	for warning: Dictionary in _all_warnings():
		var term := str(warning.get("term", ""))
		if term.is_empty():
			continue
		tagged += 1
		(
			assert_bool(Glossary.has_term(term))
			. override_failure_message(
				"warning tags term '%s', which the glossary does not define" % term
			)
			. is_true()
		)
	(
		assert_int(tagged)
		. override_failure_message(
			"no warning carries a glossary term — the tooltips have nothing to show"
		)
		. is_greater(0)
	)


## The first session's whole arc rides on this one sentence landing. It must name
## the consequence, name the fix, and say the counter-intuitive part out loud.
func test_the_tank_warning_is_readable_by_someone_who_has_never_raided() -> void:
	var found := {}
	for warning: Dictionary in _prep()["warnings"]:
		if str(warning.get("term", "")) == "uncrittable":
			found = warning
	(
		assert_dict(found)
		. override_failure_message("the crit-immunity warning did not fire")
		. is_not_empty()
	)

	var text := str(found["text"])
	# the consequence, in words anybody understands
	assert_str(text).contains("critical")
	assert_str(text.to_lower()).contains("kill him outright")
	# the fix — including the part that feels wrong: field the WORSE-geared tank
	assert_str(text.to_lower()).contains("field a tank")
	assert_str(text.to_lower()).contains("gear score is lower")
	# and the term survives, for the veteran, in parentheses
	assert_str(text).contains("(uncrittable)")


func _all_warnings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_prep()["warnings"])
	out.append_array(_prep(true)["warnings"])
	assert_int(out.size()).is_greater(0)
	return out
