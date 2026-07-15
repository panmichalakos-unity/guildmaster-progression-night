-- 0004 — the per-domain involvement contract (Manual / Assisted / Instant).
-- MI-007 / ADR-0033. Lands with M5-001, before the Phase-B screens that read it.
--
-- Involvement changes WHO AUTHORS the inputs, never how the sim resolves them.
-- GAME_CONFIG already carries `involvement_default` (the genesis preset); this adds
-- the six PER-DOMAIN overrides, so a Guildmaster can run raid nights by hand while
-- auto-resolving recruitment. Genesis initialises all six from involvement_default;
-- the three genesis presets (Full Control / Guided / Hands-Off) are UI sugar that
-- write the same value into all six, and "Custom" is a DERIVED label, never stored.
--
-- Defaulted to 'manual' only so the ALTER is valid on any existing row; genesis
-- always writes them explicitly, so the default is never the value a campaign sees.
ALTER TABLE game_config ADD COLUMN involvement_lineup TEXT NOT NULL DEFAULT 'manual'
    CHECK (involvement_lineup IN ('manual', 'assisted', 'instant'));
ALTER TABLE game_config ADD COLUMN involvement_assignments TEXT NOT NULL DEFAULT 'manual'
    CHECK (involvement_assignments IN ('manual', 'assisted', 'instant'));
ALTER TABLE game_config ADD COLUMN involvement_pulls TEXT NOT NULL DEFAULT 'manual'
    CHECK (involvement_pulls IN ('manual', 'assisted', 'instant'));
ALTER TABLE game_config ADD COLUMN involvement_loot TEXT NOT NULL DEFAULT 'manual'
    CHECK (involvement_loot IN ('manual', 'assisted', 'instant'));
ALTER TABLE game_config ADD COLUMN involvement_weekly TEXT NOT NULL DEFAULT 'manual'
    CHECK (involvement_weekly IN ('manual', 'assisted', 'instant'));
ALTER TABLE game_config ADD COLUMN involvement_recruitment TEXT NOT NULL DEFAULT 'manual'
    CHECK (involvement_recruitment IN ('manual', 'assisted', 'instant'));

-- The authorship audit column. Every authored decision records who signed it — the
-- player, or the assistant acting on their delegated involvement setting. The CHECK
-- deliberately reserves room for officer slugs in v1.1 (delegation quality as a
-- recruitable stat), so THAT feature needs no further migration. Auto-authored rows
-- are otherwise identical to manual ones, which is why every audit view and the
-- "why did this happen" report work unchanged in every mode.
ALTER TABLE raid_lineup ADD COLUMN decided_by TEXT NOT NULL DEFAULT 'player'
    CHECK (decided_by IN ('player', 'assistant'));
ALTER TABLE raid_assignment ADD COLUMN decided_by TEXT NOT NULL DEFAULT 'player'
    CHECK (decided_by IN ('player', 'assistant'));
ALTER TABLE week_action ADD COLUMN decided_by TEXT NOT NULL DEFAULT 'player'
    CHECK (decided_by IN ('player', 'assistant'));
ALTER TABLE loot_drop ADD COLUMN decided_by TEXT NOT NULL DEFAULT 'player'
    CHECK (decided_by IN ('player', 'assistant'));
