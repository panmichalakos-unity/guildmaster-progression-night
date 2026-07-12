# Guildmaster: Progression Night — The Performance-Rating Contract (v1.0)

**Created by MI-006 (2026-07-12). Locked BEFORE ratings become evidence in M6's Loot Council.**

The 1–10 rating is a linchpin: it feeds the post-night report, morale, form, **Loot Council signals**, MVP and every fairness narrative in the game. It was implemented; it was never *specified*. If a player cannot explain why somebody got a 4 or a 9, loot decisions feel arbitrary, MVP degenerates into a proxy for gear, and the flagship Council system is undermined before it ships.

---

## 1. 🔒 The governing principle

> ### A rating measures how well a raider fulfilled **their role and their assignments**, relative to **the kit, gear and situation available to them.**
> ### It is **not** raw output.

A 6.2 — never "43k".

**Why this matters more than it looks.** If a rating just re-reported raw damage, it would just re-report **gear score** — and loot awarded on that evidence would become a **feedback loop that eats itself**: the best-geared raider "earns" the loot that keeps him best-geared, forever. The rating exists precisely to break that loop. It asks *"what did you do with what you were given?"*

---

## 2. The formula

```
expected = ceiling × reference_realization      # what a plain 50-skill raider does with THIS kit
ratio    = actual contribution / expected       # ...vs THEIR OWN ceiling
rating   = clamp(round(5.5 + (ratio − 1) × spread + event deltas), 1, 10)
```

`ceiling` is derived from the raider's **own gear**. That single choice is what makes the number fair **across roles and across gear levels** without any special-casing: a tank, a healer and a ranged DPS are each measured against *their own* expectation, so they are directly comparable on the only axis that matters — **did you beat what you should have done?**

### Event deltas — the night's story moves the number

| Outcome | Δ | Why |
|---|---|---|
| avoidable death | **−2.0** | you stood in it |
| dropped an assigned job | **−2.0** | you were given it, and you dropped it |
| critical-strike death while tanking | −2.0 | the swap you missed |
| clutch save | **+1.5** | you took a death off the board |
| handled an assigned job cleanly | +0.5 | |
| nailed the cooldown window | +0.5 | |
| survived a near-death moment | +0.5 | |
| **out-damaged as tank** (`tank_overwhelmed`) | **0.0** | **not his doing — the guildmaster fielded him uncapped** |
| **fell when the healing ran dry** (`cascade_death`) | **0.0** | **not their doing — the raid ran out of healing** |

The two zeroes are the **anti-scapegoat rule** (ADR-0028), and they are load-bearing: the player does not read the design doc, they read the **ratings table.** A tank at the bottom of it *is* the game telling them to bench him.

---

## 3. The three questions the ticket demanded answers to

### ❓ Can a duty failure be double-counted through event + death + rating?

> ## **No.** A failure is charged **exactly once**, to whoever **authored** it.

Two mechanisms had to be checked, and both are clean:

1. **The assignee** takes the `duty_fail` delta (−2.0) and nothing else. The raider their miss *kills* takes **no rating hit at all** — the timeline kills the victim but **targets the event at the assignee** (`Timeline._resolve_duty`).
2. **A dead raider keeps their own `contribution`.** Death removes them from the **lane sums**, never from their **own ratio**. Otherwise dying would be charged twice — once as the −2 event delta, and again as a silently collapsed output score.

Both are enforced by `tests/rating_contract_test.gd` (`test_a_failure_is_charged_exactly_once_and_only_to_its_author`, `test_death_costs_the_event_delta_and_nothing_more`), which assert the delta is **exactly 2**, not "roughly bad".

### ❓ Can an undergeared player earn a 9 by overperforming?

> ## **Yes — by design.** That is the entire point.

A raider in rags playing out of their skin **outranks a decked-out raider coasting** at 80% of what their gear should produce. Verified: `test_an_undergeared_raider_can_outrank_a_geared_one`.

### ❓ Can a highly geared player rate poorly despite high raw output?

> ## **Yes.**

`test_raw_output_does_not_buy_a_good_rating` asserts both halves at once: the geared raider's **`raw_contribution` is genuinely the higher of the two** — he really is doing more damage — **and his rating is the lower**, because he is not using what he was given.

---

## 4. The five validation scenarios (the contract, as tests)

| # | Scenario | Contract | Actual |
|---|---|---|---|
| 1 | Highly geared tank meets expectations | ~6 | **6** — big gear is not an achievement; *using* it is |
| 2 | **Undergeared** healer lands two clutch saves | 8–9 | **9** |
| 3 | Highly geared DPS dies early to avoidable damage | 2–4 | **2** — raw output cannot buy you out of standing in the fire |
| 4 | Mid-geared DPS performs strongly + lands a critical interrupt | 8–9 | **9** |
| 5 | Low-output raider completes a uniquely hard assignment | assignment must be **visible** | **4**, and the breakdown says *"handled their assigned job cleanly"* — the job is not buried under the output score |

---

## 5. Grain — pull, night, season

| Grain | What it is | Where |
|---|---|---|
| **Pull** | the atom. One rating per raider per pull, with its own breakdown. | `PULL_PARTICIPANT.performance_rating` |
| **Night** | the **mean** across the raider's pulls, plus a tallied "why". | `NightReport.ratings[].avg_rating` / `.why` |
| **Season** | rolling form and reputation. | **M9** — out of scope here |

The night-level "why" **deliberately omits the output judgement**: a per-pull verdict does not sum, and *"about what their gear should produce, eight times"* tells a guildmaster nothing. What survives to night grain is what they **did** — saves, jobs handled, jobs dropped, deaths, and the deaths that **weren't their fault**.

---

## 6. Every rating is explicable

> **A number nobody can argue with is not evidence — it is a vibe.**

Every rating carries `rating_factors` (structured) and `rating_summary` (one line), in the player's language (MI-008: plain words, no naked jargon):

> **Shadowwhisper · tank · 7.0 (1 death)**
> *Strong output for the gear they have; **was out-damaged, not out-played — no fault of his**.*

That second clause is why the breakdown exists at all. Without it, the guildmaster reads a **corpse** next to a **number** and reaches the obvious, wrong conclusion. The report must be able to say **"this death was not their fault"** out loud — and now it does.

---

## 7. Verification

```bash
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/rating_contract_test.gd
```

Eleven tests: the five scenarios, the three questions, the no-double-counting proofs, and the breakdown itself.

**Note:** locking this contract required **no change to the rating maths.** The engine was already correct — what it lacked was a *specification* and an *explanation*. Both now exist, and the tests will hold the next person to them.
