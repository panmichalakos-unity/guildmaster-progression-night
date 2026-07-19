# Guildmaster: Progression Night — Loot & Fairness System (v0.1)

> **STATUS (2026-07-19): design contract — M6 builds this next.** Already in place from earlier milestones: `LOOT_DROP`/`LOOT_CLAIM`/`PLAYER_LOOT_STANDING`/`GUILD_CONFIG.active_loot_system` tables, `decided_by` audit (ADR-0033), per-raider ratings as evidence (MI-006), the unawarded-loot inbox queue, and both tiers' loot tables seeded. Nothing writes `LOOT_DROP` rows yet — kills report loot as an explicit M6 placeholder.

Loot is the drama engine. The design goal is **not** a fair algorithm — it's a system where *the fairness call is yours and the fallout is real.*

**Core principle: fairness isn't objective, it's per-culture.** The loot system you adopt **sets the yardstick the guild judges you by.** A points guild asks "did the numbers hold?"; a council guild asks "was the call defensible?". Same award, different verdict.

## Loot systems as pluggable policies
Each system is a culture the guildmaster adopts, sitting on the fairness ↔ efficiency ↔ drama triangle:

| System | How it works | Your agency | Drama profile | Effort |
|---|---|---|---|---|
| **Loot Council** *(flagship)* | You / officers decide each drop | **Max** | High — every call is judged | High |
| **DKP** (points economy) | Earn points (attendance + kills), spend on drops | Low | Low per-drop; rewards seniority over need | Low |
| **/roll** (random) | Pure RNG | None | "Lost 5 in a row" streak drama | Zero |
| **Soft Reserve** *(later)* | Reserve one item pre-raid; priority if it drops | Low–med | Contained to "the one thing I want" | Low |
| **EPGP / Priority** *(later)* | Self-balancing ratio / rotation list | Med | Moderate | Med |

**Design:** loot is a **pluggable policy interface**. Ship **three at launch** to cover the corners — **Loot Council** (control), **DKP** (economy), **/roll** (random). The rest are later content. (Generic community terms — IP-safe; reskin for flavor optional.)

Loot Council is the flagship: it's the only system where *you* weigh the factors and eat the blame. The others are "set a policy, let it run" cultures with less per-drop agency.

## Flagship: Loot Council decision anatomy
When an item drops, the **claims panel** lists each eligible raider with the factors behind their claim:

1. **Upgrade magnitude** — size of the power jump (raid-optimal = gear who benefits most).
2. **Performance** — recent `performance_rating` (the MVP reward).
3. **Loyalty / tenure** — long-timers expect payoff.
4. **Attendance** — showed up when it mattered.
5. **Spec priority** — main-spec raiding role vs off-spec / alt.
6. **Progression need** — does the raid *need* this person geared for the next check (e.g. the tank's resist piece)?
7. **Drought** — fed recently, or gone dry for weeks?

The drama is that these **conflict**: the MVP is a new recruit (low loyalty); the loyal vet is underperforming; the needed piece is someone's off-spec. You can't satisfy everyone — that's the game.

## Consequence model
Each award resolves against every raider's *expectation vs outcome*, filtered through psychology:

- **Recipient** → morale boost (scaled by upgrade size × ego).
- **Passed-over claimants** → morale hit = perceived-claim × ego/entitlement × temperament. A high-ego "deserving" raider → big hit, possible `DRAMA_EVENT`, and a **relationship ding toward the recipient** (feeds the chemistry graph; *Grudge-Holder* makes it stick).
- **Guild fairness perception** → the room judges the call *by its culture's yardstick*. Sustained perceived-unfairness → loyalty erosion, poach vulnerability, faction formation → feeds the **sacking meter**.
- **Loyalty drift** → rewarding builds `loyalty_current`; repeated snubs erode it.
- **Quirk hooks** → *Magpie* inflates entitlement and loss-drama; a raider waiving a claim *builds* culture.

## Strategic tension (the actual gameplay)
Every drop is: **optimize the raid** (gear the MVP / biggest upgrade) vs **reward the people** (the loyal vet) vs **serve progression** (the needed piece) vs **manage politics** (feed the drought, avoid the ego meltdown).

Over a season these compound: pure meritocracy gets strong but bleeds loyalty; pure loyalty stays happy but under-geared. Navigating the middle *is* the loot game. And if you run the optional player-GM, awarding **yourself** loot draws amplified scrutiny — the "loot-hungry GM" made mechanical.

## Sustainability (not a spreadsheet)
- The claims panel shows **readable signals**, not raw numbers to min-max: *"biggest upgrade," "MVP tonight," "on a drought," "needed next boss."*
- A **loot involvement dial** mirroring the raid-night one: full-manual Loot Council ↔ delegate to an **officer-AI policy** you configure. Point systems (DKP) already run themselves — the low-micro option for players who don't want loot decisions.

## Data model touchpoints
- **Reads:** LOOT_DROP · PLAYER (ego, loyalty_current, tenure) · recent `performance_rating` · GUILD_ENCOUNTER_PROGRESS (progression need) · attendance (availability-true rate from `EVENT_AVAILABILITY`; distinct from *participation* = non-benched lineup rate) · PLAYER_LOOT_STANDING (DKP balance).
- **Writes:** LOOT_CLAIM (decision context snapshot) · LOOT_DROP.awarded_to_player_id · PLAYER_WEEK_STATE (morale deltas) · PLAYER.loyalty_current (drift) · RELATIONSHIP (ding toward recipient) · DRAMA_EVENT · GUILD.fairness_perception · PLAYER_LOOT_STANDING (earn/spend for DKP).
- **New tables (folded into data model v0.3; loot config merged into `GUILD_CONFIG` in v0.8):** PLAYER_LOOT_STANDING · LOOT_CLAIM. Plus `GUILD.fairness_perception` and the `PLAYER.loyalty_baseline` / `loyalty_current` split.

## v1 scope
- **In:** pluggable interface with **Council + DKP + /roll**; the 7-factor claims panel (readable signals); the consequence model (morale + loyalty drift + fairness meter + relationship dings).
- **Layer later:** Soft Reserve + EPGP, deep faction politics, and the officer-AI loot policy (start with manual council + auto point-systems).

---

*v0.1 — loot systems locked; consequence weights symbolic, to be tuned. IP-original naming throughout.*
