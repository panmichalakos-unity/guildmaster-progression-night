#!/usr/bin/env python3
"""Seed integrity checker (M0-006). dbt-style checks for data/seeds/.

Pure stdlib, no Godot required. Validates the seed convention defined in
M0-005 (data/seeds/README.md, ADR-0007) by REPLAYING it:

  1. static hygiene   - manifest well-formed, files exist, headers sane,
                        slugs snake_case + unique, display_name present,
                        IP-safe naming (naming-bible deny lists)
  2. simulated load   - applies data/migrations/*.sql into :memory: sqlite
                        (foreign_keys ON) and loads every seed exactly like
                        sim/db/seed_loader.gd does (refs, coercion, upserts),
                        so the schema's own CHECK / FK / NOT NULL / UNIQUE
                        constraints validate enum domains and references
  3. idempotency      - loading twice changes nothing (counts + ids stable)
  4. M1 coverage      - dormant rules that activate as content files land
                        (6 classes, 18 specs w/ 3/4/5/6 roles, 7 event types,
                        raids have 3+ encounters, encounters have 3+ loot rows)

Exit 0 = all checks pass (warnings allowed). Exit 1 = at least one error.

Usage:
  python tools/seed_check.py
  python tools/seed_check.py --seeds-dir tests/fixtures/seeds_bad_ref   # spot checks

NOTE: this mirrors sim/db/seed_loader.gd on purpose (stack doc: Python data
checks). If the convention changes, update BOTH and data/seeds/README.md.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SLUG_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# Naming-bible hard rules (docs/guildmaster-naming-bible.md): invent every
# proper noun. ERROR terms are unambiguous foreign-IP proper nouns; WARN terms
# are generic words that read as WoW class/difficulty labels (flag, human judges).
IP_ERROR_TERMS = {
    "azeroth", "kalimdor", "orgrimmar", "stormwind", "ironforge", "undercity",
    "teldrassil", "darnassus", "silvermoon", "onyxia", "ragnaros", "nefarian",
    "naxxramas", "karazhan", "illidan", "arthas", "thrall", "sylvanas",
    "kelthuzad", "hellscream", "proudmoore", "menethil", "stormrage",
    "windrunner", "sunstrider", "deathwing", "outland", "draenor", "norrath",
    "eorzea", "hydaelyn", "tamriel", "tyria", "telara",
}
IP_WARN_TERMS = {
    "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage",
    "warlock", "druid", "monk", "evoker", "heroic", "mythic",
}


class Checker:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.passes = 0

    def ok(self, label: str) -> None:
        self.passes += 1
        print(f"  [ok]   {label}")

    def fail(self, label: str) -> None:
        self.errors.append(label)
        print(f"  [FAIL] {label}")

    def warn(self, label: str) -> None:
        self.warnings.append(label)
        print(f"  [warn] {label}")

    def check(self, condition: bool, label: str) -> bool:
        if condition:
            self.ok(label)
        else:
            self.fail(label)
        return condition


# ---------------------------------------------------------------------------
# schema + loader mirror
# ---------------------------------------------------------------------------

def build_schema(migrations_dir: Path, c: Checker) -> sqlite3.Connection | None:
    con = sqlite3.connect(":memory:")
    con.execute("PRAGMA foreign_keys = ON")
    sql_files = sorted(migrations_dir.glob("*.sql"))
    if not c.check(bool(sql_files), f"migrations exist in {migrations_dir}"):
        return None
    for sql_file in sql_files:
        try:
            con.executescript(sql_file.read_text(encoding="utf-8"))
        except sqlite3.Error as exc:
            c.fail(f"migration {sql_file.name} failed to apply: {exc}")
            return None
    c.ok(f"schema built from {len(sql_files)} migration(s)")
    return con


def table_columns(con: sqlite3.Connection, table: str) -> dict[str, str]:
    return {row[1]: (row[2] or "TEXT") for row in con.execute(f"PRAGMA table_info({table})")}


def table_pk(con: sqlite3.Connection, table: str) -> str | None:
    for row in con.execute(f"PRAGMA table_info({table})"):
        if row[5] == 1:  # pk flag
            return row[1]
    return None


def coerce(raw: str, declared: str, column: str) -> tuple[bool, object, str]:
    if raw.strip() == "":
        return True, None, ""
    declared = declared.upper()
    if "INT" in declared:
        try:
            return True, int(raw.strip()), ""
        except ValueError:
            return False, None, f"column '{column}' expects INTEGER, got '{raw}'"
    if any(t in declared for t in ("REAL", "FLOA", "DOUB")):
        try:
            return True, float(raw.strip()), ""
        except ValueError:
            return False, None, f"column '{column}' expects REAL, got '{raw}'"
    return True, raw, ""


def read_csv(path: Path) -> tuple[list[str], list[list[str]]]:
    with path.open(newline="", encoding="utf-8-sig") as fh:
        rows = [row for row in csv.reader(fh) if any(cell.strip() for cell in row)]
    return (rows[0], rows[1:]) if rows else ([], [])


def simulate_load(con: sqlite3.Connection, seeds_dir: Path, manifest: dict, c: Checker) -> bool:
    """Mirror of sim/db/seed_loader.gd load semantics. Returns True on success."""
    for entry in manifest.get("files", []):
        filename, table = entry.get("file", ""), entry.get("table", "")
        path = seeds_dir / filename
        header, rows = read_csv(path)
        columns = table_columns(con, table)
        if not c.check(bool(columns), f"{filename}: target table '{table}' exists in schema"):
            return False

        ref_by_column: dict[str, dict] = {}
        for ref in entry.get("refs", []):
            ref_table, ref_as = ref["table"], ref["as"]
            pk = table_pk(con, ref_table)
            if pk is None or "slug" not in table_columns(con, ref_table):
                c.fail(f"{filename}: ref table '{ref_table}' is missing or has no slug column")
                return False
            lookup = dict(con.execute(f"SELECT slug, {pk} FROM {ref_table}"))
            ref_by_column[ref["column"]] = {"as": ref_as, "lookup": lookup}

        db_columns = [ref_by_column[col]["as"] if col in ref_by_column else col for col in header]
        unknown = [col for col in db_columns if col not in columns]
        if not c.check(not unknown, f"{filename}: all columns map to '{table}' schema"):
            c.fail(f"{filename}: unknown columns {unknown}")
            return False

        key_columns = ["slug"] if "slug" in db_columns else [str(k) for k in entry.get("key", [])]
        if not c.check(bool(key_columns), f"{filename}: has an upsert key (slug or manifest 'key')"):
            return False
        non_key = [col for col in db_columns if col not in key_columns]
        conflict = ", ".join(key_columns)
        action = (
            "DO UPDATE SET " + ", ".join(f"{col} = excluded.{col}" for col in non_key)
            if non_key else "DO NOTHING"
        )
        sql = (
            f"INSERT INTO {table} ({', '.join(db_columns)}) "
            f"VALUES ({', '.join('?' for _ in db_columns)}) "
            f"ON CONFLICT({conflict}) {action}"
        )

        loaded = 0
        for i, row in enumerate(rows, start=2):
            if len(row) != len(header):
                c.fail(f"{filename}:{i}: {len(row)} fields, header has {len(header)}")
                return False
            values = []
            for seed_col, db_col, raw in zip(header, db_columns, row):
                if seed_col in ref_by_column:
                    lookup = ref_by_column[seed_col]["lookup"]
                    if raw.strip() == "":
                        values.append(None)
                    elif raw not in lookup:
                        c.fail(f"{filename}:{i}: unknown slug '{raw}' for ref column '{seed_col}'")
                        return False
                    else:
                        values.append(lookup[raw])
                else:
                    okay, value, err = coerce(raw, columns[db_col], db_col)
                    if not okay:
                        c.fail(f"{filename}:{i}: {err}")
                        return False
                    values.append(value)
            try:
                con.execute(sql, values)
            except sqlite3.Error as exc:
                c.fail(f"{filename}:{i}: insert into '{table}' rejected by schema: {exc}")
                return False
            loaded += 1
        c.ok(f"{filename}: {loaded} row(s) load clean into '{table}' (schema constraints enforced)")
    con.commit()
    return True


# ---------------------------------------------------------------------------
# static hygiene
# ---------------------------------------------------------------------------

def check_static(seeds_dir: Path, manifest: dict, c: Checker) -> None:
    listed = set()
    for entry in manifest.get("files", []):
        filename, table = entry.get("file", ""), entry.get("table", "")
        if not c.check(bool(filename) and bool(table), f"manifest entry has file+table: {entry}"):
            continue
        listed.add(filename)
        path = seeds_dir / filename
        if not c.check(path.is_file(), f"{filename}: file exists"):
            continue
        header, rows = read_csv(path)
        c.check(len(header) == len(set(header)), f"{filename}: no duplicate header columns")

        if "slug" in header:
            idx = header.index("slug")
            slugs = [row[idx] for row in rows if len(row) == len(header)]
            bad = [s for s in slugs if not SLUG_RE.match(s)]
            c.check(not bad, f"{filename}: slugs are snake_case ({bad if bad else 'all good'})")
            dupes = {s for s in slugs if slugs.count(s) > 1}
            c.check(not dupes, f"{filename}: slugs unique ({dupes if dupes else 'all good'})")
        if "display_name" in header:
            idx = header.index("display_name")
            empty = sum(1 for row in rows if len(row) == len(header) and not row[idx].strip())
            c.check(empty == 0, f"{filename}: display_name never empty")

        # IP-safe naming: token-match slugs, whole-word-match display names
        for i, row in enumerate(rows, start=2):
            for col in ("slug", "display_name"):
                if col not in header or len(row) != len(header):
                    continue
                value = row[header.index(col)]
                tokens = set(re.split(r"[_\s\-]+", value.lower()))
                hits_error = tokens & IP_ERROR_TERMS
                hits_warn = tokens & IP_WARN_TERMS
                if hits_error:
                    c.fail(f"{filename}:{i}: '{value}' uses foreign-IP proper noun {sorted(hits_error)} (naming bible)")
                if hits_warn:
                    c.warn(f"{filename}:{i}: '{value}' matches WoW-label word {sorted(hits_warn)} — confirm it's IP-original")

    orphans = {p.name for p in seeds_dir.glob("*.csv")} - listed
    c.check(not orphans, f"no orphan CSVs outside manifest ({orphans if orphans else 'none'})")


# ---------------------------------------------------------------------------
# M1 coverage rules (dormant until the files land in the manifest)
# ---------------------------------------------------------------------------

def check_m1_coverage(con: sqlite3.Connection, present: set[str], c: Checker) -> None:
    def count(sql: str) -> int:
        return con.execute(sql).fetchone()[0]

    if "class.csv" in present:
        c.check(count("SELECT COUNT(*) FROM class") == 6, "M1: exactly 6 classes")
    if "spec.csv" in present:
        c.check(count("SELECT COUNT(*) FROM spec") == 18, "M1: exactly 18 specs")
        for role_slug, expected in (("tank", 3), ("healer", 4), ("melee", 5), ("ranged", 6)):
            actual = count(
                "SELECT COUNT(*) FROM spec s JOIN role r ON r.role_id = s.role_id "
                f"WHERE r.slug = '{role_slug}'"
            )
            c.check(actual == expected, f"M1: {expected} {role_slug} specs (got {actual})")
    if "spec.csv" in present and "spec_utility.csv" in present:
        uncovered = count(
            "SELECT COUNT(*) FROM spec s WHERE NOT EXISTS "
            "(SELECT 1 FROM spec_utility su WHERE su.spec_id = s.spec_id)"
        )
        if uncovered:
            c.warn(f"M1: {uncovered} spec(s) bring no utility — confirm intentional (stack doc rule)")
    if "event_type.csv" in present:
        c.check(count("SELECT COUNT(*) FROM event_type") >= 7,
                "M1: at least 7 event types (core-5 + assigned_duty + cooldown)")
    if "encounter.csv" in present and "encounter_contract.csv" in present:
        # MI-009: "retuning a boss without updating its contract is a bug" was a
        # convention, and conventions do not fail builds. Every boss must carry a
        # balance contract for the harness to assert it against — a boss with no
        # contract is a boss nobody is checking, and that is how three of four of
        # them sat at a 0% win rate while CI stayed green.
        orphans = con.execute(
            "SELECT e.slug FROM encounter e WHERE NOT EXISTS "
            "(SELECT 1 FROM encounter_contract ec WHERE ec.encounter_id = e.encounter_id)"
        ).fetchall()
        c.check(not orphans,
                f"MI-009: every encounter has a balance contract ({[o[0] for o in orphans] or 'all good'})")
        bad = con.execute(
            "SELECT e.slug FROM encounter_contract ec JOIN encounter e "
            "ON e.encounter_id = ec.encounter_id "
            "WHERE ec.win_lo >= ec.win_hi OR ec.expected_gear > ec.farm_gear "
            "OR ec.farm_gear > 1.65 OR ec.signature_min_delta <= 0"
        ).fetchall()
        c.check(not bad,
                "MI-009: contracts are coherent — win_lo < win_hi, expected_gear <= farm_gear, "
                f"farm gear inside the reachable ceiling x1.64 ({[b[0] for b in bad] or 'all good'})")
    if "encounter.csv" in present and "raid.csv" in present:
        thin = con.execute(
            "SELECT r.slug, COUNT(e.encounter_id) FROM raid r "
            "LEFT JOIN encounter e ON e.raid_id = r.raid_id GROUP BY r.raid_id "
            "HAVING COUNT(e.encounter_id) < 3"
        ).fetchall()
        c.check(not thin, f"M1: every raid has 3+ encounters ({thin if thin else 'all good'})")
    if "loot_item.csv" in present and "encounter.csv" in present:
        thin = con.execute(
            "SELECT e.slug, COUNT(li.item_id) FROM encounter e "
            "LEFT JOIN loot_item li ON li.encounter_id = e.encounter_id GROUP BY e.encounter_id "
            "HAVING COUNT(li.item_id) < 3"
        ).fetchall()
        c.check(not thin, f"M1: every encounter has 3+ loot rows ({thin if thin else 'all good'})")
    if "raid.csv" in present:
        raids = count("SELECT COUNT(*) FROM raid")
        c.check(raids >= 1, f"M1: at least one raid seeded (got {raids})")
    if "life_situation.csv" in present:
        presets = count("SELECT COUNT(*) FROM life_situation")
        c.check(presets == 6, f"M2: exactly 6 life presets (got {presets})")
    if "consumable.csv" in present:
        premium = count("SELECT COUNT(*) FROM consumable WHERE tier = 'premium'")
        basic = count("SELECT COUNT(*) FROM consumable WHERE tier = 'basic'")
        c.check(premium >= 1 and basic >= 1,
                f"M1: consumables support the premium/basic/none plan ({premium} premium, {basic} basic)")
    if "encounter_event.csv" in present:
        # range profiles power the M4 comp warnings: effective selector =
        # placement override, else the event type's default
        ranged = count(
            "SELECT COUNT(*) FROM encounter_event ee JOIN event_type et "
            "ON et.event_type_id = ee.event_type_id "
            "WHERE COALESCE(ee.target_selector, et.target_selector) = 'ranged'"
        )
        melee = count(
            "SELECT COUNT(*) FROM encounter_event ee JOIN event_type et "
            "ON et.event_type_id = ee.event_type_id "
            "WHERE COALESCE(ee.target_selector, et.target_selector) = 'melee'"
        )
        c.check(ranged >= 1 and melee >= 1,
                f"M1: both range profiles present in placements ({melee} melee, {ranged} ranged)")


# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Guildmaster seed integrity checks")
    parser.add_argument("--seeds-dir", default=str(REPO_ROOT / "data" / "seeds"))
    parser.add_argument("--migrations-dir", default=str(REPO_ROOT / "data" / "migrations"))
    args = parser.parse_args()
    seeds_dir, migrations_dir = Path(args.seeds_dir), Path(args.migrations_dir)
    c = Checker()

    print(f"seed_check: seeds={seeds_dir} migrations={migrations_dir}")
    manifest_path = seeds_dir / "manifest.json"
    if not c.check(manifest_path.is_file(), "manifest.json exists"):
        return _summarize(c)
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        c.fail(f"manifest.json is not valid JSON: {exc}")
        return _summarize(c)
    if not c.check(isinstance(manifest.get("files"), list), "manifest has a 'files' array"):
        return _summarize(c)

    print("-- static hygiene --")
    check_static(seeds_dir, manifest, c)

    print("-- simulated load against real schema --")
    con = build_schema(migrations_dir, c)
    if con is None or not simulate_load(con, seeds_dir, manifest, c):
        return _summarize(c)

    print("-- idempotency --")
    tables = [e["table"] for e in manifest["files"]]
    before = {
        t: con.execute(f"SELECT COUNT(*), COALESCE(SUM(rowid), 0) FROM {t}").fetchone()
        for t in tables
    }
    if simulate_load(con, seeds_dir, manifest, c):
        after = {
            t: con.execute(f"SELECT COUNT(*), COALESCE(SUM(rowid), 0) FROM {t}").fetchone()
            for t in tables
        }
        c.check(before == after, "reload changes nothing (counts + ids stable)")

    print("-- M1 coverage rules (dormant until content lands) --")
    present = {e["file"] for e in manifest["files"]}
    check_m1_coverage(con, present, c)
    return _summarize(c)


def _summarize(c: Checker) -> int:
    print(f"seed_check: {c.passes} ok, {len(c.warnings)} warning(s), {len(c.errors)} error(s)")
    if c.errors:
        print("SEED CHECK: FAIL")
        return 1
    print("SEED CHECK: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
