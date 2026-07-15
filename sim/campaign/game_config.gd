class_name GameConfig
extends RefCounted

## GAME_CONFIG — the campaign's settings on the save root (M5-001).
##
## Difficulty, the sacking toggle, and the INVOLVEMENT contract (MI-007/ADR-0033):
## one `involvement_default` preset plus six per-domain overrides. The three genesis
## presets — Full Control / Guided / Hands-Off — are UI sugar that write one value
## into all six; per-domain overrides let a Guildmaster run raid nights by hand while
## auto-resolving recruitment. "Custom" is a DERIVED label the UI shows when the six
## disagree — never stored (same rule as archetype).
##
## Loot culture is NOT here — it is guild culture (GUILD_CONFIG.active_loot_system),
## because it survives with the guild, not the manager's preferences.

const MODES := ["manual", "assisted", "instant"]
const DOMAINS := ["lineup", "assignments", "pulls", "loot", "weekly", "recruitment"]

const DEFAULTS := {
	"difficulty": "standard",
	"involvement_default": "manual",
	"sack_risk_enabled": true,
}


## Writes the single GAME_CONFIG row for the campaign. `config` may override any of
## `difficulty`, `involvement_default`, `sack_risk_enabled`; the six per-domain
## involvement columns are all seeded from the chosen `involvement_default` (the
## preset), which is exactly what selecting a preset at genesis does. Returns true
## on success.
static func create(db: Variant, config: Dictionary = {}) -> bool:
	var difficulty := str(config.get("difficulty", DEFAULTS["difficulty"]))
	var involvement := str(config.get("involvement_default", DEFAULTS["involvement_default"]))
	if involvement not in MODES:
		push_error("GameConfig: unknown involvement_default '%s'" % involvement)
		return false
	var sack_risk := (
		1 if bool(config.get("sack_risk_enabled", DEFAULTS["sack_risk_enabled"])) else 0
	)

	return (
		db
		. query_with_bindings(
			(
				"INSERT INTO game_config (game_id, difficulty, involvement_default,"
				+ " sack_risk_enabled, involvement_lineup, involvement_assignments,"
				+ " involvement_pulls, involvement_loot, involvement_weekly,"
				+ " involvement_recruitment)"
				+ " VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?);"
			),
			[
				difficulty,
				involvement,
				sack_risk,
				involvement,  # every domain starts on the preset — the presets ARE this
				involvement,
				involvement,
				involvement,
				involvement,
				involvement,
			]
		)
	)


## Reads the config row back as a plain dictionary (all columns), or {} if absent.
static func read(db: Variant) -> Dictionary:
	db.query("SELECT * FROM game_config WHERE game_id = 1;")
	return {} if db.query_result.is_empty() else db.query_result[0].duplicate()


## The involvement mode in effect for one domain (MI-007). The per-domain column is
## authoritative; the preset is only its genesis seed.
static func involvement_for(db: Variant, domain: String) -> String:
	assert(domain in DOMAINS, "unknown involvement domain '%s'" % domain)
	var row := read(db)
	return str(row.get("involvement_%s" % domain, DEFAULTS["involvement_default"]))
