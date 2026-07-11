# Guildmaster: Progression Night — Raid-Night Presentation Contract (v1.0)

**Created by MI-004 (2026-07-11).** The pull contract said *"the feed is the show"*, but nothing defined hierarchy or pacing — so a **correct** event list was still emotionally flat. This document is the contract for the show. `game/ui/combat_log_screen.gd` implements it; `tests/presentation_test.gd` enforces the parts that live in the engine.

> **The bar:** the player must be able to feel the fight breathe, spot the moment it turned, and — on a wipe — know instantly whether they were **closer than last time.**

---

## 0. What this ticket actually found

The feed was flat, and it was *not* only a styling problem. Rendering a real first-session wipe exposed something worse:

```text
[routine]  Sabledar handles it clean.
[notable]  brynwyn survives on a sliver of health.
[routine]  stormblade10 takes the swap right at the threshold.
[routine]  stormblade10 takes the swap right at the threshold.
           raiders up: 20/20
WIPE — tank_survival: ... Shadowwhisper is NOT uncrittable ...
```

**The wipe is a tank failure, and the tank never appears in the log.** Nobody dies — 20/20 still standing. The verdict was computed *after* the timeline (`Timeline._verdict`) and **never written into the log at all**, so the player watched four forgettable lines and then a verdict materialised from nowhere. No amount of colour fixes that: **the decisive moment was not in the show.**

Fixed in the engine, not the renderer — see §3.

---

## 1. What stays visible while the pull runs

A persistent strip, above the feed. Every field is a fact the engine actually produces:

| Field | Source | Live? |
|---|---|---|
| Boss `n/4` · name · attempt | `NightRunner` | — |
| **Phase** `n — <name>` | `event.phase_order` + the runner's `phases[]` | ✅ updates as the fight moves |
| **Raiders up** `18/20` | death events, counted as they fire | ✅ |
| **Furthest yet** `boss to 41%` | `boss_hp_pct_at_end`, best over attempts | — |

### 🔒 There is deliberately **no live boss-health bar**

The engine **does not model boss HP over time.** It derives final progress from the DPS-check margin at the end of the pull. A bar draining smoothly through the fight would be the feed **inventing a number the simulation never computed** — a lie about the sim, and exactly the class of thing this project's intervention exists to stop. Boss health is therefore reported where it is real: **as the outcome** ("boss to 23%").

*If we want a live bar later, the engine must model HP per phase first.* That is a real ticket, not a UI tweak.

---

## 2. Notability — the hierarchy

Four tiers, **derived from the event's outcome, never stored** (a stored tier can drift from the fact it describes; a derived one cannot). Single source of truth: `PullContracts.notability_for()`. Every surface that shows events — the combat log, the MI-005 why-view, a future replay — calls it, so they cannot disagree about what mattered.

| Tier | Outcomes | Reads as | Style |
|---|---|---|---|
| **decisive** | `tank_death`, `boss_down`, `wipe_call` | *the pull turned here* | large, bold, `▶`, red — or **gold** for a kill |
| **critical** | `death`, `duty_fail`, `save` | real consequence | bold, ember, `•` |
| **notable** | `survived`, `surge` | the fight breathing | normal weight, full-brightness text |
| **routine** | `duty_ok`, `noop`, `steadied`, *anything unrecognised* | texture | dimmed, recedes |

**Unknown outcomes fall to `routine` on purpose.** A new event type is texture until somebody decides otherwise — it fails quiet rather than screaming a false alarm at the player.

---

## 3. The fight says how it ended

**Every pull now closes with its own `decisive` beat** (`Timeline._emit_closing_beat`), because the log is the show and a show needs an ending:

| Ending | The beat |
|---|---|
| kill | *"Gatewarden Krogg falls. **KILL**."* — gold |
| tank | *"Shadowwhisper cannot hold it — the boss breaks through the raid. **WIPE**."* |
| collapse | *"7 raiders down — there is nobody left to hold it together. **WIPE**."* |
| enrage | *"Gatewarden Krogg enrages with the raid still swinging. **WIPE**."* |

`wipe_reason` stays what it is — a **precise diagnostic string**, far too long to be a beat. It belongs on the card, not in the feed.

> ⚠️ **The closing beat must never claim a corpse the log does not contain.** A failed tank *check* is not necessarily a logged death event, which is why the tank line reads "cannot hold it", not "is cut down". See the open issue in §7.

---

## 4. Phases are beats, not more log lines

A phase change gets a ruled ember banner titled with the phase's **real name** (`──── PHASE 2 · THE MOLTEN HEART ────`), spliced into the queue wherever `phase_order` advances. `NightRunner.resolve_pull` hands the screen the `phases[]` rows for this — events carry only `phase_order`, and a bare "PHASE 2" is not a beat anybody feels.

---

## 5. The card — and the "one more pull" line

The pull ends on a card that answers the only question the player actually has.

**On a kill** — gold, and gold is reserved for *nothing else in the game*:
> ★ **KILL — Gatewarden Krogg falls on attempt 5**
> Down in 4:53 with 20/20 raiders standing. Loot drops — open the report.

**On a wipe** — name the cause, name what made it fatal, and then the line that keeps a raider pulling:
> **WIPE — tank_survival**
> **Boss to 60%** · **CLOSEST YET** (previous best 41%) · 3:12
> · healing lane fell 7.8 short — deaths came faster than heals
> · Shadowwhisper is not crit-immune — one spike can end a pull

| Comparison | Shown when |
|---|---|
| *"first attempt — that is your benchmark"* | no prior attempt |
| **"CLOSEST YET"** (gold) + previous best | this attempt got further than any before |
| *"matched your best"* | tie |
| *"your best is still 41%"* | worse |

A wipe that got further than any before it is **not a failure the player wants to walk away from — it is the reason they stay.** The contributing factors come straight from `pull.contributing_factors` (MI-002), and are the seed of MI-005's *primary cause ≠ culprit* view.

---

## 6. Pacing

| Control | Behaviour |
|---|---|
| **Pacing: Live / Instant** | Live reveals one beat every 0.45s; Instant dumps the pull and jumps to the card |
| **Speed 1x / 2x / 4x** | scales the reveal interval |
| **Skip to result** | drains the remaining beats immediately, then shows the card |
| **Pull / Skip to next boss / End night** | disabled while a reveal is running, so the feed cannot interleave |

Default is **Live at 1x** — a first-time player should watch their first pull. A veteran farming a known boss will reach for Instant, and that is fine.

---

## 7. Open issue this ticket surfaced (not fixed here)

**A `tank_survival` wipe marks nobody as dead.** The tank check fails as a *check*; no death event fires, so `participants[].died` is `false` for everyone and the post-night report will happily show **0 deaths on a wipe caused by the tank dying.** The combat log now papers over this honestly (the closing beat says "cannot hold it", and the raid counter drops to 0 on the wipe, because a wipe *is* a wipe) — but the underlying incoherence is real and belongs to the diagnostics work.

**Owner: MI-005** (diagnostic hierarchy). Either the tank-gate failure must emit a real `tank_death` event, or the report must stop implying deaths it does not have.

---

## 8. Verification

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/presentation_test.gd
```

Covers: the four tiers; that the pull-turning outcomes are `decisive`; that consequence is `critical` and texture recedes; that **every** pull closes with its own decisive beat; that a kill's beat names the boss; and that the runner hands the screen named phases.

Styling itself is not testable headless — **MI-010 (the human Fun Gate) is the real judge**, and this contract exists so that judgement is about the *game* rather than about a wall of grey text.
