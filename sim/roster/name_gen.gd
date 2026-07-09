class_name NameGen
extends RefCounted

## Raider handle generator (M2-002) — the naming bible's three weighted pools:
##   1. fantasy root+suffix (~55%)  -> Kaeldar, Brynwyn, Vexis
##   2. compound handles   (~30%)  -> Ironfang, Nightmend
##   3. "human leak"       (~15%)  -> brynna, Vexxen, Kaeldar77
## v1: handle = avatar name (one identity per raider). Collisions get a
## deterministic digit suffix. Pools are the bible's canonical alphabets.

const ROOTS: Array[String] = [
	"Ash", "Bryn", "Fen", "Kael", "Mor", "Sable", "Thorn", "Vex", "Grim", "Ryn"
]
const SUFFIXES: Array[String] = ["en", "ric", "wyn", "dar", "is", "eth", "na", "mir"]
const COMPOUND_HEADS: Array[String] = ["Shadow", "Iron", "Swift", "Grim", "Night", "Frost", "Storm"]
const COMPOUND_TAILS: Array[String] = ["blade", "fang", "mend", "arrow", "hide", "whisper", "born"]
const POOL_WEIGHTS := [55, 30, 15]  # root+suffix / compound / human leak


## One raider handle, unique against `taken` (case-insensitive).
static func generate(rng: RngStream, taken: Dictionary = {}) -> String:
	var handle := _raw_handle(rng)
	while taken.has(handle.to_lower()):
		handle = "%s%d" % [handle, rng.randi_range(2, 99)]
	taken[handle.to_lower()] = true
	return handle


static func _raw_handle(rng: RngStream) -> String:
	match rng.weighted_pick([0, 1, 2], POOL_WEIGHTS):
		0:
			return _root_suffix(rng)
		1:
			return _compound(rng)
		_:
			return _human_leak(rng)


static func _root_suffix(rng: RngStream) -> String:
	return "%s%s" % [rng.pick(ROOTS), rng.pick(SUFFIXES)]


static func _compound(rng: RngStream) -> String:
	return "%s%s" % [rng.pick(COMPOUND_HEADS), rng.pick(COMPOUND_TAILS)]


static func _human_leak(rng: RngStream) -> String:
	var base := _root_suffix(rng) if rng.randf() < 0.7 else _compound(rng)
	match rng.randi_range(0, 2):
		0:  # lowercase
			return base.to_lower()
		1:  # double a letter
			var i := rng.randi_range(1, base.length() - 1)
			return base.substr(0, i) + base[i] + base.substr(i)
		_:  # trailing digits
			return "%s%d" % [base, rng.randi_range(10, 99)]
