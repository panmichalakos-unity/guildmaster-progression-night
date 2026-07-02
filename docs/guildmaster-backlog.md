# Guildmaster: Progression Night — v1 Build Backlog

The design → build bridge. Ordered milestones sized for solo work around a job and family.

## How to run this (sustainability first)
- **Cadence over deadlines.** A few focused hours/week is enough. The plan survives interruption.
- **Every milestone is independently demoable** and park-and-resume friendly — pick it up after a busy week without re-loading everything.
- **No milestone needs a marathon.** If one feels big (M3), it's pre-split into sub-steps.
- **Prove fun before breadth.** Phase A ends in a hard gate; don't build Phase B until the slice is fun.
- **Sizing is relative** (S / M / L / XL ≈ effort), never a promise.

## The shape
```
Phase A  (M0–M4)  ──▶  ★ FUN GATE ★  ──▶  Phase B (M5–M9)  ──▶  Phase C (M10–M11)
vertical slice          is it fun?         complete v1 loop        depth & meta
                                           (Early Access cand.)    (post-launch / v1.1)
```

---

## Phase A — Vertical Slice · *prove the loop is fun*

| # | Milestone | Definition of done | Size | Depends |
|---|---|---|---|---|
| **M0** | Foundation & schema | Stack confirmed (desktop app + SQLite, per data-model); repo + CI; **v1-core tables as migrations**; seed-loader plumbing; empty app runs & migrates. | M | — |
| **M1** | Seed-data starter kit | 6 IP-safe classes × 3 specs (role-coverage matrix per content doc); utilities + synergy tags; a few consumables; **one raid, 3–4 encounters** (phases + core-7 event placements, incl. melee/ranged selectors) + loot table. Loads clean. | S–M | M0 |
| **M2** | Roster generation | Generate a believable ~28 roster (20-raid + bench): Players (traits, life presets, **correlated to avoid grey-goo**) + Avatars (class/spec/gear/familiarity). Inspectable. | M | M1 |
| **M3** | Resolution engine | Run a pull → kill/wipe + `wipe_reason` + per-raider `performance_rating` + combat log. *Pre-split below.* | XL | M2 |
| **M4** | Slice UI + **Fun Gate** | Pick raid-night roster + assignments → watch the combat-log feed → read the post-night report. **Playable single raid night end-to-end. Stop and evaluate fun.** | L | M3 |

**M3 sub-steps** (each independently testable — keeps it off the marathon path):
- **M3a** — contribution → lanes → checks (DPS/heal/tank/mechanic) → `margin → sigmoid`. Deterministic core.
- **M3b** — phase timeline + the core-7 events firing (incl. assigned-duty + cooldown).
- **M3c** — `performance_rating` + the learning arc (`encounter_progress`) + state writes.

---

## Phase B — The Season · *the complete v1 loop (Early Access candidate)*

| # | Milestone | Definition of done | Size | Depends |
|---|---|---|---|---|
| **M5** | Turn loop, calendar & genesis | FM event-day stepping over the weekly calendar (days + time slots); guild-genesis / new-game flow on the `GAME_STATE`/`GAME_CONFIG` save root; the 5 lanes + action resolver; availability; decision inbox + weekly digest. Play multiple weeks; roster gears/improves. | L | M4 |
| **M6** | Loot & consequences | Council + DKP + /roll; the 7-factor claims panel; award ripples into morale/loyalty/fairness. | M–L | M5 |
| **M7** | Economy | Treasury; donation income (culture-scaled); proceeds; repairs; the 3 policies. Provision funds consumables; death-spiral possible. | M | M6 |
| **M8** | Recruitment & roster churn | The `PROSPECT_ASSESSMENT` overlay; all 4 channels; source → assess → trial → sign under fog; weekly **population tick** + **attrition leave-check**. | M | M5 |
| **M9** | Season, objectives & stakes | Objectives issued → season-end grading (rising bar); **rival ladder** + server standings; sacking → **rebuild** (reuses genesis); career summary + **endless mode**. | M | M5 |

---

## Phase C — Depth & Meta · *post-launch / v1.1*

| # | Milestone | Definition of done | Size | Depends |
|---|---|---|---|---|
| **M10** | Social depth & drama | Chemistry *effects* wired into resolution; quirks; `DRAMA_EVENT` catalogue; loyalty/morale drift fully expressed. Emergent drama across a season. | L | M7 |
| **M11** | v1.1 meta | Multi-expansion cycle + catch-up reset; optional Player-Guildmaster; resistance & quirk events; Soft-Reserve/EPGP; professions. | L | M10 |

---

## Engineering notes (your wheelhouse)
- **Make the sim core a pure, seeded function** `(roster, encounter, seed) → outcome`. Then it's unit-testable, and you can run a **batch balance harness** (N pulls → assert win-rate ≈ the ~60–80% target, catch tuning regressions). Same discipline as data tests, but for game balance. Build the harness alongside M3 — it's the cheapest insurance against a broken feel later.
- **Content as data** — seed files (YAML/JSON) versioned in-repo, loaded via migrations. New classes/bosses/events = new rows, engine untouched. (Your dbt-seed instinct applies directly.)
- **Persistence** — SQLite for the desktop app; the schema is already lakehouse-shaped, so migrations handle evolution cleanly.
- **Observability is already designed in** — `PULL_EVENT`, `TREASURY_LEDGER`, `WEEK_ACTION` are audit trails. Surface a "why did this happen" debug view early; it doubles as your dev tooling.
- **`GUILD_CONFIG` is already merged in the model (v0.8)** — build it unified from the start.

## First concrete action (M0)
Translate the **v1-core table list** from the data-model doc into SQLite migrations, and stand up the seed-loader. That single step turns eight design docs into a running skeleton.

---

*v1 backlog — a plan, not a contract. Re-scope freely as the slice teaches you what's actually fun.*
