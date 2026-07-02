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
