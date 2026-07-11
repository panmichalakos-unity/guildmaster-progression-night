# Guildmaster: Progression Night — The First Session Contract (Night One, v1.0)

**Created by MI-003 (2026-07-11).** The first ten minutes are the whole pitch. A player who does not, in their first session, *diagnose a failure, fix it, and see the fix work* has not met the game — they have met a dice roller. This document is the contract for that experience, and `tests/first_night_test.gd` enforces every line of it.

> **The one-line bar:**
> *You are handed a losing lineup. The game tells you why. You make one decision. You kill the boss.*

---

## 1. Why the first session must be authored

Random rosters do not teach. Measured across ten guild seeds before this ticket, **not one** produced a first session with a decision in it:

| What the roster handed the player | How often | What the player learned |
|---|---|---|
| Best tank already crit-immune → default lineup is correct | 6 / 10 | Nothing. The game silently solved it for them. |
| No tank could be crit-immune at all | 3 / 10 | Nothing. A 0.5% brick wall with no lever — frustration, not a lesson. |
| A real, fixable choice | **0 / 10** | — |

So Night One **authors exactly one thing**: the tank corps. Everything else — the other 24 raiders, their traits, gear, and life situations — stays procedurally generated from the seed. See `game/demo_campaign.gd`.

---

## 2. The scenario

**The Northern Accord.** You have just taken over a guild that has been wiping.

Their best-geared tank is a hide-armoured bruiser — the biggest gear score in the room, and their obvious main tank. He is also, because of what his spec is, **not crit-immune**, and no amount of Night One loot will make him so. The properly-plated tank who *is* capped sits below him on the gear list.

**The game's own default lineup walks straight into it.** `auto_lineup` picks tanks greedily by `gear_score`, so it fields the star tank as main. That is the entire point: *the default is a heuristic, not an answer.* The lesson is not "the computer lied to you" — it is **"the biggest number is not the right call,"** which is the thesis of the whole genre.

| Role | Who | Gear | Crit-immune? |
|---|---|---|---|
| **Main tank (default)** | the incumbent — hide-armoured, best-geared | ilvl 24 | ❌ **no** — his spec caps far higher |
| **The fix** (in the lineup, not main) | the plated tank | ilvl 23 | ✅ **yes** |
| The off-tank (on the bench) | credible third tank | ilvl 22 | — |

**The fix:** bench the star tank. The crit-immune tank inherits the main-tank duty, and the off-tank steps up from the bench.

That is a genuinely uncomfortable decision — *you are benching your best player* — which is exactly the kind of call this game is about.

---

## 3. The contract (enforced by `tests/first_night_test.gd`)

Every line below must hold **for every guild seed**, not just the demo's:

1. **The flaw is present.** The default lineup's main tank is the incumbent, and he is **not** crit-immune.
2. **The failure is legible *before* the pull.** Raid prep warns: *"Main tank {name} is not uncrittable — spike-death risk."*
3. **The failure is legible *after* the pull.** Pulling anyway wins **≤ 8%**, and the dominant `wipe_reason` is **`tank_survival`** — the wipe names the tank, not the dice.
4. **The fix exists and works.** Benching the incumbent promotes a **crit-immune** main tank. (Not merely "a different tank" — the fix has to actually fix it.)
5. **The fix pays off.** After that one change the kill lands in **2–9 pulls** — earned, but not a grind.
6. **It is deterministic.** Same seed → same scenario, same lineup, same win rate.

### Measured (150 pulls per lineup, 10 guild seeds)

| Guild seed | As handed to you | After the one fix | Kill in |
|---|---|---|---|
| **133742** (demo default) | **3.3%** | **40.7%** | **~2.5 pulls** |
| 1 | 2% | 21% | ~4.7 pulls |
| 42 | 2% | 45% | ~2.2 pulls |
| 777 | 1% | 25% | ~4.1 pulls |
| 90210 | 1% | 43% | ~2.3 pulls |
| 2024 | 2% | 40% | ~2.5 pulls |
| 55 | 1% | 46% | ~2.2 pulls |
| 8 | 2% | 44% | ~2.3 pulls |
| 314 | 2% | 31% | ~3.3 pulls |
| 2718 | 2% | 46% | ~2.2 pulls |

**The arc holds on 10/10 seeds.** One decision is worth **roughly forty points of win rate** — the strongest lever in the game, and now the first one the player ever touches.

---

## 4. What had to change to make this possible

The tank gate was *already* worth a 38-point swing — but the player **could never get it wrong and could never fix it**, because crit-immunity was a pure item-level threshold (`avg_ilvl >= 22`) applied to every tank alike. Since `gear_score` is just the sum of the same 7 slot item levels, **"crit-immune" was identical to "best-geared"** — and the lineup picker takes tanks by gear score. The strongest lever in the game was decided entirely by time, never by judgement.

**ADR-0025** made the defense cap a **per-spec** property (`spec.defense_cap_ilvl`, seed data):

| Tanking spec | Defense cap | Reads as |
|---|---|---|
| **Bulwark** (Vanguard) | ilvl 20 | plated; capped early |
| **Bastion** (Templar) | ilvl 21 | plated; capped early |
| **Oakhide** (Warden) | **ilvl 27** | hide-armoured; must badly over-gear to reach the cap |

Now a tank can out-gear the room and still be crittable — so **fielding the tank who is "worse" on paper is the right call**, and the player has to understand *why* to make it. An Oakhide is not a bad spec; he is a fine tank once the tier has fed him. That is a gearing goal, not a dead pick.

---

## 5. What this contract does **not** do

- It does not curate DPS, healing, comp, or range. Those levers exist (measured: comp is worth ~11 points, healer count ~4 on this boss) but they are **not** Night One's lesson. One legible cause, one decision. Stacking flaws would muddy which fix actually mattered — the exact failure the intervention doc warns about.
- It does not survive contact with M5. `game/demo_campaign.gd` is slice scaffolding; **M5-001's guild genesis owns the real new-campaign path**, and must carry this contract forward or the game loses its opening.

---

## 6. How it is verified

```bash
# the arc, end to end, on the demo seed
godot --headless -s tools/smoke/first_night_smoke.gd -- --seed 133742

# the contract, on all ten guild seeds
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/first_night_test.gd
```

The smoke prints the whole story:

```text
FIRST NIGHT SMOKE: seed=133742
  default main tank: Shadowwhisper (Oakhide) — CRITTABLE
  prep warning: Main tank Shadowwhisper is not uncrittable — spike-death risk
  as handed to you:     3.3% win   (top wipe: tank_survival)
  bench Shadowwhisper -> main tank is now stormblade10 (Bulwark)
  after the one fix:   40.7% win   -> a kill in ~2.5 pulls
FIRST NIGHT SMOKE: PASS
```

That is the game, in six lines. **MI-010 (the human Fun Gate) scores this session.**
