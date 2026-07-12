# Guildmaster: Progression Night — Content Volume & Definition of Done (v0.1)

Pins scope: how much content v1 needs, and the bar for "done." Resolves readiness-review **move 2**. Numbers are recommendations sized for **sustainable solo authoring** — the systems do the heavy lifting, so content stays lean.

## Guiding principle
**Content = rows (your content-as-data convention); variety = systems.** Roster generation, resolution RNG, loot drama, and emergent archetypes produce the gameplay variety. So the content target is "enough for real comp gaps + a progression ramp," not breadth for its own sake. Fewer, well-tuned rows beat many shallow ones.

## Content volume targets

| Category | Phase A (slice) | **v1 EA target** | Notes / authoring load |
|---|---|---|---|
| Roles | 4 | **4** | fixed: tank / healer / melee / ranged. **Melee vs ranged is a boss-mechanic dimension** (see below) |
| Classes | 3 | **6** | identity + utility gaps; each with exactly 3 specs |
| Specs | ~4 | **18 (3/class)** | coverage: 3 tank · 4 heal · 5 melee · 6 ranged. *Bespoke tuning* |
| Raid utilities | 3 | **~8** | battle-rez, haste burst, interrupts, dispels, immunity, buffs. Scarcity = comp tension |
| Synergy tags | 2 | **~5** | caster-cleave, melee-cleave, mana-battery, threat-support, magic-debuff |
| Consumables | 3 | **~10** | premium vs basic tiers → the per-fight decision |
| Raids (tiers) | 1 | **2** | entry + step-up = a progression arc within the expansion |
| Bosses / encounters | 3–4 | **~12** (6/raid) | **the main bespoke authoring** — phases + event placements + loot |
| Loot items | ~12 | **~65** | *templatable* by slot × tier × role — low authoring pain |
| Marks vendor gear | — | **7 / tier (one per slot)** | the catch-up floor |
| Dungeon tiers (Gearing) | 1 | **~3** | *abstracted* difficulty bands, not authored instances |
| Event types | core-5 | **7** | core-5 + assigned-duty + cooldown (already promoted) |
| Life presets | 2 | **~6** | single / student / working-parent / shift-worker / veteran / young-gun |
| Objective types | 2 | **6** | fixed palette (progression/competitive/roster/cohesion/economic/development) |
| Season length | — | **~14 wk** | single v1 expansion (standard band) |
| Quirks | 0 | **0 → v1.1** | ~25 is Phase-C content; see decision 3 |
| Guild roster size | 20 | **~28 (soft cap ~30)** | 20-raid + bench depth; at ~85% avg availability, 28 → ~24 available |

### Class role-coverage matrix (locked: 6 × 3 = 18)
Names come from the naming bible; the **role patterns** are locked now so comp math and seed data have a shape:

| Class archetype | Spec 1 | Spec 2 | Spec 3 |
|---|---|---|---|
| C1 — heavy plate | Tank | Melee | Melee |
| C2 — crusader hybrid | Tank | Healer | Ranged |
| C3 — shapeshifter hybrid | Tank | Healer | Melee |
| C4 — priest archetype | Healer | Ranged | Ranged |
| C5 — spiritcaller hybrid | Healer | Melee | Ranged |
| C6 — pure DPS | Melee | Ranged | Ranged |

Coverage: **3 tank specs across 3 classes** (comp resilience — losing one class doesn't kill tanking), **4 healer specs across 4 classes**, 5 melee, 6 ranged. One pure-DPS class for MMO authenticity; utility/synergy spread assigned per spec in seed data.

### Melee vs ranged as a boss-mechanic dimension
- **`EVENT_TYPE.target_selector`** gains `melee` / `ranged` values — bosses can cleave the melee camp or storm the ranged camp (pure seed data, no schema change).
- **Boss range profiles emerge from placed events:** a melee-punisher is a boss whose harmful events target melee. The **raid-prep comp check** derives a range-balance warning per planned boss (*"⚠ 8 melee vs a melee-unfriendly boss"*).
- Comp building now has a third axis: role coverage, utility coverage, **and range balance vs tonight's bosses.**

**Where the real authoring time goes:** the ~12 bosses (bespoke — phases, event placement, tuning) and the 18 specs (utility/synergy/difficulty tuning). Everything else is templatable (loot), abstracted (dungeons), or a short fixed list. Budget accordingly.

**Rationale on the key calls:**
- **6 classes / 18 specs (3 each)** — enough that comps have gaps (you can't bring every utility → real "bring the class" decisions) and each spec is still tunable solo. Locked, with the role-coverage matrix above.
- **2 tiers / ~12 bosses** — a difficulty ramp *across the expansion* (early gear-checks → mid mechanic-checks → the end-boss wall) and a gear treadmill, without a 3rd-raid authoring load. **Each tier is its own season** (I-03).
- **~14-week season, one per tier** — each is one full objective cycle with room for the learning arc to breathe; the v1 expansion is therefore ~2 seasons. (Expansion-varying length is a v1.1 lever once multi-expansion lands.)

**Dependency flag:** the **competitive** objective type needs the **rival ladder (P1)**. If the ladder is cut from v1, drop competitive from the v1 objective set (→ 5 types).

---

## Definition of Done — two gates

### Gate 1 — Vertical Slice (Phase A, the fun-proof)

**Technical items — all shipped (M0–M4):**
- [x] Generate a 20-raider roster (traits + gear + specs), inspectable
- [x] One raid (3–4 bosses) seeded
- [x] Resolve a raid night: lineup → assignments → pull-by-pull combat log → kill/wipe + `wipe_reason` + per-raider ratings + loot drop
- [x] Post-night report readable
- [x] Deterministic: same seed → same result; batch harness runs N pulls, win rates land in each boss's contracted band (`guildmaster-encounter-contracts.md` — progression **22–35%/pull**; the old "~60–80%" figure was a *farm* feel and is superseded, ADR-0024)

**🔒 The gate itself — ✅ PASSED (2026-07-12):**
- [x] **Verdict: is the raid night fun to run?**

> ### ✅ **GATE 1 PASSED — Panos, 2026-07-12**
>
> > *"It seems solid, hard enough but doable, I feel it just about right."*
>
> **What this verdict settles.** The difficulty band is right *by feel*, and it agrees with the harness — the encounter contracts target **22–35% win per pull** on progression content (a kill in 3–8 pulls) and Night One measures **40.7%** after the readiness fix. Gut and instrumentation now say the same thing, which is the entire reason we kept both.
>
> **Where we came from.** On 2026-07-11 this same build resolved **32 pulls, 0 kills, 32 wipes**: the entry boss demanded roughly the gear it drops, and four conjunctive check-rolls capped even a healthy raid at ~41%. Milestone **MI** fixed the tier (ADR-0024), the aggregation (ADR-0023), the first session (ADR-0025/0026), the show (ADR-0027) and the diagnosis (ADR-0028).
>
> **What this verdict does NOT settle.** It speaks directly to *plausible first kill*, *meaningful decision*, and *want to continue*. It does **not** probe **"can a non-MMO player act on the UI's warnings alone?"** — the tester is an expert. That line stays open and is **MI-008**'s job.
>
> **Phase A is closed. MI's remaining polish tickets still precede M5** (see `guildmaster-backlog.md`).

#### The human Fun Gate scorecard (MI-010)

| Question | Pass condition |
|---|---|
| Can the player explain the immediate problem? | They name a roster, comp, gear, duty or readiness weakness. |
| Can they make a meaningful decision? | They intentionally change lineup, assignment, consumables or strategy. |
| Is failure legible? | They can state a primary cause **and** a contributing factor. |
| Does the next pull show a consequence? | The change produces a visible margin/event/outcome difference. |
| Is there emotional escalation? | They recognise close calls and improving/worsening attempts. |
| **Is a first kill plausible?** | A representative session produces one **without hidden setup or excessive repetition.** |
| Do named raiders matter? | They recall several people and their role in the result. |
| Is MMO terminology understandable? | A non-MMO player can act on warnings from the UI alone. |
| **Does the player want to continue?** | They ask for another pull, boss, or week. |

A weak score does **not** mean "add more systems". The remedy is balance, presentation, explanation, stronger leverage, or a better first-session scenario.

### Gate 2 — v1 Early Access (Phase B, shippable)
**Feature-complete:**
- [ ] Turn loop: plan → event-day advance → weekly digest, over a 14-week season
- [ ] 2 tiers, ~12 bosses, difficulty ramp; learning arc working
- [ ] 5 between-nights lanes with action resolution; time budget + availability gating
- [ ] Gear: per-slot equip, `gear_score`, caps-from-gear, Marks + vendor + catch-up
- [ ] Loot: Council + DKP + /roll; 7-factor panel; consequences (morale/loyalty/fairness)
- [ ] Economy: treasury, donations, proceeds, repairs, 3 policies
- [ ] Recruitment: fog overlay, 4 channels, source → assess → trial → sign
- [ ] Objectives: season-start mandate → season-end grading → confidence/reputation → rising bar; personal ambition
- [ ] Sacking → rebuild (toggle); campaign save/load (one DB per save, `rng_seed`)
- [ ] Involvement slider on raid night + loot (manual ↔ assisted ↔ instant; *v1 manual = strategy, lineup, between-pull swaps, wipe calls — mid-pull directive injection is v1.1*)

**Content-complete:** hits the v1 EA column above.

**Quality bars:**
- [ ] Balance harness green — win-rate targets + sane gearing/skill curves across a full season
- [ ] Save/load robust; a multi-season campaign completes without critical bugs
- [ ] Naming bible applied — all content IP-safe
- [ ] Observability: the "why did this happen" debug view (`PULL_EVENT` / `TREASURY_LEDGER` / `WEEK_ACTION`)

**The one-line bar** *(corrected 2026-07-11 — I-03: **Season = Tier**)*: *Start a guild → play a full **season (Tier 1, ~14 weeks)** → get graded on objectives → progress into **Season 2 (Tier 2)** at a raised bar, or get sacked and rebuild — with every core system exercised.*

> ⚠️ **Superseded wording.** This bar previously read "a full 14-week season across 2 tiers", which contradicted `guildmaster-campaign-and-objectives.md` ("Season = one raid tier"). The contradiction is resolved in favour of **Season = Tier**: one v1 expansion contains **two seasons**, one per tier. See the intervention doc's decision register (I-03).

### Explicitly OUT of v1 (Phase C / v1.1)
Chemistry graph · quirks · drama-event catalogue · resistance checks · multi-expansion · Player-Guildmaster · professions/crafting · Soft-Reserve/EPGP · full rival sim (light ladder only, or cut). *Protecting this list protects the timeline.*

---

## Decisions to lock (my defaults)
1. ~~Classes/specs~~ ✅ **locked: 6 × 3 = 18** with the role-coverage matrix; melee/ranged is a boss-mechanic dimension.
2. **2 tiers / ~12 bosses / 14-week season** for v1? → *Yes.*
3. **Quirks stay v1.1** (v1 personalities = traits + derived archetypes), keeping Phase B lean? → *Yes* — or pull a starter ~8 into v1 EA if you want more personality flavor at launch (my lean: keep them v1.1, prove the loop first).
4. **v1 EA content table + the two DoD gates** as the scope contract? → *Yes.*

Confirm (especially 1 and 3 — the real scope levers), and the last pre-build piece is **decomposing Phase A (M0–M4) into kanban stories** with acceptance criteria — then you populate the board.
