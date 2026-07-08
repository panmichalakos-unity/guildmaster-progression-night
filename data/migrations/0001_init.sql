-- ============================================================================
-- 0001_init.sql — Guildmaster: Progression Night — v1 core schema
-- Source of truth: docs/guildmaster-data-model.md (ERD v0.8), "Suggested v1
-- Prototype Spine", cross-validated against guildmaster-{conventions,gear,
-- loot,campaign-and-objectives,raid-prep,resolution,between-nights}.md.
--
-- Conventions
--   * Physical table names are lower_snake_case; SQLite matches identifiers
--     case-insensitively, so doc-style UPPER_CASE queries also work.
--   * Seed/content tables carry an immutable `slug` (natural key, snake_case)
--     plus a renameable `display_name` (naming-bible ID convention).
--     Runtime/generated entities (player, guild, ...) use integer ids only.
--   * Booleans are INTEGER 0/1 with CHECK; datetimes are TEXT ISO-8601.
--   * int scores are 0-100 unless noted; ratings are 1-10 (data-model note).
--   * The migration runner (M0-004) MUST enable `PRAGMA foreign_keys = ON`
--     on every connection (it is per-connection in SQLite, not schema state)
--     and should wrap each migration file in a transaction.
--
-- Deliberate deviations from / additions to the literal spine list
-- (rationale in docs/decisions.md ADR-0005):
--   + pull_consumable       — required by G7/G12 + raid-prep v1 consumable plan
--   + synergy_tag(+bridge)  — v1 per backlog M1 DoD + content table (~5 tags)
--   + week_action.action_type_id — relationship drawn in ERD v0.7, column
--     missing from the older v0.4 column list
--   + schema_migration      — migration bookkeeping usable pre-genesis
--   * loot_item.slot        — modeled as slot_id FK to slot (7-slot model);
--     loot_item.encounter_id nullable (vendor + generated starting gear)
--   + encounter_phase.slug + encounter_event.target_selector — M1-002 edits
--     (pre-genesis deliberate 0001 update per the M0-003 ticket rule):
--     phase natural key for seed refs; per-placement selector override so
--     range profiles stay seed data with the locked 7 event types
--
-- Deferred to v1.1+ (deliberately NOT created here, per the spine):
--   quirk, player_quirk, avatar_resistance, drama_event.
--   relationship DOES ship in v1 (write-only; chemistry effects are v1.1).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Migration bookkeeping (M0-004 records applied migrations here)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migration (
    migration_id   INTEGER PRIMARY KEY,
    filename       TEXT    NOT NULL UNIQUE,
    applied_at     TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- ----------------------------------------------------------------------------
-- 1. Kit & content lookups (seed; slug-keyed)
-- ----------------------------------------------------------------------------
CREATE TABLE role (
    role_id        INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,
    display_name   TEXT    NOT NULL
);

CREATE TABLE class (
    class_id       INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,
    display_name   TEXT    NOT NULL
);

CREATE TABLE spec (
    spec_id         INTEGER PRIMARY KEY,
    class_id        INTEGER NOT NULL REFERENCES class(class_id),
    role_id         INTEGER NOT NULL REFERENCES role(role_id),
    slug            TEXT    NOT NULL UNIQUE,
    display_name    TEXT    NOT NULL,
    spec_difficulty INTEGER NOT NULL DEFAULT 50
);
CREATE INDEX ix_spec_class ON spec(class_id);
CREATE INDEX ix_spec_role  ON spec(role_id);

CREATE TABLE raid_utility (
    utility_id     INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,
    display_name   TEXT    NOT NULL,
    category       TEXT
);

CREATE TABLE spec_utility (
    spec_id        INTEGER NOT NULL REFERENCES spec(spec_id),
    utility_id     INTEGER NOT NULL REFERENCES raid_utility(utility_id),
    PRIMARY KEY (spec_id, utility_id)
);
CREATE INDEX ix_spec_utility_utility ON spec_utility(utility_id);

CREATE TABLE synergy_tag (
    synergy_tag_id INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,
    display_name   TEXT    NOT NULL
);

CREATE TABLE spec_synergy_tag (
    spec_id        INTEGER NOT NULL REFERENCES spec(spec_id),
    synergy_tag_id INTEGER NOT NULL REFERENCES synergy_tag(synergy_tag_id),
    PRIMARY KEY (spec_id, synergy_tag_id)
);

CREATE TABLE life_situation (
    life_situation_id   INTEGER PRIMARY KEY,
    slug                TEXT    NOT NULL UNIQUE,
    display_name        TEXT    NOT NULL,
    availability_window TEXT,
    volatility_mod      INTEGER NOT NULL DEFAULT 0,
    burnout_mod         INTEGER NOT NULL DEFAULT 0,
    loyalty_mod         INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE slot (
    slot_id        INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,   -- 7 slots: head..weapon (seeded)
    display_name   TEXT    NOT NULL
);

CREATE TABLE consumable (
    consumable_id  INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,
    display_name   TEXT    NOT NULL,
    type           TEXT,
    tier           TEXT    NOT NULL CHECK (tier IN ('basic', 'premium')),
    cost           INTEGER NOT NULL DEFAULT 0 CHECK (cost >= 0)
);

CREATE TABLE objective_type (
    objective_type_id INTEGER PRIMARY KEY,
    slug              TEXT NOT NULL UNIQUE,  -- progression/competitive/roster/cohesion/economic/development
    display_name      TEXT NOT NULL,
    reads_from        TEXT                   -- source system the tracker queries
);

CREATE TABLE action_type (
    action_type_id INTEGER PRIMARY KEY,
    slug           TEXT    NOT NULL UNIQUE,
    display_name   TEXT    NOT NULL,
    lane           TEXT    NOT NULL CHECK (lane IN ('gearing', 'development', 'supply', 'people', 'rest')),
    roll_inputs    TEXT,                     -- attributes rolled vs difficulty
    output_type    TEXT,                     -- what the resolver produces
    output_range   TEXT                      -- bounded variance band
);

CREATE TABLE event_type (
    event_type_id   INTEGER PRIMARY KEY,
    slug            TEXT NOT NULL UNIQUE,    -- core-5 + assigned_duty + cooldown in v1
    display_name    TEXT NOT NULL,
    trigger         TEXT,
    target_selector TEXT CHECK (target_selector IN ('tank', 'healer', 'melee', 'ranged', 'random', 'assigned')),
    roll_attribute  TEXT,
    effect_category TEXT,
    log_template    TEXT
);

-- ----------------------------------------------------------------------------
-- 2. World, time & encounter content (seed; slug-keyed)
-- ----------------------------------------------------------------------------
CREATE TABLE expansion (
    expansion_id        INTEGER PRIMARY KEY,
    slug                TEXT    NOT NULL UNIQUE,
    display_name        TEXT    NOT NULL,
    release_order       INTEGER NOT NULL,
    season_length_weeks INTEGER NOT NULL DEFAULT 14,
    difficulty_band     TEXT
);

CREATE TABLE season (
    season_id    INTEGER PRIMARY KEY,
    expansion_id INTEGER NOT NULL REFERENCES expansion(expansion_id),
    slug         TEXT    NOT NULL UNIQUE,
    display_name TEXT    NOT NULL,
    tier_order   INTEGER NOT NULL,
    UNIQUE (expansion_id, tier_order)
);

-- Weeks are generated at runtime by the campaign layer (not seed rows).
CREATE TABLE week (
    week_id     INTEGER PRIMARY KEY,
    season_id   INTEGER NOT NULL REFERENCES season(season_id),
    week_number INTEGER NOT NULL,
    UNIQUE (season_id, week_number)
);

CREATE TABLE raid (
    raid_id             INTEGER PRIMARY KEY,
    season_id           INTEGER NOT NULL REFERENCES season(season_id),
    slug                TEXT    NOT NULL UNIQUE,
    display_name        TEXT    NOT NULL,
    attunement_required INTEGER NOT NULL DEFAULT 0 CHECK (attunement_required IN (0, 1)),  -- always 0 in v1 (attunement is v1.1)
    raid_size           INTEGER NOT NULL DEFAULT 20
);

CREATE TABLE encounter (
    encounter_id          INTEGER PRIMARY KEY,
    raid_id               INTEGER NOT NULL REFERENCES raid(raid_id),
    slug                  TEXT    NOT NULL UNIQUE,
    display_name          TEXT    NOT NULL,
    boss_order            INTEGER NOT NULL,
    resistance_type_check TEXT,               -- unused by the v1 resolver (resistance checks are v1.1)
    resistance_threshold  INTEGER,
    dps_check             INTEGER NOT NULL DEFAULT 0,
    healing_check         INTEGER NOT NULL DEFAULT 0,
    phase_count           INTEGER NOT NULL DEFAULT 1,
    difficulty            INTEGER NOT NULL DEFAULT 50,
    UNIQUE (raid_id, boss_order)
);

CREATE TABLE encounter_phase (
    phase_id        INTEGER PRIMARY KEY,
    encounter_id    INTEGER NOT NULL REFERENCES encounter(encounter_id),
    slug            TEXT    UNIQUE,           -- M1-002: natural key so seed placements can ref phases
    phase_order     INTEGER NOT NULL,
    display_name    TEXT    NOT NULL,
    entry_condition TEXT,                     -- e.g. boss HP threshold
    UNIQUE (encounter_id, phase_order)
);

CREATE TABLE encounter_event (
    encounter_event_id INTEGER PRIMARY KEY,
    slug               TEXT    NOT NULL UNIQUE,  -- natural key for idempotent seed loads
    encounter_id       INTEGER NOT NULL REFERENCES encounter(encounter_id),
    phase_id           INTEGER NOT NULL REFERENCES encounter_phase(phase_id),
    event_type_id      INTEGER NOT NULL REFERENCES event_type(event_type_id),
    -- M1-002: per-placement override of the event type's default selector.
    -- NULL = inherit from event_type. Placing harmful events on melee/ranged
    -- is how a boss gets a range profile (resolution doc) with only 7 types.
    target_selector    TEXT CHECK (target_selector IN ('tank', 'healer', 'melee', 'ranged', 'random', 'assigned')),
    severity           INTEGER NOT NULL DEFAULT 50,
    weight             INTEGER NOT NULL DEFAULT 100
);
CREATE INDEX ix_encounter_event_encounter ON encounter_event(encounter_id);
CREATE INDEX ix_encounter_event_phase     ON encounter_event(phase_id);
CREATE INDEX ix_encounter_event_type      ON encounter_event(event_type_id);

CREATE TABLE loot_item (
    item_id      INTEGER PRIMARY KEY,
    slug         TEXT    NOT NULL UNIQUE,
    display_name TEXT    NOT NULL,
    encounter_id INTEGER REFERENCES encounter(encounter_id),  -- NULL for Marks-vendor + generated starting gear
    slot_id      INTEGER NOT NULL REFERENCES slot(slot_id),
    item_level   INTEGER NOT NULL DEFAULT 0,
    role_id      INTEGER REFERENCES role(role_id),
    marks_cost   INTEGER NOT NULL DEFAULT 0 CHECK (marks_cost >= 0),  -- > 0 means it is on the Marks vendor
    spec_fit_tag TEXT
);
CREATE INDEX ix_loot_item_encounter ON loot_item(encounter_id);
CREATE INDEX ix_loot_item_slot      ON loot_item(slot_id);

-- ----------------------------------------------------------------------------
-- 3. People, guilds & gear (runtime/generated; integer ids)
-- ----------------------------------------------------------------------------
CREATE TABLE player (
    player_id              INTEGER PRIMARY KEY,
    life_situation_id      INTEGER REFERENCES life_situation(life_situation_id),
    handle                 TEXT    NOT NULL,
    -- skill facets (durable traits)
    execution              INTEGER NOT NULL DEFAULT 50,
    awareness              INTEGER NOT NULL DEFAULT 50,
    consistency            INTEGER NOT NULL DEFAULT 50,
    potential              INTEGER NOT NULL DEFAULT 50,
    growth_rate            INTEGER NOT NULL DEFAULT 50,
    -- psychology (durable traits)
    ego                    INTEGER NOT NULL DEFAULT 50,
    loyalty_baseline       INTEGER NOT NULL DEFAULT 50,   -- anchor (conventions Shape A)
    loyalty_current        INTEGER NOT NULL DEFAULT 50,   -- drifts, mean-reverts to baseline
    volatility             INTEGER NOT NULL DEFAULT 50,
    coachability           INTEGER NOT NULL DEFAULT 50,
    influence              INTEGER NOT NULL DEFAULT 50,
    -- real-life knobs (set by life situation at generation)
    time_budget_hrs        INTEGER NOT NULL DEFAULT 10,
    schedule_volatility    INTEGER NOT NULL DEFAULT 50,
    burnout_sensitivity    INTEGER NOT NULL DEFAULT 50,
    attendance_reliability INTEGER NOT NULL DEFAULT 50
);

CREATE TABLE avatar (
    avatar_id   INTEGER PRIMARY KEY,
    player_id   INTEGER NOT NULL REFERENCES player(player_id),
    class_id    INTEGER NOT NULL REFERENCES class(class_id),
    spec_id     INTEGER NOT NULL REFERENCES spec(spec_id),
    is_active   INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    item_level  INTEGER NOT NULL DEFAULT 0,
    gear_score  INTEGER NOT NULL DEFAULT 0,   -- derived + cached from avatar_item; recomputed on equip
    marks       INTEGER NOT NULL DEFAULT 0 CHECK (marks >= 0),
    familiarity INTEGER NOT NULL DEFAULT 0,   -- accumulator; resets on re-roll
    hit_capped  INTEGER NOT NULL DEFAULT 0 CHECK (hit_capped IN (0, 1)),   -- derived from equipped set
    uncrittable INTEGER NOT NULL DEFAULT 0 CHECK (uncrittable IN (0, 1)),  -- derived from equipped set
    retired_at  TEXT
);
CREATE INDEX ix_avatar_player ON avatar(player_id);
CREATE INDEX ix_avatar_spec   ON avatar(spec_id);
-- one ACTIVE avatar per player; retired/re-rolled avatars stay as history
CREATE UNIQUE INDEX ux_avatar_one_active_per_player ON avatar(player_id) WHERE is_active = 1;

CREATE TABLE player_role_proficiency (
    player_id   INTEGER NOT NULL REFERENCES player(player_id),
    role_id     INTEGER NOT NULL REFERENCES role(role_id),
    proficiency INTEGER NOT NULL DEFAULT 50,
    PRIMARY KEY (player_id, role_id)
);

-- v1 WRITE-ONLY: coach/social/referral/poach events write rows; resolution
-- chemistry effects do not read it until v1.1 (M10). Directed: from -> to.
CREATE TABLE relationship (
    player_id_from INTEGER NOT NULL REFERENCES player(player_id),
    player_id_to   INTEGER NOT NULL REFERENCES player(player_id),
    sentiment      INTEGER NOT NULL DEFAULT 0,
    rel_type       TEXT,
    origin         TEXT,
    PRIMARY KEY (player_id_from, player_id_to),
    CHECK (player_id_from <> player_id_to)
);

CREATE TABLE guild (
    guild_id              INTEGER PRIMARY KEY,
    guildmaster_player_id INTEGER REFERENCES player(player_id),  -- NULL for the player guild in v1 (disembodied manager)
    display_name          TEXT    NOT NULL,
    is_player_guild       INTEGER NOT NULL DEFAULT 0 CHECK (is_player_guild IN (0, 1)),
    progress_pace         TEXT    CHECK (progress_pace IN ('fast', 'mid', 'slow')),  -- ghost rivals only; NULL for the player guild
    reputation            INTEGER NOT NULL DEFAULT 50,
    guild_morale          INTEGER NOT NULL DEFAULT 50,
    officer_confidence    INTEGER NOT NULL DEFAULT 50,   -- the sacking meter
    fairness_perception   INTEGER NOT NULL DEFAULT 50    -- judged by the loot culture's yardstick
);

CREATE TABLE guild_membership (
    membership_id INTEGER PRIMARY KEY,
    guild_id      INTEGER NOT NULL REFERENCES guild(guild_id),
    player_id     INTEGER NOT NULL REFERENCES player(player_id),
    guild_rank    TEXT,
    status        TEXT NOT NULL DEFAULT 'member'
                  CHECK (status IN ('applicant', 'trial', 'member', 'former')),
    joined_at     TEXT,
    left_at       TEXT                                   -- set by the attrition leave-check, with reason in digest
);
CREATE INDEX ix_membership_guild  ON guild_membership(guild_id, status);
CREATE INDEX ix_membership_player ON guild_membership(player_id);

-- Recruitment fog overlay: per (guild x prospect x attribute) current belief.
-- Truth lives on player; display applies noise scaled by confidence.
CREATE TABLE prospect_assessment (
    guild_id   INTEGER NOT NULL REFERENCES guild(guild_id),
    player_id  INTEGER NOT NULL REFERENCES player(player_id),
    attribute  TEXT    NOT NULL,
    estimate   INTEGER NOT NULL DEFAULT 50,
    confidence INTEGER NOT NULL DEFAULT 0,
    revealed   INTEGER NOT NULL DEFAULT 0 CHECK (revealed IN (0, 1)),
    PRIMARY KEY (guild_id, player_id, attribute)
);
CREATE INDEX ix_prospect_assessment_player ON prospect_assessment(player_id);

-- Equipped gear per (avatar x slot). avatar.gear_score / caps derive from this.
CREATE TABLE avatar_item (
    avatar_id  INTEGER NOT NULL REFERENCES avatar(avatar_id),
    slot_id    INTEGER NOT NULL REFERENCES slot(slot_id),
    item_id    INTEGER NOT NULL REFERENCES loot_item(item_id),
    item_level INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (avatar_id, slot_id)
);
CREATE INDEX ix_avatar_item_item ON avatar_item(item_id);

-- ----------------------------------------------------------------------------
-- 4. Campaign save root, calendar, objectives & raid prep
-- ----------------------------------------------------------------------------
-- Singleton save root: the DB is the save; exactly one row, game_id = 1.
CREATE TABLE game_state (
    game_id      INTEGER PRIMARY KEY CHECK (game_id = 1),
    expansion_id INTEGER REFERENCES expansion(expansion_id),
    season_id    INTEGER REFERENCES season(season_id),
    week_id      INTEGER REFERENCES week(week_id),
    phase        TEXT    NOT NULL DEFAULT 'plan',
    rng_seed     INTEGER NOT NULL,             -- every random draw derives from this (determinism contract)
    created_at   TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE game_config (
    game_id             INTEGER PRIMARY KEY REFERENCES game_state(game_id),
    difficulty          TEXT    NOT NULL DEFAULT 'standard',
    involvement_default TEXT    NOT NULL DEFAULT 'manual'
                        CHECK (involvement_default IN ('manual', 'assisted', 'instant')),
    sack_risk_enabled   INTEGER NOT NULL DEFAULT 1 CHECK (sack_risk_enabled IN (0, 1))
);

CREATE TABLE season_objective (
    objective_id         INTEGER PRIMARY KEY,
    season_id            INTEGER NOT NULL REFERENCES season(season_id),
    objective_type_id    INTEGER NOT NULL REFERENCES objective_type(objective_type_id),
    target               TEXT,
    priority             INTEGER NOT NULL DEFAULT 1,
    is_personal_ambition INTEGER NOT NULL DEFAULT 0 CHECK (is_personal_ambition IN (0, 1)),
    result               TEXT CHECK (result IN ('exceeded', 'met', 'missed', 'failed'))  -- NULL until season-end grading
);
CREATE INDEX ix_season_objective_season ON season_objective(season_id);

-- One scheduled event per (week x day x time_slot). Supersedes RAID_NIGHT:
-- a raid night is event_type = 'raid'. Raid-grain children key off event_id.
CREATE TABLE calendar_event (
    event_id   INTEGER PRIMARY KEY,
    week_id    INTEGER NOT NULL REFERENCES week(week_id),
    raid_id    INTEGER REFERENCES raid(raid_id),        -- set when event_type = 'raid'
    day        INTEGER NOT NULL CHECK (day BETWEEN 1 AND 7),
    time_slot  TEXT    NOT NULL CHECK (time_slot IN ('afternoon', 'evening', 'late')),
    event_type TEXT    NOT NULL CHECK (event_type IN ('raid', 'dungeon', 'rest', 'social')),
    status     TEXT    NOT NULL DEFAULT 'scheduled'
               CHECK (status IN ('scheduled', 'in_progress', 'completed', 'cancelled')),
    UNIQUE (week_id, day, time_slot)
);
CREATE INDEX ix_calendar_event_week ON calendar_event(week_id);

-- Tonight's roster at event grain; pull_participant inherits and can override.
CREATE TABLE raid_lineup (
    event_id   INTEGER NOT NULL REFERENCES calendar_event(event_id),
    avatar_id  INTEGER NOT NULL REFERENCES avatar(avatar_id),
    slot_role  TEXT,                                     -- tank/healer/melee/ranged slot this avatar fills
    is_benched INTEGER NOT NULL DEFAULT 0 CHECK (is_benched IN (0, 1)),  -- bench streaks feed morale/loyalty dings
    PRIMARY KEY (event_id, avatar_id)
);
CREATE INDEX ix_raid_lineup_avatar ON raid_lineup(avatar_id);

-- Tactical plan at event grain. One row per (event, avatar, assignment_type):
-- an avatar can hold e.g. an interrupt duty AND a consumable plan.
CREATE TABLE raid_assignment (
    event_id        INTEGER NOT NULL REFERENCES calendar_event(event_id),
    avatar_id       INTEGER NOT NULL REFERENCES avatar(avatar_id),
    assignment_type TEXT    NOT NULL
                    CHECK (assignment_type IN ('tank', 'heal_focus', 'interrupt', 'soak', 'cooldown', 'consumables')),
    target          TEXT,
    PRIMARY KEY (event_id, avatar_id, assignment_type)
);
CREATE INDEX ix_raid_assignment_avatar ON raid_assignment(avatar_id);

-- Availability roll per (event x player). attendance = availability rate;
-- participation = non-benched lineup rate (derived views, G11).
CREATE TABLE event_availability (
    event_id  INTEGER NOT NULL REFERENCES calendar_event(event_id),
    player_id INTEGER NOT NULL REFERENCES player(player_id),
    available INTEGER NOT NULL DEFAULT 1 CHECK (available IN (0, 1)),
    reason    TEXT,
    PRIMARY KEY (event_id, player_id)
);
CREATE INDEX ix_event_availability_player ON event_availability(player_id);

-- Periodic snapshot of volatile per-player state (conventions: states, not traits).
CREATE TABLE player_week_state (
    player_id INTEGER NOT NULL REFERENCES player(player_id),
    week_id   INTEGER NOT NULL REFERENCES week(week_id),
    morale    INTEGER NOT NULL DEFAULT 50,
    fatigue   INTEGER NOT NULL DEFAULT 0,
    form      INTEGER NOT NULL DEFAULT 50,
    PRIMARY KEY (player_id, week_id)
);
CREATE INDEX ix_player_week_state_week ON player_week_state(week_id);

-- ----------------------------------------------------------------------------
-- 5. Execution facts (the raid-night engine writes these)
-- Raid grain: calendar_event -> pull -> pull_participant / pull_event
-- ----------------------------------------------------------------------------
CREATE TABLE pull (
    pull_id        INTEGER PRIMARY KEY,
    event_id       INTEGER NOT NULL REFERENCES calendar_event(event_id),
    encounter_id   INTEGER NOT NULL REFERENCES encounter(encounter_id),
    attempt_number INTEGER NOT NULL,
    outcome        TEXT    NOT NULL CHECK (outcome IN ('kill', 'wipe')),
    duration_sec   INTEGER,
    wipe_reason    TEXT,                                 -- named check + culprit; NULL on kill (legible failure)
    UNIQUE (event_id, encounter_id, attempt_number)
);
CREATE INDEX ix_pull_event     ON pull(event_id);
CREATE INDEX ix_pull_encounter ON pull(encounter_id);

-- THE core fact: one row per avatar per pull. performance_rating is the
-- output of the resolution formula (1-10 vs expected for gear/role).
CREATE TABLE pull_participant (
    pull_id            INTEGER NOT NULL REFERENCES pull(pull_id),
    avatar_id          INTEGER NOT NULL REFERENCES avatar(avatar_id),
    role_assigned      INTEGER REFERENCES role(role_id),
    assignment_target  TEXT,
    raw_contribution   INTEGER NOT NULL DEFAULT 0,
    performance_rating INTEGER NOT NULL CHECK (performance_rating BETWEEN 1 AND 10),
    PRIMARY KEY (pull_id, avatar_id)
);
CREATE INDEX ix_pull_participant_avatar ON pull_participant(avatar_id);

-- What was actually burned on this pull (G12: explicit consumption transaction;
-- decrements guild_stockpile + writes treasury_ledger on resolve).
CREATE TABLE pull_consumable (
    pull_id       INTEGER NOT NULL REFERENCES pull(pull_id),
    avatar_id     INTEGER NOT NULL REFERENCES avatar(avatar_id),
    consumable_id INTEGER NOT NULL REFERENCES consumable(consumable_id),
    PRIMARY KEY (pull_id, avatar_id, consumable_id)
);

-- Combat-log fact: one row per event that actually fired in a pull.
CREATE TABLE pull_event (
    pull_event_id      INTEGER PRIMARY KEY,
    pull_id            INTEGER NOT NULL REFERENCES pull(pull_id),
    encounter_event_id INTEGER REFERENCES encounter_event(encounter_event_id),
    phase_id           INTEGER REFERENCES encounter_phase(phase_id),
    target_avatar_id   INTEGER REFERENCES avatar(avatar_id),
    sequence_no        INTEGER NOT NULL,
    roll_result        TEXT,
    outcome            TEXT,
    log_line           TEXT,                             -- rendered from event_type.log_template
    UNIQUE (pull_id, sequence_no)
);
CREATE INDEX ix_pull_event_target ON pull_event(target_avatar_id);

-- Learning arc: per (guild x encounter), persists across nights. Rivals
-- advance into this same table -> server standings are a derived view.
CREATE TABLE guild_encounter_progress (
    guild_id         INTEGER NOT NULL REFERENCES guild(guild_id),
    encounter_id     INTEGER NOT NULL REFERENCES encounter(encounter_id),
    progress         INTEGER NOT NULL DEFAULT 0,
    attempt_count    INTEGER NOT NULL DEFAULT 0,
    best_attempt_pct INTEGER NOT NULL DEFAULT 0,
    first_kill_at    TEXT,
    PRIMARY KEY (guild_id, encounter_id)
);
CREATE INDEX ix_guild_encounter_progress_encounter ON guild_encounter_progress(encounter_id);

-- ----------------------------------------------------------------------------
-- 6. Loot, fairness & economy
-- ----------------------------------------------------------------------------
CREATE TABLE loot_drop (
    drop_id              INTEGER PRIMARY KEY,
    pull_id              INTEGER NOT NULL REFERENCES pull(pull_id),
    item_id              INTEGER NOT NULL REFERENCES loot_item(item_id),
    awarded_to_player_id INTEGER REFERENCES player(player_id),  -- NULL = unawarded (-> raid proceeds)
    loot_method          TEXT CHECK (loot_method IN ('council', 'dkp', 'roll'))
);
CREATE INDEX ix_loot_drop_pull    ON loot_drop(pull_id);
CREATE INDEX ix_loot_drop_item    ON loot_drop(item_id);
CREATE INDEX ix_loot_drop_awarded ON loot_drop(awarded_to_player_id);

-- Per-guild standing config (v0.8 merge): active loot culture + economy policies.
CREATE TABLE guild_config (
    guild_id           INTEGER PRIMARY KEY REFERENCES guild(guild_id),
    active_loot_system TEXT NOT NULL DEFAULT 'council'
                       CHECK (active_loot_system IN ('council', 'dkp', 'roll')),
    loot_config_params TEXT,                             -- JSON params for the active policy
    provision_policy   TEXT NOT NULL DEFAULT 'subsidized'
                       CHECK (provision_policy IN ('guild_funded', 'subsidized', 'byo')),
    contribution_policy TEXT NOT NULL DEFAULT 'suggested'
                       CHECK (contribution_policy IN ('mandatory', 'suggested', 'voluntary')),
    repair_policy      TEXT NOT NULL DEFAULT 'not_covered'
                       CHECK (repair_policy IN ('guild_covered', 'not_covered'))
);

-- Points ledger for economy loot systems (DKP in v1; EPGP is v1.1).
CREATE TABLE player_loot_standing (
    guild_id       INTEGER NOT NULL REFERENCES guild(guild_id),
    player_id      INTEGER NOT NULL REFERENCES player(player_id),
    standing_type  TEXT    NOT NULL DEFAULT 'dkp' CHECK (standing_type IN ('dkp', 'epgp')),
    standing_value INTEGER NOT NULL DEFAULT 0,
    updated_at     TEXT,
    PRIMARY KEY (guild_id, player_id, standing_type)
);

-- Per-drop decision context: one row per eligible claimant, snapshotting the
-- 7 factors. The audit trail that powers loot history + drama.
CREATE TABLE loot_claim (
    claim_id            INTEGER PRIMARY KEY,
    drop_id             INTEGER NOT NULL REFERENCES loot_drop(drop_id),
    player_id           INTEGER NOT NULL REFERENCES player(player_id),
    upgrade_magnitude   INTEGER NOT NULL DEFAULT 0,      -- factor 1
    perf_snapshot       INTEGER NOT NULL DEFAULT 0,      -- factor 2: recent performance
    loyalty_snapshot    INTEGER NOT NULL DEFAULT 0,      -- factor 3: loyalty/tenure
    attendance_snapshot INTEGER NOT NULL DEFAULT 0,      -- factor 4
    spec_priority       TEXT,                            -- factor 5
    progression_need    INTEGER NOT NULL DEFAULT 0 CHECK (progression_need IN (0, 1)),  -- factor 6
    drought_weeks       INTEGER NOT NULL DEFAULT 0,      -- factor 7
    was_awarded         INTEGER NOT NULL DEFAULT 0 CHECK (was_awarded IN (0, 1)),
    UNIQUE (drop_id, player_id)
);
CREATE INDEX ix_loot_claim_player ON loot_claim(player_id);

CREATE TABLE guild_treasury (
    guild_id INTEGER PRIMARY KEY REFERENCES guild(guild_id),
    gold     INTEGER NOT NULL DEFAULT 0,
    mats     INTEGER NOT NULL DEFAULT 0                  -- abstract scalar in v1 (itemized mats are v1.1)
);

CREATE TABLE guild_stockpile (
    guild_id      INTEGER NOT NULL REFERENCES guild(guild_id),
    consumable_id INTEGER NOT NULL REFERENCES consumable(consumable_id),
    quantity      INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    PRIMARY KEY (guild_id, consumable_id)
);

-- Every income/expense event. Nothing moves gold/mats without a ledger row
-- (observability is gameplay tooling). amount is signed: + income, - expense.
CREATE TABLE treasury_ledger (
    ledger_id        INTEGER PRIMARY KEY,
    guild_id         INTEGER NOT NULL REFERENCES guild(guild_id),
    week_id          INTEGER REFERENCES week(week_id),
    txn_type         TEXT    NOT NULL
                     CHECK (txn_type IN ('donation', 'proceeds', 'farming', 'provision', 'repair', 'purchase', 'conversion')),
    resource_type    TEXT    NOT NULL CHECK (resource_type IN ('gold', 'mats', 'consumable')),
    amount           INTEGER NOT NULL,
    source_player_id INTEGER REFERENCES player(player_id),  -- set for donations
    created_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX ix_treasury_ledger_guild_week ON treasury_ledger(guild_id, week_id);

-- The weekly plan as data: one row per resolved management action.
CREATE TABLE week_action (
    action_id      INTEGER PRIMARY KEY,
    guild_id       INTEGER NOT NULL REFERENCES guild(guild_id),
    week_id        INTEGER NOT NULL REFERENCES week(week_id),
    action_type_id INTEGER NOT NULL REFERENCES action_type(action_type_id),
    lane           TEXT    NOT NULL CHECK (lane IN ('gearing', 'development', 'supply', 'people', 'rest')),
    target_ref     TEXT,                                 -- polymorphic: player/avatar/consumable the action targets
    time_cost      INTEGER NOT NULL DEFAULT 0,
    output_type    TEXT,
    output_qty     INTEGER,
    outcome        TEXT,
    UNIQUE (guild_id, week_id, action_type_id, target_ref)
);
CREATE INDEX ix_week_action_guild_week ON week_action(guild_id, week_id);
