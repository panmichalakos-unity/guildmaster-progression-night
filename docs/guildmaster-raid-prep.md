# Guildmaster: Progression Night — Raid-Night Prep (v0.1)

Resolves readiness-review **P0 #4**: the missing core screen — who's raiding tonight and what everyone does. The raid-prep surface, where roster, comp, and gear converge visibly.

## The screen (three parts)
1. **Lineup** — fill the raid (**fixed 20**) from who's *available* (availability rolls already ran). Drag raiders into role slots (tank / healer / DPS), or **auto-fill**. Available-but-unslotted = **bench**.
2. **Comp check** — legible coverage warnings (reads `SPEC_UTILITY` + gear + the planned bosses' event placements), not raw numbers:
   `⚠ No battle-rez tonight` · `⚠ Only 4 healers (5 recommended)` · `⚠ Main tank not uncrittable` · `⚠ 8 melee vs a melee-unfriendly boss` · `✓ Haste burst covered`.
   This is where **"bring the class, not the player"** and the gear-readiness caps become tangible — the roster puzzle made visible. Comp has three axes: **role coverage, utility coverage, and range balance vs tonight's bosses** (a boss's range profile derives from its melee/ranged-targeted events).
3. **Assignments** — the tactical inputs the engine reads: **tank** (main / off), **healing focus** (tank vs raid split), **interrupt rotation**, **soak duty**, **cooldown / lust timing**, and the **consumable plan** — premium / basic / none per event (an `assignment_type='consumables'` row; per-pull overridable via `PULL_CONSUMABLE`, drawn from `GUILD_STOCKPILE`). Auto-assign defaults you override where it matters, plus **per-boss presets** so you're not re-planning every night.

**The bench has a cost.** Consecutive benchings (derived from `RAID_LINEUP` history — no new state) ding morale and loyalty scaled by ego, and surface in the digest (*"Kessa has sat out three straight nights"*). Rotate the bench or pay for it.

**Trials are lineup-eligible.** `GUILD_MEMBERSHIP.status='trial'` members can be slotted; their pull performance feeds `PROSPECT_ASSESSMENT` — the trial *is* the reveal.

## Grain (clean model fit)
Lineup + assignments live at **raid-event (`CALENDAR_EVENT`) grain** — the plan for the night. **`PULL_PARTICIPANT` inherits from them per pull and can override** — exactly the mid-fight swap the involvement slider already promised. One home, no duplication.

## Two planning-time failure modes (turned into choices)
Both caught in PLAN, *before* you commit — the "handle it right and the week still counts" feel.

**Undermanned** (too few bodies, or a required role missing):
- **Run short** — fewer bodies → harder, weaker checks.
- **Cancel** — progression stalls, the cost of a thin week.

**Undergeared** (too weak for the planned bosses) — a **readiness preview** grades each planned boss from raid gear vs `boss_demand`:
`✓ Ready · ~ Tight · ⚠ Undergeared · ✗ Heavily undergeared`. If the night is mostly ⚠/✗:
- **Push anyway** — likely wipes, but the learning arc still ticks toward a future kill.
- **Downshift bosses** — swap to an easier boss subset you *can* gear on (farm the front, gear for the back).
- **Convert to dungeon run** — scrap the raid, turn the slot into a **Gearing event** (Marks + gear). The week isn't wasted.

Both failure modes share one decision surface — the two "can't raid tonight" walls become choices instead. `Convert` = a `CALENDAR_EVENT` type change (raid → dungeon); `downshift` = scheduling a boss subset; the readiness preview = a derived view (raid gear ⋈ boss demands). All cheap.

## Scope
- **In v1:** lineup + bench; comp-coverage warnings; the **full assignment suite** (tank / heal / interrupt / soak / cooldown-lust); auto-fill / auto-assign; per-boss presets; both failure-mode decisions.
  *This promoted **assigned-duty checks + cooldown-moment events to v1** — see resolution.*
- **Deferred:** chemistry warnings in the comp check (v1.1, with the relationship graph); positioning / formation depth.

## Model impact (in data-model v0.7)
- **`RAID_LINEUP`** (event_id, avatar_id, slot_role, is_benched) · **`RAID_ASSIGNMENT`** (event_id, avatar_id, assignment_type, target) · **`RAID.raid_size`** (= 20) · comp-coverage + readiness-preview as **derived views** · `PULL_PARTICIPANT` inherits from the lineup.

---

*v0.1 — raid prep locked. Fixed 20-raider size. IP-original naming.*

---

> ### UPDATE (2026-07-19) — implementation state
> Shipped and live: the comp check + warnings (M4-002, MI-008 wording), availability rolls + both planning-time decision surfaces (M5-003 — run short / cancel / **downshift** via `target_boss_subset` / **convert** to dungeon), the persisted lineup (`RaidPrep.persist_lineup`, M5-005) and **the bench cost** (M5-007). Two semantics got locked on the way and refine this doc's wording:
> - **Benched means could have played** — a raider whose availability roll said "can't make it" gets **no** `RAID_LINEUP` row and holds no streak (attendance vs participation, ADR-0038). An unavailable night *skips* a streak rather than resetting it (ADR-0042).
> - **The ding is marginal** — each week roll charges the streak's price minus what was already charged, ego-scaled (0.5×–1.5×), morale into the new week's snapshot and `loyalty_current` only. Every sat-out night is priced exactly once; the digest reports the exact applied numbers.
> Still open: per-boss presets and the drag-drop lineup **screen** polish (the Phase-B UI pass); chemistry warnings stay v1.1.
