-- 0005 — the day cursor for the weekly turn loop (M5-002).
--
-- GAME_STATE already tracks WHICH week (week_id) and the phase; the turn loop also
-- needs to know which DAY within the week the campaign has advanced to, so empty
-- days can tick recovery exactly once and the "continue" step knows where it is.
-- Time is still represented purely through GAME_STATE + WEEK + CALENDAR_EVENT — no
-- real-time clock.
--
--   0     = the week has not been stepped into yet (planning; genesis leaves it here)
--   1..7  = the cursor sits on that day; events up to and including it are resolved
ALTER TABLE game_state ADD COLUMN current_day INTEGER NOT NULL DEFAULT 0
    CHECK (current_day BETWEEN 0 AND 7);
