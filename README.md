# Guildmaster: Progression Night

*Football Manager for old-school MMO raid guilds.* A management sim where you run a raiding guild — recruit and read people, plan the week, field a 20-raider lineup from a ~28-person roster, resolve raid nights through a deterministic combat-log engine, distribute scarce loot, and survive season objectives. You don't swing the sword; you run the guild.

## Stack (locked)

| Layer | Choice |
|---|---|
| Engine | **Godot 4.7** (pinned — do not upgrade without an ADR) |
| Language | GDScript only (typed where it helps) |
| Save/data | SQLite via `godot-sqlite` addon — one DB = one campaign save |
| Tests | GdUnit4 + the headless balance harness (per-boss contracts + prep-leverage probes) |
| Lint/format | gdtoolkit (`gdformat`, `gdlint`) |

Full contract for humans and AI agents: **[CLAUDE.md](CLAUDE.md)** (canonical) and [AGENTS.md](AGENTS.md) (short version). Design docs live in [docs/](docs/) — start at `docs/guildmaster-overview.md`. Build-time decisions are logged in `docs/decisions.md`. Tasks are tracked on the Notion Kanban (link in CLAUDE.md).

## Repo layout

```
sim/                 pure sim core — no scene-tree deps; (input_state, seed) -> outcome
game/                scenes, UI, themes
data/seeds/          slug-keyed seed rows (content lives here, not in code)
data/migrations/     numbered SQL migrations (0001_init.sql, ...)
tools/               harness.gd, seed_check.py, smoke scripts, balance lab
tests/               GdUnit4 tests
assets/              curated assets only (Git LFS); raw AI output stays out
docs/                canonical design docs + decisions.md
```

*(The legacy scaffold dirs `scenes/`, `scripts/`, `resources/` were removed 2026-07-19 — the structure above is the whole layout.)*

## Commands

Run from the repo root.

Available now:

```bash
godot --headless --quit        # project-load smoke test
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/   # unit tests
godot --headless -s tools/smoke/migrate_smoke.gd   # migration smoke: disposable DB, apply + idempotency
godot --headless -s tools/smoke/seed_smoke.gd      # seed smoke: migrate + load data/seeds twice, verify counts
godot --headless -s tools/smoke/roster_smoke.gd -- --seed 12345   # print a generated 28-roster + coverage/issues
godot --headless -s tools/smoke/first_night_smoke.gd -- --seed 133742   # the first session must TEACH (MI-003)
godot --headless -s tools/smoke/slice_smoke.gd -- --seed 133742   # Phase-A vertical slice: prep → night → report
godot --headless -s tools/smoke/genesis_smoke.gd -- --seed 12345      # M5-001: new-campaign genesis
godot --headless -s tools/smoke/turn_loop_smoke.gd -- --seed 12345    # M5-002: FM event-day stepping
godot --headless -s tools/smoke/availability_smoke.gd -- --seed 12345 # M5-003: who can raid + prep decisions
godot --headless -s tools/smoke/action_resolver_smoke.gd -- --seed 12345  # M5-004: the five weekly lanes
godot --headless -s tools/smoke/multiweek_smoke.gd -- --seed 12345 --weeks 3  # M5-005: the whole loop, repeated
godot --headless -s tools/smoke/save_load_smoke.gd -- --seed 12345    # M5-006: save round-trip + newer-build refusal
godot --headless -s tools/harness.gd -- --pulls 150 --assert-contracts   # every boss vs its OWN contract (MI-009)
godot --headless -s tools/harness.gd -- --probes --pulls 150             # does raid prep DECIDE anything? (MI-009)
godot --headless -s tools/harness.gd -- --pulls 100 --csv user://pulls.csv     # dump per-pull CSV for the balance lab
git status --short
git diff --stat
```

`--ignoreHeadlessMode` is required: GdUnit4 refuses plain headless runs by default (our tests are pure logic, no UI input). Note for headless `-s` entry points: project GDExtensions (godot-sqlite) are not auto-loaded — call `GDExtensionManager.load_extension()` first (idempotent; see `tests/addon_smoke_test.gd`).

Lint/format + seed checks (gdtoolkit installed once via `uv tool install gdtoolkit`):

```bash
gdformat --check sim/ game/ tests/ tools/smoke/    # format check (drop --check to apply)
gdlint sim/ game/ tests/ tools/smoke/              # lint
# If Windows Smart App Control blocks the .exe shims, use the module form
# (same checks): python -m gdtoolkit.formatter / python -m gdtoolkit.linter — see CLAUDE.md
python tools/seed_check.py                   # seed integrity (stdlib Python, no Godot)
```

CI (`.github/workflows/ci.yml`) runs exactly these commands — a `lint` job
(gdtoolkit + seed_check) and a `test` job (import, load smoke, GdUnit4,
migration + seed smokes) in the pinned `barichello/godot-ci:4.7` container.
If you change a command here, change it there too.

Caveats: run `godot --headless --quit` with the Godot **editor closed** (an
open editor session blocks project-run mode; the `-s` smokes work regardless).
If a tool/addon is not installed yet, report that directly and run the checks
that are available. Never fake green output.

## Ground rules (see CLAUDE.md for the full list)

- Seeded RNG only — same seed + same inputs = same outcome. No scattered `randi()`/`randf()`.
- Content as data — classes, encounters, events, loot are seed rows, never hardcoded.
- All game content is IP-original (see `docs/guildmaster-naming-bible.md`).
- One ticket at a time; do not commit unless explicitly asked.
