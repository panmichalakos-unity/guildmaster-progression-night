# Guildmaster: Progression Night — Naming Bible (v0.1)

The pre-seed-data prerequisite: naming rules + the first-pass name set for everything v1 needs. All names are working names — review freely; slugs make renames cheap.

## Rules

**IP-safety (hard rules)**
- Replicate *systems and feel*; invent every proper noun. Generic fantasy vocabulary (fire resistance, flask, tank, raid) is fine; distinctive proper nouns from other games are not.
- **Banned outright:** any Blizzard proper noun — class roster as a set, spec names, ability names (Bloodlust, Heroism, Divine Shield, Sunder Armor…), item/boss/zone names, "Heroic/Mythic" as difficulty labels, "Covenant/Legion"-style expansion words. Same rule for other MMOs' distinctive names (spec names from FF14/GW2, D2 classes, etc.).
- **Pre-launch task (not a seed blocker):** run a trademark screen on the top-level names (game title, MMO name, expansion name) before any public material.

**Style guide**
- Classes & specs: **one word**, readable, no apostrophes.
- Bosses: `Name, the Epithet` or `Role Name` (*Forgemaster Vell*).
- Abilities/utilities: compound words (*Stormsurge*), not phrases.
- Raids/zones: `The [Theme][Place]` (*The Emberdeep*).

**ID convention (seed data)**
- Every named entity: `slug` (snake_case, **immutable**, natural key for seed FKs) + `display_name` (freely renameable). Example: `spec_thornclaw` → "Thornclaw". dbt-seed friendly: taste changes never break joins.

---

## The world
| Thing | Name | Note |
|---|---|---|
| The fictional MMO | **Aethermoor** | the game-within-the-game |
| v1 expansion (base) | **Aethermoor: Crownfall** | 2 tiers, 14-week seasons |
| Marks currency | **Expedition Marks** | display "Marks" in UI is fine |
| Currencies | Gold · Materials | keep generic |

## Classes & specs (6 × 3, per the locked role matrix)
| Class | Identity | Tank | Healer | Melee | Ranged |
|---|---|---|---|---|---|
| **Vanguard** (C1, heavy plate — banners & shouts) | physical warband anchor | Bulwark | — | Ravager, Warblade | — |
| **Templar** (C2, oath & aegis) | shielded zealotry | Bastion | Absolver | — | Judicator |
| **Warden** (C3, wildshaper) | nature's guardian | Oakhide | Grovekeeper | Thornclaw | — |
| **Oracle** (C4, duality of mind) | radiant/umbral caster-priest | — | Mender | — | Radiant, Umbral |
| **Channeler** (C5, elements) | tides, storms, ash | — | Tidemender | Stormfist | Ashcaller |
| **Reaver** (C6, blade & hex — pure DPS) | mercenary killer | — | — | Cutthroat | Deadeye, Hexweaver |

Coverage check: 3 tanks (Bulwark/Bastion/Oakhide) · 4 healers (Absolver/Grovekeeper/Mender/Tidemender) · 5 melee · 6 ranged = **18** ✓. Continuity: Warden/Reaver/Mender/Channeler carried over from the pitch.

## Raid utilities (8) — the comp puzzle
| Utility (function) | Name | Provided by |
|---|---|---|
| Combat revival | **Rekindle** | Grovekeeper, Mender |
| Raid haste burst | **Stormsurge** | any Channeler *(scarce on purpose — "bring a Channeler")* |
| Interrupt | **Countercast** | Bulwark, Ravager, Cutthroat, Stormfist |
| Magic dispel | **Unweave** | Absolver, Tidemender, Mender |
| Immunity / external save | **Aegis** | Bastion, Absolver |
| Raid stat buff | **Warbanner** | any Vanguard |
| Armor debuff | **Breach** | Ravager, Cutthroat |
| Mana regen | **Wellspring** | Ashcaller, Radiant |

Synergy tags stay **functional labels** (comp vocabulary, not lore): Caster Cleave, Melee Cleave, Mana Battery, Threat Support, Magic Amplify.

## Consumables (10)
| Tier | Name | Lane |
|---|---|---|
| Premium (flasks, whole night) | **Emberflask** / **Stoneflask** / **Dawnflask** | DPS / tank EHP / healing |
| Basic (elixirs) | **Elixir of Keen Edges** / **Ironbark Elixir** / **Clearwater Elixir** | DPS / defense / mana |
| Combat potions | **Bottled Fury** / **Bottled Stone** | burst DPS / emergency defense |
| Food & kit | **Hearthstew** / **Whetstone Kit** | stats / weapon temp buff |

## Tier 1 raid — **The Emberdeep** (entry, 6 bosses)
Mechanical identities double as seed-data intent (checks + range profile):
1. **Gatewarden Krogg** — the gear gate: tank-survival check intro (uncrittable matters); range-neutral.
2. **Forgemaster Vell** — assigned-duty showcase: interrupt rotation on casts; **ranged-punisher** (storm targets the ranged camp).
3. **The Slagbeast** — healing-sustain wall; **melee-punisher** (frontal cleave).
4. **The Cinderlords** *(council)* — cooldown-window fight + soak duties.
5. **Ashpriestess Morvane** — dispels + Awareness (avoidable mechanics).
6. **Ignarok, the Emberdeep Tyrant** — end boss: enrage/DPS wall, multi-phase, mixed profile.

## Tier 2 raid — **Spire of the Drowned King** (step-up, 6 bosses)
The Hullbreaker · Sirenmatron Yssa · Rotmarshal Deyne · The Depthmaw · The Barnacle Court *(council)* · **The Drowned King** *(end boss)*. Mechanical identities authored at seed time, reusing the T1 palette at higher demands.

## Dungeons (Gearing lane, 3 bands)
Difficulty bands: **Standard → Gilded → Ordeal** *(never "Heroic/Mythic")*.
Instances: **Gloamway Crossing** (Standard) · **The Saltmines of Kher** (Gilded) · **Vault of Whispers** (Ordeal).

## Item naming (templatable — the ~65 items)
Formula: `[Theme word] [Slot noun] (of the [Epithet])?` with per-raid theme pools.
- **T1 theme pool:** Ember, Slag, Cinder, Ash, Molten, Forgeworn. **T2:** Brine, Drowned, Coral, Tide, Barnacled, Pale.
- **Slot nouns:** Helm (Head) · Mantle (Shoulder) · Cuirass/Vestment (Chest) · Grips (Hands) · Legguards (Legs) · Striders (Feet) · Weapon = named uniques.
- Examples: *Cinderforged Helm*, *Slagworn Grips*, *Mantle of the Ashpriestess*; end-boss weapon: ***Coreflame, Edge of Ignarok***.
- **Marks vendor set:** the **Expeditionary** set (*Expeditionary Striders*), one per slot per tier.

## Raider name generator (`PLAYER.handle`)
v1 simplification: **handle = avatar name** (one identity per raider). Three pattern pools, weighted:
1. **Fantasy root+suffix (~55%):** roots *Ash, Bryn, Fen, Kael, Mor, Sable, Thorn, Vex, Grim, Ryn* × suffixes *-en, -ric, -wyn, -dar, -is, -eth, -na, -mir* → *Kaeldar, Brynwyn, Vexis*.
2. **Compound handles (~30%):** *(Shadow|Iron|Swift|Grim|Night|Frost|Storm)* + *(blade|fang|mend|arrow|hide|whisper|born)* → *Ironfang, Nightmend*.
3. **"Human leak" (~15%):** the same outputs with lowercase, doubled letters, or trailing digits — *brynna, Vexxen, Kaeldar77* — because real rosters look like this.
Uniqueness: collision check → digit-suffix fallback.

## Guild name generator (ghost rivals + suggestions)
Patterns: `[The] [Adjective] [Noun]` · `[Noun] of [Place]` · single compound. Pools — adjectives: *Ashen, Gilded, Silent, Sable, Northern, Hollow*; nouns: *Order, Accord, Company, Reprisal, Oath, Remnant, Banner, Tempest* (avoid Legion/Covenant/Horde-alikes).
**v1 ghost-ladder eight:** The Gilded Order *(fast)* · Ashen Accord *(fast)* · Silent Reprisal *(mid)* · Northwatch Company *(mid)* · Emberwake *(mid)* · Salt & Sorrow *(slow)* · The Hollow Banner *(slow)* · Kindred of the Vale *(slow)*.

## Already-named systems (reference, unchanged)
Life presets: single / student / working-parent / shift-worker / veteran / young-gun · Archetype labels: Backbone, Mercenary Ace, Project, Headache, Anchor · Quirk names (v1.1): Mentor, Clutch, Tilt-Prone, Grudge-Holder, Flaky Genius, Glue, Magpie…

---

*v0.1 — first pass; slugs immutable, display names open for review. Trademark screen on top-level names before anything public.*
