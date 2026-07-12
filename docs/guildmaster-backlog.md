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

## MI — Intervention & Fun Gate · *prove the experience before adding breadth* 🔒

**Added 2026-07-11.** M4 shipped technically complete, but the default first session is **32 pulls, 0 kills** — the Fun Gate has *not* passed. Full analysis: `docs/guildmaster-intervention-and-realignment.md`. **MI blocks M5.** Nothing in Phase B starts until the slice demonstrably produces the loop:

> prepare → pull → understand failure → adjust → get closer → **kill** → want another pull

| # | Ticket | Definition of done | Size | Depends |
|---|---|---|---|---|
| **MI-001** | Encounter progression contracts + retune | A written contract per Phase-A boss (position, expected roster state, first-attempt win rate, pulls-to-kill, dominant challenge, **the player intervention that helps**, farm-state rate). Encounters retuned so a *starting* roster can kill Krogg. | M | — |
| **MI-002** | Fix check aggregation | Four independent conjunctive rolls cap even a healthy raid at ~41%; healing/mechanic double-count what the timeline already punishes via cascade/avoidable deaths. Rework so DPS/enrage + tank drive kill-vs-wipe and the soft lanes apply *pressure*. | M | — |
| **MI-003** | First-session scenario contract + curated demo | A representative demo: fixable weakness → legible failure → meaningful fix → visible improvement → **plausible kill in 3–8 pulls** → reward. Distinct from the diagnostic smoke. | M | MI-001, MI-002 |
| **MI-004** | Raid-night presentation contract | Feed hierarchy (routine/notable/critical/decisive), phase emphasis, pull-over-pull improvement, kill vs wipe treatment, speed/skip controls. Text-and-panel only — hierarchy, not graphics. | M | — |
| **MI-005** | Diagnostic contract | Player-facing: **primary cause → contributing factors → key moment → recommended intervention → recurrence**. "Culprit" becomes internal shorthand only. | S–M | — |
| **MI-006** | Performance-rating contract | Lock the player-facing meaning of 1–10 *before* it becomes evidence in Loot Council. Role/gear-relative expectation, assignment weighting, penalty/reward table, explanation breakdown. | S–M | — |
| **MI-007** | Involvement-mode contract | Manual / Assisted / Instant behaviour for lineup, assignments, pulls, loot, weekly plan, recruitment. **Contract only** — implementation stays M9-005 — so Phase-B screens are designed once. | S | — |
| **MI-008** | Terminology & accessibility contract | Dual-language rule: plain-language consequence first, MMO term second, every warning carries an actionable implication. | S | — |
| **MI-009** | Harness: per-boss contracts + prep-leverage probes | Assert each boss against *its own* contract (not one global band). Add same-seed comparative probes: assignments, healer/DPS split, melee/ranged split, consumable tier, tank choice. | M | MI-001 |
| **MI-010** | 🎮 **THE FUN GATE** — human playtest | Hands-on sessions (1 MMO veteran, 1 sim player w/o MMO history). Score against the Fun Gate scorecard. **Human verdict, not a test suite.** | — | MI-003, MI-004 |
| **MI-011** | Campaign-model doc alignment | Season = Tier locked (I-03). Align every doc, seed, objective cadence and UI string. | S | — |
| **MI-012** | Phase B-lite rescope | Restage M5–M9 into validation gates; open the breadth backlog (MB-*). | S | — |

**Gate:** MI-010 must pass before M5. A weak score means tune/clarify/re-present the slice — **not** add campaign breadth.

---

## Phase B-lite — The Season · *staged product gates, not one build commitment*

**Rescoped 2026-07-11 (I-12).** Each cluster is a **product gate**: is the previous loop enjoyable? does the new system add a *decision* or only administration? is its effect legible? Breadth (DKP//roll, deep economy, all 4 channels, rival identity) is deferred to the **MB** backlog and only pulled in once the week/season loop plays well.

| # | Milestone | Definition of done (lite) | Size | Depends |
|---|---|---|---|---|
| **M5** | Turn loop, calendar & genesis | FM event-day stepping over the weekly calendar (days + time slots); guild-genesis / new-game flow on the `GAME_STATE`/`GAME_CONFIG` save root; the 5 lanes + action resolver; availability; decision inbox + weekly digest. **Season = Tier.** Play multiple weeks; roster gears/improves. | L | **MI-010** |
| **M6** | Loot & consequences *(Council only)* | **Loot Council alone** + the 7-factor claims panel + award ripples into morale/loyalty/fairness. DKP and /roll move to MB-001. | M | M5 |
| **M7** | Economy *(basic)* | Treasury, donation income, proceeds, repairs, provision. **Deep economy + the 3-policy matrix + death-spiral tuning move to MB-002** (needs recovery valves, MB-004, first). | S–M | M6 |
| **M8** | Recruitment *(one channel)* | `PROSPECT_ASSESSMENT` fog overlay + **applicants only**: source → assess → trial → sign. Population tick + attrition leave-check. Scouting/poach/referrals move to MB-003. | S–M | M5 |
| **M9** | Season, objectives & stakes | Objectives issued → season-end grading (rising bar) → sacking → **rebuild**; career summary + endless mode. Rival *ladder* stays (competitive objective needs it); rival *identity/news* is MB-005. | M | M5 |

**Then playtest the complete week/season loop** before opening MB.

### 🚨 MC — The Tier-2 content gap (found 2026-07-12; **untracked until now**)

| # | Milestone | Definition of done | Size | Depends |
|---|---|---|---|---|
| **MC-001** | **Author Tier 2** — the second raid | A second raid (~6–8 encounters) seeded for **Season 2 / Tier 2**: phases, `encounter_event` placements, loot table, and **a contract row per boss** in `encounter_contract.csv` inside the Tier-2 gear band. `season.csv` then expresses **two** seasons of the `crownfall` expansion. | **L** | M5 |

**Why this is here.** v1's content bar is **2 tiers / ~12 bosses** (`content-and-dod` §Gate 2), and that doc itself says *"where the real authoring time goes: the ~12 bosses."* **We have 1 tier and 4 bosses.** No milestone in M0–M11 ever authored Tier 2 — M1 was explicitly a *starter kit* (one raid, 3–4 encounters), and every milestone after it builds systems, not content.

This is now the **single largest untracked v1 scope item**, and it is a hard blocker on two things:

- **MI-011** cannot pass its own acceptance (*"`season.csv` expresses two seasons"*) while only one tier of content exists. A season row pointing at a raid that does not exist would be worse than the gap.
- **Gate 2** (*"play a full season → get graded → progress into Season 2 at a raised bar"*) is not reachable without a Tier 2 to progress *into*.

**Do not fold this into M9.** Grading and season transition are *systems*; authoring 6–8 bespoke bosses is *content*, and the two have very different costs and risks. Sizing it honestly is the point of naming it.

## MB — Breadth backlog · *only after the Phase B-lite loop plays well*

| # | Ticket | Why deferred |
|---|---|---|
| **MB-001** | DKP + /roll loot policies | Council is the flagship; prove fairness consequences with one culture first. |
| **MB-002** | Full economy: 3 policies, stockpile depth, death spiral | Needs recovery valves (MB-004) or decline becomes predetermined. |
| **MB-003** | Recruitment channels: scouting, poach, referrals | One channel proves the fog/trial loop; the rest are volume. |
| **MB-004** | Economy recovery valves (I-09) | **Blocks MB-002.** A death spiral without recovery decisions is a cutscene, not gameplay. |
| **MB-005** | Rival identity & news layer (I-11) | Progress curves alone read as leaderboard timers with names. |

---

## Phase C — Depth & Meta · *post-launch / v1.1*

| # | Milestone | Definition of done | Size | Depends |
|---|---|---|---|---|
| **M10** | Social depth & drama | Chemistry *effects* wired into resolution; quirks; `DRAMA_EVENT` catalogue; loyalty/morale drift fully expressed. Emergent drama across a season. | L | M7 |
| **M11** | v1.1 meta | Multi-expansion cycle + catch-up reset; optional Player-Guildmaster; resistance & quirk events; Soft-Reserve/EPGP; professions. | L | M10 |

---

## Engineering notes (your wheelhouse)
- **Make the sim core a pure, seeded function** `(roster, encounter, seed) → outcome`. Then it's unit-testable, and you can run a **batch balance harness** (N pulls → assert each boss against **its own contract row**, catch tuning regressions). Same discipline as data tests, but for game balance. Build the harness alongside M3 — it's the cheapest insurance against a broken feel later. *(The original "~60–80% target" here was wrong on two counts: that is a farm feel, not progression, and one global band cannot catch a broken tier — see ADR-0024/0030.)*
- **Content as data** — seed files (YAML/JSON) versioned in-repo, loaded via migrations. New classes/bosses/events = new rows, engine untouched. (Your dbt-seed instinct applies directly.)
- **Persistence** — SQLite for the desktop app; the schema is already lakehouse-shaped, so migrations handle evolution cleanly.
- **Observability is already designed in** — `PULL_EVENT`, `TREASURY_LEDGER`, `WEEK_ACTION` are audit trails. Surface a "why did this happen" debug view early; it doubles as your dev tooling.
- **`GUILD_CONFIG` is already merged in the model (v0.8)** — build it unified from the start.

## First concrete action (M0)
Translate the **v1-core table list** from the data-model doc into SQLite migrations, and stand up the seed-loader. That single step turns eight design docs into a running skeleton.

---

*v1 backlog — a plan, not a contract. Re-scope freely as the slice teaches you what's actually fun.*
