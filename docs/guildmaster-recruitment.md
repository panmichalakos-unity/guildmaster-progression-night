# Guildmaster: Progression Night — Recruitment & Scouting (v0.1)

> **STATUS (2026-07-19): design contract — M8 builds this (one channel in v1; scouting/poach/referrals → MB-003).** Already in place: `PROSPECT_ASSESSMENT` table, the applications inbox queue (reads it, empty until M8), trials are lineup-eligible (M5-003), and trial pulls already feed ratings.

One system, two activities: **scouting** (reduce uncertainty about a prospect) and **recruitment** (the pipeline: source → assess → trial → sign). Too coupled to split.

**The key reuse:** the visibility line falls exactly on the **Avatar / Player** boundary we already built. No new fog-of-war concept — it's latent in the two-layer model.

## What you can and can't see
- **Avatar = the public record.** Gear, class/spec, professions, experience, boss-kill history, past guilds. Inspectable by anyone, known at recruitment, free. *But it can be carried, bought, or boosted* — a shiny Avatar can hide a rotten Player. That trap is the drama.
- **Player = the fog.** True skill, pressure-handling, culture fit, availability, attendance, loyalty, ego, coachability. Hidden until revealed.

### Three tiers of knowledge
| Tier | What you get | Cost | Reliability |
|---|---|---|---|
| **See** (Avatar) | gear, spec, professions, experience, kill history, past guilds | free, instant | true — but can be carried/boosted |
| **Told** (interview) | *stated* availability, goals, surface personality | cheap | noisy — inflated by ego/dishonesty |
| **Uncover** (Player) | true skill, pressure, culture fit, attendance, loyalty | scout / trial / tenure | true, revealed progressively |

The **Told** tier matters: the confident recruit oversells, the modest one undersells. Especially availability — they *say* "every raid," but schedule volatility means the truth differs. Self-reported data with a reliability caveat.

## The revelation gradient
| Hidden trait | Revealed by | Fully known only after |
|---|---|---|
| Skill (exec / aware) | armory prior → scout → trial | a few real raids |
| **Consistency / pressure** | trials barely show it | a *progression* pull |
| Availability fit | stated + checked vs your schedule | computable once stated |
| Attendance reliability | — | weeks of tenure |
| **Culture / chemistry fit** | relational — only vs *your* roster | raiding together |
| Loyalty / ego | interview hints | tenure + a stress event (snub, benching) |

**Two things you can never fully de-risk pre-sign:**
- **Pressure** — a farm-night trial is low-stakes; only real progression reveals whether they hold up.
- **Culture fit** — it's *relational*. A player toxic in one guild is fine in another; fit only exists against *your* people.

That irreducible gamble is the point.

## Priors from the public record (light)
The Avatar gives **noisy priors** on the hidden traits: "cleared the current tier" → initial skill estimate lands in a high-ish band (but maybe carried). Kept deliberately light — *kill history sets an initial skill estimate band, nothing more.* Cheap, readable, and it makes the armory meaningful without a sub-game.

## Sourcing channels (each a different info profile)
| Channel | Info profile | Cost / friction |
|---|---|---|
| **Applicants** (inbound) | full Avatar; volume scales with guild reputation | cheap — you sift |
| **Scout free agents** (outbound) | target comp gaps; tighten estimates | effort / time (the People lane) |
| **Poach rivals** | proven at your tier; poach a *duo* to import known chemistry | signing incentive + rival friction |
| **Referrals** | pre-revealed Player info + built-in chemistry with the referrer | limited supply — ties to your loyal roster |

**Referrals and duo-poaching are the standouts** — both let you *buy down the fog* through the chemistry graph. A referral comes with its Player traits partly pre-revealed (the referrer vouches) and a positive relationship pre-seeded; a poached duo imports a known chemistry bond.

## The pipeline
```
source  →  assess (scout to tighten estimates)  →  trial (farm night, reveals more)  →  sign / pass
```
- **Trials** = bring a prospect on a low-stakes night; they occupy a slot and generate real (if limited) performance data → estimates tighten, but pressure/culture stay partly hidden.
- **Signing** commits them to the roster (and, if poached, pays an incentive and dings the rival relationship).
- Recruitment *need* is driven by roster gaps — a comp hole, attendance risk, or a departure.

## Data model touchpoints
- **A prospect is just a `PLAYER`** with `GUILD_MEMBERSHIP.status` = `applicant` / `trial` (free agents = no active membership). **Truth lives on `PLAYER`.**
- **The fog is an overlay:** `PROSPECT_ASSESSMENT` per (guild × prospect × attribute) — the current estimate, confidence, and a revealed flag. Display applies noise scaled by confidence; truth is read from `PLAYER` only after revelation.
- **Reads:** PLAYER (truth) · AVATAR (public record) · GUILD.reputation (applicant volume) · RELATIONSHIP (referrals / duo chemistry) · roster gaps (GUILD_MEMBERSHIP).
- **Writes:** PROSPECT_ASSESSMENT (estimate/confidence updates from scout/trial) · GUILD_MEMBERSHIP (status transitions) · RELATIONSHIP (referral seed, rival friction on poach) · TREASURY_LEDGER (signing incentives) · WEEK_ACTION (scout/trial actions).
- **New table (folded into data model v0.5):** `PROSPECT_ASSESSMENT`. Everything else reuses existing entities.

*Lakehouse framing:* truth **dimension** (`PLAYER`) + a per-guild **known-state fact** (`PROSPECT_ASSESSMENT`) — the estimate converges on truth as evidence accumulates. Classic slowly-revealing-fact pattern.

## The population tick (where prospects come from)
A weekly generation tick creates new free agents and applicants. Volume and quality scale with `GUILD.reputation`; prospects come from the same roster-generation system (correlated traits, life presets), named by the naming-bible generator. Rival-guild rosters (see the rival ladder in campaign) form the **poach pool**.

## Attrition — the roster's other door
A weekly **leave-check** per member: risk rises with low `loyalty_current`, low morale, bench streaks, loot droughts, and rival interest. A departure writes `GUILD_MEMBERSHIP.left_at` + a `reason`, lands in the inbox, and — if poached — strengthens that rival. **Telegraphed, never a rug-pull:** at-risk raiders surface in the weekly digest before they walk.

## v1 scope
- **In:** Avatar-transparent / Player-hidden visibility; the revelation gradient (armory → stated → scout → trial → tenure); light kill-history priors; **all four channels** (applicants + scouting first, poach/referrals layered once the overlay works); the source→assess→trial→sign pipeline; the assessment overlay.
- **Layer later:** richer interview/negotiation, dishonest-recruit modeling depth, scouting-network/scout-quality mechanics, contract terms.

---

*v0.1 — recruitment & scouting locked; estimate-noise and reveal-rate constants symbolic, to be tuned. IP-original naming throughout.*
