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

## ADR-0016 · 2026-07-09 · Pull resolver contract: dictionaries, named checks, legibility enforced (M3-001)

**Decision:** `sim/resolution/pull_contracts.gd` (`PullContracts`) defines THE resolver boundary: `PullResolver.resolve(input: Dictionary, rng: RngStream) -> Dictionary` (M3-002 implements). **PullInput** = encounter demands + phases + effective event placements (selector already COALESCEd) + per-participant snapshot (skill facets, gear, caps, state, assignments, consumables) + `encounter_progress` + attempt + tuning. **PullResult** keys map 1:1 onto the fact tables (`pull` → PULL incl. `wipe_reason`, `participants` → PULL_PARTICIPANT with `raw_contribution` + `performance_rating` 1–10, `events` → PULL_EVENT with unique `sequence_no` + `log_line`, `state_deltas` → GUILD_ENCOUNTER_PROGRESS + morale/fatigue/form deltas) **plus one derived surface: `checks[]`** ({check, margin, passed, detail} per the doc's checks catalogue) — the legible-failure record that `wipe_reason` and the M7-005 why-view derive from.
**Validators enforce the design pillars structurally:** a wipe without `wipe_reason` is INVALID ("legible failure is the engine"), a kill with one is invalid, kills must set `drops_loot`, ratings clamp 1–10, event sequence unique, every event's log_line non-empty ("the feed is the show").
**Fixtures:** `tests/helpers/pull_fixtures.gd` — five synthetic 20-raider shapes shared by all M3 tasks (clean_kill / mechanic_failure / dps_pressure / healing_pressure / tank_pressure — the last with deliberately non-uncrittable tanks). Plain Dictionaries over typed classes: matches the project's data style, serializes trivially for the harness, and keeps the boundary engine-agnostic.

## ADR-0017 · 2026-07-09 · Resolution core math: normalization, couplings, the gate (M3-002 / M3a)

**Decision:** `sim/resolution/contribution.gd` (stages 1+2) + `sim/resolution/checks.gd` (stage 3), pure over the M3-001 contracts. Interpretation choices where the doc is symbolic (all overridable via `input.tuning`, defaults mirrored in `tuning.json` `resolution`):
1. **Per-raider lane normalization** — lane output = sum of lane contributions / STARTING lane count, so authored demands (0–100 band) compare directly regardless of comp, while deaths still drag the lane (M3-003 re-aggregates via `exclude`).
2. **Contribution math** — ceiling = avg ilvl × 2.2 · skill = exec 0.5 + proficiency 0.25 + familiarity 0.25, spec_difficulty bites at 0.4 × the shortfall BELOW the skill line only (master shrugs, novice suffers) · realization = 0.35 + skill/100 × 0.6 · situational mods each clamped [0.85, 1.15], product [0.7, 1.3] · variance width = base × (1.5 − consistency/100).
3. **The healing coupling** — demand = healing_check × (1 + avoidable_pressure + tank_wear); avoidable_pressure = max(0, 55 − avg awareness) × rate; tank_wear from main-tank ilvl below par. A sloppy raid strains its healers (tested).
4. **The tank gate** — near-binary via the hard sigmoid (scale 12 vs 25) + a flat **uncrittable_gate_penalty (25)** on the margin when the MAIN tank (assignment target "main", else first tank) is not uncrittable.
5. **Culprit hints in every check detail** ("weakest: ranged_3 (31.0)") — wipe_reason (M3-004) and the why-view consume these.
**Fixture recalibration:** clean_kill moved to gear 260 / demands 20 — its original numbers produced margin ≈ +20, which on the hard curve is only p≈0.84, NOT the "over-geared → one-shot" saturation the doc demands. Fixtures must sit where their scenario claims.
**Consequences:** M3-003 timeline calls these lanes/checks (never duplicates math); M3-005 harness asserts the 60–80% band by sliding demands against a real roster.

## ADR-0018 · 2026-07-09 · Timeline engine + resolution recalibration (M3-003 / M3b)

**Decision:** `sim/resolution/timeline.gd` (`Timeline.run(input, rng)`) walks phases in order, fires each placed ENCOUNTER_EVENT (weight→fire count), and dispatches purely on the seed row's `effect_category` — `death` / `save` / `tension` / `surge` / `duty_check` / `tank_check` — with `target_selector` (tank/healer/melee/ranged/random/assigned) choosing among the LIVING. No boss-specific code; a new boss is new rows. Deaths remove bodies → the final lane re-aggregation (via `substream("contribution")` reused identically, ADR-0012) drops the fallen = cascade. Outcome = the M3-002 checks on survivors + death-collapse, and every wipe names the dominant failed check + culprit (`_WIPE_PRECEDENCE`: tank > collapse > dps > healing > mechanic). Data-driven behaviors: cascade_death only bites after a prior death; clutch_save cancels the phase's most recent death; assigned_duty failure kills a random raider (the unchecked add); the tank gate kills only a non-uncrittable main tank.

**Three real resolution flaws surfaced by the clean_kill=one-shot test (fixed at the source, not by weakening the test):**
1. **Sigmoid scales too wide to saturate** — soft 25 / hard 12 capped even a +40 margin at p≈0.83, so "over-geared → one-shot" was mathematically unreachable. Recalibrated to **soft 12 / hard 7**: matched content (margin≈0) stays a coin flip, but a strong positive margin now saturates (kill) and a strong negative one is decisive (wipe), exactly as the doc's difficulty-via-margin demands.
2. **Lane normalization erased comp as a decision** — dividing by ACTUAL lane size meant 3 healers produced the same HPS as 5. Now lanes divide by a fixed **`reference_comp` (2 tank / 5 healer / 13 dps)**, so thin healing genuinely hurts and stacking a lane genuinely helps.
3. **Tank survival ignored healing** — the doc lists tank-healing as a tank-check input. Added `tank_healing_share` (0.35 of HPS) to tank output, so a dead/thin healer lane drops tanks too.
Also fixed: the M3-001 fixtures carried `effect_category="fixture"` (placeholder) and so drove nothing — mapped event_type_slug → real category/roll_attribute mirroring event_type.csv.

**Consequences:** all resolution constants live in `tuning.json` `resolution`; the M3-005 harness will find the gear level where margin≈0 and assert the 60–80% band there. M3-004 assembles the full PullResult (ratings + learning arc + state writes) on top of `Timeline.run`.

## ADR-0019 · 2026-07-10 · Ratings, the gated learning arc, state deltas, resolver assembly (M3-004 / M3c)

**Decision:** `sim/resolution/rating.gd` + `sim/resolution/pull_resolver.gd` complete the engine.
1. **Ratings are relative:** expected = ceiling × 0.65 (a plain 50-skill raider on that gear); rating = clamp(5.5 + (actual/expected − 1) × 12 + event deltas, 1..10). The night's STORY moves the number: avoidable death −2, missed duty −2, clutch save +1.5, clean duty/surge/near-death-survived +0.5. `raw_contribution` (×10, int) rides alongside for logs/MVP.
2. **The learning arc runs both directions.** Forward: progress bumps familiarity (skill_realization's 25% input) and SHAVES event severity (`severity_learning_rate` in Timeline) — the raid that has seen the fire stands in it less. Back: kill → 100; wipe gain = per-attempt gain × closeness, gated on the **blocking margin — the WORST failed check** (first cut used the closest failed margin; a −160 enrage wall with a coincidental near-miss on healing must teach nothing). Tested deterministically: same seed, progress 90 vs 0 → higher contested margin, ≤ deaths, ≥ kills.
3. **State deltas returned, not applied:** morale (kill +4 / wipe −2, died −1, saved +2), fatigue (+3, +1 extra on wipes — wipes grind), form ((rating − 5.5) × 0.8). The campaign layer (M5) owns `player_week_state` application.
4. **`persist()`** writes the fact rows (`pull`, `pull_participant` with role subquery, `pull_event`) and UPSERTS `guild_encounter_progress` (first_kill_at COALESCEd, set once). `pull_event.phase_id` is NULL for now (contract events carry phase_order; a phase-id map lands when the M4/M5 loader threads real ids). A synthesized `assigned_duty` check row summarizes duty outcomes when duties fired.
**Consequences:** the M3-005 harness drives `PullResolver.resolve` directly; M4's report reads `checks[]`/ratings/log verbatim; M5 applies the returned state deltas weekly. Schema note honored: pull uniqueness is (event, encounter, attempt_number) — callers increment attempts.

## ADR-0020 · 2026-07-10 · Balance harness: contract asserts, not golden numbers (M3-005)

**Decision:** `tools/harness.gd` sweeps every seeded encounter across gear multipliers (0.8→3.0, dense in the transition region) × N seeded pulls on a REAL generated campaign, reporting win rates + top wipe reasons and dumping per-pull CSV for the balance lab. `--assert-winrate LO HI` enforces the difficulty-via-margin contract as three SHAPE properties (not brittle absolute numbers): (1) the 60–80% band is REACHABLE on boss 1 at some gear step; (2) win rates are MONOTONE in gear (slack 0.06); (3) the curve SPANS decisive-wipe (≤25% undergeared) to one-shot (≥90% at next-tier gear). Wired into CI at `--pulls 100`. Also shipped `sim/resolution/pull_input_loader.gd` — the ONE DB→PullInput path (COALESCE selector override, avatar×player×spec×proficiency join, neutral state pre-M5, tuning.json merge); M4 must reuse it.
**Bug the harness caught on run #1:** the loader scaled gear but kept generation-time cap flags — a 3×-geared tank stayed "not uncrittable" forever, walling every deeper boss with tank_survival. Caps now recompute from scaled ilvl via `AvatarGen.CAP_ILVL_THRESHOLD` (M6-005 owns the real rule later).
**Balance-lab finding recorded, deliberately NOT tuned away:** Emberdeep bosses 2–4 are MECHANIC/learning walls, not gear walls (awareness-driven checks that gear cannot buy; win rates 16–29% even at 3× gear, rising with encounter_progress). Era-authentic progression shape; whether the wall heights feel right is a fun-gate/playtest question for M4, answered with this harness + the CSV in hand.

## ADR-0021 · 2026-07-10 · Post-M3 review fixes (6 findings from the b8bdd1c code review)

**Fixed:** (1) `first_kill_at` stored the literal string "now" — now a real UTC ISO timestamp via `Time.get_datetime_string_from_system(true)` (audit column, side-effect layer — deterministic results never contain wall-clock). (2) **`encounter_event.weight` was a dead knob** (every value 50–149 fired exactly once) — weight is now a true firing rate in percent: 100 = exactly once, 60 = 60% of pulls, 140 = once + 40% second shot; consumes one event-stream draw per placement (all same-seed sequences shifted — no golden hashes by design, ADR-0015; suite 105/105 and harness shape-asserts re-verified, matrix moved ≤3 points). (3) Combat-log outcome vocabulary is now `Timeline.OUTCOME_*` constants; RatingEngine's delta table keys on them — a rename breaks at parse, never silently zeroes ratings. (4) Caps-from-gear now has ONE home: `AvatarGen.derive_caps(avg_ilvl, role_slug)` — generation and gear-scaled loads both call it. (5) `PullInputLoader._participants` runs ONE IN-clause query instead of 20 round-trips, re-ordered to lineup order (participant order drives rng draw order). (6) Assigned-duty failure victims exclude the failing assignee ("X misses — X falls" read as a bug).

## ADR-0022 · 2026-07-11 · Intervention: the Fun Gate is not passed; MI blocks M5

**Context.** M4 shipped technically complete (117 tests, all gates green), but `guildmaster-intervention-and-realignment.md` challenged whether technical completion proves the *experience*. It does not. Reproduced and instrumented: the default first session is **32 pulls, 0 kills, 32 wipes**.

**Measured root cause (two compounding faults):**
1. **Content/start-state deadlock.** Boss demands were authored in M1-002 as explicitly "symbolic" numbers, never tied to real roster output. At the actual starting roster (avg ilvl 18.9, gear_score 132) the DPS lane produces 27.6 against Krogg's demand of 40; Tier-1 drops average **ilvl 31**. The entry boss demands roughly the gear it drops — no kill without loot, no loot without a kill.
2. **Conjunctive check aggregation** (found during this analysis, not in the original findings). The four checks are independent rolls that must *all* pass — a healthy raid at p=0.8 each still kills only ~41% of the time. And healing/mechanic failure are **already** modelled by the timeline as cascade/avoidable deaths, so the checks double-count them.

**Decisions (Panos, 2026-07-11):**
- **I-01/I-02 — Fix content AND aggregation.** New milestone **MI (Intervention & Fun Gate)**, which **blocks M5**. Encounter progression contracts per boss; retune so a *starting* roster kills Krogg in ~3–8 pulls after a real intervention; rework aggregation so DPS+tank drive kill-vs-wipe and soft lanes apply pressure. Harness extended to assert each boss against its own contract plus prep-leverage probes.
- **I-03 — Season = Tier (Model A).** One v1 expansion = two seasons, one per tier. Resolves the docs' contradiction; `content-and-dod`'s "14-week season across 2 tiers" bar was wrong and is corrected.
- **I-12 — Phase B-lite.** M5–M9 restaged as product gates: campaign/calendar/save → **Council-only** loot → basic treasury → **applicants-only** recruitment → one tier's objectives. Breadth (DKP//roll, deep economy, remaining channels, recovery valves, rival identity) moves to a new **MB** backlog, pulled in only after the week/season loop plays well.
- Contracts approved and scheduled: raid-night presentation (I-04), diagnostic hierarchy — "culprit" becomes internal shorthand (I-05), performance rating before M6 (I-06), involvement modes as a *contract now* to guide Phase-B UX (I-07), dual-language terminology (I-08).
- **I-10 (quirks/events in v1) deliberately NOT decided** — the doc's own guidance is to decide on playtest evidence after the Fun Gate.

**Consequence.** The Fun Gate is a **human verdict** (MI-010), scored against the card in `content-and-dod`. A weak score means tune/present/clarify — never "add more systems". No Phase-B ticket starts until MI-010 passes.
