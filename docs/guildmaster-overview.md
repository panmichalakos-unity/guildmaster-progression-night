# Guildmaster: Progression Night — Design Overview & Index

The front door to the design doc set: what each doc holds, how the systems interconnect, and the consolidated v1 scope. **Start here.**

## What it is
A Football Manager–style guild-management sim set in a fictional, old-school (Vanilla/TBC-era) fantasy MMO. You run a raiding guild — recruit, gear, train, and hold a ~28-member roster (fixed 20-raider nights) together through slow progression, loot drama, and burnout. PC / Steam, Early Access path. Systems- and text-driven → small-team feasible.

## Doc map
| Doc | Covers |
|---|---|
| **pitch** | One-page pitch: fantasy, core loop, pillars, market. |
| **data-model** | Full ERD (three subject areas), entity reference, lakehouse mapping. |
| **campaign-and-objectives** | Turn loop, calendar, season/expansion structure, save model, objectives (the success system). |
| **resolution** | Raid-night engine: pipeline, checks, difficulty, learning arc, events. |
| **raid-prep** | Lineup, comp check, assignments, undermanned/undergeared planning decisions. |
| **gear** | Per-slot equipped gear, gear_score, readiness caps, spec-fit, Marks catch-up. |
| **loot** | Loot & fairness: pluggable policies, the Council claim model, consequences. |
| **between-nights** | Weekly loop: 5 lanes, action resolver, and the guild economy. |
| **recruitment** | Scouting & recruitment: Avatar-visible / Player-hidden, channels, the fog overlay. |
| **conventions** | Modeling patterns (the baseline/current split + convention index). |
| **backlog** | The v1 build plan: phased milestones, DoD grid, critical path. |
| **content-and-dod** | v1 content volume targets + the two Definition-of-Done gates. |
| **naming-bible** | IP-safety rules, slug conventions, the full v1 name set + name generators. |
| **stack-and-tooling** | Engine (Godot 4), data/testing/CI toolchain, art pipeline policy, release path, setup playbook. |
| **v1-readiness-review** | Gap & loophole register (P0–P3) driving kanban setup. |
| **overview** | This doc. |

## Systems at a glance
- **Raider Model** — two layers. The **Player** (the human: skill, psychology, real-life constraints) persists; the **Avatar** (their character: class, gear, familiarity) is swappable. Personality is hybrid — traits drive the math, authored quirks add special behavior, the archetype label is *derived*.
- **World & Time** — a nested clock: Pull → Raid Night → Week → Season → Expansion → Career. The yearly **expansion** resets gear and the meta — replayability without live-service cost.
- **Raid Night (Resolution)** — a stat-driven probability engine presented as a live combat log. Checks (DPS / heal / tank / mechanic) resolve via `margin → sigmoid`; a per-guild learning arc drives the "8%… 3%… KILL." Every wipe names a check *and* a culprit.
- **Loot & Fairness** — the drama engine. Fairness is per-culture; the loot system you pick sets the yardstick you're judged by. Awards ripple into morale, loyalty, chemistry, and the fairness meter.
- **Between-Nights & Economy** — a weekly time budget across 5 lanes (Gearing / Development / Supply / People / Rest), gated by raider time. The economy funds "the guild provides" via **donations that scale with guild health** — good leadership funds the raid.
- **Social & Drama** — a living graph of morale, drifting loyalty, and pairwise chemistry. Feeds retention, donations, and drama events.
- **Fall & Rebuild** — sustained failure drains officer/member confidence → you're ousted → rebuild from scratch (the Player carries forward). Optional toggle.

## How it all connects
```mermaid
flowchart TD
    RAIDER["Raider Model<br/>(Player + Avatar)"]
    BN["Between-Nights<br/>weekly time budget"]
    RN["Raid Night<br/>resolution engine"]
    LOOT["Loot & Fairness"]
    SOCIAL["Social State<br/>morale · loyalty · chemistry"]
    ECON["Guild Economy<br/>treasury"]
    SACK["Sacking Meter"]
    FALL["Fall & Rebuild"]
    EXP["Expansion Cycle"]

    RAIDER --> BN
    BN -->|"gear · skill · supply · cohesion"| RN
    RN -->|"performance · loot drops"| LOOT
    RN -->|"morale/fatigue · progress"| SOCIAL
    LOOT -->|"awards & snubs"| SOCIAL
    SOCIAL -->|"guild_health"| ECON
    ECON -->|"provision · repairs"| SOCIAL
    ECON -->|"funds consumables"| BN
    RN -->|"repairs · proceeds"| ECON
    SOCIAL -->|"confidence · fairness"| SACK
    SACK --> FALL
    FALL -.->|"Player carries forward"| RAIDER
    EXP -->|"meta reset"| RAIDER
    EXP -->|"re-gear"| BN
```

The through-line: **your social management funds and enables your raid capability, and your raid results feed back into your social standing.** No system is an island.

## v1 scope, consolidated
| System | v1 core | Deferred to v1.1+ |
|---|---|---|
| **Raider** | Player+Avatar, 3 skill facets, role proficiency + familiarity, life presets | quirks, chemistry graph, resistance sets, Player-Guildmaster |
| **World / Time** | Season → Week → Raid Night; single expansion | multi-expansion, attunements |
| **Resolution** | contribution → checks → margin/sigmoid, core-5 events, learning arc, rating | resistance & assigned-duty checks, quirk events, full palette, manual jump-in directives |
| **Loot** | Council + DKP + /roll, 7-factor panel, consequence model | Soft-Reserve / EPGP, officer-AI loot policy, faction politics |
| **Between-Nights / Economy** | 5 lanes; treasury (gold/mats/consumables); donation income; 3 policies | professions/crafting, crafting sales, recruitment incentives, knowledge library, collective events |
| **Social / Drama** | morale, loyalty drift, fairness meter | full chemistry graph, DRAMA_EVENT catalogue |
| **Fall / Rebuild** | rebuild loop (toggle) | deeper politics |

## Design pillars (non-negotiables)
- **Legible failure** — nothing is opaque; every outcome names its cause.
- **Fairness is per-culture** — the system you adopt sets the yardstick.
- **Play it your way** — the involvement slider (manual ↔ auto) on both raid night and loot.
- **Sustainable by design** — Rest is a real move; donations aren't a grind; the game rewards not over-grinding.
- **Content as data** — encounters, events, quirks are seed rows; new content = new rows, engine untouched.
- **The Player persists** — re-roll, alts, and sacking carry the human forward.
- **IP-safe** — replicate systems and feel; invent every proper noun.

## Status
- **Locked & documented:** raider model · world/time · resolution · loot · between-nights/economy · recruitment · **campaign & objectives** · **gear** · **raid prep** · conventions. Data model at **v0.8**.
- **P0 blockers: resolved** (objectives, gear→power, Marks, turn/campaign frame, lineup/assignments, lane outcomes) — see v1-readiness-review.
- **G-register: resolved** — guild genesis, rival ladder (light), attrition, population tick, relationship-lite, bench costs, consumable plan, time slots, campaign horizon, `GAME_CONFIG`/`GUILD_CONFIG`, attendance, consumption.
- **Still pending:** seed data (naming bible ✅ done — unblocked) · screen map (optional one-pager) · Phase-A ticket decomposition · quirks/drama content → v1.1.
- **Final build-readiness audit (pass 3): GO** — backlog restructured (Phase B = M5–M9, Phase C = M10–M11); every DoD item has an owning milestone.
- **Stack locked:** Godot 4 + GDScript + SQLite · Python/DuckDB balance lab · GitHub (repo/Actions/Projects) · dev-time AI art with curated portrait pool.

---

*Index doc — keep in sync as systems evolve.*
