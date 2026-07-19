# Guildmaster: Progression Night — Stack & Tooling (v0.1)

Everything needed to deliver end to end, solo, sustainably. Locks the engine decision and the AI-art policy; adds the full toolchain, repo layout, CI, PM, and release path. Free unless marked €.

## Stack summary (locked)

| Layer | Choice | Why |
|---|---|---|
| Engine | **Godot 4.x** (latest stable; **pin the version** in README + CI) | Best UI toolkit for table/panel sims; GDScript ≈ Python; free/OSS; trivial Steam export |
| Language | **GDScript** (sim core + UI) | One language, near-zero ramp from Python. Fallback: Godot C# if it grates after a week |
| Save/data | **SQLite** via `godot-sqlite` addon | One DB = one save (as designed); migrations as numbered `.sql` |
| Testing | **GdUnit4** (unit) + headless batch harness | Sim core is a pure function → CI-testable |
| Balance lab | **Python 3.12 + uv** · pandas · **DuckDB** · notebooks | Harness dumps Parquet/CSV → query with DuckDB, tune in pandas. Your home turf |
| Lint/format | **gdtoolkit** (`gdformat`, `gdlint`) | pip-installable; enforced in CI. *UPDATE 2026-07-17: on the dev machine Windows Smart App Control blocks the unsigned `.exe` shims — invoke as `python -m gdtoolkit.formatter` / `python -m gdtoolkit.linter` (same checks; documented in CLAUDE.md)* |
| Editor | **VS Code** + Godot Tools ext (LSP) | Keep your muscle memory; Godot editor for scenes only |
| VCS | **GitHub private** + **Git LFS** for `assets/` | LFS free tier = 1 GB — ship only *curated* assets; raw AI output stays out of repo |
| CI/CD | **GitHub Actions** (godot-ci docker image) | Test + seed-check on push; export builds on tag |
| PM | ~~GitHub Projects kanban (rec.)~~ **UPDATE: Notion Kanban** ("Guildmaster v2" board — link in CLAUDE.md) | Paste-ready ticket bodies per task; Hermes/agents sync statuses + completion reports |
| Docs | ~~The 16 design docs~~ **26 docs** in `/docs`, version-controlled | Mermaid renders on GitHub; `decisions.md` carries the ADR log (0001→present); see the overview's doc map |
| Playtest channel | **itch.io** (private) + `butler` CLI | Pre-Steam builds for friends/testers |
| Release | **Steam** via GodotSteam addon + SteamPipe (`steamcmd`) | €100 app fee (recoupable ≥ $1k revenue) |

## Repo skeleton
```
guildmaster/
  project.godot
  sim/                # PURE sim core — no scene-tree deps: resolve_pull(), action_resolver(), gen_roster()
  game/               # scenes, UI, themes
  data/
    seeds/            # CSV/JSON, slug-keyed (naming bible)
    migrations/       # 0001_init.sql, ...
  tools/
    harness.gd        # headless: N pulls → Parquet/CSV
    seed_check.py     # dbt-style seed tests: FK integrity, enums, uniqueness, coverage
    balance_lab/      # notebooks + DuckDB queries over harness dumps
  tests/              # GdUnit4
  docs/               # the design doc set + decisions.md
  assets/             # LFS: art, audio, fonts + CREDITS.md (CC-BY attributions)
  .github/workflows/ci.yml
  .gitattributes      # LFS patterns
```

## Data workflow (your idioms, mapped)
- **Migrations** = numbered `.sql` + a ~40-line GDScript migrator (tracks `schema_version` in `GAME_STATE`). The data-model **v1 spine is the DDL list**.
- **Seeds** = dbt-seed style: slug natural keys, loaded on new-campaign. `seed_check.py` runs in CI: referential integrity, enum domains, uniqueness, and coverage asserts (e.g., "every spec has ≥1 utility or an explicit none", "18 specs", "each T1 boss has ≥3 loot rows").
- **Balance loop** = the killer pattern: **one sim implementation**, run headless → `pulls.parquet` → DuckDB/pandas → adjust constants in a `tuning.json` seed → rerun. No dual codebase, no drift; tuning becomes data work.
- **Determinism contract:** every random draw flows from `GAME_STATE.rng_seed` through passed-down RNG streams — never global RNG. This is what makes the harness and bug repros work.

## CI (GitHub Actions, sketch)
```yaml
on: [push, pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    container: barichello/godot-ci:4.x        # pin same version as local
    steps:
      - uses: actions/checkout@v4
      - run: pip install gdtoolkit duckdb pandas && gdlint sim/ game/
      - run: python tools/seed_check.py
      - run: godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/
      # MI-009: per-boss contract asserts + prep-leverage probes. NOT the old
      # `--assert-winrate LO HI` (removed) — that was ONE global band on boss 1,
      # and it passed green while three of four bosses sat at a 0% win rate.
      - run: godot --headless -s tools/harness.gd -- --pulls 150 --assert-contracts
      - run: godot --headless -s tools/harness.gd -- --probes --pulls 150
  export:
    if: startsWith(github.ref, 'refs/tags/')
    # godot export presets → Windows (primary), Linux (cheap); artifact upload
```

## Art & audio pipeline (policy locked)
- **Dev-time AI generation only; never runtime.** Curated **portrait pool** (200–500 tagged busts) sampled by roster-gen via `portrait_id`.
- **Tools:** ComfyUI (Windows portable build) + **SDXL or Flux.1-schnell (fp8)** — commercial-safe licenses; *always check model + LoRA cards; Flux.1-dev is non-commercial*. **Runs fully local on the RTX 5080 (16 GB VRAM):** SDXL ≈ seconds per 1024² image → the whole over-generated pool (~2,000–2,500 images) is an evening or two of plugged-in batch time. Use a current PyTorch (cu12.8+ wheels) — the early RTX-50/Blackwell incompatibilities are long fixed. **Cloud-GPU branch removed.**
- **Consistency pass** = Python/Pillow batch (crop, palette grade, frame overlay) — this is what prevents "AI slop" reads.
- **Human-made hero art:** Steam capsule + 12 boss splashes commissioned pre-launch (AI drafts as placeholders).
- **Icons:** game-icons.net (CC-BY → `CREDITS.md`). **Fonts:** Google Fonts (OFL). **SFX:** Kenney packs (CC0) + freesound CC0; edit in Audacity. Music: defer/commission.
- **Steam AI disclosure:** tick pre-generated AI content, one honest sentence.
- **Governing rule unchanged: zero art spend before the M4 fun gate** — silhouettes + initials until then.

## Observability
- In-game "why" debug view over `PULL_EVENT` / `TREASURY_LEDGER` / `WEEK_ACTION` (already designed) — build it in M0/M3; it's also your dev tooling.
- File logging per save (Godot logger). Crash/telemetry (Sentry Godot SDK or opt-in webhook → your own stack): **post-EA, opt-in only**.

## Costs
Everything above: **€0** except Steam Direct **€100** (at EA prep), commissioned hero art (later, ~€500–1500 budget line), optional Apple notarization €99/yr (**defer macOS**). The RTX 5080 removes the cloud-GPU line.

## Setup playbook (phased, sustainable)
**Day 1 (~2–3 h):**
1. Install Godot 4.x (pin version), VS Code + Godot Tools, Git + LFS, Python 3.12 + `uv`, DB Browser for SQLite, DuckDB CLI.
2. Create private repo from the skeleton; commit `/docs` (the 16 design docs) + `.gitattributes`.
3. Add addons: `godot-sqlite`, `GdUnit4`. `uv add` pandas/duckdb/gdtoolkit in `tools/`.
4. CI: the `quality` job green on an empty-but-wired project.

### Dev machine (locked): Windows · Razer Blade 16 (2025) · 64 GB RAM · RTX 5080
- **One-shot installs (PowerShell):**
  ```powershell
  winget install Git.Git GitHub.GitLFS Microsoft.VisualStudioCode GodotEngine.GodotEngine `
    Python.Python.3.12 astral-sh.uv DBBrowserForSQLite.DBBrowserForSQLite DuckDB.cli
  ```
- **Line endings (Windows dev, Linux CI):** enforce LF repo-side — `.gitattributes`: `* text=auto eol=lf` (plus the LFS patterns). Avoids CRLF churn in diffs and CI.
- **Optional perf:** Defender exclusion for the project folder (`Add-MpPreference -ExclusionPath "C:\dev\guildmaster"`, admin) — noticeably faster Godot imports/builds.
- **No WSL2 needed** — everything runs native; the Linux CI container covers cross-platform parity.
- **64 GB RAM** = the balance lab never thinks about memory: 100k-pull Parquet dumps fit in-RAM for DuckDB/pandas.
- **Batch-gen thermals:** portrait-pool runs plugged in, performance profile; expect fan noise, nothing else.

**Week 1 — the M0 spike (one evening's goal):** migrations from the v1 spine → seed loader → generate a 20-roster → resolve one hardcoded pull headless → print the combat log. *End-to-end proven.*

**Post-fun-gate (M4+):** ComfyUI + portrait pool · itch.io private playtests (`butler`) · GodotSteam + Steamworks account · export presets + tag-triggered builds.

**Working agreement (solo sustainability):** WIP limit 1–2 tickets · 2–3 evening blocks/week · every session ends on a green CI commit — resumable after any gap.

---

*v0.1 — stack locked (Godot 4 + GDScript + SQLite; Python balance lab; GitHub end-to-end). Revisit only on a fallback trigger (GDScript friction → C#; web-UI drift → Tauri).*
