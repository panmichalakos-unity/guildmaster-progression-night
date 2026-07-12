-- 0003 — the per-boss balance contract, as DATA.
-- MI-009 / ADR-0030.
--
-- docs/guildmaster-encounter-contracts.md declared that "retuning a boss without
-- updating its contract is a bug". That was a convention, and conventions do not
-- fail builds. This table is the machine-readable half: the balance harness
-- asserts every boss against ITS OWN row, so a boss that drifts out of its band,
-- stops being farmable, or quietly starts dying to the wrong thing turns CI red.
--
-- The harness this replaces asserted ONE global win-rate band on boss 1 and swept
-- gear to x3.0. It passed green while three of four bosses sat at a 0% win rate on
-- gear the player could never assemble. A green harness that permits an unplayable
-- game is the exact failure milestone MI exists to prevent, and it must not recur.
--
--   expected_gear        the roster state this boss is FOR (x1.00 = a fresh guild)
--   win_lo / win_hi      the progression band AT that gear, with a prepared raid
--   farm_gear            full tier BiS (x1.64 — see the gear ceiling, ADR-0024)
--   farm_win_min         farm content must not waste a night
--   dominant_failure     the wipe a PREPARED raid takes here; a boss that dies to
--                        something else is not the fight it says it is
--   signature_lever      the prep decision that DEFINES this boss (MI-009 probes)
--   signature_min_delta  percentage points that lever must move the win rate, or
--                        the fight has no identity the player can act on
CREATE TABLE encounter_contract (
    encounter_id        INTEGER PRIMARY KEY REFERENCES encounter(encounter_id),
    expected_gear       REAL    NOT NULL,
    win_lo              REAL    NOT NULL,
    win_hi              REAL    NOT NULL,
    farm_gear           REAL    NOT NULL,
    farm_win_min        REAL    NOT NULL,
    dominant_failure    TEXT    NOT NULL,
    signature_lever     TEXT    NOT NULL,
    signature_min_delta REAL    NOT NULL
);
