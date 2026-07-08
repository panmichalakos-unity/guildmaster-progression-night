# Seed data convention (M0-005)

Content lives here as data, never in engine logic. One CSV file = one table.
Loaded by `sim/db/seed_loader.gd` on campaign creation; validated by
`tools/seed_check.py` (M0-006) in CI. dbt-seed idiom: slug natural keys,
idempotent upserts, git-diffable rows.

## Files

- `manifest.json` — lists seed files **in dependency order** (parents before
  children). The loader applies exactly this order, all inside one transaction.
- `*.csv` — header row = column names; one file per table.

## Rules

1. **Slugs are the natural keys.** Every seed row carries an immutable
   snake_case `slug` plus a renameable `display_name` (naming-bible
   convention). Seed files **never** contain integer ids.
2. **FK references are authored as slugs.** Name the CSV column
   `<whatever>_slug` and declare the resolution in the manifest entry:

   ```json
   { "file": "spec.csv", "table": "spec", "refs": [
       { "column": "class_slug", "table": "class", "as": "class_id" },
       { "column": "role_slug",  "table": "role",  "as": "role_id" }
   ] }
   ```

   The loader resolves each slug against the ref table's `slug` column and
   writes the integer id into the `as` column. Works when the FK column name
   differs from the table name too (e.g. `utility_slug` → table
   `raid_utility` → `as: utility_id`).
3. **Bridge tables (no slug column)** declare their upsert key explicitly:

   ```json
   { "file": "spec_utility.csv", "table": "spec_utility",
     "key": ["spec_id", "utility_id"], "refs": [
       { "column": "spec_slug",    "table": "spec",         "as": "spec_id" },
       { "column": "utility_slug", "table": "raid_utility", "as": "utility_id" }
   ] }
   ```
4. **Upserts, not replaces.** Reloading is idempotent: existing rows are
   matched on the key and updated in place — integer PKs never change, so
   FKs written by earlier loads stay valid. Rerunning the loader on an
   unchanged seed set changes nothing.
5. **Types come from the schema.** Cells are coerced using the target
   table's declared column types (`PRAGMA table_info`). Empty cells become
   NULL. Booleans are `0`/`1` (schema CHECKs enforce it).
6. **Enum spellings are frozen in ADR-0005** (docs/decisions.md) — CHECK
   constraints will reject anything else. Consult it before authoring.

## Current structural seeds (M0-005)

| File | Table | Rows | Why here already |
|---|---|---|---|
| `role.csv` | `role` | 4 (tank/healer/melee/ranged) | Structural — fixed by the content DoD |
| `slot.csv` | `slot` | 7 (head…weapon) | Structural — the 7-slot gear model |

## What M1 adds (in this format — do not invent a parallel one)

- **M1-001:** `class.csv`, `spec.csv` (refs: class, role), `raid_utility.csv`,
  `spec_utility.csv` (bridge), `synergy_tag.csv`, `spec_synergy_tag.csv` (bridge)
- **M1-002:** `expansion.csv`, `season.csv` (ref: expansion), `raid.csv`
  (ref: season), `encounter.csv` (ref: raid), `encounter_phase.csv`
  (ref: encounter), `event_type.csv`, `encounter_event.csv`
- **M1-003:** `loot_item.csv` (refs: encounter, slot, role),
  `consumable.csv`, plus tuning values

**Decided in M1-002 (ADR-0010):** `encounter_phase` gained a `slug` column and
`encounter_event` gained a nullable `target_selector` override (NULL = inherit
from the event type) — both via deliberate edits to `0001_init.sql` (allowed
pre-genesis per the M0-003 ticket rule; no shipped DBs exist). Range profiles
(melee-punisher, ranged-punisher) are expressed as placement-level selector
overrides, keeping the locked 7 event types.
