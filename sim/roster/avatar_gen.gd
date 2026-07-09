class_name AvatarGen
extends RefCounted

## AVATAR assignment for a generated roster (M2-003).
##
## Takes persisted players and assigns each one active avatar: a role (to hit
## the tuning `roster.role_targets` coverage — 20-raider lineup + bench depth
## on every axis), a spec of that role from the M1 seed rows (never hardcoded),
## starter gear across the 7 slots (template `starter_*` loot_item rows with
## per-avatar `avatar_item.item_level`), derived+cached `gear_score`, and
## `player_role_proficiency` rows (role instincts live on the PLAYER).
##
## Gear-doc contracts honored here:
##   * gear_score = SUM of equipped slot item levels — so an upgrade's power
##     delta is exactly its slot delta (M6-005 relies on this).
##   * hit_capped / uncrittable DERIVE from the equipped set. v1-start rule is
##     a placeholder threshold until M6-005 owns caps-from-gear.
##   * familiarity is an avatar accumulator (resets on re-roll): seasoned
##     players (low growth_rate) start higher on their long-played spec.

const CAP_ILVL_THRESHOLD := 20  # avg ilvl gate for starting caps (placeholder)


## Assigns avatars for `player_rows` (each: player_id, growth_rate, execution).
## Reads specs + starter items from the DB (seed rows). Pure given (db state,
## rng): same inputs -> same assignments. Returns Array of avatar Dictionaries.
static func generate(db: Variant, player_rows: Array, rng: RngStream) -> Array[Dictionary]:
	var specs_by_role := _specs_by_role(db)
	assert(not specs_by_role.is_empty(), "class/spec seeds required (M1-001)")
	var starter_items := _starter_items(db)
	assert(starter_items.size() == 7, "starter gear templates required (one per slot)")

	var all_role_ids := _all_role_ids(specs_by_role)
	var roles := _role_plan(specs_by_role.keys(), player_rows.size(), rng.substream("roles"))
	var spec_rng := rng.substream("specs")
	var gear_rng := rng.substream("gear")
	var avatars: Array[Dictionary] = []
	for i in player_rows.size():
		var player: Dictionary = player_rows[i]
		var role: Dictionary = roles[i]
		var spec: Dictionary = spec_rng.pick(specs_by_role[role["slug"]])
		avatars.append(_generate_avatar(player, role, spec, starter_items, all_role_ids, gear_rng))
	return avatars


## Distinct role ids present in the spec seeds (no hardcoded id assumptions).
static func _all_role_ids(specs_by_role: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for role_slug in specs_by_role:
		var role_id := int(specs_by_role[role_slug][0]["role_id"])
		if role_id not in ids:
			ids.append(role_id)
	ids.sort()
	return ids


## Persists avatars + their gear + role proficiencies. Returns avatar_ids.
static func persist(db: Variant, avatars: Array[Dictionary]) -> Array[int]:
	var ids: Array[int] = []
	db.query("BEGIN TRANSACTION;")
	for avatar in avatars:
		if not (
			db
			. query_with_bindings(
				(
					"INSERT INTO avatar (player_id, class_id, spec_id, is_active, item_level,"
					+ " gear_score, marks, familiarity, hit_capped, uncrittable)"
					+ " VALUES (?, ?, ?, 1, ?, ?, 0, ?, ?, ?);"
				),
				[
					avatar["player_id"],
					avatar["class_id"],
					avatar["spec_id"],
					avatar["item_level"],
					avatar["gear_score"],
					avatar["familiarity"],
					avatar["hit_capped"],
					avatar["uncrittable"],
				]
			)
		):
			return _rollback(db, "avatar insert: %s" % db.error_message)
		db.query("SELECT last_insert_rowid() AS id;")
		var avatar_id := int(db.query_result[0]["id"])
		ids.append(avatar_id)
		for item: Dictionary in avatar["items"]:
			if not (
				db
				. query_with_bindings(
					"INSERT INTO avatar_item (avatar_id, slot_id, item_id, item_level) VALUES (?, ?, ?, ?);",
					[avatar_id, item["slot_id"], item["item_id"], item["item_level"]]
				)
			):
				return _rollback(db, "avatar_item insert: %s" % db.error_message)
		for prof: Dictionary in avatar["role_proficiencies"]:
			if not db.query_with_bindings(
				(
					"INSERT INTO player_role_proficiency (player_id, role_id, proficiency)"
					+ " VALUES (?, ?, ?);"
				),
				[avatar["player_id"], prof["role_id"], prof["proficiency"]]
			):
				return _rollback(db, "proficiency insert: %s" % db.error_message)
	db.query("COMMIT;")
	return ids


## Convenience: generate + persist for already-persisted players.
static func generate_and_persist(db: Variant, rng: RngStream) -> Array[int]:
	db.query("SELECT player_id, growth_rate, execution FROM player ORDER BY player_id;")
	var players: Array = db.query_result.duplicate()
	return persist(db, generate(db, players, rng))


## Role rows repeated per the tuning targets, scaled to `count`, then
## deterministically shuffled so role never correlates with roster order.
static func _role_plan(role_slugs: Array, count: int, rng: RngStream) -> Array[Dictionary]:
	var targets: Dictionary = Tuning.section("roster").get(
		"role_targets", {"tank": 4, "healer": 7, "melee": 8, "ranged": 9}
	)
	var plan: Array[Dictionary] = []
	var target_total := 0
	for slug in targets:
		target_total += int(targets[slug])
	for slug in ["tank", "healer", "melee", "ranged"]:
		assert(slug in role_slugs, "role '%s' missing from seeds" % slug)
		var share := int(round(count * float(targets.get(slug, 0)) / float(target_total)))
		for _i in share:
			plan.append({"slug": slug})
	while plan.size() > count:
		plan.pop_back()
	while plan.size() < count:
		plan.append({"slug": "ranged"})  # spill into the deepest role
	rng.shuffle(plan)
	return plan


static func _generate_avatar(
	player: Dictionary,
	role: Dictionary,
	spec: Dictionary,
	starter_items: Array,
	all_role_ids: Array[int],
	rng: RngStream
) -> Dictionary:
	var band: Array = Tuning.section("roster").get("starter_ilvl_band", [14, 22])
	var base_ilvl := rng.randi_range(int(band[0]), int(band[1]))
	var items: Array[Dictionary] = []
	var gear_score := 0
	for template: Dictionary in starter_items:
		var ilvl := clampi(base_ilvl + rng.randi_range(-2, 3), 10, 26)
		gear_score += ilvl
		(
			items
			. append(
				{
					"slot_id": int(template["slot_id"]),
					"item_id": int(template["item_id"]),
					"item_level": ilvl,
				}
			)
		)
	var avg_ilvl := int(round(gear_score / 7.0))
	# seasoned raiders (low growth_rate ~ older) start with more spec familiarity
	var familiarity := clampi(
		roundi(85.0 - float(player["growth_rate"]) * 0.6 + rng.randfn(0.0, 8.0)), 10, 90
	)
	return {
		"player_id": int(player["player_id"]),
		"class_id": int(spec["class_id"]),
		"spec_id": int(spec["spec_id"]),
		"role_id": int(spec["role_id"]),
		"role_slug": str(role["slug"]),
		"item_level": avg_ilvl,
		"gear_score": gear_score,
		"familiarity": familiarity,
		# placeholder start-state rule until M6-005 owns caps-from-gear
		"hit_capped": 1 if avg_ilvl >= CAP_ILVL_THRESHOLD else 0,
		"uncrittable":
		1 if (str(role["slug"]) == "tank" and avg_ilvl >= CAP_ILVL_THRESHOLD + 2) else 0,
		"items": items,
		"role_proficiencies": _proficiencies(player, spec, all_role_ids, rng),
	}


## Role instincts (PLAYER-level): assigned role strongest, one secondary
## decent, the rest weak. Uses the player's execution as the talent anchor.
static func _proficiencies(
	player: Dictionary, spec: Dictionary, all_role_ids: Array[int], rng: RngStream
) -> Array[Dictionary]:
	var assigned_role_id := int(spec["role_id"])
	var secondary: int = rng.pick(
		all_role_ids.filter(func(role_id: int) -> bool: return role_id != assigned_role_id)
	)
	var rows: Array[Dictionary] = []
	var anchor := float(player["execution"])
	for role_id in all_role_ids:
		var value: int
		if role_id == assigned_role_id:
			value = clampi(roundi(anchor * 0.55 + 35.0 + rng.randfn(0.0, 6.0)), 30, 95)
		elif role_id == secondary:
			value = clampi(roundi(anchor * 0.4 + 15.0 + rng.randfn(0.0, 8.0)), 15, 75)
		else:
			value = clampi(roundi(20.0 + rng.randfn(0.0, 8.0)), 5, 45)
		rows.append({"role_id": role_id, "proficiency": value})
	return rows


## {role_slug: [spec rows]} from the seed tables.
static func _specs_by_role(db: Variant) -> Dictionary:
	db.query(
		(
			"SELECT s.spec_id, s.class_id, s.role_id, s.slug, r.slug AS role_slug"
			+ " FROM spec s JOIN role r ON r.role_id = s.role_id ORDER BY s.spec_id;"
		)
	)
	var by_role := {}
	for row in db.query_result:
		var role_slug := str(row["role_slug"])
		if not by_role.has(role_slug):
			by_role[role_slug] = []
		by_role[role_slug].append(row)
	return by_role


## The 7 starter gear templates (slug starter_*), one per slot, slot order.
static func _starter_items(db: Variant) -> Array:
	db.query(
		"SELECT item_id, slot_id FROM loot_item" + " WHERE slug LIKE 'starter_%' ORDER BY slot_id;"
	)
	return db.query_result.duplicate()


static func _rollback(db: Variant, message: String) -> Array[int]:
	push_error("AvatarGen: persist failed: %s" % message)
	db.query("ROLLBACK;")
	return []
