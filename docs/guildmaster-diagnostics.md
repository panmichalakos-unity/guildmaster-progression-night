# Guildmaster: Progression Night — The Diagnostic Contract (v1.0)

**Created by MI-005 (2026-07-12).** *Legible failure* is the first pillar, and the original phrasing — **"every wipe names a culprit"** — is half of it. The other half is the half that matters:

> **A dominant check is not a root cause, and a root cause is not a guilty person.**

Failures in this engine are **deliberately coupled**: low awareness → avoidable damage → healing strain → the tank drops → collapse. If the UI points at a name, it teaches the player to **bench their lowest-rated raider instead of fixing the system** — which is the exact opposite of the game we are building. `sim/resolution/diagnosis.gd` is the contract; `tests/diagnostics_test.gd` enforces it.

---

## 1. The hierarchy

The engine answers five questions, in this order, and **never collapses them into one sentence**:

| # | Level | What it is | Names a person? |
|---|---|---|---|
| 1 | **Primary cause** | the gate that failed — `Tank survival`, `Raid collapse`, `Enrage` | ❌ never |
| 2 | **Contributing factors** | the coupled conditions that made it fatal | ❌ never |
| 3 | **Key moment** | a specific event, **only** when directly attributable | ⚠️ *sometimes* |
| 4 | **Recommendation** | the lever the player should actually pull | ❌ |
| 5 | **Recurrence** | *"Tank survival ended 8 of your 8 wipes here — the same wall, not bad luck."* | ❌ |

**Language rules.** "Primary cause", never "culprit". "Contributing factor", never "fault". "Key moment" for a named mistake or a named save. `wipe_reason` survives as **internal shorthand** — the precise numeric string (`margin -18.6, p=0.07`) for logs, tests and the balance lab. **It is never shown to the player.**

### What it reads like

```text
Gatewarden Krogg — OPEN (8 attempts)
    Primary cause: Tank survival
    The main tank was not crit-immune, so the boss's damage was never survivable.
      · healing lane fell 7.1 short — deaths came faster than heals
      · Shadowwhisper is not crit-immune — one spike can end a pull
    → Field a crit-immune main tank. Check the bench: a properly capped tank is
      the right call even when their gear score is lower.
    Tank survival ended 8 of your 8 wipes here — the same wall, not bad luck.
```

Note what is **absent**: a culprit. The tank is *named* — as a **condition**, not a defendant.

---

## 2. 🔒 The anti-scapegoat rule

> ### A raider may be named — or rated down — **only for a failure they authored.**

"Authored" means they were **rolled against something they control**:

| Outcome | Authored? | Key moment? | Rating |
|---|---|---|---|
| `duty_fail` — dropped a duty they were assigned | ✅ yes | ✅ nameable | **−2.0** |
| `death` — an *avoidable* death; they stood in it (Awareness roll) | ✅ yes | ✅ nameable | **−2.0** |
| `cascade_death` — the raid ran dry and it caught them | ❌ **no** | ❌ never | **0.0** |
| `tank_overwhelmed` — out-damaged, usually for want of the crit cap | ❌ **no** | ❌ never | **0.0** |

**A wipe with no key moment is the common case, and the report must stay comfortable saying so.** No key moment means *systems problem* — and the page says that, instead of reaching for somebody to bench.

### The two bugs this rule caught

Both were live, both were the same shape, and neither was cosmetic:

1. **`tank_overwhelmed` did not exist.** The stage-3 tank check is a *lane* check — it fails with **no death event anywhere in the timeline**. So a `tank_survival` wipe left the tank standing, `participants[].died` was false for everybody, and the post-night report cheerfully showed **"0 deaths" on a wipe whose stated cause was the tank dying.** A report that contradicts its own verdict is the opposite of legible failure. *(Surfaced by MI-004.)*

2. **A cascade death was billed as an avoidable one.** The resolution doc has always called `cascade_death` *"death, **not own fault**"* — but the engine emitted it as a plain `death`. So the raider the healing shortfall happened to catch was **docked the same −2.0 as somebody who stood in the fire**, and the report could name him as the "key moment". The victim of a systemic failure was being handed the blame for it.

**Both now fall in the log — and neither costs the raider anything.** They die; they do not take the blame.

> **Why this is a rating rule and not a copy rule:** the player does not read the design doc, they read the **ratings table**. If the tank who dies in every wipe sits at the bottom of it, the game has told them to bench him — whatever the prose above it says. Measured before the fix, an out-damaged tank floored at **1.0/10**. After: **5.3/10**, mid-table, exactly as he deserves.

---

## 3. Recurrence — and the bug that hid it

`top_wipe_reasons` tallied the raw `wipe_reason` string. That string embeds margins and probabilities, so **every wipe hashed unique**, every count came out as `1`, and the one sentence that tells a player *"you are not unlucky, you are stuck"* **could never appear.**

Wipes now group on the **primary cause**. Recurrence surfaces per boss once a cause has ended two or more wipes there.

---

## 4. What the player must be able to do

After a wipe, without reading a manual:

1. Understand **the immediate event** that ended the pull — the log's decisive closing beat (MI-004).
2. Understand **the systemic condition** that made it fatal — the contributing factors.
3. Know **what to change** — the recommendation.
4. Know whether **this is the same wall as last time** — recurrence.
5. **Not conclude that a person is the problem** — unless a person genuinely is, and then only for what they actually did.

---

## 5. Verification

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/diagnostics_test.gd
```

Covers the full hierarchy on a wipe; no diagnosis on a kill; the primary cause is always one of the three gates (MI-002); **only authored failures can name a person**; being out-damaged and being caught by a cascade both cost **exactly 0.0** rating while standing in the fire and dropping a duty still cost −2.0; a `tank_survival` wipe actually puts the tank on the floor; the out-damaged tank is **not** the worst-rated raider in the guild; and wipes group by cause so recurrence can surface.

**Balance is untouched.** The tank falls *after* the verdict, so the checks and the collapse fraction that decided the pull never see him — the harness reports the same win rates to the point (40 / 21 / 11 / 5 % at starting gear). This closes an incoherence; it does not open a new failure path.
