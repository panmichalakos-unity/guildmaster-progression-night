# Guildmaster: Progression Night — Between-Nights Loop (v0.1)

The management layer that *feeds* the raid night. Converts a scarce **weekly time budget** into raid readiness across several axes — gear, skill, supply, roster, cohesion — where you can't max all of them.

## The weekly budget frame
Two constraints in tension:
- **Guild action budget** — a fixed number of management actions/time slots per week (yours to allocate).
- **Raider time budgets** — each raider's own hours (from their life situation). The parent can't farm at 2 p.m.; the student can grind all week but flakes. *This is where the life-situation knobs finally pay off.*

You allocate across lanes; a progression week might be "all-in Supply + Rest," a farm week "Gearing + Development." You're never doing everything — and the raid result traces back to the week you planned.

## The five core lanes (v1)

| Lane | Actions | Feeds | Key trade-off |
|---|---|---|---|
| **Gearing** | run dungeons for **Marks** (currency) + gear drops | roster item level; expansion re-gear | who you send — gear the recruit vs let mains bank Marks |
| **Development** | drill skill facets, spec-test, **coach** (Mentor→Project) | skill growth, familiarity, chemistry | long-term investment vs short-term readiness |
| **Supply** | stock consumables: farm mats (time) / buy (gold) / convert | the per-fight consumable economy | time vs gold vs risking a shortfall on the hard pull |
| **People** | 1:1s, mediation, recruit/scout, **guild social night** | morale, retention, roster health, cohesion | finite social bandwidth — who gets it this week |
| **Rest** | schedule nothing | fatigue recovery | the sustainability valve — a real, correct move |

**Notes on the lanes:**
- **Marks** = a badge-style currency from dungeons → catch-up gear that doesn't depend on raid RNG (era-authentic, and the natural expansion re-gear path).
- **Coaching** is two systems in one action: a *Mentor* vet paired with a *Project* recruit accelerates growth **and** builds a relationship.
- **Guild social night** = a slot spent on a non-raid event → chemistry + morale, no gear/skill. Mechanizes "we're not just a grind." Cheap, and fits the not-sweaty ethos.
- A **farming push** (rally the guild hard on Supply before progression) is *emergent* from heavy Supply allocation — no special mechanic needed in v1.

## Professions (light abstraction)
Professions are a **guild-level crafting capacity** per type (alchemy capacity converts mats→consumables faster; smithing crafts BiS slot pieces), derived from the roster — **not** per-avatar micro. Keeps the maintainability bar. *Deferred to v1.1;* v1 Supply uses buy + a base mats→consumables conversion.

## Action resolution (lane outcomes) — *resolves P0 #6*
Each weekly action resolves like a **light version of the raid resolver**: roll the relevant attributes against a difficulty → a defined output. Same philosophy (stat-driven, legible), lighter machinery.

| Lane action | Roll / driver | Produces | Writes to |
|---|---|---|---|
| **Dungeon run** (Gearing) | party gear + skill vs dungeon difficulty | **Marks** + a chance at gear; minor skill XP | `Avatar.marks`, `AVATAR_ITEM`, skill facets |
| **Drill** (Development) | trainee `potential`/`growth_rate`, ceiling-gated | **skill-facet XP** | Player skill traits |
| **Coach** (Development) | Mentor's skill + `Mentor` quirk → trainee | boosted XP **+** relationship build | skill traits, `RELATIONSHIP` |
| **Spec-test** (Development) | reps on a spec | **familiarity** gain | `Avatar.familiarity` |
| **Farm mats** (Supply) | time × who's sent | **mats** | `GUILD_TREASURY.mats` |
| **Buy / convert** (Supply) | gold or mats spent | **consumables** | `GUILD_STOCKPILE` |
| **1:1 / mediation** (People) | your action + raider psychology | morale repair / loyalty nudge / defuse a feud | `PLAYER_WEEK_STATE`, `loyalty_current`, `RELATIONSHIP` |
| **Recruit / scout** (People) | scouting effort | tightens `PROSPECT_ASSESSMENT` | recruitment overlay |
| **Social night** (People) | — | broad morale + chemistry bump | morale, `RELATIONSHIP` |
| **Rest** | — | fatigue recovery across the roster | `fatigue_current` |

Three principles keep it coherent:
- **Skill growth respects the ceiling.** Drill/coach XP is gated by `potential` and slowed by `growth_rate` — diminishing returns near the cap. You can't grind anyone into a god; like FM, not everyone reaches full potential, and full potential is rarely maxed.
- **Bounded variance, no feel-bad weeks.** Actions roll (a good dungeon drops more) within readable ranges — never a zero-outcome week. "Skill dominates, luck flavors," same as raid resolution.
- **Every output writes an existing field.** The *inputs* were the gap, not new state. This is purely the action-resolution layer on top — a pure `(action, participants, seed) → outcome` function, testable by the same batch harness.

New: **`ACTION_TYPE`** (seed data — the table above as rows); `WEEK_ACTION` stores the resolved output.

---

## The Guild Economy
"The guild provides" needs funding. The treasury is also the **mechanical bridge between your social management and your raid capability** — this is where it all connects.

### The treasury (three pools)
- **Gold** — currency (scalar).
- **Mats** — abstract raw crafting input (scalar in v1; itemized later).
- **Consumable stockpile** — itemized finished flasks/pots/food (what the raid burns per fight).

### Income streams
- **Player donations *(primary)*** — gold, mats, and consumables flowing into the bank. **Modeled as passive weekly income, not a click-to-collect grind:**
  ```
  weekly_donations = contribution_policy_rate × guild_health
  guild_health     = f(avg loyalty_current, morale, fairness_perception)
  ```
  A loyal, happy, fairly-run guild funds itself; a toxic one dwindles. *You earn income by being a good leader* — no micro, and it closes the loop with loot/chemistry/morale.
- **Raid proceeds** — unawarded loot: vendor trash → gold, disenchanted gear → mats. Raiding pays for itself, partly.
- **Farming surplus** — the Gearing/Supply lanes deposit more than is immediately consumed.
- **Crafting sales** *(v1.1)* — professions produce goods sold for gold.

### Expenditures
- **Provision** — if "guild provides" is on, the bank funds raiders' per-fight consumables. **Explicit burn transaction:** on pull resolve, `GUILD_STOCKPILE` decrements per `PULL_CONSUMABLE`, with a `TREASURY_LEDGER` consumption entry when guild-provisioned.
- **Repairs** — raid nights cost repair gold; **wipe-heavy progression nights drain the treasury** (direct tie to the resolution engine).
- **Buying** — the Supply lane's "buy" path spends gold.
- **Recruitment incentives** *(v1.1)* — signing bonuses to poach talent.

### Policies (standing levers, low micro)
| Policy | Options | Trade-off |
|---|---|---|
| **Provision** | Guild-funded / Subsidized / BYO | loyalty ↑ vs gold burn |
| **Contribution** | Mandatory tithe / Suggested / Voluntary | income ↑ vs morale friction |
| **Repair** | Guild-covered / Not | goodwill ↑ vs gold |

### The feedback loop (and the death spiral)
Good leadership → high guild health → strong donations → the bank affords generous provision/repairs → morale/loyalty stay high → *more* donations. **A well-run guild is self-sustaining.**

The inverse is the drama: toxic culture → donations dry up → can't afford provision → forced onto BYO → morale drops further → attendance/performance fall → wipe-heavy nights spike repair costs → bankruptcy. That spiral feeds the **sacking meter** and is a legible, earned way to lose.

---

## Data model touchpoints
- **Reads:** PLAYER (loyalty_current, morale via PLAYER_WEEK_STATE, time_budget) · GUILD.fairness_perception · LOOT_DROP (unawarded → proceeds) · PULL (wipes → repair cost) · GUILD_CONFIG (policies).
- **Writes:** GUILD_TREASURY (gold, mats) · GUILD_STOCKPILE (consumables) · TREASURY_LEDGER (every income/expense — the audit trail) · PLAYER_WEEK_STATE (morale from provision/social) · PLAYER.loyalty_current · skill facets / familiarity (from Development) · WEEK_ACTION (the weekly plan as data).
- **New tables (folded into data model v0.4):** GUILD_TREASURY · GUILD_STOCKPILE · GUILD_CONFIG (policies; merged v0.8) · TREASURY_LEDGER · WEEK_ACTION.

## v1 scope
- **In:** the weekly budget frame + raider time gating; the 5 lanes; the guild economy — treasury (gold/mats/consumables), **donation-driven passive income**, raid proceeds, repairs, the three policies, buy + base mats→consumables conversion; `TREASURY_LEDGER` for observability.
- **Layer later:** professions/crafting capacity, crafting sales, recruitment incentives, itemized materials, the persistent **guild knowledge library** (theorycraft that compounds across nights/expansions), collective farming-push events.

---

*v0.1 — between-nights systems locked; economy weights and budget sizes symbolic, to be tuned. IP-original naming throughout.*

---

> ### UPDATE (2026-07-19) — implementation state
> The action-resolution layer above is **live** (M5-004, ADR-0037): all five lanes resolve as bounded quality rolls over `ACTION_TYPE` seed rows (`data/seeds/action_type.csv` — authored from this doc's own table, since M1's "starter kit" never actually included them), the weekly time budget is a hard wall, every applied action lands atomically with its `WEEK_ACTION` audit row (`decided_by`-stamped) and `TREASURY_LEDGER` entries, and the digest reports the week's actions. Deferred per this doc's own scoping: **coach** (needs Mentor/relationship depth — M10), **recruit/scout** (M8), dungeon **gear drops** + minor skill XP (M6-005), professions (v1.1). The economy sections below (donations, repairs, provisioning, policies) remain design — **M7** owns them; today the treasury holds gold/mats, the stockpile holds consumables, and farm/buy/convert move them with ledger rows.
