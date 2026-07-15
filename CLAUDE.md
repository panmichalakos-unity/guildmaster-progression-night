# Guildmaster: Progression Night

Godot 4.7 management sim. Hermes is the organizer / PM; Cursor with Codex plus Codex CLI are the coding agents; Godot is the engine/editor. Tasks are tracked in the Notion Kanban.

> **Notion Kanban:** https://app.notion.com/p/3914eb808192818e84b4f53579bfd5e2
> **Implementation agents:** Cursor Codex + Codex CLI. Do not assume Claude Code is part of this workflow.

## What We Are Building

**One-liner:** *Football Manager for old-school MMO raid guilds.*

The player does not directly fight. They run a raiding guild: recruit and read people, schedule the week, prepare a 20-raider lineup from a ~28-person roster, resolve raid nights through a deterministic combat-log engine, distribute scarce loot, manage morale/fairness/burnout, and survive season objectives.

### Non-negotiable design pillars

- **Legible failure:** every wipe names the failed check and the culprit / cause.
- **People are the game:** skill, consistency, awareness, loyalty, ego, fatigue, availability, benching, and loot expectations drive stories.
- **Loot is a leadership decision:** gear affects raid power, but awards also affect morale, loyalty, fairness, and retention.
- **Time is scarce:** weekly planning is trade-offs across Gearing, Development, Supply, People, and Rest.
- **Seeded determinism:** same seed + same inputs = same outcome, for tests, balance harnesses, and bug repros.
- **Content as data:** classes, specs, encounters, events, loot, objectives, and actions are seed rows. Do not bake content into engine logic.
- **IP-safe fantasy:** replicate old-school MMO systems and feel, but invent every proper noun.

## Canonical Design Docs

The design docs are versioned inside this repo at:

```text
docs/
```

From the repo root (`guildmaster-progression-night/`), coding agents must read relevant docs before implementation. Start with:

1. `docs/guildmaster-overview.md` — index and system map.
2. `docs/guildmaster-content-and-dod.md` — v1 scope and done gates.
3. `docs/guildmaster-backlog.md` — milestone plan M0–M11.
4. The specific system doc for the task being implemented.

Doc map:

| Doc | Use when working on |
|---|---|
| `guildmaster-pitch.md` | Product fantasy, audience, design pillars |
| `guildmaster-data-model.md` | SQLite schema, entities, facts, grains, v1 prototype spine |
| `guildmaster-campaign-and-objectives.md` | calendar, turn loop, save root, objectives, rival ladder, sacking/rebuild |
| `guildmaster-resolution.md` | raid-night resolution engine, checks, events, learning arc, ratings |
| `guildmaster-encounter-contracts.md` | **per-boss tuning contracts** — expected gear, win-rate bands, dominant challenge, the gear ceiling. Retuning a boss without updating its contract is a bug |
| `guildmaster-first-session.md` | **the Night One contract** — the curated first session that must teach diagnose → fix → succeed |
| `guildmaster-presentation.md` | **the raid-night show** — notability hierarchy, phase beats, the closing beat, "closest yet", pacing |
| `guildmaster-diagnostics.md` | **why did we wipe** — primary cause vs contributing factors vs key moment; the anti-scapegoat rule |
| `guildmaster-terminology.md` | **dual-language UI copy** — consequence first, action always, MMO term in parentheses; the glossary |
| `guildmaster-rating.md` | **the 1-10 performance rating** — what it measures, the event deltas, no double-counting; loot evidence for M6 |
| `guildmaster-involvement.md` | **Manual / Assisted / Instant** — per-domain delegation contract; who authors the inputs; the fallible-officer rule; the Night One PIN. Phase-B screens build all three modes from v1 |
| `guildmaster-raid-prep.md` | lineup, comp warnings, assignments, benching, consumable plan |
| `guildmaster-gear.md` | 7-slot gear model, `gear_score`, caps, spec-fit, Marks |
| `guildmaster-loot.md` | Council/DKP/roll, claims panel, fairness consequences |
| `guildmaster-between-nights.md` | weekly lanes, action resolver, economy, treasury, stockpile |
| `guildmaster-recruitment.md` | scouting, prospects, fog overlay, trials, attrition |
| `guildmaster-conventions.md` | baseline/current modeling, traits vs state, derived archetypes |
| `guildmaster-naming-bible.md` | IP-safe names, slugs, classes/specs, bosses, utilities |
| `guildmaster-stack-and-tooling.md` | locked stack, repo skeleton, CI, tooling |
| `guildmaster-v1-readiness-review.md` | resolved gaps and build-readiness trace |

Repo-local `docs/` is the canonical source of truth for build specs. Do not rely on sibling/outside-repo doc folders unless explicitly instructed.

## v1 Scope Contract

### Gate 1 — Phase A vertical slice / fun proof

Phase A ends only when this is playable and fun enough to continue:

- Generate a 20-raider lineup from a believable ~28-person roster.
- Seed one raid with 3–4 bosses.
- Plan raid-night lineup + assignments.
- Resolve pull-by-pull combat log.
- Produce kill/wipe, `wipe_reason`, per-raider `performance_rating`, loot drop, and post-night report.
- Determinism verified: same seed => same result.
- Batch harness can run N pulls and report sane win-rate bands.

### Gate 2 — v1 Early Access loop

The one-line bar:

> Start a guild → play a full 14-week season across 2 tiers → get graded on objectives → progress to the next season/endless mode, or get sacked and rebuild — with every core system exercised.

Out of v1 unless explicitly re-scoped: chemistry effects, quirks, deep drama catalogue, resistance checks, multi-expansion, Player-Guildmaster, professions/crafting, Soft Reserve/EPGP, full rival simulation.

## Milestone Plan

Phase A — prove the loop:

- **M0 — Foundation & schema:** Godot app, SQLite path, migrations, seed-loader plumbing, empty app runs and migrates.
- **M1 — Seed starter kit:** 6 classes × 3 specs, utilities, consumables, one raid with 3–4 encounters, core event placements, loot table.
- **M2 — Roster generation:** ~28 Players + Avatars with traits, life presets, gear, familiarity, role coverage, inspectable output.
- **M3 — Resolution engine:** seeded pull resolver, checks, events, learning arc, rating, combat log.
- **M4 — Slice UI / Fun Gate:** lineup + assignments UI, combat-log feed, post-night report.

Phase B — complete v1 loop:

- **M5:** turn loop, calendar, genesis, weekly lanes, availability, inbox, digest.
- **M6:** loot policies + claims panel + consequences.
- **M7:** economy, treasury, donations, repairs, stockpile, policies.
- **M8:** recruitment, prospect fog, population tick, attrition.
- **M9:** objectives, rival ladder, season grading, sacking/rebuild, endless mode.

Phase C / v1.1:

- **M10:** social depth, chemistry effects, quirks, drama catalogue.
- **M11:** multi-expansion, Player-Guildmaster, resistance/quirk events, professions, additional loot policies.

## Architecture Rules

1. **GDScript only.** No C#, no C++. Use typed GDScript where it improves clarity.
2. **Godot 4.7 pinned locally.** Do not introduce engine-version-dependent features without noting them.
3. **Pure sim core first.** Core simulation code must be callable without scene-tree dependencies. Prefer pure functions such as `(input_state, seed) -> outcome` for roster generation, action resolution, and pull resolution.
4. **Nodes over inheritance.** Use Godot scenes/nodes for UI and presentation. Avoid deep class hierarchies.
5. **Signals for coupling.** Use signals or an `EventBus` autoload for cross-system communication. Avoid direct calls between unrelated systems.
6. **Autoloads are explicit singletons only.** Expected autoloads include `GameState`, `EventBus`, `RNG`, and later DB/data loading services. Do not create a god-object.
7. **Seeded RNG only.** No `randi()`, `randf()`, `RandomNumberGenerator.new()` scatter, or hidden randomness outside the dedicated RNG flow. Random behavior must be seedable and reproducible.
8. **SQLite-backed save/data path.** The SQLite DB is the campaign save. Migrations are numbered SQL files. Seed data uses immutable `slug` natural keys plus mutable `display_name`.
9. **Content as seed data.** Classes/specs, utilities, encounters, event types, encounter events, loot, consumables, objectives, and actions belong in data files/migrations, not hardcoded gameplay arrays.
10. **Observability is gameplay tooling.** Preserve audit trails: `PULL_EVENT`, `WEEK_ACTION`, `TREASURY_LEDGER`, `LOOT_CLAIM`, etc. Build “why did this happen?” views early.
11. **Tests for sim/logic.** Every deterministic sim/logic function gets tests. Prefer GdUnit4 for Godot tests, plus Python seed checks where useful.
12. **Small, ticket-scoped changes.** Do not invent new systems, rename architecture, or expand scope beyond the ticket.
13. **Conventional commits when explicitly requested.** Use `feat:`, `fix:`, `refactor:`, `test:`, `chore:`. If the task does not ask for a commit, leave changes uncommitted and report diff + tests.

## Target Repo Structure

Preferred structure from the design docs:

```text
guildmaster-progression-night/
├── project.godot
├── CLAUDE.md
├── sim/                    # pure sim core; no scene-tree dependencies
├── game/                   # scenes, UI, themes, Godot-facing presentation
├── data/
│   ├── seeds/              # CSV/JSON/YAML seed rows, slug-keyed
│   └── migrations/         # 0001_init.sql, 0002_*.sql, ...
├── tools/
│   ├── harness.gd          # headless simulation / balance harness
│   ├── seed_check.py       # seed integrity checks
│   └── balance_lab/        # DuckDB/pandas notebooks/queries later
├── tests/                  # GdUnit4 tests
├── assets/                 # curated assets only; raw AI output stays out
└── docs/                   # canonical design docs and build specs
```

The initial scaffold may still contain `scenes/`, `scripts/`, and `resources/`. For new implementation work, prefer the target structure above unless a migration ticket says otherwise.

## Modeling Conventions To Preserve

- **Player vs Avatar:** `PLAYER` is the human and persists; `AVATAR` is the character and can be rerolled/swapped.
- **Traits vs states:** durable traits live on entities; volatile state lives in snapshots/facts.
- **Movable attributes:** use the conventions doc:
  - Baseline + current for same-unit drift read later, e.g. loyalty.
  - Accumulator + rate trait for fatigue/familiarity-like quantities.
  - Trait + runtime modifier when the adjusted value does not need persistence.
- **Archetype is derived, never stored.** Labels must not contradict the underlying traits/quirks.
- **Raid event grain:** `CALENDAR_EVENT` is the scheduled event; `RAID_LINEUP` and `RAID_ASSIGNMENT` live at event grain; `PULL_PARTICIPANT` inherits and can override per pull.
- **Performance rating is relative:** 1–10 rating vs expected for gear/role, not raw throughput.
- **Attendance vs participation:** attendance is availability rate; participation is non-benched lineup rate.
- **Bench has cost:** repeated benching affects morale/loyalty and must surface in digest/reporting.

## Current Key Commands

Run from the repo root.

```bash
# Project load smoke test (run with the Godot editor CLOSED — an open editor
# session blocks project-run mode; -s script smokes below work regardless)
godot --headless --quit

# GdUnit4 tests (addon installed in M0-002; --ignoreHeadlessMode is required for headless runs)
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/

# Lint/format (gdtoolkit installed via `uv tool install gdtoolkit`; M0-007)
gdformat --check sim/ game/ tests/ tools/smoke/
gdlint sim/ game/ tests/ tools/smoke/

# ⚠️ If gdformat/gdlint fail with "Application Control policy has blocked this file":
# Windows Smart App Control (ENFORCED on this machine) blocks the UNSIGNED .exe
# launcher shim — not the linter itself, which is pure Python. Bypass the shim by
# invoking the module through the (signed, trusted) python.exe. Same checks, no
# security change, no one-way SAC toggle:
python -m gdtoolkit.formatter --check sim/ game/ tests/ tools/smoke/ tools/harness.gd
python -m gdtoolkit.linter sim/ game/ tests/ tools/smoke/ tools/harness.gd
# (one-time: `python -m pip install gdtoolkit` into whatever python you invoke)

# Seed integrity checks (M0-006; stdlib Python, no Godot needed)
python tools/seed_check.py

# Vertical slice smoke (M4-005)
godot --headless -s tools/smoke/slice_smoke.gd -- --seed 133742

# Git inspection before/after work
git status --short
git diff --stat
git diff
```

If a tool/addon is not installed yet, report that directly and continue with the checks that are available. Do not fake green test output.

### ⚠️ Looping `gdsqlite` GDExtension error in the editor — cause and fix

**Symptom:** the Godot editor spams, on repeat:

```text
ERROR: Failed to open '.../addons/godot-sqlite/bin/~libgdsqlite.windows.template_debug.x86_64.dll'
ERROR: Error copying library: .../libgdsqlite.windows.template_debug.x86_64.dll
ERROR: Can't open GDExtension dynamic library: 'res://addons/godot-sqlite/gdsqlite.gdextension'
ERROR: Error loading extension: 'res://addons/godot-sqlite/gdsqlite.gdextension'
```

**Cause.** Godot copies a GDExtension DLL to a `~`-prefixed temp file so it can hot-reload it. Running a **second Godot process while the editor is open** (i.e. any `godot --headless …` command during a session) makes that copy fail, and Windows leaves a `~libgdsqlite.windows.template_debug.x86_64.dll~RF*.TMP` turd behind. They **accumulate silently** — one per session — until one collides with the copy target, the extension fails to load, and the editor **retries forever**. The game code is not involved.

**Fix (safe — they are gitignored build turds, never tracked):**

```bash
rm -f addons/godot-sqlite/bin/'~libgdsqlite'*.TMP
```

Then restart the editor. **Prevention:** close the Godot editor before running headless commands — the same rule that already applies to `--headless --quit`. If you must run both, sweep `bin/` afterwards.

## Hermes / Cursor / Codex Workflow

```text
HERMES / PM
  - maintains project context and Notion Kanban
  - decomposes milestones into ticket-sized tasks
  - writes paste-ready implementation prompts
  - reviews diffs and runs verification
  - updates task status after real verification

PANOS
  - chooses scope and approves gates
  - pastes Hermes prompts into Cursor/Codex when human-in-the-loop is desired
  - playtests fun gates

CURSOR CODEX / CODEX CLI
  - implements one ticket at a time
  - reads CLAUDE.md + relevant docs before editing
  - keeps changes small and test-backed
  - returns summary, files changed, tests run, and blockers
```

## Coding Agent Contract

Before editing:

1. Read `CLAUDE.md`.
2. Read `docs/guildmaster-overview.md` and the relevant system doc.
3. Run `git status --short`.
4. Identify exact files to touch.
5. Ask if the ticket conflicts with the design docs.

During implementation:

- Keep all game content IP-original and slug-keyed.
- Do not add hidden randomness.
- Do not hardcode seed content into engine logic.
- Do not introduce C#, C++, plugins, or dependencies unless the ticket explicitly asks.
- Do not broaden scope beyond acceptance criteria.
- Prefer deterministic, testable functions for sim logic.

Before declaring done:

- Run the relevant tests/checks that exist.
- Run `godot --headless --quit` when project-load risk exists.
- Report exact commands and outcomes.
- Report changed files.
- If tests cannot run because setup is missing, say exactly what is missing.

## Immediate Next Build Step

The docs identify the next real build move as **Phase-A ticket decomposition**, then **M0 Foundation & schema**:

1. Keep repo-local `docs/` current as the canonical design source.
2. Install/confirm GdUnit4 and `godot-sqlite` when M0 begins.
3. Create `data/migrations/0001_init.sql` from the v1 prototype spine in `guildmaster-data-model.md`.
4. Add seed-loader plumbing.
5. Add a headless smoke path proving the empty app can open and migrate.

Do not start breadth work before the Phase A vertical slice proves the raid-night loop is fun.
