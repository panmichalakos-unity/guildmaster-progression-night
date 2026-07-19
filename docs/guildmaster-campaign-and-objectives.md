# Guildmaster: Progression Night — Campaign, Turn Structure & Objectives (v0.1)

The meta layer: how time advances, how a campaign is saved, and what the player is working toward. Resolves readiness-review **P0 #1 & #2**.

## The turn loop — FM-style event-day stepping
Week-based, **player-paced** (no real-time clock — sustainable, take as long as you like). You populate a weekly **calendar** with events, then advance through it.

```
PLAN (weekly)
 · read last week's digest + clear the decision inbox
 · populate the calendar — raid nights, dungeon nights, rest, social (on specific days **and time slots**: afternoon / evening / late — where life-situation windows bite)
 · for each raid night: set lineup + assignments (see raid-prep)
ADVANCE
 · "Continue" → jump to the next event day (or step day-by-day), pause for edits anytime
 · empty days: state ticks (fatigue recovery), no stop
 · event days resolve — dungeon runs, or an interactive raid night
 · decision interrupts (drama, recruit reply) → pause for input
REPORT
 · end-of-week digest: results, progression, loot, ratings, morale/roster, income/expense,
   new applicants, events, objective progress
 → next week
```

The **calendar is a first-class object** — events scheduled on days. The old "time budget" becomes concrete: *how many event-slots the week holds, and who's available for each.*

## Season & expansion structure

> ✅ **LOCKED 2026-07-11 (I-03, Model A).** **Season = Tier.** The v1 expansion contains **two seasons**: Season 1 / Tier 1 (~12–14 wk) → grading → Season 2 / Tier 2 (~12–14 wk) → final grading → career summary → endless mode or rebuild. This is now canonical across all docs; `guildmaster-content-and-dod.md`'s old "one 14-week season across 2 tiers" wording was the contradiction and has been corrected. Every calendar/objective/rival/UI string must express this model.

- **Season = one raid tier.** Its **length is a property of the expansion** — a variety lever:

  | Expansion shape | Season | Feel |
  |---|---|---|
  | Tight | ~12 wk | fewer pulls per boss — brutal, race the clock |
  | Standard | ~14 wk | baseline |
  | Sprawling | ~16 wk+ | harder bosses, more runway to learn them |

  A short season + hard bosses = you may *not* clear before the reset. That "did we make it in time?" pressure is the old-school feel, and it makes each expansion play differently.
- **Expansion = a container of seasons**, ending with the **meta reset** (gear/balance). Carried by `Expansion.season_length_weeks` + `difficulty_band`.
- 🔒 **v1 = a single expansion of EXACTLY TWO seasons — i.e. two tiers.** One season *is* one tier (see the locked banner above), so the Gate-2 bar — *"play a full 14-week season across 2 tiers"* — means **two seasons**, not two tiers inside one season. An earlier line here read *"1–3 tiers — a content-volume call"*, which contradicted the locked Season = Tier model; it is **removed**, and the count is no longer an open question.

## Save / campaign model
- **One save file = one campaign** — the SQLite DB *is* the save. No `campaign_id` stamped on every table.
- **`GAME_STATE`** (singleton): current expansion/season/week, current phase, `rng_seed`, created-at. Settings (`GAME_CONFIG`, P1) attach here. The **`rng_seed` makes whole campaigns reproducible** — pairs with the batch balance harness.

## Decision inbox (UX primitive)
An FM-style single queue for everything needing your attention: applications, recruit replies, drama choices, delegated-off loot calls, objective updates. A lightweight `INBOX_ITEM` view over existing queues — not heavy new structure.

---

## Objectives — the success system
The missing half: only *failure* (the sacking meter) was defined. Objectives define what "doing well" means — as **expectations, not quests.**

### The model
At **season start**, the guild issues a small set of **objectives** (shaped by standing + reputation + history) with priorities; at **season end** they're **graded**; grades feed officer/member confidence (the sacking meter) and set next season's bar. This *reuses* the confidence system — objectives are its input, so nothing dangles.
- Top guild → "server-first." Rebuild → "clear Tier 1, stop the bleeding."
- Beat them → confidence + reputation climb → next season's bar rises. **That rising bar is the long-game difficulty curve.**

### Objective types (composable, from data the systems already emit)
| Type | Example | Reads from |
|---|---|---|
| **Progression** | clear the tier / down the end boss by wk 10 | `GUILD_ENCOUNTER_PROGRESS` |
| **Competitive** | top-3 on the server for the tier | rival ladder (P1) |
| **Roster** | retain the core / keep ≥3 raid-ready tanks | `GUILD_MEMBERSHIP`, roster |
| **Cohesion** | keep guild morale above X | morale / `fairness_perception` |
| **Economic** | end the tier solvent | `GUILD_TREASURY` |
| **Development** | graduate a Project to a raid-ready main | skill / familiarity |

*Progression + one other* per season keeps it focused. Being judged on **people and money, not just kills** is what stops it feeling like a raid-logger.

### Two rules that keep it a sim, not a checklist
1. **Outcomes, not to-dos.** "Retain the core" is graded from what *emerges* across the season — pursued *through* the systems, never a quest tracker. This is the line between a management sim and a mission list.
2. **Spectrum grades** — Exceeded / Met / Missed / Failed, each nudging confidence proportionally. A near-miss stings without being terminal — room for a redemption season.

### Personal ambition (v1)
You set **one self-directed goal** beyond the mandate ("go for the server-first though they only asked for a clear") — reach for glory, risk overextension. Player-authored stakes. *(Per-raider goals + mid-season renegotiation → v1.1.)*

### Season bookends (ties to the turn frame)
- **Start:** objectives issued → land in the inbox as your mandate.
- **End:** grading screen → confidence + reputation update → next season's objectives generated at the new bar → optional expansion reset.

This gives the campaign its **rhythm and its scoring** in one stroke — the thing that was entirely missing.

## Guild genesis — new game & rebuild (one flow)
Both entry points share one machinery:
1. **Found the guild** — name it; set toggles (sack risk, involvement defaults, difficulty) → `GAME_CONFIG`; choose the loot culture → `GUILD_CONFIG`.
2. **Generate the starting roster** (~28 via roster-gen; quality band from difficulty).
3. **Seed treasury + reputation.**

- **New game:** neutral reputation, modest gold, a green roster.
- **Rebuild (post-sack):** the same flow with **damaged reputation** (lower applicant volume/quality), thin gold, and carried history — your record persists, and a few loyalists may follow you out (loyalty-gated).

## The rival ladder (light)
~6–10 **ghost guilds** populate the server — no full simulation:
- Each is a `GUILD` row (`is_player_guild=false`) with a `progress_pace` band (fast / mid / slow).
- Their progression advances on a curve **into the same `GUILD_ENCOUNTER_PROGRESS` table** → server standings are a **derived view** (drives competitive objectives + the server-first race).
- Their rosters are generated `PLAYER`s → the **poach pool**; rivals can poach *your* raiders too (feeds attrition).

## Campaign horizon (v1)
One expansion, two tiers. After the final season is graded: a **career summary**, then **endless mode** — re-run the final tier against the rising expectations bar (with continued roster churn) until sacked or retired. Multi-expansion continuation is v1.1.

## Model impact (in data-model)
- **`GAME_STATE`** (singleton) · **`CALENDAR_EVENT`** (day, type, status; **`RAID_NIGHT` becomes its raid specialization**) · **`SEASON_OBJECTIVE`** (type, target, priority, `is_personal_ambition`, result) · **`OBJECTIVE_TYPE`** + **event types** as seed data · **`Expansion.season_length_weeks`** + **`difficulty_band`** · **`INBOX_ITEM`** as a derived view.
- **v0.8 additions:** `GAME_CONFIG` (difficulty, involvement defaults, sack-risk toggle) · `CALENDAR_EVENT.time_slot` (afternoon / evening / late; availability = life-situation window match + volatility roll) · `GUILD.progress_pace` (ghost-guild pacing).

---

*v0.1 — campaign frame + objectives locked. Season length varies by expansion. IP-original naming.*

---

> ### UPDATE (2026-07-19) — implementation state
> **Live since M5 (ADRs 0034–0038, 0042–0043):** the turn loop's PLAN → ADVANCE → REPORT beat exactly as drawn above — genesis on the `GAME_STATE` save root (Night One always curated), FM event-day stepping with empty-day recovery ticks, availability's two gates (window, then volatility — retuned 2026-07-18 so evenings field ~19–22 of 28), the five lanes, the decision inbox (a purely derived `INBOX_ITEM` view, as specified), the weekly digest, the bench cost at week roll, and **load/continue** (one DB = one save; a newer-build save is refused, content refreshes on load, campaign state persists). The season boundary stops at a `grade` phase and holds — **grading, objectives, the rival ladder, sacking/rebuild and endless mode are M9**, still design-only. `SEASON_OBJECTIVE`/`OBJECTIVE_TYPE` tables exist and the inbox/digest already read them (empty until M9 issues the mandate). Both seasons of the v1 expansion are seeded (MC-001) — the "progress into Season 2" bar is content-real.
