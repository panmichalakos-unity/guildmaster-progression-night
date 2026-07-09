# Build Decisions (ADR log)

Running log of build-time decisions that aren't captured in the design docs. One entry per decision, newest last. Format: ID · date · decision · why · consequences.

---

## ADR-0001 · 2026-07-02 · Stack locked

**Decision:** Godot **4.7** (pinned) · GDScript only · SQLite via `godot-sqlite` (one DB = one campaign save) · GdUnit4 + headless harness for tests · gdtoolkit for lint/format · GitHub Actions CI.
**Why:** Per `docs/guildmaster-stack-and-tooling.md` — best UI toolkit for panel sims, one language, lakehouse-shaped schema maps cleanly to SQLite, everything free.
**Consequences:** No C#/C++/plugins without a ticket that asks for them. Engine upgrades require a new ADR.

## ADR-0002 · 2026-07-06 · Agent guardrail files

**Decision:** Added `AGENTS.md` (Codex CLI convention) and `.cursor/rules/guildmaster.mdc` (`alwaysApply: true`) pointing at `CLAUDE.md` as the canonical contract.
**Why:** Coding agents should load project rules even when a full ticket body isn't pasted.
**Consequences:** If guardrails ever disagree, `CLAUDE.md` wins; keep the two pointer files thin.

## ADR-0003 · 2026-07-07 · Repo skeleton normalized (M0-001)

**Decision:** Created the target structure from `CLAUDE.md` (`sim/`, `game/`, `data/seeds/`, `data/migrations/`, `tools/`, `tests/`, `assets/`) with `.gitkeep` markers. Legacy empty scaffold dirs (`scenes/`, `scripts/`, `resources/`) left in place but unused — new work goes in the target structure.
**Why:** M0-001 acceptance criteria; pure sim core (`sim/`) must stay scene-tree-free and separately testable.
**Consequences:** `assets/` is Git-LFS-tracked by extension patterns in `.gitattributes`; only curated assets are committed (raw AI output stays out of the repo).

## ADR-0004 · 2026-07-07 · Addons installed: godot-sqlite v4.7 + GdUnit4 v6.1.3 (M0-002)

**Decision:** Installed `godot-sqlite` **v4.7** (2shady4u, GDExtension, `compatibility_minimum 4.5`) and `GdUnit4` **v6.1.3** (now at `godot-gdunit-labs/gdUnit4`) into `addons/`. GdUnit4 editor plugin enabled in `project.godot`. Kept only **Windows + Linux x86_64** godot-sqlite binaries (~14 MB); dropped macOS/iOS/Android/web binaries incl. two ~135 MB iOS `libgodot-cpp` xcframeworks (full addon would be 320 MB).
**Why:** Locked targets are Windows dev + Linux CI (macOS deferred, no mobile/web — stack doc). Repo stays clonable; addons/ is not LFS-tracked.
**Consequences:** Exporting to a dropped platform requires re-adding its binaries from the upstream release (`v4.7/bin.zip` + `demo.zip`). Upgrading either addon gets a new ADR.

**Two facts every headless/CI consumer must know (found the hard way in M0-002):**
1. GdUnit4 refuses plain headless runs — the canonical test command is `godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/` (CLAUDE.md + README updated; M0-007 CI must match).
2. Headless `-s` script runs do **not** auto-load project GDExtensions in Godot 4.7 — the `SQLite` class (from `res://addons/godot-sqlite/gdsqlite.gdextension`) is only available after an idempotent `GDExtensionManager.load_extension()` guard. Pattern lives in `tests/addon_smoke_test.gd::_ensure_sqlite_loaded()`; **M0-004's migration service must reuse it** in its headless entry point.

## ADR-0005 · 2026-07-07 · v1 core schema decisions (M0-003, `0001_init.sql`)

**Decision:** Translated the v1 Prototype Spine (data-model v0.8) into `data/migrations/0001_init.sql` — 50 game tables + `schema_migration` bookkeeping. Physical names are `lower_snake_case` (SQLite matches identifiers case-insensitively, so doc-style `UPPER_CASE` queries still work). Seed/content tables carry immutable `slug` + renameable `display_name` (naming-bible convention); runtime entities use integer ids.

**Deliberate deviations from the literal spine list** (each cross-validated against the system docs):
1. **`pull_consumable` added** — omitted from the spine's in-v1 list but required by G7/G12 (readiness review) and the raid-prep v1 consumable plan; M7-003 depends on it.
2. **`synergy_tag` + `spec_synergy_tag` added** — spine says defer, but backlog M1 DoD ("utilities + synergy tags"), the v1 content table ("~5 synergy tags"), and the naming bible (5 named tags) all put them in v1. Spine is the outlier.
3. **`week_action.action_type_id` added** — the ERD draws `ACTION_TYPE → WEEK_ACTION` (v0.7) but the older v0.4 column list predates it.
4. **`loot_item.slot` → `slot_id` FK** to `slot` (relational 7-slot model), and **`loot_item.encounter_id` nullable** — Marks-vendor gear and generated starting gear (M2-003) don't drop from bosses.
5. **`schema_migration` table** instead of `GAME_STATE.schema_version` (stack-doc sketch) — `game_state` has no row until genesis, so a migrated-but-empty DB needs trackable state. M0-004 records applied filenames here.

**Structural constraints downstream code can rely on:** one active avatar per player (partial unique index); `game_state` singleton (`CHECK game_id = 1`); one scheduled event per (week, day, time_slot); `raid_assignment` PK includes `assignment_type` (an avatar can hold interrupt duty AND a consumable plan); `pull.attempt_number` unique per (event, encounter); `performance_rating` CHECK 1–10; `relationship` bans self-reference.

**Enum spellings the M1/M5 seeds and services MUST match (CHECKed in schema):** time slots `afternoon/evening/late` · event types `raid/dungeon/rest/social` · lanes `gearing/development/supply/people/rest` · assignment types `tank/heal_focus/interrupt/soak/cooldown/consumables` · loot systems `council/dkp/roll` · policies `guild_funded/subsidized/byo`, `mandatory/suggested/voluntary`, `guild_covered/not_covered` · involvement `manual/assisted/instant` · membership status `applicant/trial/member/former` · objective results `exceeded/met/missed/failed` · target selectors `tank/healer/melee/ranged/random/assigned` · ledger txn types `donation/proceeds/farming/provision/repair/purchase/conversion`. Extending any enum = a new numbered migration, not an ad-hoc edit.

**Consequences:** M0-004 must run `PRAGMA foreign_keys = ON` per connection and wrap migrations in transactions. Deferred v1.1 tables (`quirk`, `player_quirk`, `avatar_resistance`, `drama_event`) arrive as new migrations in M10/M11; `relationship` ships now but is write-only until M10.

## ADR-0006 · 2026-07-08 · Migration service pattern + a dev-machine caveat (M0-004)

**Decision:** `sim/db/migrator.gd` (pure static `Migrator`, no scene-tree deps) owns DB opening and migrations: idempotent extension guard → open with `foreign_keys` ON → apply pending `data/migrations/*.sql` in filename order, one transaction per file, recording filenames in `schema_migration`. Failures name the offending file and roll back. Headless smoke: `godot --headless -s tools/smoke/migrate_smoke.gd`. Probed godot-sqlite v4.7 facts the design relies on: `query()` executes multi-statement scripts; `error_message` carries the SQLite error; the `foreign_keys` property works. **Convention: migration files must not contain their own BEGIN/COMMIT** (the runner owns transactions).

**Dev-machine caveat — ROOT CAUSE FOUND & FIXED (2026-07-08):** `godot --headless --quit` hung on *any* project because the CLI shim pointed at the **Steam build** of Godot: launching that exe directly bounces through the Steam launcher, which pops a "how do you want to open Godot" launch-option dialog — invisible and unanswerable in headless runs, so the process waits forever. (Diagnosed by elimination: pristine copies and a brand-new minimal project hung; `-s`/`--import` modes worked; Panos observed the popup interactively.)
**Fix:** `~/.local/bin/godot` now points at the **official pinned `Godot_v4.7-stable_win64_console.exe`** (installed at `~/.local/godot-4.7/`, console build for reliable CLI pipes; Steam shim backed up as `godot.steam.bak`). Same engine commit as the Steam build (`5b4e0cb0f`) — full version/determinism parity. The Steam editor remains fine for interactive use; all CLI/CI-style verification uses the official binary. Full battery re-verified on it: `--quit` exits cleanly, GdUnit 9/9, migration smoke PASS.

**Second mechanism found (2026-07-08, M0-006):** even on the official binary, **project-run mode (`--headless --quit`) hangs while a Godot editor has the project open and busy** (fresh editor session importing/holding the project); `-s` script mode, `--import`, GdUnit, and all smokes are unaffected. Local rule: run `-s`-based smokes freely; run `godot --headless --quit` only with the editor closed (CI containers have no editor and are unaffected). Once M4-001 adds a main scene, the `--quit` smoke gains real value — revisit then.

## ADR-0007 · 2026-07-08 · Seed format: CSV rows + JSON manifest, slug refs, true upserts (M0-005)

**Decision:** Seeds are **CSV files (one per table)** listed by **`data/seeds/manifest.json` in dependency order**, loaded by `sim/db/seed_loader.gd` in a single all-or-nothing transaction. Full convention in `data/seeds/README.md`.
- **Slug natural keys everywhere; seed files never carry integer ids.** FK columns are authored as `*_slug`; the manifest's `refs` entries declare the resolution (`{"column": "class_slug", "table": "class", "as": "class_id"}`), which also covers FK names that differ from the ref table (`utility_slug` → `raid_utility` → `utility_id`). Bridge tables declare `"key": [...]` for their composite upsert key.
- **True UPSERT (`ON CONFLICT ... DO UPDATE/DO NOTHING`), never `INSERT OR REPLACE`** — reloads are idempotent and integer PKs stay stable, so FKs written by earlier loads never dangle.
- **Types come from the schema** (`pragma_table_info` coercion; empty cell → NULL), so CSV needs no type annotations and Python checks (M0-006) can validate the same way.
- Structural seeds shipped now: `role.csv` (4 roles), `slot.csv` (7 gear slots) — fixed by the design docs, needed by M1 anyway.

**Why CSV+JSON:** dbt-seed idiom (git-diffable rows), `FileAccess.get_csv_line()` built in, trivial for `seed_check.py`; the manifest needs nesting → JSON.
**Consequences:** M1 tasks fill this format in (no parallel formats). Known M1-002 decision point: `encounter_event` → phase refs need either a `slug` on `encounter_phase` via a new migration (preferred) or composite-key ref support — decide there. Loader distinguishes "ref table empty" (per-row unknown-slug error) from "ref table missing/no slug column" (structural error).

## ADR-0008 · 2026-07-08 · CI quality gate + local/CI parity contract (M0-007)

**Decision:** `.github/workflows/ci.yml` runs two jobs on push/PR — `lint` (ubuntu, Python 3.12: `gdtoolkit==4.5.*` format+lint, then `tools/seed_check.py`) and `test` (container **`barichello/godot-ci:4.7`**, pinned to the local engine: import → project-load smoke → GdUnit4 with `--ignoreHeadlessMode` → migration smoke → seed smoke). Scope is quality only; export/release jobs arrive at EA prep. The M3-005 balance-harness gate is a commented TODO.
**Parity contract:** every CI command mirrors a documented local command (README "Commands" + CLAUDE.md) — change one, change both. Local gdtoolkit is installed via `uv tool install gdtoolkit` (isolated; gdformat/gdlint 4.5.0); the whole codebase was formatted with it and gdlint is clean, so CI is born green.
**Notes:** lint paths are `sim/ tests/ tools/smoke/` (grows with `game/` at M4). CI containers run no editor, so the ADR-0006 editor-contention caveat does not apply there. First real push should confirm the container behaves like local; adjust then if needed.

## ADR-0009 · 2026-07-08 · Class/spec/utility seed content + two authored judgment calls (M1-001)

**Decision:** Seeded the full naming-bible kit verbatim: 6 classes, 18 specs (3/4/5/6 role matrix), 8 raid utilities with the bible's exact provider lists (21 `spec_utility` links, incl. "any Channeler" → Stormsurge and "any Vanguard" → Warbanner), 5 synergy tags. Six specs (Judicator, Oakhide, Thornclaw, Umbral, Deadeye, Hexweaver) intentionally bring **no** utility — the bible's scarcity is the comp puzzle; `seed_check` warns on them by design.
**Two things the bible does NOT specify, authored here as first passes (retune freely, they're seed rows):**
1. **`spec_difficulty` values** — symbolic 45–75 band around the schema default 50 (e.g. Warblade/Radiant 45 = entry specs; Hexweaver 75 = highest ceiling). Only relative order is meant to carry signal; the M3-005 harness is the real judge.
2. **`spec_synergy_tag` mapping** (14 links) — thin comp vocabulary derived from class identities (caster/melee cleave by damage profile, Mana Battery = Wellspring providers, Threat Support = Vanguard melee, Magic Amplify = Umbral/Hexweaver). v1 reads tags only for comp warnings; effects are v1.1.
**Consequences:** M2 avatar assignment and M4 comp warnings must consume these rows via joins — never re-declare class/spec lists in code. Tests that count bridge rows assert deltas, not absolutes (real seeds pre-populate tables).

## ADR-0010 · 2026-07-08 · Emberdeep encounter seeds + two deliberate schema edits (M1-002)

**Decision:** Seeded the world spine (`expansion` Aethermoor: Crownfall → `season` Tier 1 → `raid` The Emberdeep) and the **first 4 of 6 Emberdeep bosses** per the naming bible's mechanical identities (Phase-A scope is 3–4): Gatewarden Krogg (tank-check gate, 1 phase), Forgemaster Vell (assigned-duty interrupts, **ranged-punisher**, 2 phases), The Slagbeast (healing-sustain wall, **melee-punisher**, 2 phases), The Cinderlords (council: soak duties + cooldown windows, 2 phases). Plus the **core-7 `event_type` palette** (avoidable_death, clutch_save, near_death, cooldown_moment, cascade_death, assigned_duty, tank_swap) with triggers/roll attributes/log templates from the resolution doc, and **21 `encounter_event` placements**. Bosses 5–6 (Ashpriestess Morvane, Ignarok) arrive with the Phase-B tier completion.

**Two deliberate `0001_init.sql` edits** (pre-genesis direct edit per the M0-003 ticket rule — no shipped DBs exist, all test/smoke DBs are disposable):
1. **`encounter_phase.slug`** (unique) — natural key so `encounter_event` seeds can reference phases; keeps the loader generic (no composite-key refs needed).
2. **`encounter_event.target_selector`** (nullable, CHECKed) — per-placement override of the event type's default selector; NULL = inherit. This is how a boss gets a **range profile** (resolution doc) while the event-type count stays at the locked 7. M3-003 must read placement selector `COALESCE`d with the type default; M4 comp warnings derive range balance from these placements.

**Tuning is symbolic:** `dps_check`/`healing_check`/`difficulty` ramp 35→60 across boss_order; severities 35–70; weights 80–140. The M3-005 harness is the judge; retune freely — these are seed rows.

## ADR-0011 · 2026-07-08 · Loot, consumables & the tuning seed (M1-003)

**Decision:** Seeded **23 `loot_item` rows** — 16 boss drops (4 per Emberdeep boss, exactly 4 per role, item level ramp 28→34 by boss_order, named via the bible's `[Theme][Slot noun]` formula from the T1 pool + two named-unique weapons: *Stormanvil, Vell's Hammer* and *Emberbrand, the First Flame*) and the **Expeditionary Marks-vendor set** (7, one per slot, ilvl 26 — below current-tier drops, above entry bar; `marks_cost` 75/90, `encounter_id` NULL). Plus the bible's **10 consumables verbatim** (3 premium flasks, 7 basic) and **`data/seeds/tuning.json`** — the balance-lab constants file (resolution sigmoid scales + 0.6–0.8 win-rate band, gear spec-fit multiplier, consumable bonuses, genesis defaults). tuning.json is config seed data read directly by sim code, not a DB table (not in the manifest).
**First-pass vocabulary authored here (retune freely):** `spec_fit_tag` values — `tank_plate / melee_physical / ranged_physical / caster / healer_focus` (Deadeye is the ranged-physical outlier; M6-005's fit multiplier consumes these).
**Consequences:** ALL seed_check M1 coverage rules are now active and green (6 classes, 18 specs 3/4/5/6, ≥7 event types, raids ≥3 encounters, encounters ≥3 loot rows). M2-003 generates starting gear as generated `loot_item`-compatible rows or below-vendor ilvl items; M3 reads `tuning.json` resolution keys; changing tuning KEY NAMES requires a cross-validated ticket (values are free).

## ADR-0012 · 2026-07-08 · RngStream: named hierarchical streams + the GlobalScope shadow trap (M2-001)

**Decision:** `sim/rng/rng_stream.gd` (`RngStream`) is THE one RNG pattern for sim code. Named streams derive from the master seed (`RngStream.derive(seed, "roster_gen")`) via our own **FNV-1a 64** (not `String.hash()` — derived seeds can never shift under an engine upgrade); `substream("traits")` forks hierarchically WITHOUT advancing the parent, so systems cannot perturb each other's sequences. Draw API: `randi_range/randf/randf_range/randfn/pick/weighted_pick/shuffle`, plus `draw_count` and `stream_path` for observability/repros. `tests/helpers/sim_fixture.gd` (`SimFixture`) is the sim test pattern: `new_campaign_db()` (migrated+seeded :memory:), `rng(name)` off `TEST_SEED`, run-twice-compare determinism proofs. Sim code must accept `(input_state, rng)` explicitly.

**Trap found & fixed (regression-guarded):** inside a GDScript class, an UNQUALIFIED call like `randf_range(...)` can bind to the **unseeded `@GlobalScope` function** instead of the class's own method — hidden global randomness inside the RNG class itself. Caught immediately by the lockstep determinism test (`draw_count` stayed 0 while sequences diverged). Rule: **inside RngStream, every internal draw is `self.`-qualified**; tests assert exact `draw_count` so a binding regression fails loudly. Sim code elsewhere always draws through a held stream object (`rng.randf()`), which is naturally qualified — but never name a sim function `randf`/`randi_range`/etc.

## ADR-0013 · 2026-07-08 · Roster generation: latent factors, not independent dice (M2-002)

**Decision:** `sim/roster/roster_gen.gd` (`RosterGen`) generates PLAYER rosters as a pure `(presets, count, rng) -> players` function. Anti-grey-goo model: every trait derives from **four latent factors + bounded noise** — `talent` (stratified star/core/fringe tiers so every roster has aces, a middle, and projects), `steadiness` (consistency/loyalty/coachability up; volatility/ego down), `drive` (growth/influence/ego up; burnout hotter), and `experience` (from the life preset: young_gun ≈25 vs veteran ≈80 — raises current skill/influence/loyalty, lowers potential headroom/growth/coachability). Life presets stamp availability windows + volatility/burnout/loyalty mods. `loyalty_current` starts AT `loyalty_baseline` (conventions Shape A anchor). Distribution parameters live in `tuning.json` `roster` (tiers, shares, experience map, preset weights); derivation coefficients are generator shape in code.
**Also:** `data/seeds/life_situation.csv` — the 6 canonical presets (single/student/working_parent/shift_worker/veteran/young_gun), which no M1 ticket owned; gated in seed_check ("exactly 6"). `sim/roster/name_gen.gd` (`NameGen`) — the naming bible's three weighted handle pools (root+suffix 55 / compound 30 / human-leak 15, collision → digit suffix). `sim/core/tuning.gd` (`Tuning`) — shared cached loader for tuning.json.
**Consequences:** M2-003 assigns avatars WITHOUT touching PLAYER semantics (strict boundary); M8-001 population tick reuses `RosterGen`+`NameGen` (do not fork). Correlation gates live in tests (execution↔awareness > 0.25 etc. over n=300) — retuning coefficients must keep them true or consciously change them.

## ADR-0014 · 2026-07-09 · Avatar assignment: role plan, template starter gear, additive gear_score (M2-003)

**Decision:** `sim/roster/avatar_gen.gd` (`AvatarGen`) assigns each player one active avatar. **Role plan** fills tuning `roster.role_targets` (4 tank / 7 healer / 8 melee / 9 ranged for 28 — a 20-lineup of 2–3T/5H/13D with bench depth on every axis), deterministically shuffled so role never correlates with roster order; spec picked uniformly among that role's seed specs. **Starter gear = 7 template rows** in `loot_item.csv` (`starter_*`, "Worn Helm"…, encounter NULL, marks 0) with the actual level on `avatar_item.item_level` — the denorm column carries per-avatar variance, zero generated-row pollution. **`gear_score` = SUM of equipped slot levels** — an upgrade's power delta is exactly its slot delta (the gear-doc contract M6-005 builds on); `avatar.item_level` = rounded average. Caps use a placeholder threshold rule (hit_capped ≥20 avg, uncrittable = tank ≥22) until M6-005 owns caps-from-gear — starting tanks sit near the uncrittable line ON PURPOSE (Gatewarden Krogg is the gear gate). `player_role_proficiency` generated here (assigned role strongest, one secondary, others weak — anchored on execution); `familiarity` inversely tied to `growth_rate` (seasoned players know their spec). Role ids derived from seed rows, never hardcoded.
**Consequences:** M4 lineup UI and M3 resolver consume avatar rows + `role_slug`; M6-005 replaces the caps placeholder; M8-001 reuses the full RosterGen→AvatarGen chain for prospects.

## ADR-0015 · 2026-07-09 · Roster inspection: shared read model + fingerprint determinism (M2-004)

**Decision:** `sim/roster/roster_report.gd` (`RosterReport`) is the ONE roster read model — `build(db)` returns structured data (players joined with avatar/spec/preset, role coverage, utility provider counts, issue flags for 20-lineup minima and comp gaps); `to_text()` renders it for terminals with an **FNV-1a fingerprint** line (`RngStream.fingerprint()` made public for this). The M4 lineup UI must consume `build()`, not re-interpret roster tables. Harness: `godot --headless -s tools/smoke/roster_smoke.gd -- --seed N` prints the roster and self-proves determinism by rebuilding the entire chain (migrate→seeds→players→avatars) in a second fresh DB and comparing rendered output.
**Golden-test judgment call:** no stored golden hashes (they break on every intentional coefficient retune). Instead: whole-chain cross-DB identity tests + the printed fingerprint for eyeball/machine diffing across runs and machines.
