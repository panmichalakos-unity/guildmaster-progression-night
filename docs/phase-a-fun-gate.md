# Phase A Fun Gate — checklist (M4-005)

The hard stop before Phase B. Fill this in after the vertical slice is playable end-to-end.

## How to verify (commands)

From the repo root (Godot editor closed for `--quit`):

```bash
python tools/seed_check.py
godot --headless --quit
godot --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a tests/
godot --headless -s tools/smoke/slice_smoke.gd -- --seed 133742
godot --headless -s tools/harness.gd -- --pulls 100 --assert-winrate 0.6 0.8
```

Manual playtest: open the project in Godot → F5 → set a night seed → Assemble the Raid → tweak lineup → Lock in Lineup → Pull through Emberdeep → End night → read the report.

## Gate 1 objective checks

From `docs/guildmaster-content-and-dod.md`:

| Check | Status | Notes |
|---|---|---|
| Generate ~28 roster (traits + gear + specs), inspectable | | RosterReport + prep screen |
| One raid (3–4 bosses) seeded | | Emberdeep, 4 bosses |
| Lineup → assignments → pull-by-pull combat log → kill/wipe + wipe_reason + ratings + loot | | M4-002…004 UI |
| Post-night report readable | | M4-004 |
| Deterministic: same seed → same result; harness ~60–80% band | | slice_smoke + harness |
| **Verdict: is the raid night fun to run?** | | Human only — below |

## Playtest questions (Panos)

Answer after at least two full nights (different seeds):

1. Did you understand *why* a wipe happened from the combat log + wipe_reason?
2. Did lineup / comp warnings feel like meaningful decisions?
3. Did bosses 2–4 (mechanic/learning walls per ADR-0020) feel fair, or just opaque?
4. Would you want to play another night tonight?
5. What is the single most confusing or boring moment?

## Verdict

- Date:
- Seed(s) tried:
- Fun enough to continue into Phase B (M5+)? **Yes / No / Not yet — tune first**
- If tune first: what to change (severity, learning rate, UI clarity — not new systems):

## Known gaps (do not hide)

- Loot is **display-only** (no claims / awards) — M6
- State deltas (morale/fatigue/form) are returned but not applied — M5
- Demo campaign is in-memory slice scaffolding — M5-001 genesis replaces it
- No save/load of the night mid-pull
- Automated `NightRunner.run_night` caps at 8 attempts per boss then advances
- **Starter gear is under the matched band.** Slice smoke on seed 133742: 32 wipes / 0 kills. Harness (ADR-0020) reaches ~60–80% on boss 1 near **gear ×2.25**. Expect heavy wipes until Marks/gearing (M5–M7) or a temporary slice gear bump is decided in playtest — do not hide this behind fake UI wins.

## Linked evidence

- Balance harness: `tools/harness.gd` (ADR-0020/0021)
- Slice smoke: `tools/smoke/slice_smoke.gd`
- Notion: M4-005 task on Guildmaster v2 board
