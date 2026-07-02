# Guildmaster: Progression Night — Gear & Power (v0.1)

Resolves readiness-review **P0 #3 & #5**: loot now actually raises power, and Marks are the catch-up floor.

## Per-slot equipped gear
Each Avatar has **7 equipment slots** — Head, Shoulder, Chest, Hands, Legs, Feet, Weapon. Each holds an item with an item level. **Avatar power (`gear_score`) = the aggregate of equipped slots** — derived and **cached**, recomputed on equip (per the conventions doc: cache it, because the resolution engine reads it every pull).

Awarding loot = equip it *if it's an upgrade* → power rises by exactly that slot's delta. This is the authentic slot-by-slot treadmill; the expansion reset just repopulates slots at a new tier.

**Why per-slot over an abstract score:** it makes the loot panel *real* — "upgrade magnitude" = the actual slot delta, and "biggest upgrade" / BiS become computed facts, not hand-waves. The loot-drama system needs this to mean anything.

*(7 slots, not 12 — trimmed to keep it a sim without accessory busywork. Fewer slots also means each drop is more contested → higher loot-drama density.)*

## Readiness caps derive from gear
`hit_capped` / `uncrittable` are computed from the **equipped set's** stats, not manual flags — so gearing toward "raid-ready" is a real, visible target, and the near-binary tank check stays honest.

## Spec-fit (light)
An item isn't a pure number — it can be a big raw upgrade but *wrong* for the spec (armor type, off-stats). v1-light: items carry a **spec-fit tag**; poor fit → a smaller *effective* upgrade (a fit multiplier). This creates the classic "technically an upgrade, but not for *me*" loot argument — one tag, high drama payoff.

## Marks — the catch-up currency
- **`marks`** — a per-**raider** balance. Earned from dungeon events; spent at a **Marks vendor** on catch-up gear (`LOOT_ITEM.marks_cost > 0`) that equips into the same 7 slots. **One gear model, two sources** — raid RNG + deterministic grind.
- **Per-raider, not a guild pool** → gearing becomes a **targeting decision** (whose Marks do you grow this week).
- **Design role:** Marks gear sits *below* current-tier drops but *above* the entry bar — it closes the floor so an unlucky raider stays raid-viable. This makes "the unlucky player falls behind" solvable by **management**, not luck.
- **Expansion reset:** Marks gear is the **catch-up ramp** — a fresh, slightly-behind-tier vendor set that re-gears the roster fast after the wipe, so the reset isn't a brutal regrind.

## Scope
- **In v1:** 7 equipped slots; derived+cached `gear_score`; exact upgrade deltas; caps-from-gear; spec-fit tags; Marks + vendor + catch-up ramp.
- **Deferred:** full stat sheets (crit/haste as individual budgets), gems/enchants, set bonuses, itemized mats.

## Model impact (in data-model v0.7)
- **`AVATAR_ITEM`** (avatar_id, slot, loot_item_id, item_level) · **`SLOT`** lookup (7) · **`Avatar.gear_score`** (derived/cached) + **`Avatar.marks`** · **`LOOT_ITEM`** gains `marks_cost` + `spec_fit_tag` · caps derived from equipped set. Resolution's `throughput_ceiling` now reads `gear_score` (a real source, not a static scalar).

---

*v0.1 — gear model locked. 7 slots. IP-original naming.*
