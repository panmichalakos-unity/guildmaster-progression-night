class_name DemoCampaign
extends RefCounted

## Slice entry point (M4-001), now a THIN SHIM over real guild genesis (M5-001).
##
## Everything this used to do — migrate, seed, roster, avatars, the Night One tank
## curation, guild, calendar event — moved into `Genesis` / `FirstSession`, so the
## first-session logic lives in exactly one place and the slice UI exercises the
## real new-game path. This keeps `DemoCampaign.build(seed)` working for the M4 app
## shell and the existing smokes/tests; the handle Genesis returns is a superset of
## the old one.
##
## Prefer calling `Genesis.new_in_memory(...)` directly in new code.

const DEMO_GUILD_NAME := Genesis.DEFAULT_GUILD_NAME


## Builds a playable campaign for `seed_value` and returns the campaign handle
## ({db, seed, guild_id, event_id, guild_name, scenario, ...}), or {} on failure.
## The caller owns closing `handle.db`.
static func build(seed_value: int) -> Dictionary:
	return Genesis.new_in_memory({"guild_name": DEMO_GUILD_NAME, "seed": seed_value})
