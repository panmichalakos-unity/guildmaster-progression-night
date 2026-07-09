class_name Tuning
extends RefCounted

## Shared loader for data/seeds/tuning.json (the balance-lab constants seed).
## Pure and cached per process; every value in that file is symbolic —
## the M3-005 harness and playtests tune them. See ADR-0011.

const TUNING_PATH := "res://data/seeds/tuning.json"

static var _cache: Dictionary = {}


## The whole tuning dictionary (cached after first read).
static func data() -> Dictionary:
	if _cache.is_empty():
		var file := FileAccess.open(TUNING_PATH, FileAccess.READ)
		if file == null:
			push_error("Tuning: cannot read %s" % TUNING_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_cache = parsed
		else:
			push_error("Tuning: %s is not valid JSON" % TUNING_PATH)
	return _cache


## One namespaced section, e.g. Tuning.section("roster"). Empty dict if absent.
static func section(name: String) -> Dictionary:
	var value: Variant = data().get(name, {})
	return value if value is Dictionary else {}
