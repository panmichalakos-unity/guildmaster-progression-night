# Phase A Fun Gate — ✅ PASSED (2026-07-12)

The hard stop before Phase B. **Gate 1 is passed** — see ADR-0029 and `guildmaster-content-and-dod.md`.

> ### Verdict — Panos, 2026-07-12, seed 133742
>
> > *"It seems solid, hard enough but doable, I feel it just about right."*
>
> **Fun enough to continue into Phase B? → YES.**
>
> ⚠️ **Passed by an expert MMO player.** The scorecard line *"can a non-MMO player act on the UI's warnings alone?"* is **still open** — see §Remaining validation.

---

## How to verify (commands)

From the repo root (Godot editor closed for `--quit`):

```bash
python tools/seed_check.py
godot --headless --quit
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/

# the first session must TEACH (MI-003)
godot --headless -s tools/smoke/first_night_smoke.gd -- --seed 133742
# the full four-boss slice must be completable (M4-005)
godot --headless -s tools/smoke/slice_smoke.gd -- --seed 133742

# per-boss balance contracts, and proof that raid prep DECIDES anything (MI-009)
godot --headless -s tools/harness.gd -- --pulls 150 --assert-contracts
godot --headless -s tools/harness.gd -- --probes --pulls 150
```

> **Note:** the old gate command `--assert-winrate 0.6 0.8` **no longer exists.** MI-009 replaced that single global band on boss 1 — the gate that passed green while three of four bosses sat at a 0% win rate — with per-boss contract assertions. Do not resurrect it.

Manual playtest: open the project in Godot → F5 → set a night seed → Assemble the Raid → read the warnings → tweak the lineup → Lock in Lineup → pull through Emberdeep → End night → read the report.

## Gate 1 objective checks

From `docs/guildmaster-content-and-dod.md`:

| Check | Status | Notes |
|---|---|---|
| Generate ~28 roster (traits + gear + specs), inspectable | ✅ | RosterReport + prep screen |
| One raid (3–4 bosses) seeded | ✅ | Emberdeep, 4 bosses |
| Lineup → assignments → pull-by-pull combat log → kill/wipe + wipe_reason + ratings + loot | ✅ | M4-002…004 UI |
| Post-night report readable | ✅ | M4-004, + the MI-005 diagnosis and MI-006 rating breakdowns |
| Deterministic: same seed → same result | ✅ | slice_smoke runs twice and diffs |
| Every boss inside its own contract band, on reachable gear | ✅ | MI-009 `--assert-contracts` |
| Raid prep is tactics, not administration | ✅ | MI-009 `--probes`: every boss answers to its own lever |
| **Verdict: is the raid night fun to run?** | ✅ **PASSED** | Human only — above |

---

## Current evidence (2026-07-12)

```text
FIRST NIGHT SMOKE: seed=133742
  default main tank: Shadowwhisper (Oakhide) — CRITTABLE
  prep warning: Your main tank Shadowwhisper can be hit by a critical strike — one
    unlucky spike will kill him outright and end the pull, and no amount of healing
    prevents it. Field a tank who cannot be critically hit, even if their gear score
    is lower (uncrittable).
  as handed to you:     5.3% win   (top wipe: tank_survival)
  bench Shadowwhisper -> main tank is now stormblade10 (Bulwark)
  after the one fix:   44.0% win   -> a kill in ~2.3 pulls
FIRST NIGHT SMOKE: PASS

SLICE SMOKE: seed=133742
  pulls=18 kills=4 wipes=14
  Killed 4/4 bosses (Gatewarden Krogg, Forgemaster Vell, The Slagbeast, The Cinderlords)
SLICE SMOKE: PASS
```

157 tests · 277 seed checks · lint + format clean · both harness gates green.

### 📛 Pre-intervention baseline — **historical, do NOT use as current evidence**

On **2026-07-11**, the same build produced:

```text
SLICE SMOKE: seed=133742
  pulls=32 kills=0 wipes=32       <- the entire tier was uncompletable
```

Starter gear sat far under the demanded band: the entry boss demanded roughly the gear it *drops*, and four conjunctive check-rolls capped even a healthy raid at ~41%. The harness of the day reported a healthy band only near **gear ×2.25** — gear the player could never reach (the real Tier-1 ceiling is **×1.64**). **Every automated gate was green while this was true.** That contradiction is what milestone **MI** existed to resolve; see `guildmaster-intervention-and-realignment.md`.

---

## Remaining validation (the gate is passed; this is not finished)

The verdict above came from **an expert MMO player**. It speaks to *"is a first kill plausible"*, *"is there a meaningful decision"* and *"do you want another pull"*. It says **nothing** about the scorecard line:

> **"Can a management-sim player with no MMO history act on the warnings without external explanation?"**

MI-008 makes that outcome *plausible* (plain-language-first warnings, glossary, enforced by tests). It does not make it *proven*. **The only thing that proves it is running Night One in front of somebody who has never raided, and not helping them.**

Watch for, without teaching:

1. Do they read the tank warning, and understand it?
2. Do they identify the actual problem?
3. Do they look at the bench?
4. Do they make a meaningful change — and if not, what do they try instead?
5. Do they understand why the second attempt went better?
6. Do they understand the post-night report?
7. Do they ask for another pull?

The question is **not** whether they solve it instantly. It is whether the interface supports understandable learning.

---

## Known gaps (do not hide)

- Loot is **display-only** (no claims / awards) — M6
- State deltas (morale/fatigue/form) are returned but not applied — M5
- Demo campaign is in-memory slice scaffolding — **M5-001 genesis replaces it, and MI-013 must carry the Night One contract across or the shipped game loses its opening**
- No save/load of the night mid-pull
- Automated `NightRunner.run_night` caps at 8 attempts per boss then advances
- The engine does **not** model boss HP over time, so there is deliberately no live boss-health bar (ADR-0027) — progress is reported where it is real: as the outcome

## Linked evidence

- Verdict: **ADR-0029**; scorecard in `guildmaster-content-and-dod.md`
- Encounter contracts: `guildmaster-encounter-contracts.md` + `data/seeds/encounter_contract.csv`
- First session: `guildmaster-first-session.md`
- Balance harness: `tools/harness.gd` (ADR-0024, ADR-0030)
- Smokes: `tools/smoke/first_night_smoke.gd`, `tools/smoke/slice_smoke.gd`
- Notion: M4-005 and MI-010 on the Guildmaster v2 board
