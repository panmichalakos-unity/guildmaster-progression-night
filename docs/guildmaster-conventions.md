# Guildmaster: Progression Night — Modeling Conventions

Canonical modeling patterns for the project. Add new conventions here as they're established.

---

## Convention 1 — Movable attributes = Baseline + Current

**Problem.** Some attributes are durable identity (who a raider fundamentally is); others drift constantly from events (loyalty after a loot snub, morale after a wipe). Storing a single mutable value throws away the anchor — you lose "who they really are," and drift becomes unbounded and irreversible.

**Rule.** Any attribute gameplay can *move* is split into a durable part and a volatile part. But not everything drifts the same way — there are **three shapes**, and picking the right one is the convention.

### The three shapes

**A. Baseline + Current** — a same-unit value that drifts around an anchor and whose drifted value *other systems read later*.
- `<attr>_baseline` — durable anchor; set at generation, moves only via deliberate mechanisms (training, life events, expansion patches).
- `<attr>_current` — working value; starts at baseline, moves with events, **mean-reverts toward baseline** over time.
- *Optional scarring:* sustained pressure on `current` can bleed the `baseline` itself (months of snubs permanently lower `loyalty_baseline`). A scar, not a bruise.
- *Example:* loyalty, morale.

**B. Accumulator + Rate-trait** — a quantity that builds or depletes, governed by a durable *rate/sensitivity* trait (a different unit).
- The durable part is a **rate**, not a same-unit baseline.
- The volatile part accumulates/depletes and has a defined recovery.
- *Example:* fatigue (`fatigue_current` accumulates; `burnout_sensitivity` governs the rate; recovers with rest). Familiarity (grows per week-on-spec; `growth_rate` governs; **resets to 0 on re-roll**).

**C. Trait + Runtime modifier** — a durable trait whose *effective* value is nudged at compute time by transient states, with **nothing extra persisted**.
- No `_current` column. The modifier is applied in the resolution formula, not stored.
- *Example:* skill facets (Execution / Awareness / Consistency) are traits that grow slowly via training; morale/form/fatigue modulate them multiplicatively *at resolution* — we never store `execution_current`.

### Decision rule (checklist)
1. Does gameplay move it? **No →** plain trait, done.
2. **Yes →** Does another system need to read the *drifted* value later?
   - **No** (only matters at the instant of resolution) → **Shape C** (runtime modifier; don't persist).
   - **Yes →** same-unit drift around an anchor, or an accumulating/depleting quantity?
     - Same-unit around anchor → **Shape A** (baseline + current).
     - Accumulating/depleting → **Shape B** (accumulator + rate-trait).

### Storage / lakehouse mapping
| Part | Lives as |
|---|---|
| Baseline | Dimension attribute (SCD-2 if deliberate changes should be historized) |
| Current (persisted) | Working column on the dimension, mutated in place; history captured in the periodic-snapshot fact (e.g. `PLAYER_WEEK_STATE`). If it's naturally snapshot-grained, it lives *only* in the snapshot fact. |
| Accumulator | Periodic-snapshot fact (or working column + snapshot history) |
| Runtime modifier | Not stored — computed in the resolution transform/query |

### Attribute inventory (current)
| Attribute | Shape | Durable part | Volatile part | Reversion |
|---|---|---|---|---|
| Loyalty | A | `loyalty_baseline` | `loyalty_current` | slow toward baseline; sustained snubs scar baseline down |
| Morale | A | resting level (from temperament) | `morale_current` | toward resting between events |
| Form (streak) | B* | anchor = neutral | `form` | decays to neutral |
| Fatigue / burnout | B | `burnout_sensitivity` (rate) | `fatigue_current` | recovers with rest |
| Familiarity | B | `growth_rate` (rate) | `familiarity` (per avatar) | resets to 0 on re-roll; grows with weeks-on-spec |
| Skill facets | C | the facet value (grows via training) | — | modifier applied at resolution, not stored |
| Chemistry (sentiment) | A | origin/base sentiment | `sentiment_current` | decays toward base; *Grudge-Holder* slows it |

\* Form is a Shape-B accumulator with a neutral anchor and no rate trait — the lightest case.

**Guiding principle:** *store a `current` only when a future decision needs the drifted value.* Otherwise modulate at compute time (Shape C) and keep the schema lean.

---

## Related conventions already in play
Brief index; each is specced in its own doc.

- **Traits vs States, physically separated** — durable attributes on the entity; volatile values in snapshot tables. *(data-model)*
- **Player persists, Avatar is swappable** — parent/child dimension; re-roll/sacking carry the human forward. *(data-model, pitch)*
- **Archetype is derived, never stored** — computed from the trait+quirk cluster so the label can't contradict behavior. *(data-model, pitch)*
- **Content as data, not code** — encounters, events, and quirks are seed rows the engine reads; new bosses = new rows. *(resolution)*
- **Pluggable policy interface** — loot systems (and later, officer-AI behaviors) are swappable policies; swapping one swaps the *culture*. *(loot)*
- **IP-safe naming** — replicate systems and feel; invent every proper noun. *(pitch)*

---

*v0.1 — conventions index. Extend as new patterns are locked.*
