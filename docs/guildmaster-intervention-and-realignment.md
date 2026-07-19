# Guildmaster: Progression Night — Intervention & Re-alignment Checkpoint

> **CLOSED (2026-07-19): historical register.** Every MI ticket shipped; the Fun Gate passed 2026-07-12 (ADR-0029); the decision register I-01…I-12 is fully executed (I-03 verified end-to-end by ADR-0041, I-12 formally approved by Panos 2026-07-18). Kept verbatim as the record of the 2026-07-11 intervention — do not edit history; the live status lives in the overview and backlog.

> **Purpose:** This document is the breakpoint between the implemented Phase A vertical slice (M0–M4) and the planned campaign/meta work (M5+).
>
> It records the evidence, weaknesses, contradictions, risks, and product questions identified during the first full design-and-repository assessment. Its purpose is not to reverse the project, silently expand scope, or declare new decisions locked. Its purpose is to ensure that the player experience is validated before Phase B makes the current assumptions expensive to change.
>
> **Status:** Intervention recommended. Technical completion of M4 is not automatic evidence that the qualitative Fun Gate has passed.
>
> **Scope:** Product, game design, balance, UX, presentation, accessibility, and roadmap reassessment. Suggestions in this document remain proposals until Panos explicitly approves them and follow-up work is converted into deliberate tasks.

---

## Executive diagnosis

Guildmaster has a strong product thesis, unusually mature systems design, a deterministic simulation core, robust content-as-data foundations, and a working vertical slice. The project is in a healthy technical state.

The largest uncertainty is no longer whether the project *can be built*. It is whether the currently implemented experience creates the intended player loop:

```text
prepare → pull → understand failure → adjust → get closer → kill
→ receive reward/consequence → want another pull and another week
```

The project should therefore move from **architecture validation** to **experience validation** before beginning M5–M9.

The central intervention question is:

> Does the player feel that their decisions—not merely hidden statistics or RNG—caused the raid to improve, fail, or finally succeed?

If the answer is not clearly yes in hands-on playtests, Phase B should not expand the game yet. The vertical slice should be tuned, re-presented, clarified, or narrowed until it demonstrates the core fantasy.

---

# 1. Current breakpoint: what exists and what is proven

## 1.1 Implemented scope

| Area | Current state |
|---|---|
| Godot 4.7 project and application shell | Implemented |
| SQLite migration and migration service | Implemented |
| Transactional seed loader with slug references and upserts | Implemented |
| Six classes and eighteen specs | Implemented |
| Utilities, synergy tags, consumables, loot and starter tuning | Implemented |
| Four Phase-A encounters with phases and event placements | Implemented |
| Correlated 28-player roster generation | Implemented |
| Avatar, role, gear, proficiency and familiarity generation | Implemented |
| Hierarchical deterministic RNG streams | Implemented |
| Pull contribution, lanes, checks and timeline | Implemented |
| Combat events, ratings, learning and persistence | Implemented |
| Balance harness | Implemented |
| Raid-preparation read model and UI | Implemented |
| Combat-log UI | Implemented |
| Post-night report UI | Implemented |
| Full campaign, loot governance, economy, recruitment and objectives | Planned for M5–M9 |

The Notion Kanban showed **26 Done** tasks through M4 and **33 Waiting** tasks for M5 onward.

## 1.2 Verified technical evidence

At the checkpoint review:

- GdUnit4: **117/117 tests passed**, across 16 suites.
- Seed checker: **264 checks passed**, one intentional utility-scarcity warning, zero errors.
- Formatting and linting: clean.
- End-to-end slice smoke: passed.
- Balance harness: passed its current property contract.

These results prove that the implementation is disciplined, deterministic, integrated, and technically healthy.

## 1.3 What the automated gates do not prove

They do not prove:

- that the game is fun;
- that the combat log creates tension;
- that preparation choices feel consequential;
- that non-MMO players understand the terminology;
- that the full raid progression curve is viable;
- that generated raiders feel memorable;
- that the campaign structure is internally aligned;
- that the planned v1 scope is the correct product scope.

This is why the intervention exists.

---

# 2. Critical findings

## W1 — The vertical slice is technically complete, but the Fun Gate is not proven

**Severity:** Critical

### Observed evidence

The repository contains the complete M4 path:

- `game/scenes/main.tscn`
- `game/demo_campaign.gd`
- `game/ui/raid_prep_screen.gd`
- `game/ui/combat_log_screen.gd`
- `game/ui/post_night_report_screen.gd`
- `sim/raid_prep/raid_prep.gd`
- `sim/raid_prep/night_runner.gd`
- `sim/raid_prep/night_report.gd`

The slice uses the real pipeline:

```text
migration → seeds → generated roster → generated avatars → raid prep
→ pull resolution → event log → persistence → post-night report
```

The end-to-end smoke completed successfully, but its actual result was:

```text
SLICE SMOKE: seed=133742
pulls=32 kills=0 wipes=32
Night ended with no kills (32 wipes).
SLICE SMOKE: PASS
```

This is correct as a technical smoke: it proves that repeated pulls, persistence, encounter traversal, report generation, and deterministic reconstruction work. It is not evidence that the default experience provides a satisfying raid night.

### Risk / weakness

A technically correct loop can still feel repetitive, passive, or hopeless if:

- the player cannot identify a meaningful corrective action;
- preparation changes do not visibly alter the outcome;
- progression is too slow to perceive in one session;
- no success payoff occurs;
- the combat feed does not communicate escalation;
- the player cannot tell whether the latest pull was better than the previous one.

The current smoke may intentionally be diagnostic rather than representative. If so, it should not be treated as the first-session product proof.

### Why it matters

The project’s central emotional promise is:

```text
“We almost had it. Change the plan. Give them one more pull.”
```

The existing smoke demonstrates the reliability of the engine, but not that emotional arc. Phase B would multiply the cost of changing the core experience if the raid night is later found to be flat or opaque.

### Suggested intervention

Create and test a **curated first-session scenario** distinct from the general smoke scenario:

1. The initial roster has a clear, fixable weakness.
2. Raid prep presents at least two plausible choices.
3. The first pull fails for a legible reason.
4. The diagnosis points to a concrete intervention.
5. The player changes lineup, assignment, target, strategy, or consumables.
6. A later pull visibly improves.
7. A first kill is plausibly achievable within the session.
8. The kill creates a reward and a meaningful follow-up decision.

This does not need to represent the full campaign economy. It needs to prove the product fantasy.

Possible approaches to assess:

- A demo-only tuning profile.
- A curated roster rather than a fully unconstrained random one.
- A deliberately fixable tank-readiness, range-balance, or assignment weakness.
- A short sequence in which Boss 1 can die within approximately 3–8 pulls after a meaningful adjustment.

### Decision required

Decide what the current M4 demo is intended to be:

- a diagnostic smoke scenario;
- an intentionally undergeared progression scenario;
- or a representative first player experience.

If it is not representative, define a separate first-session demo contract.

### Validation / exit criteria

The qualitative Fun Gate should require human evidence that:

- the player understands why an attempt failed;
- the player can name a change worth trying;
- the change produces a visible consequence;
- a credible first-kill payoff occurs;
- the player wants another pull, another boss, or another week.

---

## W2 — The balance harness validates only part of the progression curve

**Severity:** High

### Observed evidence

The balance harness correctly checks important shape properties:

- win rate improves monotonically with gear;
- undergeared raids fail decisively;
- overgeared raids saturate toward clean kills;
- the first boss can reach the intended 60–80% band.

A 200-pull sweep at the checkpoint produced:

| Encounter | x1.00 | x2.00 | x2.25 | x2.50 | x3.00 | Dominant x1.00 failure |
|---|---:|---:|---:|---:|---:|---|
| Gatewarden Krogg | 1% | 56% | 63% | 84% | 92% | DPS enrage |
| Forgemaster Vell | 0% | 7% | 13% | 18% | 28% | Tank survival |
| Slagbeast | 0% | 4% | 6% | 10% | 14% | Tank survival |
| Cinderlords | 0% | 3% | 6% | 9% | 17% | Tank survival |

The harness passed because its current acceptance contract deliberately requires the target band to be reachable on the first boss. It does not assert that every boss reaches a planned band at a plausible campaign state.

### Risk / weakness

A green harness can coexist with an unvalidated raid progression path.

Open questions include:

- At what gear level is each boss intended to be attempted?
- Are x2.0–x3.0 multipliers plausible from available loot and Marks?
- Can learning bridge the gap between initial gear and encounter demand?
- Should later bosses be impossible on the first night, or merely difficult?
- Why does tank survival dominate the later encounters?
- Do the encounters currently express distinct identities?
- Can the full raid be cleared inside the intended season/tier window?
- Do assignments and composition materially shift the curve?

The current results do not prove the resolution engine is broken. They prove that the full encounter progression contract is not yet specified and validated.

### Why it matters

The boss curve drives:

- perceived fairness;
- gearing cadence;
- Marks value;
- learning progression;
- night scheduling;
- player motivation;
- tier duration;
- objective viability.

If later bosses are unreachable—or reachable only through unrealistic gear—the campaign’s central progression loop cannot close.

### Suggested intervention

Define an explicit **encounter progression contract** for every Phase-A boss.

| Field | Required design answer |
|---|---|
| Progression position | Entry, early wall, mid-tier, end-tier |
| Expected roster state | Gear, caps, skill, familiarity and supplies |
| First-attempt win rate | Intended initial risk |
| Expected pulls to first kill | Including learning |
| Dominant challenge | Tank, healing, DPS, mechanic, duty, range, etc. |
| Primary player intervention | The preparation decision expected to help |
| Required prior reward | Gear, Marks, utility, learning or roster change |
| Farm-state win rate | Expected mastery outcome |
| Failure diversity | Expected distribution of wipe reasons |

Illustrative—not locked—shape:

| Boss | Intended role | Expected intervention |
|---|---|---|
| Gatewarden Krogg | Entry readiness gate | Correct main tank/readiness issue |
| Forgemaster Vell | Duty and range-balance test | Improve interrupts and ranged plan |
| Slagbeast | Healing-sustain wall | Reduce avoidable pressure or strengthen healing |
| Cinderlords | Coordination wall | Improve soaks and cooldown timing |

Then extend the harness to validate each boss against its own contract, not one global band.

Also add comparative probes for:

- assignment configurations;
- composition configurations;
- consumable tiers;
- learning progress;
- plausible gear gained from prior bosses.

### Decision required

Clarify whether the four seeded encounters are:

- one sequentially playable Phase-A raid;
- illustrative content with only Boss 1 tuned for the demo;
- or a raid whose later bosses intentionally require campaign systems not yet implemented.

### Validation / exit criteria

For every Phase-A boss, the project can answer and empirically demonstrate:

> At what plausible roster state should this boss be attempted, and what player-controlled intervention makes the next attempt better?

---

## W3 — Season and tier structure is contradictory across the design set

**Severity:** Critical before M5

### Observed evidence

The documents currently imply incompatible models:

- `guildmaster-campaign-and-objectives.md`: **Season = one raid tier.**
- `guildmaster-content-and-dod.md`: the one-line v1 bar describes a **14-week season across two tiers**.
- The campaign horizon describes **one expansion with two tiers**, followed by a career summary and endless mode.

These imply at least three possible structures:

### Model A — One season per tier

```text
Expansion
├── Season 1 / Tier 1: approximately 12–14 weeks
└── Season 2 / Tier 2: approximately 12–14 weeks
```

### Model B — One season contains both tiers

```text
Expansion
└── One approximately 14-week season
    ├── Tier 1
    └── Tier 2
```

### Model C — Asymmetric progression

Tiers exist inside an expansion but do not map cleanly to season bookends.

### Risk / weakness

This is not merely terminology. It affects:

- calendar implementation;
- objective issuance and grading;
- rival progression;
- raid unlock timing;
- loot and Marks cadence;
- sacking thresholds;
- expansion length;
- economy pacing;
- content consumption;
- save-state transitions;
- UI language.

Implementing M5 before resolving this could encode the wrong model into services and screens.

### Why it matters

Campaign rhythm is the structure that gives individual raid nights meaning. A tier, season, and expansion need clear beginnings, pressure windows, grading moments, and transitions.

### Suggested intervention

Choose one canonical model.

Recommended default for consideration:

```text
One v1 expansion
├── Season 1 / Tier 1: approximately 12–14 weeks
│   ├── objectives issued
│   ├── progression and farm window
│   ├── tier grading
│   └── confidence/reputation update
└── Season 2 / Tier 2: approximately 12–14 weeks
    ├── raised expectations
    ├── new progression and farm window
    ├── final grading
    └── career summary → endless mode or rebuild
```

Advantages:

- One clear progression arc per raid tier.
- Natural objective cadence.
- Space for loot and learning to matter.
- Clear rival-race windows.
- Stronger season-end presentation.

This recommendation is not locked by this document.

### Decision required

Choose explicitly:

1. One season equals one tier; v1 expansion has two seasons.
2. One season contains both tiers.
3. Another fully specified model.

### Validation / exit criteria

All relevant docs, seeds, objective cadence, backlog wording, expected campaign duration, and UI terminology express the same model before M5 calendar and state services are implemented.

---

# 3. Product-promise and presentation findings

## W4 — “People are the game” is the promise, but much social expression is deferred

**Severity:** Medium-high product risk

### Observed evidence

The pitch and overview emphasize:

- personalities;
- cliques;
- grudges;
- mentorship;
- toxic stars;
- loyalty;
- burnout;
- relationship-driven performance;
- emergent social stories.

The v1 scope deliberately defers or limits:

- quirks and quirk effects;
- chemistry effects in resolution;
- the drama-event catalogue;
- faction politics;
- the relationship read model.

`RELATIONSHIP` intentionally ships as write-only in v1, with gameplay chemistry effects planned for M10/v1.1.

The current v1 personality foundation still includes meaningful variables:

- Execution, Awareness and Consistency.
- Ego, loyalty, influence and coachability.
- Life situations and availability.
- Morale, fatigue and form.
- Bench streaks.
- Loot expectations and fairness consequences.
- Recruitment uncertainty and attrition.

### Risk / weakness

The scope decision is rational, but it creates a possible gap between:

- the marketing fantasy: a living guild of memorable people;
- the initial mechanics: generated raiders differentiated mainly by statistics, availability and inferred archetypes.

Different campaigns may be mathematically distinct while feeling emotionally similar.

This is currently a **risk requiring playtest**, not a proven failure.

### Why it matters

Football Manager’s long-term attachment comes from remembered people, not merely tactical systems. Guildmaster needs players to remember:

- the healer who saved the first kill;
- the veteran who resented being benched;
- the recruit who was better or worse than advertised;
- the star who destabilized loot culture;
- the loyal member who stayed through a rebuild.

### Suggested intervention

Do not automatically expand v1 before the Fun Gate.

After raid-loop validation, assess whether a deliberately small identity layer should move into Early Access:

- 6–8 highly legible quirks;
- 10–15 high-value social/inbox events;
- no full chemistry graph integration initially;
- every effect tied to existing systems such as loot, benching, fatigue, attendance, coaching, recruitment, or loyalty.

Possible starter quirks:

- Mentor.
- Clutch.
- Tilt-Prone.
- Grudge-Holder.
- Flaky Genius.
- Glue.
- Magpie.
- Big-Game Player.

Possible starter events:

- A veteran challenges a loot decision.
- A benched player requests a conversation.
- A recruit’s availability claim proves unreliable.
- A member waives a loot claim.
- A rival approaches a core player.
- The roster asks for a rest week.
- A first kill creates a loyalty surge.

### Decision required

After playtesting, decide whether traits + loot + attendance + benching make raiders sufficiently memorable, or whether a small personality layer is required to support the Early Access promise.

### Validation / exit criteria

A playtester can recall several named raiders and explain why they matter beyond class, role and gear.

---

## W5 — Combat-log correctness is not the same as combat-log entertainment

**Severity:** High

### Observed evidence

The M4 combat screen correctly consumes the real deterministic resolution pipeline. The engine guarantees:

- ordered events;
- readable log lines;
- phase and event behavior;
- deaths, saves, duties and cooldown moments;
- wipe reasons;
- ratings;
- persisted facts.

The pull contract explicitly recognizes:

> “the feed is the show.”

However, no qualitative presentation contract currently defines:

- pacing;
- event hierarchy;
- phase-transition emphasis;
- key highlights versus full feed;
- close-call readability;
- pull-over-pull comparison;
- momentum or escalation;
- speed controls;
- kill versus wipe emotional treatment.

### Risk / weakness

A correct event list can be informative but emotionally flat. If players cannot feel a phase change, recognize the key mistake, or notice that the latest attempt improved, the raid night risks becoming passive reading.

This is a presentation risk—not evidence that the event engine is wrong.

### Why it matters

The combat log is Guildmaster’s match engine. Football Manager’s appeal does not come from displaying every simulation event equally. It comes from selection, timing, interpretation, and the relationship between tactical decisions and visible consequences.

### Suggested intervention

Write a lightweight **raid-night presentation contract** and playtest multiple generated nights.

The contract should define:

- What remains visible throughout a pull.
- How phases begin and end.
- Which events count as routine, notable, critical and decisive.
- How deaths, clutch saves, duty failures and cooldown windows are emphasized.
- How the player sees that an attempt was closer than the previous one.
- How learning progression is communicated.
- How a kill is made meaningfully distinct from a normal result.
- Whether the default is live commentary, key highlights, instant result, or configurable.
- What speed, pause, and skip controls are appropriate.

The first version can remain text-and-panel driven. The intervention concerns hierarchy and pacing, not expensive graphics.

### Decision required

Define the intended raid-night emotional mode:

- live tactical drama;
- fast management simulation with key highlights;
- highly readable after-action simulation;
- or a configurable combination.

### Validation / exit criteria

After a pull, a playtester can identify the decisive moment and whether the raid is improving without rereading an undifferentiated wall of text.

---

## W6 — “Every wipe names a culprit” risks false certainty and scapegoating

**Severity:** Medium

### Observed evidence

The design correctly prioritizes legible failure. The engine records:

- failed checks;
- check margins;
- deaths;
- missed duties;
- weak contributions;
- wipe reason;
- participant ratings.

But raid failures are intentionally coupled:

```text
low awareness
→ avoidable damage
→ increased healing demand
→ reduced tank support
→ tank death
→ raid collapse
```

The timeline uses a wipe-precedence order to select a concise dominant failure. This is useful for technical reporting, but one dominant check does not always equal one root cause or one morally responsible person.

### Risk / weakness

If the UI frames one player as “the culprit,” it could:

- feel arbitrary when RNG selects a different victim;
- teach the player to replace the lowest-rated person rather than solve the system;
- hide composition, gear or assignment problems;
- turn nuanced leadership into scapegoating.

### Why it matters

The player is supposed to become a better guildmaster. The diagnosis should teach causal reasoning, not simplistic blame.

### Suggested intervention

Adopt a player-facing diagnostic hierarchy:

1. **Primary failed check**
   - Example: Tank survival.

2. **Contributing factors**
   - Main tank lacks the readiness cap.
   - Healing lane is below recommendation.
   - Two avoidable events increased pressure.
   - A missed interrupt removed a healer.

3. **Key responsible moment**
   - Name an individual only when a specific event is directly attributable.

4. **Recommended intervention**
   - Improve gear/caps, change composition, reassign duty, spend supplies, downshift, or rest.

5. **Confidence and recurrence**
   - Example: “Tank survival failed in four of the last five pulls.”

Preferred language:

- “Primary cause” rather than “culprit.”
- “Contributing factor” rather than “fault.”
- “Key moment” for a named mistake or success.

### Decision required

Decide whether “culprit” remains player-facing language or becomes an internal diagnostic shorthand.

### Validation / exit criteria

A player can understand both:

- the immediate event that ended the pull;
- the systemic condition that made that event fatal.

---

## W7 — Performance ratings are politically important but under-specified as a product contract

**Severity:** High before M6

### Observed evidence

The simulation implements 1–10 performance ratings in `sim/resolution/rating.gd`. Tests validate the rating range and expected mechanical behavior.

Ratings feed or are intended to feed:

- post-night reports;
- morale and form;
- Loot Council signals;
- MVP decisions;
- guild expectations;
- fairness narratives.

The design generally says that performance is judged relative to expected output for gear and role, but it does not yet define the player-facing rating contract in sufficient detail.

Open questions include:

- Is expectation based on gear, role, spec difficulty, assignment or all four?
- How are tanks, healers, melee and ranged compared?
- Does a difficult assignment alter expected performance?
- Is avoidable death always penalized?
- Can a duty failure be double-counted through events, death and rating?
- Can an undergeared player earn an excellent rating by overperforming?
- Can a highly geared player rate poorly despite high raw output?
- How much are clutch saves and successful duties worth?
- Is consistency measured per pull, per night, or over recent weeks?

### Risk / weakness

Ratings can become a hidden authority system. If players do not understand why someone received a 4 or a 9:

- loot decisions may feel arbitrary;
- morale effects may feel unfair;
- “MVP” may become a proxy for gear;
- role comparisons may be invalid;
- players may optimize for rating rather than raid success.

### Why it matters

The rating is a linchpin connecting performance, morale, loot and narrative. A poorly understood rating could undermine the flagship Loot Council system.

### Suggested intervention

Write a rating design contract before M6.

Recommended governing principle:

> A performance rating measures how well a raider fulfilled their role and explicit assignments relative to the kit, gear, and situation available to them—not merely how large their raw output was.

The contract should specify:

- Expected contribution by gear, role and spec.
- Assignment difficulty and duty weighting.
- Avoidable damage and death penalties.
- Clutch-save and duty-success rewards.
- Role-specific expectations.
- Whether ratings are pull-level, night-level, rolling, or all three.
- A player-facing explanation breakdown.

Validation scenarios should include:

| Scenario | Intended rating behavior |
|---|---|
| Highly geared tank meets normal expectations | Around 6 |
| Undergeared healer executes two clutch saves | Around 8–9 |
| Highly geared DPS dies early to avoidable damage | Around 2–4 |
| Mid-geared DPS performs strongly and completes a critical interrupt | Around 8–9 |
| Low-output player completes a uniquely difficult assignment | Assignment contribution is visible |

### Decision required

Lock the rating’s player-facing meaning and permissible uses before it becomes evidence in loot decisions.

### Validation / exit criteria

Every displayed rating can be explained by a concise breakdown such as:

> Strong output for available gear; completed assigned duty; one avoidable death reduced the final rating.

---

## W8 — Raid preparation offers configuration, but its tactical payoff must be proven

**Severity:** Medium

### Observed evidence

The current raid-prep surface supports:

- a 20-person lineup from a larger roster;
- bench and lineup swaps;
- role coverage;
- utility warnings;
- melee/ranged profile warnings;
- assignments;
- consumable tier;
- auto-fill and auto-assignment.

The resolver reads tactical inputs including tank, duty, cooldown and consumable assignments.

The current balance harness varies gear, but does not yet provide comparative evidence that different assignment or composition configurations materially change outcomes at the same roster power.

### Risk / weakness

Prep can feel administrative if the player cannot observe the consequence of their decision.

Football Manager’s tactical depth comes not from the number of controls alone, but from the visible relationship:

```text
choice → match consequence → report explanation
```

### Why it matters

Raid prep is one of the player’s primary agency surfaces. If its controls are weak, the pull feels like a passive simulation of roster statistics.

### Suggested intervention

For every prep control, define a trade-off and an observable consequence:

| Control | Trade-off | Expected consequence | Report evidence |
|---|---|---|---|
| Add healer | Lower DPS, higher sustain | Better healing/tank survival | Check margin comparison |
| Add ranged | Possible utility/role trade-off | Lower melee-targeted pressure | Event and death summary |
| Change tank | Gear/cap versus familiarity/skill | Different tank-failure risk | Tank check breakdown |
| Assign interrupter | Uses a specific player’s skill/reliability | Duty event succeeds or fails | Duty history |
| Premium consumables | Stock/gold cost | Better margins and survival | Consumed resources and effect |
| Downshift/farm | Slower progression | Safer reward path | Readiness and reward report |

Add balance probes using the same seed, roster and gear with different:

- assignment configurations;
- healer/DPS splits;
- melee/ranged splits;
- consumable plans;
- tank choices.

Possible additional tactical postures to assess—but not automatically add—include:

- safe versus aggressive;
- learning pull versus kill attempt;
- protect a weak player versus assign responsibility;
- conservative versus burst cooldown plan.

### Decision required

Identify which preparation choices must be meaningful in the first-session demo. Controls without observable payoff should be strengthened, simplified, clarified, or deferred.

### Validation / exit criteria

A playtester can describe at least one preparation choice that changed a later pull, and the report provides evidence for that interpretation.

---

## W9 — The involvement slider is a core audience strategy but is scheduled late

**Severity:** Medium

### Observed evidence

Manual-to-auto flexibility is a non-negotiable design pillar for raid night and loot. The consolidated implementation task is currently `M9-005`, after calendar, loot, economy, recruitment and objectives.

The involvement model affects:

- screen complexity;
- automation boundaries;
- recommendations;
- key-moment presentation;
- report detail;
- accessibility;
- pacing;
- delegation quality.

### Risk / weakness

If all Phase-B screens are designed for full manual operation and automation is specified only at M9, earlier UX may require rework.

This is not an argument that the entire slider must be implemented now. It is an argument that its behavior contract should guide Phase-B design now.

### Why it matters

The game targets both:

- MMO veterans who want deep control;
- sim players who want recommendations, delegation and faster pacing.

One deep simulation with configurable responsibility is a strong differentiator.

### Suggested intervention

Define the behavior contract before Phase B:

| Domain | Manual | Assisted | Instant |
|---|---|---|---|
| Lineup | Player selects | Recommended, editable | Auto-fill |
| Assignments | Player assigns | Auto plan with warnings/overrides | Auto |
| Pulls | Pull-by-pull/key calls | Key moments and recommendations | Result plus highlights |
| Loot | Manual award | Recommendation plus approval | Policy auto-resolves |
| Weekly plan | Player allocates | Advisor proposal | Auto-plan |
| Recruitment | Player scouts/signs | Ranked shortlist | Policy-driven |

For each mode specify:

- what is automated;
- what the player can override;
- what information remains visible;
- whether automation quality can vary;
- how reports differ.

### Decision required

Define what Manual, Assisted and Instant mean across every major system before designing M5–M9 screens.

### Validation / exit criteria

Phase-B screens can be designed once with clear automation hooks rather than retrofitted later.

---

## W10 — MMO terminology may alienate management-sim players

**Severity:** Medium

### Observed evidence

The design uses authentic MMO terms:

- battle-rez;
- uncrittable;
- DKP;
- Loot Council;
- Soft Reserve;
- soak;
- dispel;
- haste burst;
- progression pull;
- farm night.

This language is attractive and efficient for veteran MMO players. The stated target audience also includes management-sim players who may not know these terms.

Current warning examples such as “No battle-rez tonight” and “Main tank not uncrittable” are legible to veterans but may not tell a new sim player what the consequence is or what action to take.

### Risk / weakness

The addressable audience narrows if understanding the interface requires prior raid-leading knowledge.

### Why it matters

Football Manager handles domain complexity with:

- contextual explanations;
- staff recommendations;
- tooltips;
- comparisons;
- delegation;
- progressive disclosure.

Guildmaster should preserve MMO authenticity without making MMO literacy a prerequisite.

### Suggested intervention

Adopt a dual-language UI convention:

| Specialist term | Player-facing explanation |
|---|---|
| No battle-rez | No emergency combat revival is available after a key death |
| Main tank not uncrittable | Main tank is vulnerable to critical boss attacks; one spike may cause a wipe |
| Too many melee | Too many close-range attackers are exposed to this boss’s mechanics |
| Soak assignment | A designated player must absorb or manage this attack |
| Loot drought | This raider has gone unusually long without a meaningful reward |

Principles:

- Plain-language consequence first.
- MMO term second, in parentheses or a tooltip.
- Every warning includes an actionable implication.
- Advanced detail remains available for experienced players.
- A glossary is accessible but not required for basic play.

### Decision required

Adopt or reject the rule that every specialist warning must explain both the consequence and likely intervention in plain language.

### Validation / exit criteria

A management-sim player without MMO history can act on raid-prep warnings without external explanation.

---

# 4. Campaign-depth and roadmap findings

## W11 — The economy death spiral has no defined recovery path

**Severity:** Medium

### Observed evidence

The between-nights design intentionally creates a negative feedback loop:

```text
poor culture and morale
→ lower donations
→ weaker provision
→ worse raid readiness
→ more wipes and repair costs
→ lower morale and loyalty
→ further economic decline
→ possible bankruptcy and sacking
```

This is a coherent and thematic failure model. The current design does not specify enough recovery mechanisms for a guild already inside the spiral.

### Risk / weakness

A decline can become predetermined rather than managed if the player has no viable intervention once resources, morale and performance begin reinforcing one another.

The game should allow hard failure. The concern is not difficulty; it is whether collapse continues to contain meaningful decisions.

### Why it matters

Football Manager and similar simulations provide recovery valves:

- tactical change;
- easier fixtures;
- player sales;
- wage reduction;
- board support;
- temporary loans;
- expectation management.

Guildmaster needs equivalents appropriate to guild leadership.

### Suggested intervention

Design at least 3–4 explicit recovery valves before M7 implementation. Options to assess:

- Emergency officer or loyalist contribution.
- Temporary austerity policy.
- Convert a raid night into a gearing event.
- Farm easier bosses.
- Sell unused materials.
- Temporary BYO consumables with morale cost.
- Rest or social recovery week.
- Reputation-cost emergency funding.
- Reduced expectations following a severe roster crisis.
- Rebuild-oriented recruitment.

Each recovery option should impose a trade-off. The goal is not a free bailout.

The weekly digest should telegraph the spiral before terminal failure:

- donations below projected costs;
- repair expenditure accelerating;
- provision unsustainable;
- roster fatigue increasing;
- confidence approaching danger levels.

### Decision required

Define:

- which crises are recoverable;
- which interventions exist;
- what each intervention costs;
- when sacking becomes the intended terminal state.

### Validation / exit criteria

A player in a weak economic state has at least two intelligible recovery choices with materially different costs.

---

## W12 — Rival guilds are useful abstractions but may not feel alive

**Severity:** Medium

### Observed evidence

The light rival model includes:

- approximately 6–10 ghost guilds;
- fast/mid/slow progression curves;
- shared encounter-progress representation;
- server standings;
- generated rival rosters;
- poaching potential.

This is an appropriate solo-scope compromise. Rival guilds do not need a full simulation.

No minimum presentation layer is yet defined for rival identity, history, news or visible behavior.

### Risk / weakness

Progress curves alone may feel like leaderboard timers with names. Competitive objectives and server-first races rely on rivals feeling like organizations rather than scheduled percentages.

This is currently a presentation risk, not evidence that the light simulation model is inadequate.

### Why it matters

Football Manager turns simulations into worlds through:

- news;
- rival identity;
- histories;
- staff and manager personalities;
- transfer stories;
- standings context.

Guildmaster can create similar world texture cheaply from its existing state.

### Suggested intervention

Add low-cost presentation rather than expensive rival AI:

- Guild culture/archetype.
- Signature strength and weakness.
- Named guildmaster or officer.
- Progression headlines.
- First-kill notifications.
- Public recruitment posts.
- Poach attempts.
- Rival roster loss or recovery stories.
- Server-forum or gossip-style inbox items.
- Standings movement with short reasons.

Example:

> **The Gilded Order** — aggressive progression, Loot Council culture, strong ranged roster, known for poaching healers.

### Decision required

Define the minimum rival identity and news layer required for v1. Keep the underlying simulation light unless evidence demands more.

### Validation / exit criteria

A player can describe at least two rivals as distinct organizations, not only different progress bars.

---

## W13 — Replay variety may be thin if personality and world presentation arrive late

**Severity:** Low-medium now; higher for Early Access

### Observed evidence

The v1 content target is intentionally sustainable:

- 6 classes / 18 specs;
- approximately 12 bosses across two tiers;
- approximately 65 loot items;
- three loot policies;
- recruitment;
- economy;
- objectives;
- generated rosters.

This is a reasonable content target for solo development.

Several major variety sources are deferred:

- quirks;
- chemistry effects;
- drama catalogue;
- multiple expansions;
- deeper rival behavior.

Boss content is fixed. Roster generation creates statistical variety, but repeated campaigns may still tell similar stories if personality and world presentation are too limited.

### Risk / weakness

Two campaigns could feel like the same twelve-boss solution with different names and distributions rather than two genuinely different guild histories.

This requires playtesting and cannot be concluded from code alone.

### Why it matters

The design claims that systems create replayability and emergent stories. The project must identify which systems actually carry campaign-to-campaign variation in v1.

### Suggested intervention

Prioritize **variety per authoring hour** rather than raw content count.

High-leverage candidates after the Fun Gate:

1. Small quirk set.
2. Small social-event set.
3. Rival identity/news layer.
4. Guild chronicle/history system.
5. Encounter modifiers that reuse existing event types.
6. Different objective profiles or guild cultures.
7. Multiple starting-roster archetypes.

A guild chronicle could surface:

- first kills;
- best attempts;
- wipe counts;
- legendary loot awards;
- departures and poaches;
- longest-serving members;
- season outcomes;
- sacking and rebuild history.

These may create more perceived variety than adding more bosses.

### Decision required

After the Fun Gate, compare the value of:

- additional encounters and items;
- versus a small personality and world-presentation layer.

### Validation / exit criteria

The v1 roadmap names the specific systems expected to make one campaign meaningfully different from another.

---

## W14 — The full v1 scope remains large despite strong scope fencing

**Severity:** High roadmap risk

### Observed evidence

Beyond the completed M0–M4 slice, the planned v1 includes:

- persistent campaign creation and save/load;
- calendar and event-day advancement;
- availability;
- five between-night lanes;
- gear and Marks;
- three loot policies and consequences;
- treasury, stockpile and economy policies;
- recruitment, scouting, trials and signing;
- attrition and population generation;
- objectives and grading;
- rival ladder;
- sacking and rebuilding;
- involvement modes;
- two tiers and associated content;
- UI and reporting for every system.

M10–M11 are fenced, but M5–M9 still represent substantial implementation, tuning, UX and content work.

### Risk / weakness

The project can build backend systems faster than it can validate, present and tune them. The largest danger is not architectural failure. It is reaching a broad but emotionally under-polished Early Access build.

### Why it matters

For a solo developer, every system has at least four costs:

1. Implementation.
2. UI and explanation.
3. Balance and integration.
4. Content and long-term maintenance.

A technically small feature can be product-expensive.

### Suggested intervention

Treat M5–M9 as sequential product gates, not one automatic build commitment:

```text
M4 Fun Gate
→ M5 campaign skeleton gate
→ M6 loot/fairness gate
→ M7 economy sustainability gate
→ M8 recruitment/roster-churn gate
→ M9 full-season gate
```

At each gate ask:

- Is the previous loop enjoyable?
- Does the new system add a decision or only administration?
- Is its effect legible?
- Is the UI understandable?
- Is the content burden sustainable?
- Should a lower-value subsystem be simplified or deferred?

Also assess a **Phase B-lite** option after the Fun Gate:

- Campaign/calendar/save loop.
- One flagship loot system first—probably Loot Council.
- Basic loot consequences.
- Basic treasury/provision rather than full economy.
- One recruitment channel before all four.
- Objectives and grading sufficient for one complete tier.

Then playtest the complete week/season loop before adding breadth such as DKP, roll, deeper economy and full recruitment.

This is a proposal for reassessment, not a locked scope reduction.

### Decision required

Choose whether Phase B proceeds as:

- the full current M5–M9 plan;
- a deliberately staged Phase B-lite followed by breadth;
- or another reduced validation path.

### Validation / exit criteria

Every major Phase-B cluster has a human product gate in addition to technical acceptance criteria.

---

# 5. Cross-cutting intervention contracts to create

These are suggested design artifacts. They should become tasks only after approval.

## 5.1 First-session scenario contract

Define:

- starting roster state;
- visible weakness;
- intended first failure;
- intended player intervention;
- target number of pulls;
- first-kill payoff;
- loot or consequence;
- expected session length.

## 5.2 Encounter progression contracts

For every boss:

- plausible first-attempt state;
- intended challenge;
- expected pull count;
- expected intervention;
- learning contribution;
- gear progression;
- farm state;
- allowed failure distribution.

## 5.3 Campaign structure contract

Lock:

- season versus tier;
- expansion duration;
- objective cadence;
- grading cadence;
- raid unlock rules;
- rival pacing;
- transition and endless-mode behavior.

## 5.4 Raid-night presentation contract

Define:

- feed hierarchy;
- phases;
- pacing;
- highlights;
- improvement comparison;
- decisive moments;
- speed and involvement modes;
- kill and wipe treatment.

## 5.5 Diagnostic contract

Define:

- primary cause;
- contributing factors;
- key moment;
- recommended intervention;
- confidence/recurrence;
- player-facing blame language.

## 5.6 Performance-rating contract

Define:

- role-relative expectations;
- gear-relative expectations;
- assignment weighting;
- avoidable failure penalties;
- clutch and duty rewards;
- pull/night/history aggregation;
- explanation format.

## 5.7 Involvement-mode contract

Define Manual, Assisted and Instant behavior for:

- weekly planning;
- lineup;
- assignments;
- pulls;
- loot;
- recruitment;
- reports.

## 5.8 Accessibility and terminology contract

Define:

- plain-language-first warnings;
- secondary MMO terminology;
- actionable tooltips;
- glossary behavior;
- progressive disclosure.

## 5.9 Economy recovery contract

Define:

- recoverable crisis states;
- terminal failure state;
- recovery options;
- costs;
- warning thresholds;
- sacking relationship.

## 5.10 Replayability contract

Identify which v1 systems are expected to create campaign variety:

- roster generation;
- guild culture;
- loot history;
- objectives;
- rival identity;
- quirks/events if approved;
- encounter variation;
- chronicle/history.

---

# 6. Recommended intervention sequence

## Gate I-1 — Play the existing M4 slice

### Action

Run hands-on sessions with:

- at least one old MMO-raiding veteran;
- at least one management-sim player with limited MMO knowledge;
- ideally one broader strategy/simulation player.

Observe rather than teach.

### Questions

- What do they think the immediate problem is?
- Which warning do they act on?
- What do they change after a wipe?
- Do they see improvement?
- Do they remember raiders by name?
- Do they understand the jargon?
- Do they want another pull or night?

### Pass criterion

The slice demonstrates understandable agency and desire to continue.

### Fail action

Tune, clarify or re-present the slice. Do not add campaign breadth.

---

## Gate I-2 — Validate a curated first-session payoff

### Action

Create a representative demo contract with:

- a fixable weakness;
- a legible failure;
- a meaningful corrective action;
- visible improvement;
- a plausible kill;
- a reward/consequence.

### Pass criterion

The intended loop works reliably enough to evaluate with human players.

### Fail action

Revisit encounter tuning, preparation leverage, learning visibility or report presentation.

---

## Gate I-3 — Resolve the campaign model

### Action

Lock the season/tier/expansion structure and align all affected design assumptions.

### Pass criterion

One consistent campaign rhythm governs calendar, objectives, progression, rivals, gear and grading.

### Fail action

Do not implement M5 calendar or campaign services.

---

## Gate I-4 — Approve the product UX contracts

### Action

Approve at minimum:

- screen/navigation map;
- involvement modes;
- terminology rules;
- raid-night presentation;
- diagnostic hierarchy;
- rating contract.

### Pass criterion

Phase-B screens can be designed consistently and support both MMO veterans and sim players.

### Fail action

Keep M5 implementation blocked while interaction assumptions remain unresolved.

---

## Gate I-5 — Confirm economy, rival and personality direction

### Action

Decide:

- economy recovery valves;
- minimum rival identity/news layer;
- whether a starter personality/event layer is needed for v1;
- which systems carry replayability.

### Pass criterion

The v1 promise, content budget and replay strategy are aligned.

### Fail action

Keep these systems simplified or deferred rather than implementing ambiguous breadth.

---

## Gate I-6 — Reconfirm Phase B scope

### Action

Choose full Phase B or Phase B-lite.

### Pass criterion

The chosen roadmap is sized around validated player value, not only the existing backlog.

### Fail action

Reduce or stage scope before opening implementation tasks.

---

# 7. Human Fun Gate scorecard

This complements automated tests. It does not replace them.

| Question | Pass condition |
|---|---|
| Can the player explain the immediate guild/raid problem? | They identify a roster, composition, gear, duty or readiness weakness. |
| Can they make a meaningful decision? | They intentionally change lineup, assignment, consumables, target or strategy. |
| Is failure legible? | They can state a primary cause and at least one contributing factor. |
| Does the next pull show a consequence? | The change produces a visible margin, event, survival or outcome difference. |
| Is there emotional escalation? | The player recognizes close calls, clutch moments, and improving/worsening attempts. |
| Is a first kill plausible? | A representative session can produce one without hidden setup or excessive repetition. |
| Do named raiders matter? | The player recalls several people and their role in the result. |
| Is MMO terminology understandable? | A non-MMO player can act on warnings using the UI explanation. |
| Does the player want to continue? | They ask for another pull, boss, week or season. |

A weak score does not automatically imply that more systems are needed. The remedy may be balance, presentation, explanation, stronger leverage, or a better first-session scenario.

---

# 8. What should not change during the intervention

The following remain the project’s strongest identity and should not be diluted without strong playtest evidence:

1. **People are the game.** The roster is the central management challenge.
2. **Legible causal outcomes.** Every result should teach the player something.
3. **Loot as leadership and culture.** The adopted system defines fairness expectations.
4. **Player persists; Avatar is swappable.** Human identity survives rerolls, expansion resets and rebuilds.
5. **Rest and sustainability are valid strategy.** The game should not reward endless grinding by default.
6. **Content as data.** New encounters, items and events should not require boss-specific engine code.
7. **Deterministic simulation.** Same seed and inputs produce the same outcome.
8. **IP-safe original setting.** Recreate the management fantasy, not another game’s proper nouns.
9. **Fixed raid-night scale.** A 20-person raid selected from a larger roster creates bench and coverage tension.
10. **Recruitment uncertainty.** Avatar-visible / Player-hidden knowledge is a strong core model.

The intervention is intended to prove and present these pillars—not replace them.

---

# 9. Assumptions to reconsider

| Existing assumption | Intervention question |
|---|---|
| M4 technical completion means the project can move to M5 | Has the qualitative Fun Gate actually passed? |
| A green harness means the raid progression curve is healthy | Does every boss meet an explicit, plausible progression contract? |
| The campaign structure is already locked | Do season, tier and expansion mean the same thing in every document? |
| The current v1 personality scope fulfills “people are the game” | Are generated raiders memorable enough in real playtests? |
| Correct event logs are entertaining | Does presentation create tension, hierarchy and memory? |
| Every wipe needs one culprit | Should reports distinguish primary cause, contributing factors and key moment? |
| Ratings can remain mostly implicit | Are ratings understandable enough to influence loot and morale? |
| Existing prep controls are inherently tactical | Do their outcomes differ visibly and materially? |
| Involvement can be added at M9 | Should its behavior guide all Phase-B UX now? |
| MMO terminology is naturally legible | Can a sim player understand and act without prior raid knowledge? |
| A death spiral is meaningful because it is harsh | Does decline contain recovery decisions before terminal failure? |
| Rival progress curves create a living server | Is an identity/news layer required? |
| More bosses are the main replayability lever | Would quirks, events, rivals and history provide more value per authoring hour? |
| The Phase-B backlog should be executed as written | Should it be staged into smaller product-validation gates? |

---

# 10. Decision register

Suggestions above are not locked until recorded here by human decision.

**Decisions taken 2026-07-11** (Panos, after the checkpoint assessment). See ADR-0022 in `docs/decisions.md`.

| ID | Decision | Status | Rationale | Follow-up task(s) |
|---|---|---|---|---|
| I-01 | Define the representative first-session scenario | **Approved** | The default slice is a 32-wipe/0-kill session (verified). It must become a representative first session with a plausible kill. | MI-003 |
| I-02 | Define boss-by-boss progression contracts | **Approved** | Boss demands were authored as symbolic numbers never tied to real roster output. Root cause of the 0-kill session (see 10.1). | MI-001, MI-009 |
| I-03 | Lock the season/tier/expansion model | **Approved: Model A — Season = Tier** | One v1 expansion = Season 1/Tier 1 (~12–14 wk) → Season 2/Tier 2 (~12–14 wk). Clean objective cadence, natural grading ceremony, clear rival-race windows. | MI-011 |
| I-04 | Define the raid-night presentation contract | **Approved** | "The feed is the show" has no hierarchy/pacing contract. | MI-004 |
| I-05 | Define diagnostic hierarchy and player-facing blame language | **Approved** | "Culprit" becomes internal shorthand; player-facing = primary cause → contributing factors → key moment → recommended intervention. | MI-005 |
| I-06 | Define the performance-rating contract | **Approved** | Must be locked before ratings become evidence in Loot Council (M6). | MI-006 |
| I-07 | Define the involvement-mode contract | **Approved** | Contract written NOW to guide Phase-B UX; full implementation stays at M9-005. | MI-007 |
| I-08 | Adopt or reject dual-language MMO terminology | **Approved (adopt)** | Plain-language consequence first, MMO term second. Widens the addressable audience without diluting authenticity. | MI-008 |
| I-09 | Define economy recovery valves | **Approved (deferred to pre-M7)** | Required before economy implementation, not before the Fun Gate. | MB-004 |
| I-10 | Decide whether starter quirks/events enter v1 | **Deferred by design** | Doc's own guidance: decide AFTER the Fun Gate, on playtest evidence. Do not pre-commit scope. | Revisit at Gate I-1 |
| I-11 | Define the minimum rival identity/news layer | **Approved (deferred to pre-M9)** | Low-cost presentation layer; needed before objectives/rivals land. | MB-005 |
| I-12 | Confirm full Phase B or Phase B-lite | **Approved: Phase B-lite, then breadth** | Stage campaign → Council-only loot → basic treasury → one recruitment channel → one tier's objectives. Playtest the week/season loop before adding breadth. Each cluster gets a human product gate. | MI-012 + the M5–M9 rescope; breadth tracked as MB-001…005 |

## 10.1 Root-cause evidence for I-01 / I-02 (measured 2026-07-11)

The default first session was reproduced and instrumented. At the **real** starting roster (avg ilvl 18.9, gear_score 132):

| Boss | DPS lane / demand | Healing lane / demand | P(all four checks pass) |
|---|---|---|---|
| Gatewarden Krogg | 27.6 / 40.0 | 25.6 / 44.8 | **1.17 %** |
| Forgemaster Vell | 27.6 / 50.0 | 25.6 / 50.4 | 0.08 % |
| Slagbeast | 27.6 / 45.0 | 25.6 / 72.8 | 0.005 % |
| Cinderlords | 27.6 / 55.0 | 25.6 / 61.6 | 0.001 % |

Two compounding causes:

1. **Content/start-state deadlock.** Tier-1 boss drops average **ilvl 31** against a starting roster of **ilvl 18.9**. The loot *is* the gear ramp — but the entry boss already demands roughly the gear it drops. You cannot kill without loot and cannot loot without a kill.
2. **Conjunctive check aggregation (not named in the original findings).** The four checks are independent rolls that must *all* pass. Even a healthy raid at p=0.8 per check would kill only ~41 % of the time. Worse, healing failure and mechanic failure are **already** modelled by the timeline as cascade deaths and avoidable deaths — the separate checks double-count them.

Both are addressed by MI-001 (encounter contracts + retune) and MI-002 (aggregation fix).

---

# 11. Final checkpoint statement

Guildmaster’s foundation is excellent. The technical architecture, deterministic simulation, data model, content pipeline, test coverage, raid-resolution framework and vertical-slice integration are real accomplishments.

The intervention is necessary precisely because the project has reached a healthy breakpoint:

- enough exists to evaluate the experience honestly;
- relatively little Phase-B code exists that would make changes prohibitively expensive;
- the major remaining questions are product questions rather than architecture questions.

The project should not interpret this pause as reversal or loss of confidence. The objective is to protect the strongest parts of the design by proving that they produce the intended experience before adding campaign breadth.

The next milestone should not be defined only as “M5 implementation begins.” It should be:

> A player understands the raid, makes a consequential decision, sees the difference, earns a memorable result, and wants to continue the guild’s story.

---

*Intervention checkpoint created after the M0–M4 vertical-slice assessment. Review and decide Gates I-1 through I-6 before Phase-B expansion.*
