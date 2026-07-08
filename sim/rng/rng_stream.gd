class_name RngStream
extends RefCounted

## Named, seeded random stream (M2-001) — THE one RNG pattern for sim code.
##
## Determinism contract (CLAUDE.md rule 7, stack doc):
##   * Every random draw flows from GAME_STATE.rng_seed through streams like
##     this one. No scattered randi()/randf()/RandomNumberGenerator.new().
##   * Same master seed + same stream name + same draw order = same sequence,
##     on every platform (Godot pinned at 4.7).
##   * Streams are NAMED and hierarchical so systems cannot perturb each
##     other's sequences: `RngStream.derive(seed, "roster_gen")` and
##     `derive(seed, "resolution")` are fully independent, and
##     `stream.substream("traits")` forks without advancing the parent.
##
## Stream-name -> seed derivation uses our own FNV-1a 64 (not String.hash())
## so derived seeds can never shift under an engine upgrade.
##
## Usage:
##   var rng := RngStream.derive(game_seed, "roster_gen")
##   var traits_rng := rng.substream("traits")
##   var v := traits_rng.randfn(50.0, 10.0)

const _FNV_OFFSET := -3750763034362895579  # 0xcbf29ce484222325 as signed 64-bit
const _FNV_PRIME := 1099511628211  # 0x100000001b3

var stream_path: String  # e.g. "roster_gen/traits" — for logs and repros
var draw_count: int = 0  # observability: draws made on this stream

var _rng := RandomNumberGenerator.new()
var _seed_value: int


## Root derivation from a master seed (usually GAME_STATE.rng_seed).
static func derive(master_seed: int, stream_name: String) -> RngStream:
	var stream := RngStream.new()
	stream._seed_value = _fnv1a("%d/%s" % [master_seed, stream_name])
	stream.stream_path = stream_name
	stream._rng.seed = stream._seed_value
	return stream


## Forks a child stream. Does NOT advance or disturb this stream's sequence.
func substream(name: String) -> RngStream:
	var child := RngStream.derive(_seed_value, name)
	child.stream_path = "%s/%s" % [stream_path, name]
	return child


func randi_range(from: int, to: int) -> int:
	draw_count += 1
	return _rng.randi_range(from, to)


func randf() -> float:
	draw_count += 1
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	draw_count += 1
	return _rng.randf_range(from, to)


## Gaussian draw — roster generation's correlated-trait workhorse.
func randfn(mean: float, deviation: float) -> float:
	draw_count += 1
	return _rng.randfn(mean, deviation)


## Uniform pick. Returns null on an empty array.
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[randi_range(0, items.size() - 1)]


## Weighted pick: weights align with items by index; weight <= 0 never picked.
## Returns null when items are empty or total weight is not positive.
func weighted_pick(items: Array, weights: Array) -> Variant:
	assert(items.size() == weights.size(), "items and weights must align")
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, float(weight))
	if items.is_empty() or total <= 0.0:
		return null
	var roll := randf_range(0.0, total)
	var cumulative := 0.0
	for i in items.size():
		cumulative += maxf(0.0, float(weights[i]))
		if roll <= cumulative:
			return items[i]
	return items[items.size() - 1]  # float edge: roll == total


## In-place Fisher-Yates shuffle driven by this stream.
func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := randi_range(0, i)
		var swap: Variant = items[i]
		items[i] = items[j]
		items[j] = swap


static func _fnv1a(text: String) -> int:
	var hashed := _FNV_OFFSET
	for byte in text.to_utf8_buffer():
		hashed ^= byte
		hashed *= _FNV_PRIME  # 64-bit wrap is defined behavior in GDScript
	return hashed
