# Guildmaster: Progression Night — Post-Intervention Assessment

> **Purpose:** Reassess the project after the M0–M4 intervention work, compare it with the pre-intervention baseline, determine whether the project is on track, and identify the remaining gates before Phase B-lite.
>
> **Assessment date:** 2026-07-12
>
> **Scope:** Repository, documentation corpus, Git history, automated verification, balance and smoke evidence, and the Guildmaster v2 Notion Kanban.
>
> **Assessment rule:** This document separates verified evidence from interpretation and recommendation. No code, seeds, existing documentation, or Notion records were modified during the reassessment.

---

## 1. Executive verdict

**The project is on a substantially better track.**

The intervention was not merely documented. It produced focused implementation, tuning, UX, accessibility, and verification changes that directly addressed the most serious M0–M4 risks.

The project has moved from:

> A technically robust simulation whose default vertical slice could produce 32 wipes and no kills.

To:

> A testable first-session experience in which the player diagnoses a concrete problem, makes a counterintuitive roster decision, sees a material improvement, and can complete the four-boss slice.

The core recommendation is now:

> Complete the remaining product-alignment and audience-validation tasks, then begin **Phase B-lite** rather than resuming the original full M5–M9 breadth plan.

The intervention is successful. It is not entirely closed.

The largest remaining validation gap is audience-specific: the Fun Gate was passed by an expert MMO player, while a management-sim player without MMO experience has not yet been observed using the first-session flow.

---

## 2. Measured improvement since the intervention baseline

| Area | Pre-intervention | Current verified state |
|---|---:|---:|
| Automated tests | 117 tests / 16 suites | **157 tests / 21 suites** |
| Test failures | 0 | **0** |
| Seed validation | 264 checks passed | **277 checks passed** |
| Seed validation errors | 0 | **0** |
| Formatting and linting | Clean | **Clean** |
| Slice smoke | 32 wipes, 0 kills | **18 pulls, 4 kills, 14 wipes** |
| First-session teaching arc | Not reliably generated | **Authored and tested** |
| Boss-balance validation | Boss-1/global target | **Per-boss seeded contracts** |
| Preparation leverage | Assumed from design | **Measured with same-seed probes** |
| Presentation | Functional feed | **Pacing, hierarchy, phases, and decisive-beat contract** |
| Diagnostics | Dominant failure could imply blame | **Cause, factors, key moment, recommendation, recurrence** |
| Ratings | Implemented but under-specified | **Explicit role/gear-relative contract** |
| Terminology | MMO knowledge load-bearing | **Plain-language-first glossary system** |

### 2.1 Current technical verification

At reassessment time:

```text
GdUnit4:
157 test cases
0 errors
0 failures
0 flaky
0 skipped
21/21 suites

Seed checker:
277 checks passed
1 intentional utility-scarcity warning
0 errors

Formatting and linting:
54 files unchanged
Success: no problems found
```

### 2.2 Current working-tree state during reassessment

The repository working tree was clean before this assessment document was created.

### 2.3 What this evidence proves

The current evidence proves that:

- the intervention changes are integrated;
- the deterministic contracts remain intact;
- the seed data and schema are coherent;
- the first-session scenario works across its tested seeds;
- the full four-boss slice can complete;
- per-boss balance assertions pass;
- the major presentation, diagnostic, terminology, and rating rules are covered by tests.

It does **not** prove that:

- all target audiences understand the game equally well;
- repeated raid nights remain entertaining over a campaign;
- the complete M5–M9 season loop is fun;
- deferred social, economy, rival, and replayability systems are correctly scoped;
- all canonical docs and Notion statuses are synchronized.

---

# 3. What changed

## 3.1 Intervention commits

| Commit | Intervention work | Result |
|---|---|---|
| `a48d9fd` | Intervention checkpoint / M5 block | Formalized the post-M4 reassessment gate |
| `152823f` | MI-002 — Gating versus pressure checks | Removed the prior approximate 41% kill ceiling |
| `e16d9ba` | MI-001 — Encounter contracts | Anchored encounters to reachable Tier-1 gear |
| `1cfb2b0` | MI-003 — First Session | Authored a teachable Night One decision |
| `fcd6379` | MI-004 — Presentation | Added pacing, hierarchy, phases, and decisive beats |
| `6a8956e` | MI-005 — Diagnostics | Replaced culprit framing with structured diagnostics |
| `359ef97` | MI-010 — Fun Gate | Recorded the human MMO-expert playtest result |
| `f871ca2` | MI-009 — Harness / healer tuning | Added boss contracts and fixed the healer trap |
| `ac798f4` | MI-008 — Terminology | Added glossary and plain-language warning enforcement |
| `29212ea` | MI-006 — Rating contract | Locked ratings before Loot Council implementation |

Across the intervention range:

- **61 files changed**
- **6,594 additions**
- **399 deletions**

This is a substantial change set, but it is coherent: almost every change maps directly to an intervention finding rather than unrelated feature expansion.

## 3.2 New durable design contracts

The intervention created explicit contracts rather than relying on informal intent:

- `guildmaster-first-session.md`
- `guildmaster-encounter-contracts.md`
- `guildmaster-presentation.md`
- `guildmaster-diagnostics.md`
- `guildmaster-rating.md`
- `guildmaster-terminology.md`
- `guildmaster-intervention-and-realignment.md`

The implementation also added or expanded:

- `data/seeds/encounter_contract.csv`
- `data/seeds/glossary.json`
- `sim/resolution/diagnosis.gd`
- `sim/core/glossary.gd`
- first-night, diagnostics, presentation, terminology, and rating tests;
- encounter-contract and defense-cap migrations;
- per-boss balance assertions and preparation-leverage probes.

This is a strength. The changes are traceable, testable, and mostly connected to machine-enforced behavior.

---

# 4. Major improvements

## 4.1 Night One now teaches the game

### Previous problem

Ten generated roster seeds were measured before MI-003:

| Starting condition | Frequency | What the player learned |
|---|---:|---|
| Best tank already crit-immune | 6 / 10 | Nothing; auto-lineup was already correct |
| No tank could become crit-immune | 3 / 10 | Nothing; the problem had no player lever |
| A real, fixable player choice | **0 / 10** | — |

A fully procedural opening did not reliably teach the intended decision loop.

### Current solution

Night One authors only the tank corps:

- The default auto-lineup selects the highest-gear tank.
- That tank is vulnerable to critical boss attacks.
- A lower-gear alternative is properly capped.
- The player must bench the apparent star and field the prepared tank.
- The rest of the roster remains procedurally generated.

Verified smoke:

```text
FIRST NIGHT SMOKE: seed=133742
Opened database successfully (:memory:)
  default main tank: Shadowwhisper (Oakhide) — CRITTABLE
  prep warning: Your main tank Shadowwhisper can be hit by a critical strike — one unlucky spike will kill him outright and end the pull, and no amount of healing prevents it. Field a tank who cannot be critically hit, even if their gear score is lower (uncrittable).
  as handed to you:     5.3% win   (top wipe: tank_survival)
  bench Shadowwhisper -> main tank is now stormblade10 (Bulwark)
  after the one fix:   44.0% win   -> a kill in ~2.3 pulls
Closed database (:memory:)
FIRST NIGHT SMOKE: PASS
```

### Why this is the right lesson

The opening teaches the game’s central management principle:

> The strongest-looking individual asset is not always the correct organizational decision.

The player must:

1. Read the warning.
2. Distrust the default heuristic.
3. Look beyond gear score.
4. Bench the apparent star.
5. Field the less impressive but properly prepared tank.
6. Observe an approximately 39-percentage-point improvement.

This teaches the player how to think rather than merely where to click.

### Assessment

This is the strongest intervention outcome.

Curating one educational choice while preserving procedural variety elsewhere is an appropriate compromise. It does not undermine the simulation; it gives the player the vocabulary required to participate in it.

### Remaining requirement

`MI-013` must remain a hard dependency of `M5-001`.

When demo scaffolding is replaced by real guild genesis, the new-campaign path must preserve this opening contract or provide an equally teachable alternative.

---

## 4.2 The complete four-boss slice is now viable

### Previous state

```text
32 pulls
0 kills
32 wipes
```

### Current state

```text
SLICE SMOKE: seed=133742
Opened database successfully (:memory:)
Closed database (:memory:)
  pulls=18 kills=4 wipes=14
  Killed 4/4 bosses (Gatewarden Krogg, Forgemaster Vell, The Slagbeast, The Cinderlords) across 14 wipes.
Opened database successfully (:memory:)
Closed database (:memory:)
SLICE SMOKE: PASS
```

### Assessment

The vertical slice is no longer structurally deadlocked.

It can now demonstrate:

```text
Failure
→ diagnosis
→ preparation change
→ closer pulls
→ kill
→ continued raid progression
```

This does not prove that every manual playthrough is ideal or that all pacing is final. It proves that the core slice can produce the intended progression result.

---

## 4.3 Encounter tuning now has explicit, reachable contracts

The old harness could demonstrate success at gear multipliers the campaign could not realistically provide.

The intervention established a reachable Tier-1 ceiling:

| Roster state | Average item level | Gear score | Multiplier |
|---|---:|---:|---:|
| Fresh guild | 18.9 | 132 | x1.00 |
| A boss or two farmed | 22 | 154 | x1.16 |
| Half the tier geared | 26 | 182 | x1.38 |
| Mostly tier-geared | 29 | 203 | x1.53 |
| Full Tier-1 BiS | 31 | 217 | **x1.64** |

Every Phase-A encounter is now required to live within that range.

### Machine-readable encounter contracts

`data/seeds/encounter_contract.csv` defines:

| Boss | Expected gear | Expected win band | Farm gear | Farm floor | Dominant failure | Signature lever |
|---|---:|---:|---:|---:|---|---|
| Gatewarden Krogg | x1.00 | 30–50% | x1.64 | 85% | DPS enrage | Tank cap |
| Forgemaster Vell | x1.12 | 24–44% | x1.64 | 55% | DPS enrage | Duties |
| Slagbeast | x1.28 | 22–42% | x1.64 | 48% | Tank survival | Healers |
| Cinderlords | x1.42 | 13–33% | x1.64 | 35% | DPS enrage | Consumables |

### Current measured harness results

Verified with 200 pulls per cell:

```text
== balance harness: 200 pulls x 7 gear steps per boss ==
BOSS                 x0.85   x1.00   x1.12   x1.28   x1.42   x1.55   x1.64   top wipe reason (at x1.00)
gatewarden_krogg        0%     40%     56%     71%     85%     90%     97%   dps_enrage
forgemaster_vell        0%     20%     34%     43%     59%     63%     65%   dps_enrage
slagbeast               1%     13%     17%     32%     40%     47%     58%   dps_enrage
cinderlords             0%      8%      6%     14%     23%     34%     45%   dps_enrage
HARNESS: PASS
```

| Boss | x1.00 | x1.12 | x1.28 | x1.42 | x1.55 | x1.64 |
|---|---:|---:|---:|---:|---:|---:|
| Krogg | 40% | 56% | 71% | 85% | 90% | 97% |
| Vell | 20% | 34% | 43% | 59% | 63% | 65% |
| Slagbeast | 13% | 17% | 32% | 40% | 47% | 58% |
| Cinderlords | 8% | 6% | 14% | 23% | 34% | 45% |

The current harness passes every encounter against its own expected progression and farm contract.

### Assessment

This resolves the prior balance-harness weakness.

The project now has a safer content-authoring model:

> Retuning a boss without updating its contract is a failing build, not a forgotten design note.

---

## 4.4 Preparation choices are now measured rather than assumed

The new probes compare same-seed outcomes with one preparation decision changed.

| Lever | Krogg | Vell | Slagbeast | Cinderlords |
|---|---:|---:|---:|---:|
| Tank cap | **+40.0pp** | 0 | −2.5 | 0 |
| Duties | 0 | **+5.5pp** | +2.0 | +2.5 |
| More healers | −3.0 | −13.5 | **+10.0pp** | −12.5 |
| Range composition | +14.5 | +12.5 | +8.0 | +10.0 |
| Consumables | +10.0 | +7.0 | +11.0 | **+6.0pp** |

This is healthy tactical shape:

- A tank cap solves Krogg specifically.
- Duties matter most on Vell.
- More healers help Slagbeast but harm DPS-race encounters.
- Consumables matter especially on Cinderlords.
- Range composition has meaningful broad impact.

### Assessment

Raid preparation is increasingly supported as a real decision surface rather than a decorative configuration screen.

The next validation is campaign-contextual: these choices must remain meaningful when gear, learning, fatigue, form, supplies, and loot progression enter the loop.

---

## 4.5 The healer trap was discovered and fixed

### Previous problem

Slagbeast was intended as a healing wall, but more healers made the raid worse:

- Healing demand was unreachable.
- Tank survival was already saturated.
- Additional healers reduced DPS.
- Reduced DPS made enrage the practical deciding gate.
- The optimal response was to strip healers and stack damage.

This contradicted the encounter’s identity.

### Fix

The intervention adjusted data and reusable tuning constants:

- Healing demands were lowered into a reachable range.
- `tank_healing_share` increased from `0.35` to `0.50`.
- `healing_deficit_lethality` increased from `0.6` to `1.0`.
- Slagbeast cascade behavior was retuned.

### Assessment

This was strong corrective work.

The project fixed the model rather than hiding the issue with boss-specific code. The result expresses a meaningful trade-off:

> Bring more healing for a real healing wall; do not bring it automatically to every encounter.

Because this is a fresh tuning change, it should continue to be monitored as the campaign adds gear distribution, Marks, fatigue, form, consumable scarcity, encounter learning, and broader roster variation.

---

## 4.6 The combat feed now behaves like a match presentation, not a raw log

### Previous problem

A `tank_survival` wipe could show:

```text
raiders up: 20/20
WIPE — tank_survival
```

The tank had failed as a check, but no decisive event existed in the visible feed. The result appeared without a corresponding event.

### Current solution

Every pull now closes with a decisive event:

- Boss defeated.
- Tank overwhelmed.
- Raid collapse.
- Enrage.

The presentation contract also defines:

- Persistent pull context.
- Boss and attempt context.
- Phase banners.
- Raiders-up count.
- Event tiers: routine, notable, critical, decisive.
- “Closest yet” comparison.
- Live and instant presentation modes.
- Speed controls.
- Skip-to-result behavior.
- Distinct kill treatment.

### Truth-preserving presentation

The UI deliberately does not display a fake live boss-health bar. The simulation derives final progress from the DPS-check result rather than simulating continuous boss HP. The UI therefore shows progress only where the engine produces a truthful value.

### Assessment

This is a meaningful improvement in trust and readability.

Headless tests can verify event structure. They cannot prove:

- readability at normal screen size;
- whether live pacing feels right;
- whether repeated pulls remain engaging;
- whether the kill payoff is emotionally sufficient.

Those questions still require real players.

---

## 4.7 Diagnostics now teach system thinking instead of scapegoating

The former “culprit” concept has been replaced with:

```text
Primary cause
→ contributing factors
→ attributable key moment
→ recommendation
→ recurrence
```

Examples:

- **Primary cause:** Tank survival.
- **Contributing factors:** uncapped tank, insufficient healing, avoidable pressure.
- **Key moment:** a directly attributable missed interrupt, if one occurred.
- **Recommendation:** field a crit-immune tank, add healing, change assignment, or spend resources.
- **Recurrence:** identify the same repeated failure rather than imply bad luck.

### Rating and blame rules

| Event | Personally authored? | Rating penalty |
|---|---:|---:|
| Missed assigned duty | Yes | −2.0 |
| Avoidable death | Yes | −2.0 |
| Cascade death | No | 0 |
| Tank overwhelmed by bad raid setup | No | 0 |

The intervention also fixed recurrence grouping. Previously, raw `wipe_reason` strings included changing numeric margins and probabilities, so identical systemic failures could be counted as unrelated strings.

The game can now say:

> Tank survival ended 8 of your 8 wipes here—the same wall, not bad luck.

### Assessment

This resolves one of the most important product risks.

The player is meant to become a better guildmaster, not learn to bench whoever has the lowest visible number.

---

## 4.8 Ratings are now fairer and suitable for Loot Council

The governing rule is:

> A rating measures how well a raider fulfilled their role and assignments relative to the kit, gear, and situation available to them. It is not raw output.

This prevents the harmful loop:

```text
more gear
→ higher raw output
→ higher rating
→ stronger loot claim
→ even more gear
```

The formula compares a player’s actual contribution to expectations based on their own gear ceiling and role.

Tests protect scenarios such as:

- an undergeared player overperforms and earns a strong rating;
- a highly geared player underperforms and rates poorly;
- duty failures are not double-counted;
- clutch performance is visible;
- systemic deaths are explained rather than punished;
- every rating is accompanied by a player-readable reason.

### Assessment

This weakness is resolved at the current scope and was correctly locked before M6 turns ratings into political Loot Council evidence.

---

## 4.9 Terminology is no longer load-bearing MMO knowledge

The project now uses:

```text
Plain-language consequence
→ actionable recommendation
→ MMO term last, in parentheses
```

For example:

> Your main tank can be hit by a critical strike. One unlucky spike will kill them outright and end the pull, and no amount of healing prevents it. Field a tank who cannot be critically hit, even if their gear score is lower (uncrittable).

The glossary is content data in `data/seeds/glossary.json`, and tests enforce:

- warnings include a real action;
- warnings do not begin with jargon;
- terms used by warnings have glossary entries;
- entries have usable plain-language definitions;
- the Night One warning keeps the required consequence and action.

### Assessment

The implementation weakness is resolved.

The audience-validation question remains open: no actual non-MMO player has yet demonstrated that they understand and act on the warning without help.

---

# 5. Current status of the original intervention findings

| ID | Finding | Current status | Assessment |
|---|---|---|---|
| W1 | Fun Gate unproven | **Partially closed** | Strong technical and expert-MMO evidence. Non-MMO/sim audience still untested. |
| W2 | Balance harness too narrow | **Resolved** | Per-boss contracts, reachable gear ceiling, lever probes, contract assertions. |
| W3 | Season/tier contradiction | **Decision made; alignment incomplete** | `Season = Tier` is locked, but stale contradictory wording remains. |
| W4 | Social promise exceeds v1 expression | **Open by design** | Quirks and drama remain appropriately deferred. |
| W5 | Combat feed may not be entertaining | **Substantially improved** | Presentation structure exists; broader human validation remains. |
| W6 | Culprit framing risks scapegoating | **Resolved** | Cause, factors, key moment, recommendation, and recurrence implemented. |
| W7 | Ratings under-specified | **Resolved** | Explicit contract and test coverage added. |
| W8 | Raid prep may be administrative | **Substantially improved** | Measured signature-lever effects now exist. |
| W9 | Involvement slider arrives too late | **Open** | MI-007 remains `To Do`. |
| W10 | MMO terminology may exclude sim players | **Mechanically resolved; audience proof open** | Glossary and warning enforcement exist; non-MMO test still needed. |
| W11 | Economy spiral lacks recovery | **Open** | MB-004 correctly remains `Waiting`. |
| W12 | Rivals may feel lifeless | **Open** | MB-005 correctly remains `Waiting`. |
| W13 | Replay variety may be thin | **Open** | Personality and world-presentation decisions remain deferred. |
| W14 | Full v1 scope too broad | **Direction improved; status mismatch** | Phase B-lite exists in the repo backlog; MI-012 remains `To Do` in Notion. |

### Summary

- **Resolved:** W2, W6, W7.
- **Mechanically resolved with audience proof still open:** W10.
- **Substantially improved:** W1, W5, W8, W14.
- **Decision made but alignment incomplete:** W3.
- **Still open by design:** W4, W9, W11, W12, W13.

The remaining open findings are no longer reasons to doubt the simulation foundation. They are roadmap, audience, and campaign-depth questions that must remain visible as Phase B progresses.

---

# 6. Fun Gate caveat: the evidence covers only half the target audience

The repository contains a commit and ADR asserting:

> Gate 1 PASSED—the raid night is fun.

The terminology contract also records that:

> The Fun Gate was passed by an expert MMO player.

It explicitly acknowledges:

> The non-MMO player question has never been tested on an actual non-MMO player.

Meanwhile, `docs/phase-a-fun-gate.md` remains blank in its manual verdict section and retains stale pre-intervention evidence.

## 6.1 What has been proven

- The slice is technically complete.
- The full raid can be cleared.
- Night One contains a legible and consequential decision.
- The decision produces a large, measured improvement.
- An expert MMO player judged the raid night fun enough to continue.
- Presentation and diagnostics are materially stronger.

## 6.2 What has not been proven

- A management-sim player without MMO experience notices the important warning.
- They understand it without external explanation.
- They choose a meaningful response.
- They understand why the second setup is better.
- They understand the post-pull diagnosis.
- They enjoy the combat-feed pacing.
- They want another pull or week.

## 6.3 Accurate current interpretation

The honest status is:

> **Phase A Fun Gate: passed for an expert MMO player; dual-audience validation remains open.**

This is not a reason to undo intervention work. It is a reason to complete the exact audience validation the product strategy requires.

One observed session with a non-MMO management-sim player is now more valuable than another major engine feature.

---

# 7. Documentation and project-management alignment issues

The intervention documents are strong, but not every source of truth has been synchronized.

## 7.1 `phase-a-fun-gate.md` is stale

It still reports the former baseline:

```text
32 wipes / 0 kills
```

Current slice evidence is:

```text
18 pulls / 4 kills / 14 wipes
```

Its verdict section is also blank despite the ADR and commit recording a passed expert-MMO Fun Gate.

### Recommendation

Retain the old result as a clearly labeled pre-intervention baseline, but update the current-state evidence and verdict record.

---

## 7.2 `guildmaster-encounter-contracts.md` contains a contradictory Slagbeast invariant

The retuned section correctly defines Slagbeast’s intended dominant failure as `tank_survival`, representing healing failure ultimately overwhelming the tank.

A later invariant still says:

> A Slagbeast that dies to `tank_survival` is mistuned.

That statement is obsolete and contradicts the current contract row.

### Recommendation

Correct or retire the stale invariant before agents use this document to author further content.

The document also retains older tables marked as superseded. This preserves useful history, but it increases the risk that a reader or agent uses the wrong values. The canonical/current table should be unmistakable.

---

## 7.3 Campaign documentation contains remaining tier-count ambiguity

`guildmaster-campaign-and-objectives.md` correctly locks:

```text
Season = Tier.
v1 expansion = two seasons / two tiers.
```

But another line still refers to:

```text
v1 = a single expansion (1–3 tiers)
```

### Recommendation

Remove or reframe that old content-volume language. The locked model should be unambiguous before M5 calendar, objective, rival-pacing, and transition work begins.

---

## 7.4 Notion and repository backlog status are not fully aligned

The repository backlog records:

- MI-011 campaign-model alignment as locked.
- MI-012 Phase B-lite as defined.
- M5–M9 as a staged Phase B-lite path.

The Notion board still lists:

- `MI-011` as **To Do**.
- `MI-012` as **To Do**.

### Interpretation

This can mean one of three things:

1. The repository work is complete and the board is stale.
2. The design direction is drafted but not formally approved.
3. The central decisions are made, but not every acceptance criterion is complete.

The remaining documentation contradictions indicate that MI-011 is not fully complete even though the central decision is locked.

MI-012 appears substantially present in the repository backlog, but still needs formal review and roadmap approval before its Notion status should change.

### Recommendation

Do not mark either task complete automatically.

- Complete MI-011 only after all canonical wording is aligned.
- Complete MI-012 only after Phase B-lite is explicitly approved as the active roadmap.

---

# 8. Notion Kanban status

## 8.1 Current state

| Column | Count |
|---|---:|
| Done | **35** |
| To Do | **3** |
| Waiting | **39** |

## 8.2 Current To Do tasks

1. **MI-007 — Involvement-mode contract**
2. **MI-011 — Campaign-model alignment: Season = Tier**
3. **MI-012 — Phase B-lite rescope: restage M5–M9 into product gates**

These are appropriate immediate tasks. They are product-contract and alignment decisions rather than broad feature implementation.

## 8.3 Waiting work

The board correctly keeps the larger M5–M9 expansion and optional breadth behind gates, including:

- full loot-policy breadth;
- economy depth;
- recruitment breadth;
- rival identity and news;
- observability tooling;
- involvement-slider implementation;
- gear and catch-up systems;
- social depth and drama;
- multi-expansion systems.

This is healthier than automatically resuming the original broad roadmap.

## 8.4 Phase B-lite direction

The repository backlog now proposes:

### M5 — Turn loop, calendar, and genesis

- Campaign and save root.
- Event-day stepping.
- Calendar.
- Availability.
- Between-night actions.
- Inbox and digest.

### M6 — Loot Council only

- Flagship policy first.
- Claims panel.
- Award consequences.
- DKP and `/roll` deferred.

### M7 — Basic economy

- Treasury.
- Donations.
- Repairs.
- Provision.
- Full policy depth deferred.

### M8 — One recruitment channel

- Applicants.
- Assessment fog.
- Trial.
- Sign.
- Other channels deferred.

### M9 — Season and stakes

- Objectives.
- Grading.
- Sacking.
- Rebuild.
- Career summary.
- Rival ladder.

### Assessment

This is the right type of rescope. It preserves essential loops while deferring breadth until the weekly and season structure proves enjoyable.

---

# 9. Remaining product risks

## 9.1 The Fun Gate has not been demonstrated with the non-MMO target audience

The current evidence comes from an expert MMO player.

That is valuable but incomplete because the product also targets management-sim players with little or no MMO vocabulary.

The terminology system makes success plausible. It does not prove it.

### Required observation

Run Night One with at least one management-sim or strategy player who has not raid-led in an MMO.

Observe without teaching:

- Do they understand the tank warning?
- Do they identify the actual problem?
- Do they inspect the bench?
- Do they make a meaningful change?
- If not, what do they try?
- Do they understand why the result changed?
- Do they understand the report?
- Do they ask for another pull or another week?

The question is not whether they solve the problem instantly. The question is whether the interface supports understandable learning.

---

## 9.2 Involvement modes must be decided before Phase B UI work

MI-007 remains important because Manual, Assisted, and Instant influence every future screen.

The contract should clarify at least:

| Domain | Manual | Assisted | Instant |
|---|---|---|---|
| Weekly planning | Player allocates | Advisor proposal | Auto-plan |
| Lineup | Player selects | Recommended and editable | Auto-fill |
| Assignments | Player assigns | Auto plan with overrides | Auto |
| Raid pulls | Pull-by-pull or key calls | Key moments and recommendations | Result plus highlights |
| Loot | Player awards | Recommendation plus approval | Auto-resolution |
| Recruitment | Player scouts and signs | Shortlist/recommendation | Policy-driven |

Without this, Phase B may be designed for full manual control and require costly retrofits later.

---

## 9.3 The authored Night One tutorial needs a durable campaign policy

The current demo solution is good. M5 must decide how it persists in the real product.

Possible approaches:

1. Mandatory guided opening.
2. Optional tutorial campaign start.
3. Standalone prologue before normal campaign generation.
4. Adaptive onboarding that creates another fixable roster weakness.
5. Experienced-player skip after first completion.

The project should explicitly decide:

- Does every new campaign repeat the tank lesson?
- Can it be skipped?
- Does difficulty alter the lesson?
- How much procedural variety remains?
- What replaces it for experienced players?

This decision belongs with MI-013 and M5-001.

---

## 9.4 “Farm” may currently mean late progression rather than reliable repeat clear

Current farm minimums include:

- Slagbeast: 48%.
- Cinderlords: 35%.

For MMO players, “farm” typically means relatively reliable repeat clears. These values may be reasonable if they represent a pre-M5 pure-resolution state before learning, better planning, Marks, form, and premium resources are fully represented.

### Recommendation

Revisit terminology and thresholds when Phase B systems exist:

- Reserve `farm` for reliable repeated clears.
- Consider labels such as `expected_progression`, `prepared`, `mastery`, and `farm`.
- Distinguish per-pull win rate from per-night and per-week clear probability.

This is not an immediate M5 blocker, but it should remain visible.

---

## 9.5 Harness output should foreground contract-state outcomes

The terminal harness currently prints the top wipe reason at x1.00.

This can be misleading because some bosses’ identity is evaluated at their expected progression gear rather than fresh-guild gear.

For example:

- Slagbeast’s contract is evaluated at x1.28.
- Its terminal summary can still show `dps_enrage` at x1.00.
- The contract expects `tank_survival` at the intended progression state.

The assertions appear to use the correct contract state because the harness passes. The human-readable summary is the remaining issue.

### Future observability recommendation

Have the harness summary print:

| Field | Why it matters |
|---|---|
| Expected gear | The contract’s intended state |
| Observed win rate at expected gear | Direct pass/fail understanding |
| Contract band | Intended progression target |
| Dominant failure at expected gear | Boss identity check |
| Signature-lever delta | Confirms prep control matters |
| Farm-state result | Confirms late-tier viability |

---

## 9.6 Social identity and replayability remain intentionally open

No personality breadth was added during intervention. That was the correct decision.

The eventual question remains:

> Are ratings, attendance, gear, roles, loyalty, loot history, and benching sufficient to make generated raiders memorable?

If not, a small starter set of quirks and social events may be more valuable than additional boss quantity.

This should be evaluated through multi-week playtests after M5 and M6, not decided from design theory alone.

---

## 9.7 Economy and rivals remain correctly deferred

The board appropriately keeps:

- economy recovery valves;
- full economy breadth;
- rival identity and news;

in `Waiting`.

Neither should be implemented before the weekly and season loop exists.

For the economy, decline must contain recovery decisions before full death-spiral depth is introduced.

For rivals, identity and news are likely a better first investment than full rival AI.

---

# 10. Is the project ready for M5?

## 10.1 Technical readiness

**Yes.**

The repository is healthy:

- 157/157 tests pass.
- 277 seed checks pass.
- Formatting and linting pass.
- First-session smoke passes.
- Complete-slice smoke passes.
- Per-boss harness passes.
- The working tree was clean during reassessment.

## 10.2 Product readiness

**Almost.**

Before M5 implementation begins, complete:

1. **Non-MMO management-sim playtest.**
2. **MI-007 involvement-mode contract.**
3. **MI-011 canonical-document alignment.**
4. **MI-012 formal approval of Phase B-lite.**
5. **MI-013 decision for preserving Night One in real guild genesis.**

Then begin M5 narrowly.

---

# 11. Recommended next sequence

## Step 1 — Validate Night One with the second target audience

Do this before more engine work.

Observe comprehension, decision-making, satisfaction, and desire to continue without explaining the correct answer.

## Step 2 — Synchronize source-of-truth documents and Kanban

Resolve:

- stale Fun Gate evidence;
- the Slagbeast contract contradiction;
- remaining `1–3 tiers` language;
- MI-011 completion criteria and status;
- MI-012 review and status.

Preserve old evidence as historical baseline where useful, but label it unambiguously.

## Step 3 — Complete MI-007

Lock Manual, Assisted, and Instant behavior before M5 UI work begins.

## Step 4 — Preserve the opening lesson

Make MI-013 a real dependency of M5 guild genesis and decide whether Night One is:

- a mandatory guided start;
- an optional tutorial;
- a prologue;
- adaptive onboarding;
- or skippable after first completion.

## Step 5 — Open Phase B-lite sequentially

```text
M5 campaign skeleton
→ play the multi-week loop
→ M6 Loot Council
→ validate fairness, tension, and consequences
→ M7 basic economy
→ validate sustainability and recovery
→ M8 applicant/trial recruitment
→ validate roster churn
→ M9 one complete season
→ playtest before opening breadth
```

Do not automatically open:

- DKP and `/roll`;
- full economy policy breadth;
- all recruitment channels;
- rival news and identity;
- deeper social systems;
- multi-expansion systems.

Validate the core weekly and season loop first.

---

# 12. What must not be diluted

The intervention reinforced rather than weakened these non-negotiables:

1. **People are the game.**
2. **Legible causal outcomes.**
3. **Loot is leadership and culture.**
4. **Player persists; Avatar can change.**
5. **Rest and sustainability are valid strategy.**
6. **Content remains data, not boss-specific engine code.**
7. **The simulation remains deterministic and testable.**
8. **The setting remains IP-safe and original.**
9. **The 20-person lineup and larger roster preserve bench and coverage tension.**
10. **Recruitment remains uncertain: Avatar-visible, Player-hidden.**

These are the product’s identity.

---

# 13. Final conclusion

The intervention succeeded.

The project’s response to the original risks was disciplined:

- It did not add unrelated systems.
- It identified structural failures through evidence.
- It created explicit design contracts.
- It moved relevant constraints into data.
- It added regression tests and harness assertions.
- It authored an educational first session rather than trusting randomness.
- It made raid outcomes more truthful and readable.
- It prevented blame and gear from becoming misleading authority systems.
- It narrowed Phase B toward player-value gates rather than backlog completion.

The most accurate current statement is:

> The raid-night loop is technically healthy, demonstrably completable, and fun enough for at least one expert MMO player. The project is close to Phase B-lite, but it must still validate the management-sim/non-MMO audience and finish its remaining alignment contracts.

The core product thesis is now visible in play:

```text
The apparent star is the wrong choice.
You understand why.
You make the difficult call.
The raid improves.
The boss dies.
```

That is Guildmaster.

---

*Post-intervention assessment completed after the MI-001 through MI-010 change set. This document records the read-only reassessment; it does not itself approve pending roadmap decisions or change Notion status.*
