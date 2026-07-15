# Guildmaster: Progression Night — The Involvement Contract (Manual / Assisted / Instant, v1.0)

**Created by MI-007 (2026-07-12). CONTRACT ONLY — no implementation here.** Implementation is `M9-005` (raid-night + loot wiring) and the Phase-B screens themselves (M5–M9). This document exists so those screens are designed **once**, with automation hooks from the first version, instead of being built for full manual control and retrofitted at M9.

> Design method: three independent contracts were drafted from distinct lenses (FM-authentic delegation · minimal-honest-v1 · teaching-and-trust) and triangulated. All three converged on the same spine unprompted; where they diverged — chiefly *how Night One survives a player who delegates everything* — this contract takes the most robust position and records why.

---

## 0. Why this is a pillar, not a setting

Manual↔auto flexibility is a **non-negotiable design pillar** and a **core audience strategy**: MMO veterans want to run every pull by hand; management-sim players want to delegate and still feel like the boss. If the earlier Phase-B screens assume full manual operation and automation only shows up at M9, every one of them needs rework. So the contract lands **now**, before the screens multiply.

---

## 1. 🔒 The one principle

> ### Involvement changes **who authors the inputs** — never how the sim resolves them, and never what information exists.

Everything else follows from this. Three invariants make it enforceable:

1. **Determinism is untouched.** Same seed + same inputs = same outcome (the seeded-determinism pillar). Delegation decides *who fills in the lineup / assignments / loot award*; the resolver then runs on those inputs bit-for-bit identically in every mode. Automation is never a second, hidden RNG.
2. **One brain, one set of tools.** In v1 the "officer" who acts for you uses **exactly the heuristics already printed on your screen** — `PullInputLoader.auto_lineup()`, `RaidPrep.build()`'s default assignments, the active loot policy's own math. There is **no smarter optimizer** hiding behind Instant. (See §5 — this is load-bearing for the teaching.)
3. **Delegation never hides information.** Every decision the game makes for you is written to the same fact rows a manual decision would write, tagged as auto-authored, and **surfaced** — in the post-night report and the weekly digest. Automation moves *where* a decision is shown (blocking screen → handoff card → report), never *whether it exists*.

---

## 2. Storage (the shape M5-001 must migrate)

Involvement is a **player preference on the save root**, not guild culture — it survives sacking and rebuild — so it lives in `GAME_CONFIG` (one row on `GAME_STATE`), **not** `GUILD_CONFIG`.

```
GAME_CONFIG
  involvement_default   TEXT NOT NULL   -- already planned in the data model; the genesis preset
                        CHECK (involvement_default IN ('manual','assisted','instant'))
  -- MI-007: six per-domain overrides, each initialised from the preset, editable anytime
  involvement_lineup        TEXT NOT NULL CHECK (x IN ('manual','assisted','instant'))
  involvement_assignments   TEXT NOT NULL CHECK (...)
  involvement_pulls         TEXT NOT NULL CHECK (...)
  involvement_loot          TEXT NOT NULL CHECK (...)
  involvement_weekly        TEXT NOT NULL CHECK (...)
  involvement_recruitment   TEXT NOT NULL CHECK (...)
```

- **Presets are UI sugar.** Genesis offers three: **Full Control** (all `manual`), **Guided** (all `assisted`, the default), **Hands-Off** (all `instant`). Choosing one writes that value into all six columns. Touching any single domain flips the displayed preset to **"Custom"** — which is **derived, never stored** (same rule as archetype: the label must never contradict the underlying state).
- **Per-domain, because delegation is not all-or-nothing.** FM players delegate team-talks but pick the lineup; a Guildmaster should be able to run raid nights by hand while auto-resolving recruitment. Per-domain from day one is what prevents the retrofit.

### The audit column — who signed each decision

Add to the four fact tables that record authored decisions:

```
RAID_LINEUP · RAID_ASSIGNMENT · WEEK_ACTION · LOOT_DROP
  decided_by  TEXT NOT NULL DEFAULT 'player'
              CHECK (decided_by IN ('player','assistant'))
```

The CHECK **deliberately reserves room for officer slugs** in v1.1, when delegation quality becomes a recruitable stat (§5) — so v1.1 needs no migration. Auto-authored rows are otherwise **identical** to manual ones, which is why the existing `PULL_EVENT` / `LOOT_CLAIM` / `WEEK_ACTION` audit trails and the "why did this happen" view (M7-005) work unchanged in every mode.

**This migration lands with M5-001**, before Phase-B screens start writing these tables.

---

## 3. The domain matrix

Every cell maps to something that already exists, is planned in M5–M9 (lite), or is explicitly deferred. "Visible always" is the same in all three modes — it is the information contract.

| Domain | **Manual** | **Assisted** *(default)* | **Instant** | Visible in every mode |
|---|---|---|---|---|
| **Lineup** | Empty grid (or "copy last night"); player picks all 20 + bench; comp warnings fire live, block nothing. A `[Suggest lineup]` button is a one-shot upgrade to Assisted. | **The shipped M4 `RaidPrep.build()` flow, canonised.** `auto_lineup()` prefills; the full warning strip renders; every slot editable; `[Reset to suggestion]`. Nothing requires acknowledgement — visibility *is* the contract. | `auto_lineup()` applied, prep screen skipped, but a pre-flight **handoff card** shows the 20 + bench + **every outstanding warning in full MI-008 text** before the night runs. `[Run the night]` / `[Review lineup]`. | The fielded 20 + bench; every comp warning, computed identically; role/utility/range coverage; gear scores. |
| **Assignments** | Player assigns every duty from scratch; unfilled-duty warnings (MI-008 form). | Default assignment plan prefilled per encounter; gaps warned; every duty reassignable; `[Reset duty]`. | Defaults applied without a screen; the handoff card + report print the **full who-had-which-job table** (mandatory — `duty_fail` −2.0 ratings are unreadable otherwise). | The complete assignment table at raid-event grain; duty-coverage warnings; every `duty_fail`/`duty_ok` rating factor links back to the row that handed out the job. |
| **Pulls** *(raid night)* | **The v1 fence, verbatim:** strategy posture, between-pull lineup/assignment swaps, consumable adjustments, wipe calls, end-night. **No mid-pull directive injection in any mode** (v1.1). | The Manual controls, **plus** the diagnosis `recommendation` (MI-005) becomes one-click: "Field a crit-immune main tank" renders as `[Bench Shadowwhisper → promote stormblade10]` with the expected consequence stated. Never zero-click — the player always approves. | `NightRunner.run_night()` — the engine's existing headless resolve, now a mode. **The assistant never applies wipe recommendations between pulls** — it runs the lineup you handed it, and the same wall stops it every time, which is exactly what the recurrence line then reports. | The full combat log (watched live, or replayed at Live pacing from the report — every beat persists via `PULL_EVENT`); per-wipe diagnosis; "closest yet"; per-raider ratings with breakdowns. **Instant hides pacing, never content.** |
| **Loot** | Every drop stops the flow: Council 7-factor claims panel / DKP confirm-each-spend / `/roll` trigger-and-read. | Claims panel opens **pre-ranked** with readable reason chips ("biggest upgrade", "on a 3-week drought", "MVP tonight"); `[Award as suggested]` is one click; any veto is frictionless. DKP//roll auto-resolve but **pause on contested/notable drops**. | The active `GUILD_CONFIG` loot policy resolves every drop at night's end. DKP and `/roll` run their real policy math. **Council-on-Instant is clamped in v1** (see §8) — the toggle is greyed with the reason shown. | Every award + its reason; the full consequence ripple (morale/loyalty/fairness/ego); loot-claim history; drought tracking. |
| **Weekly plan** | Player allocates the 5 lanes (Gearing/Development/Supply/People/Rest) by hand; availability + inbox shown. | An **advisor proposal** prefills the week (continuity + gap-fill + a Rest recommendation when fatigue is high); every lane editable; the proposal's reasoning shown. | Proposal auto-committed; the **weekly digest** prints what was allocated and, crucially, **what it skipped** (an unread drama, a raider on a burnout cliff). | The lane allocation; availability; the inbox; the digest — the digest is where an Instant week stays legible. |
| **Recruitment** | Player reads the fog overlay, runs trials, signs. | A **ranked shortlist** with assessment-fog-aware reason chips; player still signs. | Policy-driven: the active recruitment policy sources/assesses/signs to fill role gaps; the digest reports who came and went. *(Instant is **contract-only** in v1 — see §4.)* | The roster; open role gaps; the fog overlay; who was signed/released and why. |

---

## 4. What is *functional* in v1 vs contract-only

Not every cell gets a working switch in the v1 build. The contract specifies all of them so the screens are shaped right; v1 **wires** the ones the engine can already serve.

**Functional three-state switches in v1** (built mode-aware from each screen's first Phase-B version; raid-night + loot wired at M9-005):

- **Lineup · Assignments · Pulls** — the engine already contains both ends: `RaidPrep.build()` prefill *is* Assisted, `NightRunner.run_night()` *is* Instant, hand-editing *is* Manual. M9-005 is wiring + the one-click recommendation mapping + the report sections.
- **Weekly plan** — all three. The advisor-proposal function M5 must build for Assisted also serves as Instant's auto-commit (one function, two call sites).
- **Loot** — Manual + Assisted for **Council**; all three for **DKP / `/roll`** (their Instant *is* their native "set a policy, let it run" form).

**Contract-only in v1** (screen designed with the hook; switch deferred, toggle greyed with reason):

- **Recruitment Instant** — Manual + Assisted ship in M8; policy-driven auto-recruit is a small M8/M9 follow-on or MB-003 breadth. The screen is built to accept it.
- **Council-on-Instant** — the auto-steward that awards Council drops with no player press is v1.1 (the loot doc already defers officer-AI). Clamped to Assisted in v1.

**One small new engine function the contract mandates** (so the Weekly/Lineup Assisted-and-Instant modes share a code path, not two): a **continuity + gap-fill** wrapper over the existing lineup/week persistence — "keep last week's standing choices, fill only the holes." ~20 lines over `auto_lineup()` + persistence. It is *not* a smarter optimiser (§5); it is a more honest **default policy** than "regenerate greedily every week."

---

## 5. 🔒 Delegation quality — one fallible officer, on purpose

> ### In v1 there is **one** assistant, and it is **deliberately fallible**: it uses the exact heuristics the game's own warnings critique.

`auto_lineup()` stays **greedy by gear score**. Assisted prefills it; Instant commits it; Manual can summon it with `[Suggest]`. It is the same naive draft everywhere, and the warning strip says so.

This is the single most important decision in the contract, and it exists to protect the game's proven core. Night One's entire thesis is **"the biggest number is not the right call."** A smarter Instant optimiser would silently append *"…unless you stop looking, in which case the computer secretly knows better"* — which **poisons the player's mental model of every prefill they ever see.** Delegation must mean **trust in a legible, imperfect officer**, not access to a hidden better answer.

Three reasons this is also the *correct* engineering call:

1. **Teaching.** One honest heuristic keeps the player's mental model true (above).
2. **Determinism + cost.** One heuristic per decision = one pure code path (a function of DB + seed), one test surface, and **no divergence between what the screen suggests and what the delegate does.** A second "smart" brain would double all of that and could contradict the warnings on screen.
3. **Quality varies by domain, legibly, never by hidden dice.** Loot-policy math (DKP//roll) is *exact* because the policy **is** the decision. The lineup heuristic is *naive* and says so via the warning strip. The weekly advisor is a *gap-filler*, not a strategist, and the digest prints what it skipped. **No hidden competence stat exists anywhere in v1.**

**Deferred to v1.1 (already reserved):** delegation quality as a **recruitable officer stat** — a bad lieutenant gives bad advice, and *which* officer you trust becomes a people-decision, which is deeply on-theme. The `decided_by` CHECK already reserves room for officer slugs, so this ships without a migration.

---

## 6. 🔒 Night One survives any settings choice — the PIN + defence in depth

Night One is the game's whole pitch (`guildmaster-first-session.md`), and a brand-new player who picks **Hands-Off** at genesis must not skip it or — worse — auto-wipe at 5% all night, which is precisely the 32-wipes feeling milestone MI existed to kill. Two layers guarantee the authored session regardless of what the player chose:

**Primary — the PIN.** *The first raid night of a new campaign forces Lineup / Assignments / Pulls / Loot to **Assisted**, regardless of involvement settings,* with the copy:

> *"Your first night with a new guild — walk the floor once. From next week, your officers can take over."*

Assisted is exactly the experience Night One was measured on: the flawed greedy draft arrives prefilled, the crittable-tank warning is on screen, the fix is one bench toggle, and the diagnosis recommendation prompts it after a wipe. A genesis-time Instant choice simply takes effect **from week two**. The PIN is not a block — it is a one-week deferral of the player's preference, framed as onboarding.

**Defence in depth — it would teach itself anyway.** Even without the PIN, the fallible officer does *not* pre-solve the lesson: on Instant it fields the same crittable default, wipes with `tank_survival` as primary cause, hits the recurrence threshold ("the same wall, not bad luck"), and the printed recommendation is the fix. The player learns the lesson through the report instead of the prep screen. The PIN exists so they learn it the *good* way; the fallback exists so the contract is honest that the lesson is load-bearing in the systems, not just the tutorial.

*(This makes `tests/first_night_test.gd` a natural sibling for a "PIN holds on Instant" case when M5-001 lands.)*

---

## 7. Legible delegation — where the skipped decisions go

Delegation that hides information is a betrayal of the "legible failure" pillar. Every mode's automated decisions surface in two fixed places:

- **Post-night report → "Decisions made for you"** — the lineup the officers fielded, the assignments they set, the loot they awarded, and **every warning they ran past** ("ran tonight with 1 unresolved warning: *Your main tank can be hit by a critical strike…*").
- **Weekly digest → the same, at week grain** — what the advisor allocated, and what it *skipped* (an unread drama, a burnout-cliff raider, a snubbed loot claim). An unresolved warning **escalates** week over week so delegation can never quietly bury a growing problem.

The rule: **an Instant player sees the same facts a Manual player sees — later, and summarised, but never fewer.**

---

## 8. Instant loot does not break "loot is a leadership decision"

The pillar was never *"loot is a per-drop click."* It is **choosing and owning the culture.** Three things square it:

1. **Choosing the culture IS the decision.** Fairness is per-culture (its own pillar). Adopting DKP or `/roll` at genesis is the leadership act of binding yourself to a yardstick — and both, by design, *"already run themselves — the low-micro option"* (loot doc). Their Instant mode is their **native form**, and the guild judges you by that yardstick ("did the numbers hold?").
2. **Consequences are mode-independent.** Every auto award runs the **full** consequence model — recipient morale, passed-over claimants' ego, loyalty drift, `fairness_perception`, drama — and attaches to the **guildmaster** identically regardless of `decided_by`. The board still sacks the manager whose fair-shares collapsed on autopilot.
3. **The one culture whose whole point is the per-drop call — Loot Council — is clamped to Assisted in v1.** The game pre-sorts the panel and recommends, but **you press the button**, because a Council where nobody weighs the factors isn't a Council. Auto-steward Council is v1.1 (the loot doc already defers the officer-AI it would need).

---

## 9. Mode switching

- **Change any domain anytime**, from `Settings → Responsibilities`. It takes effect at the **next event of that domain's grain** (next raid night, next week, next drop) — never retroactively, so it can't rewrite a decision already made.
- **One-shot contextual overrides** are always available and never persisted: `[Take control of this drop]` on an Instant-loot night, `[Let the officers run it]` on a Manual prep screen. These are ephemeral UI state, not config writes.
- **The PIN (§6) overrides all of this for exactly the first raid night**, then releases.

---

## 10. What v1.1 inherits (reserved, no migration needed)

- **Delegation quality as a recruitable officer stat** — `decided_by` already reserves officer slugs.
- **Mid-pull directive injection** — the resolution doc's phase-boundary/cooldown-moment jump-ins. The v1 fence explicitly stops at between-pull; this is the layer above it.
- **Council-on-Instant auto-steward** and **Recruitment-Instant** implementation.

---

## 11. How Phase-B screens cite this

Every M5–M9 screen ticket points at the row(s) of §3 it implements and builds its **three modes from the first version** — never "manual now, automation later." Concretely:

- **M5** (weekly plan, calendar, genesis): builds the advisor-proposal function (Assisted + Instant share it), migrates the `GAME_CONFIG` columns + `decided_by`, and implements the **PIN**.
- **M6** (loot): Council Manual + Assisted; DKP//roll all three; Council-Instant toggle greyed with reason.
- **M8** (recruitment): Manual + Assisted; the Instant hook present, greyed.
- **M9-005** (raid-night + loot involvement wiring): the one-click recommendation, the handoff card, the "Decisions made for you" report section, and the functional Pulls/Lineup/Assignments switches.

## 12. Acceptance

- ✅ `docs/guildmaster-involvement.md` exists with the full matrix filled in.
- ✅ Every Phase-B screen ticket can cite a specific row for its automation hooks.
- ✅ Does not contradict the v1 manual fence: manual raid control is strategy / lineup / between-pull swaps / wipe calls; **no mid-pull injection** in any mode (§3 Pulls, §10).
- ✅ Contract only — implementation stays at M9-005 and the Phase-B screens.
