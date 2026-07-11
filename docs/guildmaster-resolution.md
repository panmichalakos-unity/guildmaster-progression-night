# Guildmaster: Progression Night — Raid Resolution System (v0.1)

Systems locked; numeric constants are symbolic (`scale`, clamps, win-rate targets) and get tuned later.

## Philosophy
Not a combat sim — a **stat-driven probability engine presented as a live event.** Checks are the skeleton; the phase timeline is the flesh that produces the combat-log show, the individual moments, and the surface for live jump-ins.

**Legible failure is the engine.** Every wipe names a check *and* a culprit. The diagnose → adjust → succeed loop is the core fun of the genre — nothing wipes for opaque reasons.

> ✅ **STAGE 3 REWORKED — MI-002 (2026-07-11), ADR-0023.** Checks are now of **two kinds**:
>
> - **GATING — `dps` and `tank`.** Rolled through the sigmoid; these alone decide kill vs wipe. DPS/enrage is the race; tank survival is the near-binary gate (a non-uncrittable main tank eats a flat margin penalty). A healthy raid's odds are now **p(dps) × p(tank)** — not a four-way product.
> - **PRESSURE — `healing` and `mechanic`.** *Not* rolled and *never* a kill-gate. They report whether the lane met its demand, and their real teeth are in the **timeline**: a healing shortfall raises the effective severity of every death event (`healing_deficit_lethality`), and low awareness already drives avoidable deaths. Deaths piling past the collapse threshold still wipe the raid — that is how healing/mechanic failure stays lethal: *the raid runs out of bodies.*
>
> **Why:** previously all four rolled independently and *all* had to pass, capping even a healthy raid at ~41% **and double-counting failure** — the timeline already punished low awareness and thin healing through events, then the checks punished them again. Pressure lanes now surface as **contributing factors** in the diagnosis, never as phantom independent wipes. See `guildmaster-intervention-and-realignment.md` §10.1.

## Pipeline (5 stages)

**1 — Per-participant contribution**
```
contribution = throughput_ceiling      # gear (item_level) + spec — what the kit *could* do
             × skill_realization        # fraction of that ceiling actually hit
             × situational_mods         # morale · fatigue · form · consumables · chemistry · quirks · your_call
             × (1 ± variance)           # width set by Consistency
```
- **skill_realization** folds Execution × role_proficiency × familiarity. **spec_difficulty** subtracts, but only bites when skill is low → *hard spec + low skill = liability; hard spec + high skill = monster.*
- **situational_mods** are multiplicative and each clamped (~0.8–1.2, dir.) so nothing explodes.
- **variance** width comes from Consistency (steady vs spiky).

**2 — Lane aggregation** → raid DPS, raid HPS, mechanic-handling, tank survivability.
Key coupling: **healing demand = tank damage taken + avoidable damage eaten (Awareness).** A sloppy raid fails the healing check even with great healers. This coupling is where "it all connects."

**3 — Check resolution (margin → probability)**
```
margin  = raid_output − boss_demand
P(pass) = sigmoid(margin / scale)
```
- Saturated margin → decisive (one-shot or clean wipe). Margin ≈ 0 → coin-flip (the exciting zone).
- Hard checks (tank-alive, enrage) use a **steeper curve** — a cliff, not a slope.

**4 — Timeline & outcome** → run phases; **events** fire (raiders roll attribute vs severity); deaths cascade (fewer bodies → lower DPS/HPS → other checks tip). **Kill** if boss HP → 0 before a hard-fail; else **wipe** on the dominant failed check → `wipe_reason`.

**5 — Write state** → each participant gets a `performance_rating`; the pull writes morale/fatigue/form deltas, updates `encounter_progress`, emits `PULL_EVENT` log rows, and may spawn a `DRAMA_EVENT`.

## Checks catalogue
| Check | Inputs | Demand from | Curve |
|---|---|---|---|
| DPS / enrage | raid DPS lane | boss HP + enrage timer | steep |
| Healing sustain | raid HPS vs incoming | tank dmg + avoidable dmg | moderate |
| Mechanic execution | per-event Awareness rolls | phase severities | per-event |
| Tank survival | EHP × mitigation × tank-healing, **uncrittable gate** | boss melee / spikes | near-binary |
| Resistance | AVATAR_RESISTANCE vs element | elemental phase | moderate |
| Assigned-duty | assignee role_prof + Execution | interrupt / soak / dispel window | per-event |

**Tank check is deliberately near-binary** (and era-authentic): not uncrittable → spike death → wipe. Makes tank gearing + healer-on-tank assignment a load-bearing decision, not a rounding error.

## Difficulty via margin (no special-casing)
Boss difficulty just slides `boss_demand`; the sigmoid does the rest:
- **Over-geared vs low tier** → big + margin → curve saturates → **one-shot.**
- **Matched progression** → margin ≈ 0 → **22–35% win/pull** → a kill in **3–8 pulls**. This is the "one more pull" zone.
- **Under-geared** → big − margin → **decisive wipes.**

> ⚠️ **Superseded number — MI-001 (2026-07-11).** This section previously targeted **~60–80% win/pull** for matched content. That was wrong: at 70%/pull a progression boss dies on attempt 1–2, which is a *farm* feel, not progression, and it contradicts the learning arc's own "8%… 3%… KILL" language two sections down. 60–80% is now the **farm-state** band.
>
> **Per-boss win-rate, gear, and dominant-failure contracts now live in [`guildmaster-encounter-contracts.md`](guildmaster-encounter-contracts.md)**, which is the source of truth for tuning. Boss demands must never again be authored as free-floating "symbolic" numbers — they are anchored to what a real roster actually produces, inside the realistic **x1.00 → x1.64** in-tier gear band.

## Learning arc (the emotional core)
`encounter_progress` — tracked **per guild per encounter**, persists across nights — climbs with attempts and nudges `skill_realization` up / avoidable-death rates down.
- **Gated to hard fights:** only bites when `|margin|` is near zero. Farm content (strong + margin) short-circuits it and dies on attempt 1 → easy bosses stay fast; the "8%… 3%… KILL" arc is reserved for content that earns it.
- Drives the pull-count drama and the **"one more pull?"** tension (progress vs fatigue).

## Performance rating (not raw output)
`performance_rating` = FM-style **1–10**, contribution vs **expected for their gear + role** (a 6.2, not "43k"). Powers three systems at once:
- **Loot MVP** — reward the raid's *actual* best, not the highest-geared.
- **Morale deltas** — did you carry or feed?
- **Post-night report.**

`raw_contribution` is kept alongside for the combat log and the MVP math.

## Event system (data-driven)
Events are **seed data, not code** — a new boss is new rows, engine untouched.
```
EVENT_TYPE       : reusable palette — trigger · target_selector · roll_attribute · effect_category · log_template
ENCOUNTER_EVENT  : places an EVENT_TYPE into an encounter/phase with tuned severity + weight
PULL_EVENT       : the fact — what actually fired this pull (target, roll, outcome, log line)
```
Each event: pick target → roll `attribute vs severity` → apply effects (damage / death / rating delta / state delta) → emit a log line.

**Target selectors include range:** `target_selector` values cover role *and* range — `tank / healer / melee / ranged / random / assigned`. Placing harmful events on `melee` or `ranged` is how a boss gets a **range profile** (a melee-punisher cleaves the melee camp) — pure seed data, no engine change. The raid-prep comp check derives range-balance warnings from these placements.

### Event palette (core 5 + extended — all in)
| Event | Trigger | Roll | Effect |
|---|---|---|---|
| **Avoidable death** | mechanic hit | Awareness vs severity | death + rating hit |
| **Clutch save** | ally near death | Consistency / *Clutch* | prevents death + rating boost |
| **Near-death** | damage spike | survives the roll | tension, minor rating |
| **Cooldown moment** | phase beat | *(your jump-in point)* | output surge window |
| **Cascade death** | resource starvation | no roll — overwhelm | death, not own fault |
| **Assigned-duty check** | interrupt / soak / dispel window | assignee role_prof + Execution | fail → raid damage or add lives |
| **Tank swap / spike** | stack threshold | off-tank Awareness + Familiarity | fail → tank death → wipe |
| **Soft enrage push** | enrage timer | DPS margin vs timer | kill-or-melt |
| **Tilt cascade** | after a death | *Tilt-Prone* quirk | temp Execution hit; spiral risk |
| **Rally / morale surge** | after a death | *Glue* / Influence | resists the spiral |
| **Consumable payoff / shortfall** | lethal check | had / skipped the consumable | survive / die — makes prep visible |
| **Resistance moment** | elemental phase | AVATAR_RESISTANCE vs element | mitigates / scrambles |
| **Carry window** | hot form + high skill | — | big rating boost, drags a check |

**`log_template` examples:** `"{tank} eats a fifth stack and gibs — wipe."` · `"Fire elixir holds — {name} survives the breath at 200 HP."` · `"{name} is locked in tonight, dragging the DPS check alone."`

## Involvement integration
The **same pipeline** runs at every involvement level:
- **Auto** — default policies (assignments, consumable tiers, cooldown timing) drive the rolls.
- **Assisted / manual** — your jump-ins inject directives at **phase boundaries** and **cooldown-moment events** (move, pop CD, swap, wipe-call). Directives still route through the participant's attributes — a shaky hand fumbles the right call. Manual is a lever, not a god button.

## Data model touchpoints
- **Reads:** PLAYER traits + PLAYER_WEEK_STATE · AVATAR power + familiarity + AVATAR_RESISTANCE · assignments (PULL_PARTICIPANT) · PULL_CONSUMABLE · RELATIONSHIP · PLAYER_QUIRK · ENCOUNTER + ENCOUNTER_PHASE + ENCOUNTER_EVENT · GUILD_ENCOUNTER_PROGRESS.
- **Writes:** PULL.outcome + wipe_reason · PULL_PARTICIPANT.performance_rating + raw_contribution · PULL_EVENT · PLAYER_WEEK_STATE deltas · GUILD_ENCOUNTER_PROGRESS · DRAMA_EVENT.
- **New tables (now folded into the data model v0.2):** ENCOUNTER_PHASE · EVENT_TYPE · ENCOUNTER_EVENT · PULL_EVENT · GUILD_ENCOUNTER_PROGRESS. Plus `PULL_PARTICIPANT`: `performance_score` → `performance_rating`, add `raw_contribution`.

## v1 resolution scope
- **In:** contribution → lanes → checks (DPS, healing, tank, mechanic, **assigned-duty**) → margin/sigmoid → phase timeline with the **core-5 events + assigned-duty checks + cooldown-moment events** → rating → learning arc. *(Assigned-duty + cooldown promoted to v1 — they're the payoff of the raid-prep assignment suite: interrupts, soaks, and lust/cooldown timing.)*
- **`throughput_ceiling` now reads the derived `gear_score`** (per-slot equipped gear — see gear doc), not a static `item_level` scalar.
- **Layer later:** resistance checks, quirk-driven events (tilt / rally / carry), the remaining palette, and manual jump-in directives.

---

*v0.1 — resolution systems locked; constants symbolic, to be tuned against the ~60–80% matched-content win target. IP-original naming throughout.*
