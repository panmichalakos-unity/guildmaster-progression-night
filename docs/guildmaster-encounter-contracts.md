# Guildmaster: Progression Night — Encounter Progression Contracts (v1.0)

**Created by MI-001 (2026-07-11). Retuned by MI-009 (2026-07-12).** The missing artifact that let the tier become uncompletable: boss demands were authored as "symbolic" numbers with **nothing tying them to what a real roster produces**. This document is the source of truth, and **`data/seeds/encounter_contract.csv` is now its machine-readable half** — the harness asserts every boss against its own row, so "retuning a boss without updating its contract is a bug" is a **failing build** rather than a convention.

> **The governing question for every boss:**
> *At what plausible roster state should this boss be attempted, and what player-controlled intervention makes the next attempt better?*

---

## ⚠️ RETUNED BY MI-009 (2026-07-12) — READ THIS BEFORE THE TABLES BELOW

**The seed values and win-rate tables in §2 and §2.5 are superseded by the table here.**

MI-009's prep-leverage probes found that **healers were a trap**: bringing more of them made the raid *worse on every boss* — including **The Slagbeast, the fight whose entire identity is the healing wall.** The optimal play was to strip healers and stack DPS. Three things conspired, and all three were authored here:

| | |
|---|---|
| **The demand was unreachable** | Slagbeast asked for **77** healing against a lane that tops out near **46**. Not a wall — a locked door. A marginal healer barely dented it. |
| **The healers' contribution was wasted** | Slagbeast's tank check was *saturated* (p≈0.94), so the healing that feeds tank survival bought nothing… |
| **…while the DPS they cost was not** | …and the damage sacrificed came straight off `dps_enrage`, the only gate actually deciding the fight. |

**The fix** (seed data + two tuning constants): healing demands made **closable** by a good healer comp; `tank_healing_share` 0.35 → **0.50**, so healers protect a gate that actually binds; `healing_deficit_lethality` 0.6 → **1.0** plus two more cascade beats on Slagbeast, so a thin healing lane genuinely **bleeds bodies**.

**The Fun Gate verdict (ADR-0029) was a hard constraint.** The win rate at the default comp had to land where Panos played it — and it does, within 2 points on every boss. The *gradient* changed; the *feel* did not.

> ### 🔒 "More healers is always better" is **NOT** the rule.
> Over-healing a DPS race *should* cost you — healers run **−13.5pp** on Cinderlords, and that opportunity cost is what makes comp a **decision** rather than a checklist. What a lever may never do is fail on **its own** boss. That is the invariant the harness asserts.

### The contracts as they now stand

| Boss | Expected gear | Win @ that gear | Band | Farm @x1.64 | Dominant failure | **Signature lever** |
|---|---|---|---|---|---|---|
| Gatewarden Krogg | **x1.00** (a fresh guild) | **40%** | 30–50% | 97% | `dps_enrage` | **tank_cap · +40.0pp** |
| Forgemaster Vell | x1.12 | **34%** | 24–44% | 65% | `dps_enrage` | **duties · +5.5pp** |
| The Slagbeast | x1.28 | **32%** | 22–42% | 58% | `tank_survival` | **healers · +10.0pp** |
| The Cinderlords | x1.42 | **23%** | 13–33% | 45% | `dps_enrage` | **consumables · +6.0pp** |

**Slagbeast dies to `tank_survival`, and that is correct.** A healing wall kills by running the healers dry until the tank drops. It is not Krogg's readiness gate in disguise, and the diagnosis (ADR-0028) keeps them apart exactly where it matters: Krogg's contributing factor is *"not crit-immune"*, Slagbeast's is *"the healing lane fell short"*, and its recommendation reads *"put more healing on the tank — he is being out-damaged, not out-played."*

### Prep leverage — is raid prep tactics, or administration?

Same seed, same roster, same gear; **one** decision changed. Percentage points gained by making the **right** call:

| Lever | Krogg | Vell | Slagbeast | Cinderlords |
|---|---|---|---|---|
| **tank_cap** | **+40.0** | +0.0 | −2.5 | +0.0 |
| **duties** | +0.0 | **+5.5** | +2.0 | +2.5 |
| **healers** | −3.0 | −13.5 | **+10.0** | −12.5 |
| **range_comp** | +14.5 | +12.5 | +8.0 | +10.0 |
| **consumables** | +10.0 | +7.0 | +11.0 | **+6.0** |

Every lever is a real decision **somewhere**, and every boss answers to **its own**. Enforced in CI by `--probes`.

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
3. **Each boss's dominant failure matches the `dominant_failure` in its contract row** — the machine-readable one in `data/seeds/encounter_contract.csv`, which the harness asserts *at the boss's own expected gear*. A boss that dies to something other than its contract is not the fight it says it is.
4. **Each boss answers to its own signature lever** (`signature_lever`, ≥ `signature_min_delta`). If bringing healers doesn't measurably improve the healing wall, the prep control is decorative — fix it or cut it. **This is what boss identity actually means**, and MI-009's prep-leverage probes assert it.
5. **A lever is allowed to COST you on a fight it is not for.** Stacking healers into a DPS race *should* hurt (−13.5pp on Cinderlords); that opportunity cost is what makes comp a decision rather than a checklist. "More healers is always better" is **not** the rule.
6. Retune **seed rows**, never engine code. Content as data.

> ### ⚠️ Superseded invariant — do not act on it
> An earlier version of this list said: *"A Slagbeast that dies to `tank_survival` is mistuned."* **That is wrong and has been removed.** Slagbeast's contracted dominant failure **is** `tank_survival`, because that is what a healing wall actually does: it runs the healers dry until the tank drops. It is not Krogg's readiness gate in disguise — the diagnosis (ADR-0028) separates them by *contributing factor* (*"the healing lane fell short"* vs *"not crit-immune"*) and by *recommendation* (*"put more healing on the tank"* vs *"field a crit-immune tank"*).
>
> Boss identity lives in the **signature lever**, not in the wipe-reason string. An agent "fixing" Slagbeast to stop it dying to `tank_survival` would be breaking a boss that works.

## 4. How this is enforced

**MI-009** asserts every boss against *its own* contract row — progression win-rate band, farm band, monotonicity in gear, and dominant failure **at the gear the boss is for** — instead of one global band on Boss 1. The gear sweep is clamped to the reachable band, `seed_check` fails a boss with **no** contract row, and CI gates on both `--assert-contracts` and `--probes`. A boss that passes only on gear the player cannot reach is a **failing** boss.

> **Terminology debt (not a blocker).** `farm_win_min` currently sits at 48% (Slagbeast) and 35% (Cinderlords) — which is *late progression*, not what an MMO player means by **farm** (a reliable repeat clear). These are pure-resolution numbers measured **before** learning, Marks, form, consumable scarcity and better planning enter the loop in Phase B. Revisit the thresholds *and the word* once those systems exist, and consider splitting the concept into `expected_progression` / `prepared` / `mastery` / `farm`, plus distinguishing **per-pull** win rate from **per-night clear** probability.
