# Guildmaster: Progression Night — v1 Readiness Review

End-to-end audit of all nine docs. Goal: surface every gap that blocks a fleshed-out, buildable v1, prioritized so each item becomes a decision or a ticket.

## Verdict
The **systems** are done and coherent — the social → economy → raid → social loop interlocks cleanly. What's missing is the **shell around the systems**: player goals, the gear→power link, the turn/campaign frame, and UI — plus content volume and ticket-level decomposition. None are hard design problems; all are bounded scoping calls. Resolve the P0 set and you have a complete, build-ready v1 spec.

Severity: **P0** blocks a coherent game · **P1** needed for a fleshed-out feel · **P2** content volume · **P3** process to run the board.

> **Status update:** All **P0 blockers are now resolved** and folded into the docs (data-model → v0.7; new docs: campaign-and-objectives, gear, raid-prep). Kept below for the record, each marked ✅. Remaining open work is **P1 / P2 / P3** + consistency merges.

---

## P0 — Blockers ✅ RESOLVED (data-model v0.7)

1. **No objective / success system.** Only *failure* (the sacking meter) is defined. The player has no goals, expectations, or score — nothing tells them "you're doing well." *This is the single biggest gap for a fleshed-out feel.*
   → **Fix:** add a season-expectations layer (FM board-expectations analog): goals set at season start ("clear Tier 1," "top-3 server progress," "retain the core"), tracked live, success/failure feeds confidence. New entity: `SEASON_OBJECTIVE`.

2. **Gear → power is undefined.** Loot is awarded (`LOOT_DROP`) but nothing specs how it raises an Avatar's power. `item_level` is a static scalar; there's no equipped-gear or gear-score mechanic. *Loot and progression don't actually function yet.*
   → **Fix:** pick the abstraction. Lightest = a `gear_score` on Avatar that each award increments by a defined amount per slot/upgrade; richer = per-slot equipped items (`LOOT_ITEM` already has `slot`). Recommend **per-slot equipped model** — it makes "biggest upgrade" and BiS real without much cost.

3. **Marks currency missing from the model.** The Gearing lane depends on it; there's no field or table.
   → **Fix:** add `Marks` (per-player balance) + a Marks→catch-up-gear vendor mapping. Small.

4. **The turn / campaign frame is undefined.** How a week *executes* (plan phase → resolve), season length, how time advances, and what a "save/campaign" is. `SEASON`/`WEEK` are time buckets but the execution model isn't specced.
   → **Fix:** define the turn loop (discrete plan → resolve → report) + season length + a `CAMPAIGN` / `GAME_STATE` root entity (the save). Prerequisite for any UI or loop code.

5. **Raid-night lineup & assignment flow not modeled.** Only per-pull `PULL_PARTICIPANT` exists. The core "select tonight's raid from available players + set tank/heal/interrupt assignments" step — a whole screen — has no home.
   → **Fix:** add a raid-night roster/assignment set (`RAID_NIGHT_ROSTER` at raid-night grain; assignments copy down per pull).

6. **Lane action → outcome unspecced.** `WEEK_ACTION` stores an `outcome` but not *how* each lane resolves (Gearing → Marks + gear roll; Development → skill delta; Supply → stockpile gain).
   → **Fix:** a small action-resolution spec (input → output per lane). Needed to build the between-nights loop (M5).

---

## P1 — Design gaps (fleshed-out feel)

1. **Rival guilds / competitive layer.** Referenced everywhere — poaching, server-firsts, reputation — but never specced; no rival simulation exists.
   → **Fix:** decide now. Recommend a **lightweight rival ladder** for v1 (a few ghost competitors whose progress advances on a curve, drives server-first stakes + poaching pressure) rather than a full guild sim. Or explicitly cut and stub `reputation`.

2. **New-game / onboarding flow.** Creating a guild, choosing difficulty/toggles, starting roster + gold — undefined.
   → **Fix:** define the setup flow and starting conditions.

3. **Settings / config has no home.** The involvement slider, difficulty, and the sack-risk toggle aren't stored anywhere.
   → **Fix:** a campaign-level `GAME_CONFIG` (difficulty, involvement defaults, toggles, active loot system).

4. **Attrition triggers.** Players leaving is a key churn mechanic (poach vulnerability, "walk"), but *when/why* a player quits isn't specced (loyalty threshold? poach success? burnout?).
   → **Fix:** define the quit/poach-away triggers; `GUILD_MEMBERSHIP.status/left_at` already supports the record.

---

## P2 — Content gaps (volume for "fleshed out")

- **Content volume targets undecided.** How many classes/specs/utilities/consumables/raids/bosses/tiers, and weeks-per-season. This drives seed-data scope *and* the "done" bar.
  → **Fix:** set explicit v1 targets (I can propose a minimal-but-fleshed set).
- **Naming bible** is a **prerequisite for seed data (M1)** but currently parked as "later."
  → **Fix:** promote to a pre-M1 task.
- **Planned content debt:** seed data (M1), the ~25 quirk library (M9), the drama-event catalogue (M9). Tracked, not yet authored — fine, but on the critical path to "fleshed out."

---

## P3 — Process / buildability (to run the board)

- **Backlog is milestone-level, not ticket-level.** A kanban needs epics → stories with acceptance criteria.
  → **Fix:** decompose at least Phase A (M0–M4) into stories now.
- **No game-level "v1 Definition of Done."** Feature + content completeness bar for shipping.
  → **Fix:** write an explicit v1 DoD.
- **Presentation / juice scope.** Even text-driven UI needs minimal feedback/polish; currently unscoped.
  → **Fix:** one-line scope note, or defer explicitly.

---

## Consistency nits (quick fixes)
- **`GUILD_LOOT_CONFIG` + `GUILD_POLICY` → merge** into one `GUILD_CONFIG` (already flagged in the model).
- **Attendance source** — `LOOT_CLAIM.attendance_snapshot` needs data; availability (`RAID_NIGHT_AVAILABILITY`) ≠ attendance. Derive attendance from `PULL_PARTICIPANT` presence, or add a light attendance fact.
- **Consumable consumption flow** — decrementing `GUILD_STOCKPILE` on use isn't an explicit transaction; wire `GUILD_STOCKPILE ↔ PULL_CONSUMABLE (+ TREASURY_LEDGER)`.
- **Player-GM copy** — deferred to v1.1, but loot/pitch reference it; make v1 copy consistent (in v1 the player is a disembodied manager).

---

## Second-Pass Audit (post-P0 full re-read)
Verdict: **the core loops are complete and consistent** — plan → raid → loot → consequences → economy → season grading all close. What remains is a handful of **missing links** (mostly system *edges* and lifecycle flows), plus the known P1/P2 items.

### Fixed during this audit (mechanical)
- ✅ `RAID_NIGHT` fully refactored to `CALENDAR_EVENT` in SA2 (relationships, `PULL.event_id`, `RAID_NIGHT_AVAILABILITY` → **`EVENT_AVAILABILITY`**); stale `performance_score` text corrected.
- ✅ Class/spec locked **6 × 3 = 18** with a role-coverage matrix (3 tank / 4 heal / 5 melee / 6 ranged); **melee vs ranged** wired as a boss-mechanic dimension (event `target_selector` + range-balance comp warning). Content/backlog/pitch/overview synced (roster ~28, fixed 20-raid, core-7 events).

### G-register — ✅ ALL RESOLVED (defaults confirmed; folded in, model v0.8)
| # | Gap | Recommendation (default) |
|---|---|---|
| **G1** | **Guild-genesis flow** — new-game onboarding *and* post-sack rebuild are both unspecced; they're the same machinery | One "found a guild" flow (name, toggles, starting roster gen, starting gold/rep) used by both; rebuild = same flow with damaged rep + carried history |
| **G2** | **Attrition triggers** — when/why a raider quits or accepts a poach | Weekly leave-check: `loyalty_current` below threshold + morale + rival interest (if ladder) + a fired `reason`; writes `GUILD_MEMBERSHIP.left_at` + inbox notice |
| **G3** | **Rival layer decision** — blocks competitive objectives + gives poaching a source | **Light ladder in v1**: ~6–10 ghost guilds with progress curves + rosters-as-name-pools; full sim stays out |
| **G4** | **World population** — who generates new applicants/free agents over time (and their names) | Weekly generation tick: N new prospects scaled by `GUILD.reputation`, drawn from the same roster-gen system; name generator = naming-bible task |
| **G5** | **RELATIONSHIP-in-v1 tension** — coach/social/mediation/referrals all *write* relationships, but the table is deferred to v1.1 | Include **RELATIONSHIP-lite in v1**: table exists, written by those actions, read only by referrals/duo-poach — **no resolution/chemistry effects until v1.1** |
| **G6** | **Bench consequences** — repeated benching has no cost; classic drama source missing | Bench-streak tracking → morale/loyalty ding scaled by ego; surfaces in the digest ("X has sat out 3 straight") |
| **G7** | **Per-fight consumable plan has no prep home** — resolution consumes them, prep never chooses them | Add consumable tier (premium/basic/none) to raid-prep as an `assignment_type='consumables'` row per event, per-pull overridable (existing `PULL_CONSUMABLE`) |
| **G8** | **Time-of-day slots** — life-situation windows ("raids after 11pm") can't bite: `CALENDAR_EVENT` has day only | Add `time_slot` enum (afternoon / evening / late); availability = window match + volatility roll |
| **G9** | **Campaign horizon** — v1 = 1 expansion / 2 tiers; season 2 ends… then what? | Soft-end: career summary screen + "continue in endless mode" (repeat final tier at rising bar); multi-expansion is v1.1 |
| **G10** | **`GAME_CONFIG`** — difficulty, involvement defaults, sack toggle, active loot system have no home (P1, still open) | One config table on `GAME_STATE`; fold the `GUILD_LOOT_CONFIG`+`GUILD_POLICY` merge into the same pass |
| **G11** | **Attendance derivation** — `LOOT_CLAIM.attendance_snapshot` has no defined source | Define: attendance = `EVENT_AVAILABILITY.available=true` rate; participation = non-benched lineup rate; loot factor uses attendance |
| **G12** | **Stockpile consumption transaction** — burn isn't an explicit flow | On pull resolve: decrement `GUILD_STOCKPILE` per `PULL_CONSUMABLE` (if provisioned) + `TREASURY_LEDGER` entry |
| **G13** | **World buffs** — mentioned once in the pitch, never specced | Cut from v1; treat as a v1.1 prep-layer idea (or delete the pitch mention) |
| **G14** | **Trial raiders in lineup** — eligibility never stated | One line in raid-prep: `status='trial'` members are lineup-eligible; trial performance feeds `PROSPECT_ASSESSMENT` |

### Still open from first pass
P2: ~~naming bible~~ ✅ done (see naming-bible doc), seed data (**unblocked**), quirk library (v1.1), drama catalogue (v1.1) · P3: Phase-A ticket decomposition, v1 screen map (one-pager of the ~10 screens — recommended before slicing).

**After the G-register lands:** docs are genuinely build-complete for v1 — remaining work is content authoring + tickets.

---

## Final Build-Readiness Audit (pass 3) — **VERDICT: GO**
Full third re-read of all 15 docs. Specs, model (v0.8), naming, and DoD are consistent and complete. One structural catch, fixed in this pass: **the backlog predated the P0/G scope expansion** — objectives, genesis, rivals, attrition, and the campaign horizon had no owning milestone.

### Fixes applied in this pass
- **Backlog restructured:** Phase B = **M5–M9**. M5 → turn loop / calendar / genesis (save root); M8 gains population tick + attrition; **new M9 — Season, objectives & stakes** (grading, rising bar, rival ladder, sacking → rebuild, endless mode). Phase C renumbered **M10–M11**; stale `GUILD_CONFIG`-merge note corrected (already merged in v0.8).
- Marks vendor volume aligned to the gear model: **7 / tier (one per slot)**.
- DoD clarified: v1 manual = strategy + lineup + between-pull swaps + wipe calls; **mid-pull directive injection = v1.1** (matches resolution scope).
- Guild genesis now also sets the loot culture (`GUILD_CONFIG`).

### Feature → owner trace (v1)
| Loop / feature | Spec doc | Model | Milestone |
|---|---|---|---|
| Turn loop, calendar, save, genesis | campaign | GAME_STATE/GAME_CONFIG, CALENDAR_EVENT | M0 · M5 |
| Roster generation + raider model | data-model, recruitment | PLAYER / AVATAR (+ items) | M2 |
| Raid prep (lineup, assignments, consumable plan, undermanned/undergeared) | raid-prep | RAID_LINEUP / RAID_ASSIGNMENT, EVENT_AVAILABILITY | M4 |
| Resolution (checks, core-7 events, learning arc, rating) | resolution | PULL*, GUILD_ENCOUNTER_PROGRESS | M3 |
| Gear & Marks | gear | SLOT, AVATAR_ITEM, marks | M3 · M5 |
| Loot & consequences | loot | GUILD_CONFIG, LOOT_CLAIM / STANDING | M6 |
| Economy & policies | between-nights | TREASURY / STOCKPILE / LEDGER | M7 |
| Recruitment, population, attrition | recruitment | PROSPECT_ASSESSMENT, RELATIONSHIP (lite) | M8 |
| Objectives, rivals, sacking → rebuild, endless | campaign | SEASON_OBJECTIVE, progress_pace | **M9** |
| Seed content (world, 6×3, T1/T2, items) | naming-bible, content-and-dod | seed tables | M1 |

Every Gate-2 DoD line now has an owning milestone.

### Deliberately open (not blockers)
Numeric tuning (symbolic by design — the batch harness validates) · quirks / chemistry effects / drama catalogue (v1.1, fenced) · screen map (optional one-pager) · **Phase-A ticket decomposition — the next step**.

---

## Recommended sequence (updated)
1. ~~Resolve the P0 decisions~~ ✅ **done** — folded into docs, model at v0.7.
2. ~~Set v1 content volume + Definition of Done~~ ✅ **done** — see content-and-dod (targets + two DoD gates).
3. ~~Resolve P1 + consistency~~ ✅ **done via the G-register** — guild genesis, rival ladder, attrition, population, relationship-lite, bench costs, consumable plan, time slots, horizon, `GAME_CONFIG`/`GUILD_CONFIG`, attendance, consumption. (G13 was already clean — no world-buffs mention exists.)
4. **Decompose Phase A (M0–M4) into kanban stories** with acceptance criteria — then populate the board.

~~**Recommended next:** Phase-A ticket decomposition — seed data is unblocked and gets authored inside ticket M1.~~ *(Done long since — Phase A shipped and passed its gate; see the update below.)*

---

*v1 readiness review — P0 resolved; re-run after P1/content land.*

---

> ### UPDATE (2026-07-19) — this register is fully discharged in CODE, not just design
> Every P0 and G-item above was resolved on paper before the build; as of M5's completion the load-bearing ones are shipped and test-pinned: G6 bench consequences (M5-007 — marginal, ego-scaled, the digest reports the applied numbers), G11 attendance vs participation (locked into `RAID_LINEUP` semantics, ADR-0038/0042), the P0 turn/campaign frame, lane outcomes, lineup/assignments, gear→power and Marks earning. Remaining paper-only items ride their owning milestones (M6 loot consequences, M7 economy, M8 recruitment/attrition, M9 objectives/rivals/sacking). This doc stays as the historical register; the backlog's gap list is the live one.
