class_name Glossary
extends RefCounted

## MI-008 — the dual-language contract, in one place.
##
## The UI speaks fluent MMO: uncrittable, battle-rez, interrupt, soak, enrage.
## That is efficient for a veteran and completely opaque to the management-sim
## half of the audience — and it is not a cosmetic problem. The single string the
## entire first session hangs on used to read:
##
##     "Main tank Shadowwhisper is not uncrittable — spike-death risk"
##
## Two terms a non-raider cannot parse, no consequence, and no action. If that
## sentence does not land, MI-003's whole diagnose -> fix -> succeed arc collapses
## for exactly the player this game is supposed to reach.
##
## THE RULE (docs/guildmaster-terminology.md):
##   1. plain-language CONSEQUENCE first
##   2. the ACTION the player can take
##   3. the MMO term LAST, in parentheses — kept, never removed
##
## Terms stay because the authenticity is the point. They are simply never
## LOAD-BEARING: a player who ignores every parenthesis must still be able to act.
## Depth stays available for the veteran (tooltips, the glossary screen) and is
## never required for basic play — progressive disclosure, not dumbing down.
##
## Definitions live in data/seeds/glossary.json (content as data, same pattern as
## tuning.json). Pure and cached; no DB, no scene tree.

const GLOSSARY_PATH := "res://data/seeds/glossary.json"

static var _cache: Dictionary = {}


## Every term, keyed by its lowercase lookup key.
static func terms() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open(GLOSSARY_PATH, FileAccess.READ)
		if file == null:
			push_error("Glossary: cannot read %s" % GLOSSARY_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and parsed.has("terms"):
			_cache = parsed["terms"]
		else:
			push_error("Glossary: %s is not valid JSON with a 'terms' object" % GLOSSARY_PATH)
	return _cache


## {term, plain, detail} for `key`, or {} if the term is not defined. A term the
## UI uses without an entry here is a term nobody has explained — the tests treat
## that as a failure, not an oversight.
static func entry(key: String) -> Dictionary:
	var found: Variant = terms().get(key.to_lower(), {})
	return found if found is Dictionary else {}


## The plain-language phrase that stands in for a term in body copy.
static func plain(key: String) -> String:
	return str(entry(key).get("plain", key))


## The long explanation — for a tooltip or the glossary screen. Never required
## reading; the warning itself must already be actionable without it.
static func detail(key: String) -> String:
	return str(entry(key).get("detail", ""))


static func has_term(key: String) -> bool:
	return not entry(key).is_empty()
