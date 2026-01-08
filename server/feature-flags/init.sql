-- UnaMentis Feature Flag Database Initialization
-- This script runs on first PostgreSQL startup

-- Unleash creates its own tables, but we add custom metadata tracking

-- Extension for UUID generation (if not exists)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Custom table for flag lifecycle metadata
-- Unleash doesn't track ownership/expiration natively
CREATE TABLE IF NOT EXISTS flag_metadata (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    flag_name VARCHAR(255) NOT NULL UNIQUE,
    owner VARCHAR(255) NOT NULL,           -- GitHub username of flag owner
    description TEXT,                       -- Purpose of the flag
    category VARCHAR(50) NOT NULL DEFAULT 'release',  -- release, experiment, ops, permission
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    target_removal_date DATE,              -- When flag should be removed
    last_reviewed_at TIMESTAMP WITH TIME ZONE,
    review_notes TEXT,
    jira_ticket VARCHAR(50),               -- Optional: linked ticket
    is_permanent BOOLEAN DEFAULT FALSE,    -- For ops/permission flags
    CONSTRAINT valid_category CHECK (category IN ('release', 'experiment', 'ops', 'permission'))
);

-- Index for querying overdue flags
CREATE INDEX IF NOT EXISTS idx_flag_metadata_removal_date
    ON flag_metadata(target_removal_date)
    WHERE target_removal_date IS NOT NULL AND is_permanent = FALSE;

-- Index for querying by owner
CREATE INDEX IF NOT EXISTS idx_flag_metadata_owner
    ON flag_metadata(owner);

-- Table for flag usage analytics (aggregated)
CREATE TABLE IF NOT EXISTS flag_usage_stats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    flag_name VARCHAR(255) NOT NULL,
    date DATE NOT NULL,
    platform VARCHAR(50) NOT NULL,         -- ios, web, server
    evaluation_count BIGINT DEFAULT 0,
    true_count BIGINT DEFAULT 0,
    false_count BIGINT DEFAULT 0,
    unique_users BIGINT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(flag_name, date, platform)
);

-- Index for querying usage by flag
CREATE INDEX IF NOT EXISTS idx_flag_usage_stats_flag
    ON flag_usage_stats(flag_name, date DESC);

-- View for flags needing attention
CREATE OR REPLACE VIEW flags_needing_review AS
SELECT
    fm.flag_name,
    fm.owner,
    fm.category,
    fm.target_removal_date,
    fm.last_reviewed_at,
    CASE
        WHEN fm.is_permanent THEN 'permanent'
        WHEN fm.target_removal_date < CURRENT_DATE THEN 'overdue'
        WHEN fm.target_removal_date < CURRENT_DATE + INTERVAL '14 days' THEN 'due_soon'
        WHEN fm.last_reviewed_at IS NULL THEN 'never_reviewed'
        WHEN fm.last_reviewed_at < CURRENT_DATE - INTERVAL '30 days' THEN 'needs_review'
        ELSE 'ok'
    END AS status,
    fm.target_removal_date - CURRENT_DATE AS days_until_removal
FROM flag_metadata fm
WHERE fm.is_permanent = FALSE
ORDER BY
    CASE
        WHEN fm.target_removal_date < CURRENT_DATE THEN 0
        WHEN fm.target_removal_date < CURRENT_DATE + INTERVAL '14 days' THEN 1
        ELSE 2
    END,
    fm.target_removal_date NULLS LAST;

-- Function to register a new flag with metadata
CREATE OR REPLACE FUNCTION register_flag(
    p_flag_name VARCHAR(255),
    p_owner VARCHAR(255),
    p_description TEXT,
    p_category VARCHAR(50) DEFAULT 'release',
    p_target_removal_days INTEGER DEFAULT 30,
    p_is_permanent BOOLEAN DEFAULT FALSE,
    p_jira_ticket VARCHAR(50) DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO flag_metadata (
        flag_name, owner, description, category,
        target_removal_date, is_permanent, jira_ticket
    ) VALUES (
        p_flag_name, p_owner, p_description, p_category,
        CASE WHEN p_is_permanent THEN NULL ELSE CURRENT_DATE + p_target_removal_days END,
        p_is_permanent, p_jira_ticket
    )
    ON CONFLICT (flag_name) DO UPDATE SET
        owner = EXCLUDED.owner,
        description = EXCLUDED.description,
        last_reviewed_at = NOW()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Function to mark a flag as reviewed
CREATE OR REPLACE FUNCTION review_flag(
    p_flag_name VARCHAR(255),
    p_notes TEXT DEFAULT NULL,
    p_extend_days INTEGER DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    UPDATE flag_metadata
    SET
        last_reviewed_at = NOW(),
        review_notes = COALESCE(p_notes, review_notes),
        target_removal_date = CASE
            WHEN p_extend_days IS NOT NULL AND NOT is_permanent
            THEN GREATEST(target_removal_date, CURRENT_DATE) + p_extend_days
            ELSE target_removal_date
        END
    WHERE flag_name = p_flag_name;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Sample flags for initial setup (commented out - uncomment for testing)
-- SELECT register_flag('new_voice_engine', 'ramerman', 'New voice processing engine', 'release', 30);
-- SELECT register_flag('dark_mode', 'ramerman', 'Dark mode UI theme', 'release', 60);
-- SELECT register_flag('maintenance_mode', 'ramerman', 'Enable maintenance mode', 'ops', 0, TRUE);

-- Grant permissions (Unleash user needs access)
-- Using least-privilege principle: only grant what's necessary for operations
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO unleash;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO unleash;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO unleash;
