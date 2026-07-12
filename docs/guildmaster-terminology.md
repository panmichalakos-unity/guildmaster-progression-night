# Guildmaster: Progression Night — Terminology & Accessibility Contract (v1.0)

**Created by MI-008 (2026-07-12).** The UI spoke fluent MMO. Efficient for a veteran; opaque for the management-sim half of the audience — the half this game is trying to *reach*. `sim/core/glossary.gd` + `data/seeds/glossary.json` are the implementation; `tests/terminology_test.gd` enforces it mechanically, because a copy pass rots the moment somebody adds the next warning.

---

## 0. Why this is not a cosmetic ticket

The single string the **entire first session** hangs on used to read:

> ⚠️ *"Main tank Shadowwhisper is not uncrittable — spike-death risk"*

Two terms a non-raider cannot parse. **No consequence. No action.** MI-003 built the whole opening around the player reading that sentence, understanding it, and benching their best-geared tank because of it. If it doesn't land, the diagnose → fix → succeed arc collapses — *for exactly the player this game is supposed to win over.*

It now reads:

> ⚠️ **"Your main tank Shadowwhisper can be hit by a critical strike — one unlucky spike will kill him outright and end the pull, and no amount of healing prevents it. Field a tank who cannot be critically hit, even if their gear score is lower (uncrittable)."**

Same fact. Same term, still there. But now a person who has never raided knows **what will happen** and **what to do about it** — including the counter-intuitive part, said out loud: *field the tank who looks worse on paper.*

---

## 1. 🔒 The rule

> ### Plain-language **consequence** first. The **action** always. The MMO **term** last, in parentheses.

1. **Consequence** — what will actually happen to you, in words anybody understands.
2. **Action** — what to *do*. A warning that doesn't tell you what to change is an observation, not a warning.
3. **Term** — kept, never removed, but **never load-bearing.** A player who ignores every parenthesis must still be able to act.

**Terms stay because the authenticity is the point.** This is a game about old-school raid guilds; stripping the vocabulary would be stripping the fantasy. The goal is not to remove jargon — it is to make jargon **optional**.

### Progressive disclosure

| Layer | Who it's for | Required? |
|---|---|---|
| The warning text | everyone | ✅ always sufficient to act |
| The parenthesised term | veterans, pattern-matching fast | never required |
| The tooltip (`Glossary.detail`) | the curious | never required |
| The glossary screen | the student | never required |

---

## 2. Before / after

| Before | After |
|---|---|
| *"Main tank is not uncrittable — spike-death risk"* | *"Your main tank **X** can be hit by a critical strike — one unlucky spike will kill him outright and end the pull, and no amount of healing prevents it. **Field a tank who cannot be critically hit, even if their gear score is lower** (uncrittable)."* |
| *"No battle-rez tonight (Rekindle) — a death is a lost body"* | *"**Nobody can revive a fallen raider mid-fight** — every death is permanent for the rest of the pull, and each lost body costs the raid damage and healing. **Field a Rekindle caster** (battle-rez)."* |
| *"No interrupt (Countercast) — enemy casts go unchecked"* | *"**Nobody can cut off the boss's spellcasting** — its worst spells will land on the raid unchecked. **Field a Countercast caster** (interrupt)."* |
| *"No haste burst (Stormsurge) — bring a Channeler"* | *"**Nobody can push the raid's damage for a burst window** — you lose your best shot at beating the boss's time limit. **Field a Channeler** (Stormsurge, a haste burst)."* |
| *"Only 3 healers (5 recommended)"* | *"**Only 3 healers — they cannot keep up with the damage this fight puts out**, and raiders will start dying with nothing coming. **Field at least 5.**"* |
| *"Only 10 DPS (12 recommended)"* | *"**Only 10 raiders are dealing damage** — the boss will outlast you and its damage will become unsurvivable before it dies. **Field at least 12** (damage dealers, or DPS)."* |
| *"12 melee into a melee-punishing night — consider more ranged"* | *"**12 of your raiders fight from close range, and tonight's boss aims its worst attacks exactly there** — they will be caught by mechanics they cannot avoid. **Swap some for raiders who fight at a distance** (melee vs ranged)."* |
| *"Comp looks solid — lineup is raid-ready"* | *"Lineup looks raid-ready — roles, utilities and range are all covered."* |

**The same rule applies after the pull, not just before it.** It would be incoherent to make raid prep readable and leave the wipe report in engine-speak, so the diagnosis (ADR-0028) speaks the same language: *"your healers could not keep up with the damage"* rather than *"healing lane fell 5.6 short"*, and *"the boss outlasted you: its damage became unsurvivable while it still had health left"* rather than *"enrage"*.

---

## 3. How it is enforced

`tests/terminology_test.gd` makes the rule **mechanical**, not aspirational:

| Test | What it forbids |
|---|---|
| **every warning tells the player what to do** | a warning with no action verb — *an observation, not a warning* |
| **no warning leads with jargon** | any term from the jargon list appearing **before** a `(` — i.e. naked, unexplained |
| **every term a warning tags is in the glossary** | the UI saying a word nobody has defined |
| **every glossary entry is complete** | a term whose `plain` phrase is *itself* the jargon |
| **the tank warning is readable by someone who has never raided** | the load-bearing sentence losing its consequence, its fix, or the *"even if their gear score is lower"* clause |

> The **old** tank warning fails two of these outright. That is the point: the tests would have caught it.

---

## 4. The glossary

`data/seeds/glossary.json` — content as data, same pattern as `tuning.json`. Every term carries:

- `term` — how it's displayed (*"Uncrittable"*)
- `plain` — the phrase that stands in for it in body copy (*"cannot be critically hit"*)
- `detail` — the tooltip / glossary-screen explanation

Current entries: **uncrittable · battle-rez · interrupt · haste burst · enrage · DPS · melee · ranged · soak · dispel · wipe · pull · comp · gear score.**

Adding a term the UI will say **without adding it here is a test failure**, not an oversight.

---

## 5. What this does *not* claim

The Fun Gate (ADR-0029) was passed by **an expert MMO player**, so the scorecard line *"can a non-MMO player act on the warnings alone?"* has still **never been tested on an actual non-MMO player.** This ticket makes that outcome *plausible*; it does not make it *proven*. The only thing that proves it is putting the first session in front of somebody who has never raided and watching whether they bench the tank.

**That is the remaining open line on the Gate 1 scorecard.**
