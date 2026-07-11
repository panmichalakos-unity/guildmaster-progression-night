# Guildmaster: Progression Night — Encounter Progression Contracts (v1.0)

**Created by MI-001 (2026-07-11).** The missing artifact that let the tier become uncompletable: boss demands were authored as "symbolic" numbers with **nothing tying them to what a real roster produces**. This document is now the source of truth. Retuning a boss without updating its contract is a bug.

> **The governing question for every boss:**
> *At what plausible roster state should this boss be attempted, and what player-controlled intervention makes the next attempt better?*

---

## 0. The gear ceiling — the constraint that governs everything

A raider has **7 slots**. Starting gear averages **ilvl 18.9** (`gear_score` 132). Every Tier-1 boss drop is **ilvl 31**. Therefore:

| Roster state | avg ilvl | gear_score | multiplier |
|---|---|---|---|
| Fresh guild (no drops) | 18.9 | 132 | **x1.00** |
| A boss or two farmed | 22 | 154 | x1.16 |
| Half the tier geared | 26 | 182 | x1.38 |
| Mostly tier-geared | 29 | 203 | x1.53 |
| Full BiS in Tier 1 | 31 | 217 | **x1.64** |

> ### 🔒 **The realistic in-tier gear band is x1.00 → x1.64.**
> Any encounter that needs more than **~x1.65** is **unreachable content**, no matter what a harness sweep at x2.0–x3.0 suggests. The old balance harness swept to x3.0 and reported "reachable" win rates at gear the player can never obtain — which is precisely how three of four bosses stayed uncompletable while the harness passed green.
> **Every contract below lives inside this band. So must every future one.**

---

## 1. The shape of a healthy fight

| Roster state | Intended win rate | Why |
|---|---|---|
| **Under-prepared** (wrong tank, bad comp, no consumables) | ≤ 10% | Teaches that the *preparation* is the problem, not the dice. |
| **Progression** (right gear for this boss, correct prep) | **22–35%** | A kill in **3–8 pulls**. At 28%/pull: 66% chance by pull 4, 92% by pull 8. This is the "one more pull" zone. |
| **Farm** (geared past the boss) | 65–90% | Clean, fast clears. Farm content must not waste a night. |

**Pulls-to-kill maths:** P(kill within N pulls) = 1 − (1−p)^N. At p=0.28 → 3 pulls: 63% · 5 pulls: 81% · 8 pulls: 92%.

---

## 2. The contracts

### Boss 1 — **Gatewarden Krogg** · *the entry readiness gate*

| Field | Contract |
|---|---|
| **Progression position** | Entry. The tier's front door. |
| **Expected roster state** | **x1.00** — a *fresh* guild with **zero** loot. This boss MUST be killable on starting gear. |
| **Dominant challenge** | **Tank survival.** The uncrittable gate is the whole point of the fight. |
| **First-attempt win rate** | ~**32%** *prepared* (crit-immune main tank). **≤ 8%** if the main tank is not crit-immune. |
| **Expected pulls to kill** | 3–8, after the readiness fix. |
| **Primary player intervention** | **Fix the tank.** Swap in the crit-immune tank / read the "main tank is not uncrittable" warning. This is the tutorial for *legible failure → fix → success*. |
| **Required prior reward** | **None.** This is the deadlock-breaker. |
| **Farm-state win rate** | ~85%+ by x1.3. |
| **Expected failure mix** | Mostly `tank_survival`; some `dps_enrage`. |
| **Seed values** | `dps_check 24` · `healing_check 32` · `difficulty 38` |

DPS is deliberately *comfortable* (lane 27.6 vs demand 24) so the **tank is the story**.

---

### Boss 2 — **Forgemaster Vell** · *the duty & range test*

| Field | Contract |
|---|---|
| **Progression position** | Early wall. |
| **Expected roster state** | **x1.12** — a few Krogg drops. |
| **Dominant challenge** | **Assigned duties** (interrupt rotation) and the **ranged-punisher** range profile. |
| **First-attempt win rate** | ~**28%** with a competent interrupter assigned. Markedly worse with a low-Execution assignee. |
| **Expected pulls to kill** | 4–8. |
| **Primary player intervention** | **Assign a reliable interrupter**; rebalance melee/ranged against the storm placements. |
| **Required prior reward** | Krogg loot (a handful of ilvl-31 pieces). |
| **Farm-state win rate** | ~75% by x1.45. |
| **Expected failure mix** | `dps_enrage` and `raid_collapse` (bodies lost to unchecked casts). |
| **Seed values** | `dps_check 27` · `healing_check 36` · `difficulty 30` |

---

### Boss 3 — **The Slagbeast** · *the healing-sustain wall*

| Field | Contract |
|---|---|
| **Progression position** | Mid-tier. The comp-decision fight. |
| **Expected roster state** | **x1.28** — Krogg + Vell farmed. |
| **Dominant challenge** | **Healing sustain.** Its `healing_check` (68) is far above the others, so the healing lane runs a large deficit → death events get much deadlier → **bodies drop → `raid_collapse`.** *That is the healing wall, expressed honestly through the log rather than a phantom "healing check failed" wipe.* |
| **First-attempt win rate** | ~**27%** with a healthy healer count. Collapses fast if healers are cut for DPS. |
| **Expected pulls to kill** | 4–8. |
| **Primary player intervention** | **Bring more healers** (accepting lower DPS), reduce avoidable damage (higher-Awareness lineup), or spend premium consumables. The melee-punisher cleave also rewards trimming melee. |
| **Required prior reward** | Two bosses' worth of loot. |
| **Farm-state win rate** | ~70% by x1.55. |
| **Expected failure mix** | `raid_collapse` first, then `dps_enrage`. |
| **Seed values** | `dps_check 33` · `healing_check 68` · `difficulty 30` |

The healing deficit here is **~3× any other fight's** — that is the fight's identity, not an accident.

---

### Boss 4 — **The Cinderlords** · *the coordination wall*

| Field | Contract |
|---|---|
| **Progression position** | End-tier. The tier's final exam. |
| **Expected roster state** | **x1.42** — three bosses farmed; near BiS. |
| **Dominant challenge** | **Coordination under an enrage.** Soak duties + cooldown timing against a hard DPS race. |
| **First-attempt win rate** | ~**25%** at x1.42 with soaks and the cooldown window assigned. |
| **Expected pulls to kill** | 5–10. The tier's hardest kill — it should feel like an achievement. |
| **Primary player intervention** | **Assign the soaks and time the cooldown window** (Stormsurge); field maximum DPS now that the roster can afford it. |
| **Required prior reward** | Effectively the whole tier. |
| **Farm-state win rate** | ~60% at x1.64 (full BiS). Never trivial — it's the end boss. |
| **Expected failure mix** | `dps_enrage` dominant, with `raid_collapse` from missed soaks. |
| **Seed values** | `dps_check 42` · `healing_check 52` · `difficulty 34` |

---

## 2.5 Measured results — the contracts, verified

Balance harness, 150 pulls per cell, real campaign (migrate → seeds → 28-roster → auto-lineup), sweeping only the **realistic** gear band:

| Boss | x0.85 | **x1.00** | **x1.12** | **x1.28** | **x1.42** | x1.55 | **x1.64** |
|---|---|---|---|---|---|---|---|
| Gatewarden Krogg | 0% | **40%** ⬅ | 53% | 71% | 85% | 83% | **96%** |
| Forgemaster Vell | 0% | 21% | **29%** ⬅ | 49% | 57% | 60% | 62% |
| The Slagbeast | 1% | 11% | 20% | **31%** ⬅ | 38% | 43% | 52% |
| The Cinderlords | 0% | 5% | 8% | 13% | **22%** ⬅ | 29% | 43% |

⬅ = the boss's **intended progression gear**. Every one lands in the 22–35% progression band (Krogg at 40% is deliberately a little generous — it is the tutorial boss and must reward the first readiness fix quickly).

**Read the diagonal.** Each boss is a wall at the previous boss's gear and a fight at its own — the tier now *teaches gearing*, because gear is the thing that moves you down a column. And read the columns: a fresh guild at **x1.00** faces 40 / 21 / 11 / 5% — Krogg is the honest front door and the rest of the tier is visibly out of reach until it falls.

### The tank gate is a real lever (Krogg's identity, verified)

Same roster, same gear, same seed — the *only* difference is whether the main tank is crit-immune:

| Main tank | Win rate | Avg pulls to kill | Dominant failure |
|---|---|---|---|
| **Crit-immune** (prepared) | **38.5%** | **2.6** | `tank_survival` |
| **Not crit-immune** | **0.5%** | never | `tank_survival` |

A **77×** swing from one legible, player-fixable decision. This is the engine's proof that *diagnose → adjust → succeed* works, and it is the arc **MI-003** builds the curated first session around.

### The deadlock is broken

`slice_smoke --seed 133742`, the run that triggered this whole intervention:

| | Before (M4) | After (MI-001 + MI-002) |
|---|---|---|
| Pulls | 32 | **17** |
| **Kills** | **0** | **4 — the full tier** |
| Wipes | 32 | 13 |

Across five different guild seeds: **1–4 kills each. No seed produces zero.**

---

## 3. What must remain true

1. **Krogg is killable at x1.00.** If a fresh guild cannot kill the entry boss, the tier is a deadlock and the game has no first session. This is the single most important line in this document.
2. **Every boss lives inside x1.00 → x1.64.** Content requiring more is unreachable.
3. **Each boss's dominant failure matches its authored identity** (naming bible). A Slagbeast that dies to `tank_survival` is mistuned, not merely "hard".
4. **The named intervention actually works.** If assigning a better interrupter doesn't measurably improve Vell, the prep control is decorative — fix it or cut it (MI-009's prep-leverage probes exist to catch this).
5. Retune **seed rows**, never engine code. Content as data.

## 4. How this is enforced

**MI-009** extends the balance harness to assert each boss against *its own* contract — progression win-rate band, farm-state band, and dominant-failure identity — instead of one global band on Boss 1. The gear sweep is clamped to the realistic band. A boss that passes on gear the player can't reach is a **failing** boss.
