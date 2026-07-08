# AGENTS.md — Guildmaster: Progression Night

Guardrails for AI coding agents (Cursor Codex, Codex CLI, and any other LLM agent) working in this repo.

> **Read [`CLAUDE.md`](CLAUDE.md) first — it is the canonical contract.** This file is a short pointer to it. If the two ever disagree, `CLAUDE.md` wins.

## What this is

A **Godot 4.7** management sim — *"Football Manager for old-school MMO raid guilds."* GDScript only. The player runs a raiding guild (recruit, schedule, prepare a 20-raider lineup from a ~28-person roster, resolve raid nights through a deterministic combat-log engine, distribute loot, manage morale/fairness/burnout, survive season objectives). The player does not fight directly.

## Before you edit (every ticket)

1. Read `CLAUDE.md`.
2. Read `docs/guildmaster-overview.md` and the specific system doc for your ticket (see the doc map in `CLAUDE.md`).
3. Run `git status --short`.
4. Identify the exact files to touch. Keep changes ticket-scoped.

## Non-negotiable architecture rules

- **GDScript only.** No C#, no C++, no new plugins/deps unless the ticket explicitly asks.
- **Pure, seeded sim core.** Simulation code in `sim/` must be callable without the scene tree — prefer pure functions like `(input_state, seed) -> outcome`. UI/presentation lives in `game/`.
- **Seeded RNG only.** No `randi()`/`randf()`/`RandomNumberGenerator.new()` scatter. Every random draw flows from `GAME_STATE.rng_seed` through passed-down RNG streams. Same seed + same inputs = same outcome.
- **Content as data.** Classes/specs, encounters, events, loot, consumables, objectives, actions are **seed rows** (`data/seeds/`, slug-keyed) loaded via numbered migrations (`data/migrations/`). Never hardcode content into engine logic.
- **SQLite is the save.** One DB = one campaign. Migrations are numbered `.sql` files.
- **Signals / EventBus for cross-system coupling.** Autoloads are explicit singletons only (`GameState`, `EventBus`, `RNG`, DB services) — no god-object.
- **Observability is gameplay tooling.** Preserve audit trails: `PULL_EVENT`, `WEEK_ACTION`, `TREASURY_LEDGER`, `LOOT_CLAIM`.
- **Tests for sim/logic.** Prefer GdUnit4; add Python seed checks where useful.
- **IP-safe fantasy.** Invent every proper noun (see `docs/guildmaster-naming-bible.md`).

## Repo layout

```
sim/    pure sim core (no scene-tree deps)
game/   scenes, UI, themes
data/   seeds/ (slug-keyed) + migrations/ (0001_init.sql, ...)
tools/  harness.gd, seed_check.py, smoke/, balance_lab/
tests/  GdUnit4
docs/   canonical design docs
```

## Working contract

- Implement **one ticket at a time**. Do not invent new systems, rename architecture, or expand scope.
- Do not add hidden randomness or bake seed content into engine logic.
- **Do not commit unless the user explicitly asks.** Report: summary, files changed, checks run + exact outcomes, blockers.
- If a tool/addon isn't installed yet, say so exactly and continue with the checks that are available. **Never fake green test output.**

## Common commands (run from repo root)

```bash
godot --headless --quit                                              # project-load smoke
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/    # tests (once GdUnit4 installed)
python tools/seed_check.py                                           # seed integrity (once it exists)
gdformat --check sim/ game/ tests/ && gdlint sim/ game/ tests/       # lint/format (once gdtoolkit installed)
git status --short && git diff --stat
```
