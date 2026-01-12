-- ============================================================================
-- UMCF (Una Mentis Curriculum Format) Normalized Database Schema
-- PostgreSQL 15+ with pg_trgm and pg_search (ParadeDB) extensions
-- ============================================================================
--
-- Architecture: Normalized tables with JSON export capability
-- - Granular editing: Each piece of content in its own table
-- - Fast queries: Indexed metadata columns
-- - JSON export: Rebuild full UMCF documents on demand
-- - Full-text search: Using pg_trgm for fuzzy matching
--
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Curricula: Top-level container for a learning curriculum
CREATE TABLE curricula (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id VARCHAR(255) UNIQUE,  -- The UMCF id.value field
    catalog VARCHAR(100),              -- The UMCF id.catalog field

    -- Core metadata
    title VARCHAR(500) NOT NULL,
    description TEXT,

    -- Version info
    version_number VARCHAR(50) DEFAULT '1.0.0',
    version_date TIMESTAMPTZ,
    version_changelog TEXT,

    -- Lifecycle
    lifecycle_status VARCHAR(50) DEFAULT 'draft',  -- draft, review, final, deprecated
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Educational context (denormalized for fast queries)
    difficulty VARCHAR(50),            -- easy, medium, difficult
    age_range VARCHAR(50),             -- e.g., "18+", "12-14"
    typical_learning_time VARCHAR(50), -- ISO 8601 duration, e.g., "PT4H"
    language VARCHAR(10) DEFAULT 'en-US',

    -- Search optimization
    keywords TEXT[],                   -- Array of keywords for filtering
    subjects TEXT[],                   -- Subject areas

    -- JSON cache for fast export (rebuilt on changes via trigger)
    json_cache JSONB,
    json_cache_updated_at TIMESTAMPTZ,

    -- Indexes for search
    search_vector tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(array_to_string(keywords, ' '), '')), 'C')
    ) STORED
);

CREATE INDEX idx_curricula_search ON curricula USING GIN(search_vector);
CREATE INDEX idx_curricula_keywords ON curricula USING GIN(keywords);
CREATE INDEX idx_curricula_difficulty ON curricula(difficulty);
CREATE INDEX idx_curricula_status ON curricula(lifecycle_status);
CREATE INDEX idx_curricula_updated ON curricula(updated_at DESC);

-- Contributors to a curriculum
CREATE TABLE curriculum_contributors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    curriculum_id UUID NOT NULL REFERENCES curricula(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    role VARCHAR(100) NOT NULL,  -- author, editor, reviewer, subject matter expert
    organization VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_contributors_curriculum ON curriculum_contributors(curriculum_id);

-- Educational alignment (standards, frameworks)
CREATE TABLE curriculum_alignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    curriculum_id UUID NOT NULL REFERENCES curricula(id) ON DELETE CASCADE,
    alignment_type VARCHAR(50),      -- teaches, requires, assesses
    framework_name VARCHAR(255),     -- e.g., "Common Core", "ACM Computing Curricula"
    target_name VARCHAR(500),
    target_description TEXT,
    target_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_alignments_curriculum ON curriculum_alignments(curriculum_id);

-- Prerequisites for a curriculum
CREATE TABLE curriculum_prerequisites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    curriculum_id UUID NOT NULL REFERENCES curricula(id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    prerequisite_type VARCHAR(50),   -- knowledge, skill, course
    is_required BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_prerequisites_curriculum ON curriculum_prerequisites(curriculum_id);

-- ============================================================================
-- CONTENT HIERARCHY
-- ============================================================================

-- Topics: Main content units within a curriculum (can be nested)
CREATE TABLE topics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id VARCHAR(255),         -- The UMCF id.value field
    curriculum_id UUID NOT NULL REFERENCES curricula(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES topics(id) ON DELETE CASCADE,  -- For nested topics

    -- Core info
    title VARCHAR(500) NOT NULL,
    description TEXT,
    content_type VARCHAR(50) DEFAULT 'topic',  -- unit, topic, subtopic, lesson
    order_index INTEGER DEFAULT 0,

    -- Time estimates by depth level
    time_overview VARCHAR(50),
    time_introductory VARCHAR(50),
    time_intermediate VARCHAR(50),
    time_advanced VARCHAR(50),
    time_graduate VARCHAR(50),
    time_research VARCHAR(50),

    -- Tutoring configuration
    content_depth VARCHAR(50),         -- overview, introductory, intermediate, etc.
    interaction_mode VARCHAR(50),      -- lecture, socratic, guided, exploratory
    checkpoint_frequency VARCHAR(50),  -- high, medium, low

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Search
    search_vector tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(description, '')), 'B')
    ) STORED
);

CREATE INDEX idx_topics_curriculum ON topics(curriculum_id);
CREATE INDEX idx_topics_parent ON topics(parent_id);
CREATE INDEX idx_topics_order ON topics(curriculum_id, order_index);
CREATE INDEX idx_topics_search ON topics USING GIN(search_vector);

-- Learning objectives for a topic
CREATE TABLE learning_objectives (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id VARCHAR(255),
    topic_id UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,

    statement TEXT NOT NULL,
    abbreviated_statement VARCHAR(500),
    blooms_level VARCHAR(50),  -- remember, understand, apply, analyze, evaluate, create
    order_index INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_objectives_topic ON learning_objectives(topic_id);

-- ============================================================================
-- TRANSCRIPT CONTENT
-- ============================================================================

-- Transcript segments: Individual speakable content pieces
CREATE TABLE transcript_segments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    segment_id VARCHAR(255),          -- The original segment ID from UMCF
    topic_id UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,

    -- Content
    segment_type VARCHAR(50) NOT NULL,  -- introduction, explanation, example, analogy, summary, checkpoint, transition
    content TEXT NOT NULL,
    order_index INTEGER DEFAULT 0,

    -- Speaking notes
    pace VARCHAR(50),                  -- slow, moderate, normal, brisk
    emotional_tone VARCHAR(50),        -- enthusiastic, thoughtful, encouraging, serious
    pause_after VARCHAR(50),           -- e.g., "1s", "2s"
    emphasis_words TEXT[],             -- Words to emphasize
    pronunciations JSONB,              -- {"word": "pronunciation"} map

    -- Checkpoint info (if segment_type = 'checkpoint')
    checkpoint_type VARCHAR(50),       -- comprehension, reflection, recall
    checkpoint_question TEXT,
    expected_response_type VARCHAR(50),
    expected_keywords TEXT[],
    expected_patterns TEXT[],
    celebration_message TEXT,

    -- Stopping point info
    stopping_point_type VARCHAR(50),
    prompt_for_continue BOOLEAN DEFAULT false,
    suggested_prompt TEXT,

    -- Glossary references
    glossary_refs TEXT[],              -- Array of glossary term IDs

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Full-text search on content
    search_vector tsvector GENERATED ALWAYS AS (
        to_tsvector('english', coalesce(content, ''))
    ) STORED
);

CREATE INDEX idx_segments_topic ON transcript_segments(topic_id);
CREATE INDEX idx_segments_order ON transcript_segments(topic_id, order_index);
CREATE INDEX idx_segments_type ON transcript_segments(segment_type);
CREATE INDEX idx_segments_search ON transcript_segments USING GIN(search_vector);

-- Alternative explanations for a segment
CREATE TABLE alternative_explanations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    segment_id UUID NOT NULL REFERENCES transcript_segments(id) ON DELETE CASCADE,

    style VARCHAR(50),                 -- simpler, technical, analogy, visual
    content TEXT NOT NULL,
    order_index INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_alternatives_segment ON alternative_explanations(segment_id);

-- ============================================================================
-- EDUCATIONAL CONTENT
-- ============================================================================

-- Glossary terms: Vocabulary definitions
CREATE TABLE glossary_terms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    term_id VARCHAR(255),             -- The original term ID from UMCF
    curriculum_id UUID NOT NULL REFERENCES curricula(id) ON DELETE CASCADE,

    term VARCHAR(255) NOT NULL,
    pronunciation VARCHAR(255),
    definition TEXT,
    spoken_definition TEXT,           -- TTS-friendly definition
    simple_definition TEXT,           -- For younger audiences

    examples TEXT[],
    related_terms TEXT[],             -- References to other term_ids

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Search
    search_vector tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(term, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(definition, '')), 'B')
    ) STORED
);

CREATE INDEX idx_glossary_curriculum ON glossary_terms(curriculum_id);
CREATE INDEX idx_glossary_term ON glossary_terms(term);
CREATE INDEX idx_glossary_search ON glossary_terms USING GIN(search_vector);

-- Examples for a topic
CREATE TABLE examples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id VARCHAR(255),
    topic_id UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,

    example_type VARCHAR(50),          -- real_world, analogy, worked_problem, counter_example
    title VARCHAR(500),
    content TEXT NOT NULL,
    explanation TEXT,
    order_index INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_examples_topic ON examples(topic_id);

-- Misconceptions: Common misunderstandings to address
CREATE TABLE misconceptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id VARCHAR(255),
    topic_id UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,

    triggers TEXT[],                   -- Phrases that indicate this misconception
    misconception TEXT NOT NULL,       -- The incorrect belief
    correction TEXT NOT NULL,          -- The correct understanding
    explanation TEXT,                  -- Why this misconception occurs
    order_index INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_misconceptions_topic ON misconceptions(topic_id);
CREATE INDEX idx_misconceptions_triggers ON misconceptions USING GIN(triggers);

-- Assessments: Questions and quizzes
CREATE TABLE assessments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    external_id VARCHAR(255),
    topic_id UUID NOT NULL REFERENCES topics(id) ON DELETE CASCADE,

    assessment_type VARCHAR(50),       -- multiple_choice, text_entry, verbal, true_false
    question TEXT NOT NULL,
    correct_answer TEXT,
    hint TEXT,

    -- Feedback messages
    feedback_correct TEXT,
    feedback_incorrect TEXT,
    feedback_partial TEXT,

    order_index INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_assessments_topic ON assessments(topic_id);

-- Assessment options (for multiple choice)
CREATE TABLE assessment_options (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    assessment_id UUID NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,

    option_id VARCHAR(50),             -- e.g., "a", "b", "c"
    option_text TEXT NOT NULL,
    is_correct BOOLEAN DEFAULT false,
    order_index INTEGER DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_options_assessment ON assessment_options(assessment_id);

-- ============================================================================
-- FUNCTIONS FOR JSON EXPORT
-- ============================================================================

-- Function to build full UMCF JSON for a curriculum
CREATE OR REPLACE FUNCTION build_umcf_json(p_curriculum_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_result JSONB;
    v_curriculum RECORD;
    v_topics JSONB;
    v_glossary JSONB;
BEGIN
    -- Get curriculum
    SELECT * INTO v_curriculum FROM curricula WHERE id = p_curriculum_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Build topics array with nested content
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', jsonb_build_object('catalog', 'UUID', 'value', t.external_id),
            'title', t.title,
            'type', t.content_type,
            'orderIndex', t.order_index,
            'description', t.description,
            'timeEstimates', jsonb_build_object(
                'overview', t.time_overview,
                'introductory', t.time_introductory,
                'intermediate', t.time_intermediate,
                'advanced', t.time_advanced,
                'graduate', t.time_graduate,
                'research', t.time_research
            ),
            'tutoringConfig', jsonb_build_object(
                'contentDepth', t.content_depth,
                'interactionMode', t.interaction_mode,
                'checkpointFrequency', t.checkpoint_frequency
            ),
            'learningObjectives', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', jsonb_build_object('catalog', 'UUID', 'value', lo.external_id),
                        'statement', lo.statement,
                        'abbreviatedStatement', lo.abbreviated_statement,
                        'bloomsLevel', lo.blooms_level
                    ) ORDER BY lo.order_index
                )
                FROM learning_objectives lo
                WHERE lo.topic_id = t.id
            ),
            'transcript', jsonb_build_object(
                'segments', (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'id', ts.segment_id,
                            'type', ts.segment_type,
                            'content', ts.content,
                            'speakingNotes', CASE WHEN ts.pace IS NOT NULL THEN
                                jsonb_build_object(
                                    'pace', ts.pace,
                                    'emotionalTone', ts.emotional_tone,
                                    'pauseAfter', ts.pause_after,
                                    'emphasis', ts.emphasis_words,
                                    'pronunciation', ts.pronunciations
                                )
                            ELSE NULL END,
                            'checkpoint', CASE WHEN ts.checkpoint_type IS NOT NULL THEN
                                jsonb_build_object(
                                    'type', ts.checkpoint_type,
                                    'question', ts.checkpoint_question,
                                    'expectedResponse', jsonb_build_object(
                                        'type', ts.expected_response_type,
                                        'keywords', ts.expected_keywords,
                                        'acceptablePatterns', ts.expected_patterns
                                    ),
                                    'celebrationMessage', ts.celebration_message
                                )
                            ELSE NULL END,
                            'stoppingPoint', CASE WHEN ts.stopping_point_type IS NOT NULL THEN
                                jsonb_build_object(
                                    'type', ts.stopping_point_type,
                                    'promptForContinue', ts.prompt_for_continue,
                                    'suggestedPrompt', ts.suggested_prompt
                                )
                            ELSE NULL END,
                            'glossaryRefs', ts.glossary_refs,
                            'alternativeExplanations', (
                                SELECT jsonb_agg(
                                    jsonb_build_object(
                                        'style', ae.style,
                                        'content', ae.content
                                    ) ORDER BY ae.order_index
                                )
                                FROM alternative_explanations ae
                                WHERE ae.segment_id = ts.id
                            )
                        ) ORDER BY ts.order_index
                    )
                    FROM transcript_segments ts
                    WHERE ts.topic_id = t.id
                )
            ),
            'examples', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', jsonb_build_object('catalog', 'UUID', 'value', e.external_id),
                        'type', e.example_type,
                        'title', e.title,
                        'content', e.content,
                        'explanation', e.explanation
                    ) ORDER BY e.order_index
                )
                FROM examples e
                WHERE e.topic_id = t.id
            ),
            'misconceptions', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', jsonb_build_object('catalog', 'UUID', 'value', m.external_id),
                        'trigger', m.triggers,
                        'misconception', m.misconception,
                        'correction', m.correction,
                        'explanation', m.explanation
                    ) ORDER BY m.order_index
                )
                FROM misconceptions m
                WHERE m.topic_id = t.id
            ),
            'assessments', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', jsonb_build_object('catalog', 'UUID', 'value', a.external_id),
                        'type', a.assessment_type,
                        'question', a.question,
                        'correctAnswer', a.correct_answer,
                        'hint', a.hint,
                        'feedback', jsonb_build_object(
                            'correct', a.feedback_correct,
                            'incorrect', a.feedback_incorrect,
                            'partial', a.feedback_partial
                        ),
                        'options', (
                            SELECT jsonb_agg(
                                jsonb_build_object(
                                    'id', ao.option_id,
                                    'text', ao.option_text,
                                    'isCorrect', ao.is_correct
                                ) ORDER BY ao.order_index
                            )
                            FROM assessment_options ao
                            WHERE ao.assessment_id = a.id
                        )
                    ) ORDER BY a.order_index
                )
                FROM assessments a
                WHERE a.topic_id = t.id
            )
        ) ORDER BY t.order_index
    )
    INTO v_topics
    FROM topics t
    WHERE t.curriculum_id = p_curriculum_id AND t.parent_id IS NULL;

    -- Build glossary
    SELECT jsonb_build_object(
        'terms', jsonb_agg(
            jsonb_build_object(
                'id', gt.term_id,
                'term', gt.term,
                'pronunciation', gt.pronunciation,
                'definition', gt.definition,
                'spokenDefinition', gt.spoken_definition,
                'simpleDefinition', gt.simple_definition,
                'examples', gt.examples,
                'relatedTerms', gt.related_terms
            )
        )
    )
    INTO v_glossary
    FROM glossary_terms gt
    WHERE gt.curriculum_id = p_curriculum_id;

    -- Build full UMCF document
    v_result := jsonb_build_object(
        'umcf', '1.0.0',
        'id', jsonb_build_object(
            'catalog', v_curriculum.catalog,
            'value', v_curriculum.external_id
        ),
        'title', v_curriculum.title,
        'description', v_curriculum.description,
        'version', jsonb_build_object(
            'number', v_curriculum.version_number,
            'date', v_curriculum.version_date,
            'changelog', v_curriculum.version_changelog
        ),
        'lifecycle', jsonb_build_object(
            'status', v_curriculum.lifecycle_status,
            'created', v_curriculum.created_at,
            'modified', v_curriculum.updated_at,
            'contributors', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'name', cc.name,
                        'role', cc.role,
                        'organization', cc.organization
                    )
                )
                FROM curriculum_contributors cc
                WHERE cc.curriculum_id = p_curriculum_id
            )
        ),
        'metadata', jsonb_build_object(
            'language', v_curriculum.language,
            'keywords', v_curriculum.keywords,
            'subject', v_curriculum.subjects
        ),
        'educational', jsonb_build_object(
            'difficulty', v_curriculum.difficulty,
            'typicalAgeRange', v_curriculum.age_range,
            'typicalLearningTime', v_curriculum.typical_learning_time,
            'alignment', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'alignmentType', ca.alignment_type,
                        'educationalFramework', ca.framework_name,
                        'targetName', ca.target_name,
                        'targetDescription', ca.target_description,
                        'targetUrl', ca.target_url
                    )
                )
                FROM curriculum_alignments ca
                WHERE ca.curriculum_id = p_curriculum_id
            ),
            'prerequisites', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'description', cp.description,
                        'type', cp.prerequisite_type,
                        'required', cp.is_required
                    )
                )
                FROM curriculum_prerequisites cp
                WHERE cp.curriculum_id = p_curriculum_id
            )
        ),
        'content', COALESCE(v_topics, '[]'::jsonb),
        'glossary', COALESCE(v_glossary, jsonb_build_object('terms', '[]'::jsonb))
    );

    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- Function to update JSON cache
CREATE OR REPLACE FUNCTION update_curriculum_json_cache()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the curriculum's JSON cache
    UPDATE curricula
    SET json_cache = build_umcf_json(NEW.curriculum_id),
        json_cache_updated_at = NOW()
    WHERE id = NEW.curriculum_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers to update JSON cache when content changes
CREATE TRIGGER trg_update_cache_on_topic_change
    AFTER INSERT OR UPDATE OR DELETE ON topics
    FOR EACH ROW
    EXECUTE FUNCTION update_curriculum_json_cache();

CREATE TRIGGER trg_update_cache_on_segment_change
    AFTER INSERT OR UPDATE OR DELETE ON transcript_segments
    FOR EACH ROW
    EXECUTE FUNCTION update_curriculum_json_cache();

CREATE TRIGGER trg_update_cache_on_objective_change
    AFTER INSERT OR UPDATE OR DELETE ON learning_objectives
    FOR EACH ROW
    EXECUTE FUNCTION update_curriculum_json_cache();

-- ============================================================================
-- HELPER VIEWS
-- ============================================================================

-- View for curriculum summaries (fast listing)
CREATE VIEW curriculum_summaries AS
SELECT
    c.id,
    c.external_id,
    c.title,
    c.description,
    c.version_number,
    c.difficulty,
    c.age_range,
    c.typical_learning_time,
    c.keywords,
    c.lifecycle_status,
    c.updated_at,
    (SELECT COUNT(*) FROM topics t WHERE t.curriculum_id = c.id) as topic_count,
    (SELECT COUNT(*) FROM glossary_terms gt WHERE gt.curriculum_id = c.id) as glossary_count,
    (SELECT COUNT(*) FROM transcript_segments ts
     JOIN topics t ON ts.topic_id = t.id
     WHERE t.curriculum_id = c.id) as segment_count
FROM curricula c;

-- View for topic details with segment counts
CREATE VIEW topic_details AS
SELECT
    t.id,
    t.external_id,
    t.curriculum_id,
    t.title,
    t.description,
    t.content_type,
    t.order_index,
    t.content_depth,
    (SELECT COUNT(*) FROM transcript_segments ts WHERE ts.topic_id = t.id) as segment_count,
    (SELECT COUNT(*) FROM assessments a WHERE a.topic_id = t.id) as assessment_count,
    (SELECT COUNT(*) FROM examples e WHERE e.topic_id = t.id) as example_count,
    EXISTS(SELECT 1 FROM transcript_segments ts WHERE ts.topic_id = t.id) as has_transcript
FROM topics t;

-- ============================================================================
-- SAMPLE DATA (for testing)
-- ============================================================================

-- Insert a sample curriculum for testing
-- (This would be populated by importing existing UMCF files)

COMMENT ON TABLE curricula IS 'Top-level curriculum containers for UMCF documents';
COMMENT ON TABLE topics IS 'Hierarchical content units within a curriculum';
COMMENT ON TABLE transcript_segments IS 'Individual speakable content pieces with TTS metadata';
COMMENT ON TABLE glossary_terms IS 'Vocabulary definitions for a curriculum';
COMMENT ON TABLE assessments IS 'Questions and quizzes for learner assessment';
COMMENT ON FUNCTION build_umcf_json IS 'Reconstructs full UMCF JSON from normalized tables';

-- ============================================================================
-- USER MANAGEMENT AND AUTHENTICATION
-- ============================================================================
--
-- Architecture: User management with privacy tiers
--
-- OPEN SOURCE (Free):
-- - Users: Individual accounts with role-based access
-- - Devices: Multi-device support per user
-- - Sessions: Token-based authentication with refresh rotation
-- - Consent: GDPR/COPPA compliant consent tracking
-- - Audit: SOC2-ready audit logging
-- - Privacy Tiers: Configurable data handling
--
-- ENTERPRISE EXTENSION POINTS (Commercial Add-on):
-- - Organizations: Multi-tenant support for schools/institutions
-- - Organization Memberships: User-to-org role management
-- - Guardian Relationships: Parent/guardian linking for minors
-- - SSO Configuration: SAML/OIDC/LDAP integration
-- - Advanced RBAC: Fine-grained permissions per organization
--
-- Note: Users work independently by default (organization_id is null).
-- Enterprise plugins enable multi-tenant features by populating organizations
-- and linking users to them.
--
-- ============================================================================

-- Enable pgcrypto for password hashing
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- PRIVACY TIERS
-- ============================================================================

-- Privacy tier configurations
CREATE TABLE privacy_tiers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tier_type VARCHAR(20) NOT NULL UNIQUE CHECK (tier_type IN ('minimal', 'standard', 'comprehensive')),
    display_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_system_default BOOLEAN DEFAULT false,

    -- Feature flags
    allow_progress_sync BOOLEAN DEFAULT false,
    allow_analytics BOOLEAN DEFAULT false,
    allow_performance_tracking BOOLEAN DEFAULT false,
    allow_progress_sharing BOOLEAN DEFAULT false,
    require_session_logging BOOLEAN DEFAULT false,

    -- Retention
    retention_days_min INTEGER DEFAULT 0,
    retention_days_max INTEGER DEFAULT 365,

    -- Compliance
    require_audit_trail BOOLEAN DEFAULT false,
    require_data_portability BOOLEAN DEFAULT true,
    allow_erasure BOOLEAN DEFAULT true,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed default privacy tiers
INSERT INTO privacy_tiers (tier_type, display_name, description, is_system_default,
    allow_progress_sync, allow_analytics, allow_performance_tracking, allow_progress_sharing,
    require_session_logging, retention_days_min, retention_days_max,
    require_audit_trail, require_data_portability, allow_erasure) VALUES
('minimal', 'Privacy-First', 'Maximum privacy, all data on-device only', false,
    false, false, false, false, false, 0, 30, false, true, true),
('standard', 'Standard', 'Balanced privacy with optional syncing', true,
    true, true, true, true, false, 30, 365, false, true, true),
('comprehensive', 'Institutional', 'Full compliance for educational institutions', false,
    true, true, true, true, true, 90, 2555, true, true, false);

-- ============================================================================
-- ORGANIZATIONS (Multi-tenancy) - ENTERPRISE EXTENSION POINT
-- ============================================================================
-- This table and related organization features are extension points for the
-- enterprise commercial add-on. The open source version operates with users
-- having organization_id = NULL (personal accounts).

CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Identity
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    external_id VARCHAR(255) UNIQUE,

    -- Contact
    domain VARCHAR(255),
    contact_email VARCHAR(255),

    -- Type and tier
    org_type VARCHAR(50) DEFAULT 'personal' CHECK (org_type IN (
        'personal', 'school', 'district', 'university', 'enterprise', 'homeschool_coop'
    )),
    subscription_tier VARCHAR(50) DEFAULT 'free' CHECK (subscription_tier IN (
        'free', 'basic', 'pro', 'enterprise'
    )),
    privacy_tier_id UUID REFERENCES privacy_tiers(id),

    -- Location (for jurisdiction)
    country_code CHAR(2),
    region_code VARCHAR(10),

    -- SSO Configuration (Commercial Plugin Extension Point)
    sso_provider VARCHAR(50),
    sso_config JSONB,

    -- Legal/Compliance
    is_educational BOOLEAN DEFAULT false,
    dpa_signed_at TIMESTAMPTZ,
    dpa_version VARCHAR(20),
    dpo_email VARCHAR(255),

    -- Hierarchy (for districts)
    parent_organization_id UUID REFERENCES organizations(id),

    -- Settings (extensible JSON)
    settings JSONB DEFAULT '{}',

    -- Status
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Metadata
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX idx_organizations_slug ON organizations(slug);
CREATE INDEX idx_organizations_domain ON organizations(domain);
CREATE INDEX idx_organizations_type ON organizations(org_type);
CREATE INDEX idx_organizations_parent ON organizations(parent_organization_id);
CREATE INDEX idx_organizations_active ON organizations(is_active) WHERE is_active = true;

-- ============================================================================
-- USERS
-- ============================================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Organization relationship (null = personal account)
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,

    -- Identity
    email VARCHAR(255) NOT NULL,
    email_verified BOOLEAN DEFAULT false,
    email_verified_at TIMESTAMPTZ,
    external_id VARCHAR(255),

    -- Authentication
    password_hash VARCHAR(255),
    password_updated_at TIMESTAMPTZ,

    -- Profile
    display_name VARCHAR(255),
    avatar_url TEXT,
    locale VARCHAR(10) DEFAULT 'en-US',
    timezone VARCHAR(50) DEFAULT 'UTC',

    -- Age/Minor status (for COPPA)
    date_of_birth DATE,
    is_minor BOOLEAN,
    age_verified_at TIMESTAMPTZ,

    -- Role and permissions
    role VARCHAR(50) DEFAULT 'user' CHECK (role IN (
        'user', 'admin', 'org_admin', 'super_admin'
    )),
    permissions JSONB DEFAULT '[]',

    -- Status
    is_active BOOLEAN DEFAULT true,
    is_locked BOOLEAN DEFAULT false,
    locked_at TIMESTAMPTZ,
    locked_reason TEXT,

    -- OAuth/SSO tracking
    auth_providers JSONB DEFAULT '[]',

    -- MFA
    mfa_enabled BOOLEAN DEFAULT false,
    mfa_secret VARCHAR(255),
    mfa_backup_codes JSONB,

    -- Privacy
    privacy_tier_id UUID REFERENCES privacy_tiers(id),
    privacy_consent_at TIMESTAMPTZ,
    privacy_consent_version VARCHAR(20),
    marketing_consent BOOLEAN DEFAULT false,

    -- Lifecycle
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_login_at TIMESTAMPTZ,

    -- Search
    search_vector tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(display_name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(email, '')), 'B')
    ) STORED,

    CONSTRAINT unique_email_per_org UNIQUE (organization_id, email)
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_org ON users(organization_id);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_search ON users USING GIN(search_vector);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = true;
CREATE INDEX idx_users_external ON users(external_id) WHERE external_id IS NOT NULL;

-- ============================================================================
-- DEVICES (Multi-device Support)
-- ============================================================================

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Device identification
    device_fingerprint VARCHAR(255) NOT NULL,
    device_name VARCHAR(255),
    device_type VARCHAR(50) CHECK (device_type IN ('ios', 'android', 'web', 'desktop')),

    -- Device metadata
    device_model VARCHAR(100),
    os_version VARCHAR(50),
    app_version VARCHAR(50),

    -- Push notifications
    push_token TEXT,
    push_platform VARCHAR(20),

    -- Security
    is_trusted BOOLEAN DEFAULT false,
    trust_verified_at TIMESTAMPTZ,

    -- Status
    is_active BOOLEAN DEFAULT true,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_ip_address INET,

    -- Lifecycle
    created_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT unique_device_per_user UNIQUE (user_id, device_fingerprint)
);

CREATE INDEX idx_devices_user ON devices(user_id);
CREATE INDEX idx_devices_fingerprint ON devices(device_fingerprint);
CREATE INDEX idx_devices_last_seen ON devices(last_seen_at DESC);
CREATE INDEX idx_devices_active ON devices(is_active) WHERE is_active = true;

-- ============================================================================
-- REFRESH TOKENS (RFC 9700 Compliant)
-- ============================================================================

CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,

    -- Token data (store hash, not plaintext)
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    token_family UUID NOT NULL,

    -- Rotation tracking
    generation INTEGER DEFAULT 1,
    parent_token_id UUID REFERENCES refresh_tokens(id),

    -- Validity
    issued_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,

    -- Revocation
    is_revoked BOOLEAN DEFAULT false,
    revoked_at TIMESTAMPTZ,
    revoked_reason VARCHAR(100),

    -- Security context
    ip_address INET,
    user_agent TEXT,

    CONSTRAINT valid_expiry CHECK (expires_at > issued_at)
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_device ON refresh_tokens(device_id);
CREATE INDEX idx_refresh_tokens_family ON refresh_tokens(token_family);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_active ON refresh_tokens(is_revoked, expires_at)
    WHERE is_revoked = false;

-- ============================================================================
-- SESSIONS
-- ============================================================================

CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    refresh_token_id UUID REFERENCES refresh_tokens(id) ON DELETE SET NULL,

    -- Session metadata
    session_type VARCHAR(20) DEFAULT 'normal' CHECK (session_type IN (
        'normal', 'api', 'impersonation'
    )),

    -- Context
    ip_address INET,
    user_agent TEXT,
    location_country VARCHAR(2),
    location_city VARCHAR(100),

    -- Status
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_activity_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ,

    -- Termination
    ended_at TIMESTAMPTZ,
    end_reason VARCHAR(50)
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_device ON sessions(device_id);
CREATE INDEX idx_sessions_active ON sessions(is_active, last_activity_at DESC)
    WHERE is_active = true;

-- ============================================================================
-- ORGANIZATION MEMBERSHIPS - ENTERPRISE EXTENSION POINT
-- ============================================================================
-- Organization membership management is an enterprise feature.
-- Open source version does not use this table.

CREATE TABLE organization_memberships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,

    -- Role within organization
    role VARCHAR(50) NOT NULL CHECK (role IN (
        'student', 'teacher', 'admin', 'parent', 'guardian', 'dpo'
    )),

    -- Permissions (JSON for flexibility)
    permissions JSONB DEFAULT '{}',

    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN (
        'pending', 'active', 'suspended', 'left'
    )),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    left_at TIMESTAMPTZ,

    invited_by UUID REFERENCES users(id),
    invited_at TIMESTAMPTZ,

    UNIQUE(user_id, organization_id)
);

CREATE INDEX idx_membership_user ON organization_memberships(user_id);
CREATE INDEX idx_membership_org ON organization_memberships(organization_id);
CREATE INDEX idx_membership_role ON organization_memberships(organization_id, role);
CREATE INDEX idx_membership_active ON organization_memberships(status) WHERE status = 'active';

-- ============================================================================
-- GUARDIAN RELATIONSHIPS (For Minors) - ENTERPRISE EXTENSION POINT
-- ============================================================================
-- Guardian relationships for institutional use (schools managing minors).
-- Enterprise feature for educational compliance.

CREATE TABLE guardian_relationships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guardian_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    child_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id),

    -- Relationship type
    relationship_type VARCHAR(50) NOT NULL CHECK (relationship_type IN (
        'parent', 'guardian', 'school_authorized'
    )),

    -- Verification
    verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMPTZ,
    verification_method VARCHAR(50),

    -- Permissions
    can_view_progress BOOLEAN DEFAULT true,
    can_view_transcripts BOOLEAN DEFAULT false,
    can_manage_consent BOOLEAN DEFAULT true,
    can_delete_data BOOLEAN DEFAULT false,

    -- Status
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN (
        'pending', 'active', 'revoked'
    )),
    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(guardian_user_id, child_user_id)
);

CREATE INDEX idx_guardian_guardian ON guardian_relationships(guardian_user_id);
CREATE INDEX idx_guardian_child ON guardian_relationships(child_user_id);
CREATE INDEX idx_guardian_active ON guardian_relationships(status) WHERE status = 'active';

-- ============================================================================
-- CONSENT RECORDS
-- ============================================================================

CREATE TABLE consent_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Consent category
    consent_category VARCHAR(50) NOT NULL CHECK (consent_category IN (
        'core_tutoring', 'progress_tracking', 'analytics',
        'progress_sharing', 'third_party_ai', 'marketing'
    )),

    -- Status
    status VARCHAR(20) NOT NULL CHECK (status IN ('granted', 'denied', 'withdrawn')),
    granted_at TIMESTAMPTZ,
    withdrawn_at TIMESTAMPTZ,

    -- Legal basis
    legal_basis VARCHAR(50) NOT NULL CHECK (legal_basis IN (
        'consent', 'legitimate_interest', 'public_task',
        'parental_consent', 'school_authorization'
    )),

    -- For minors
    is_minor BOOLEAN DEFAULT false,
    parent_consent_id UUID REFERENCES consent_records(id),

    -- For institutions
    organization_id UUID REFERENCES organizations(id),
    authorized_by_role VARCHAR(50),

    -- Versioning
    privacy_policy_version VARCHAR(20) NOT NULL,
    consent_version INTEGER DEFAULT 1,

    -- Audit context
    ip_address_hash VARCHAR(64),
    user_agent_hash VARCHAR(64),
    collection_method VARCHAR(50),

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(user_id, consent_category)
);

CREATE INDEX idx_consent_user ON consent_records(user_id);
CREATE INDEX idx_consent_category ON consent_records(user_id, consent_category);
CREATE INDEX idx_consent_org ON consent_records(organization_id);

-- Consent audit log
CREATE TABLE consent_audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    consent_record_id UUID NOT NULL REFERENCES consent_records(id) ON DELETE CASCADE,
    action VARCHAR(20) NOT NULL CHECK (action IN ('granted', 'withdrawn', 'updated')),
    previous_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_by UUID REFERENCES users(id),
    change_reason TEXT,
    ip_address_hash VARCHAR(64),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_consent_audit_record ON consent_audit_log(consent_record_id);
CREATE INDEX idx_consent_audit_created ON consent_audit_log(created_at DESC);

-- ============================================================================
-- DATA RETENTION POLICIES
-- ============================================================================

CREATE TABLE data_retention_policies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    privacy_tier_id UUID NOT NULL REFERENCES privacy_tiers(id),

    -- Per data type retention (days, -1 = indefinite)
    session_data_days INTEGER DEFAULT 90,
    progress_data_days INTEGER DEFAULT 365,
    transcript_data_days INTEGER DEFAULT 30,
    audit_log_days INTEGER DEFAULT 2555,
    consent_record_days INTEGER DEFAULT -1,

    -- Anonymization vs deletion
    anonymize_on_expiry BOOLEAN DEFAULT true,

    -- Educational exceptions
    maintain_educational_records BOOLEAN DEFAULT true,
    educational_record_years INTEGER DEFAULT 7,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(organization_id)
);

CREATE INDEX idx_retention_org ON data_retention_policies(organization_id);

-- ============================================================================
-- AUTHENTICATION AUDIT LOG
-- ============================================================================

CREATE TABLE auth_audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Actor
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    device_id UUID REFERENCES devices(id) ON DELETE SET NULL,
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,

    -- Event
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'login', 'login_failed', 'logout', 'token_refresh', 'token_revoked',
        'password_change', 'password_reset_request', 'password_reset_complete',
        'mfa_enabled', 'mfa_disabled', 'mfa_verified', 'mfa_failed',
        'device_registered', 'device_removed', 'device_trusted',
        'session_created', 'session_terminated',
        'user_created', 'user_updated', 'user_deleted',
        'role_changed', 'permission_changed',
        'data_export', 'data_deletion'
    )),
    event_status VARCHAR(20) NOT NULL CHECK (event_status IN ('success', 'failure')),
    event_details JSONB DEFAULT '{}',

    -- Context
    ip_address INET,
    user_agent TEXT,
    request_id VARCHAR(36),

    -- Result
    error_code VARCHAR(50),
    error_message TEXT,

    -- Immutability check
    checksum VARCHAR(64),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_user ON auth_audit_log(user_id);
CREATE INDEX idx_audit_org ON auth_audit_log(organization_id);
CREATE INDEX idx_audit_event ON auth_audit_log(event_type);
CREATE INDEX idx_audit_created ON auth_audit_log(created_at DESC);
CREATE INDEX idx_audit_status ON auth_audit_log(event_status, created_at DESC);

-- ============================================================================
-- HELPER FUNCTIONS FOR AUTH
-- ============================================================================

-- Function to hash password using bcrypt
CREATE OR REPLACE FUNCTION hash_password(password TEXT)
RETURNS TEXT AS $$
BEGIN
    RETURN crypt(password, gen_salt('bf', 12));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to verify password
CREATE OR REPLACE FUNCTION verify_password(password TEXT, hash TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN crypt(password, hash) = hash;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to revoke all tokens in a family (for replay detection)
CREATE OR REPLACE FUNCTION revoke_token_family(p_family_id UUID, p_reason VARCHAR(100) DEFAULT 'security')
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE refresh_tokens
    SET is_revoked = true,
        revoked_at = NOW(),
        revoked_reason = p_reason
    WHERE token_family = p_family_id
      AND is_revoked = false;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up expired tokens
CREATE OR REPLACE FUNCTION cleanup_expired_tokens()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM refresh_tokens
    WHERE expires_at < NOW() - INTERVAL '7 days';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- AUTH TABLE COMMENTS
-- ============================================================================

COMMENT ON TABLE privacy_tiers IS 'Privacy tier configurations for data handling';
COMMENT ON TABLE organizations IS 'Multi-tenant organizations (schools, companies, etc.)';
COMMENT ON TABLE users IS 'User accounts with authentication and profile data';
COMMENT ON TABLE devices IS 'Registered devices per user for multi-device support';
COMMENT ON TABLE refresh_tokens IS 'Refresh tokens with RFC 9700 rotation tracking';
COMMENT ON TABLE sessions IS 'Active user sessions tied to devices';
COMMENT ON TABLE organization_memberships IS 'User membership in organizations with roles';
COMMENT ON TABLE guardian_relationships IS 'Parent/guardian relationships for minors';
COMMENT ON TABLE consent_records IS 'GDPR/COPPA compliant consent tracking';
COMMENT ON TABLE consent_audit_log IS 'Audit trail for consent changes';
COMMENT ON TABLE data_retention_policies IS 'Per-organization data retention configuration';
COMMENT ON TABLE auth_audit_log IS 'SOC2-ready authentication audit trail';

-- ============================================================================
-- CURRICULUM IMPORT TRACKING
-- ============================================================================
-- Tracks which source courses have been imported to UMCF format

CREATE TABLE imported_courses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    source_id VARCHAR(100) NOT NULL,
    course_id VARCHAR(255) NOT NULL,
    curriculum_id UUID REFERENCES curricula(id) ON DELETE SET NULL,
    imported_at TIMESTAMPTZ DEFAULT NOW(),
    imported_by UUID REFERENCES users(id) ON DELETE SET NULL,
    import_job_id VARCHAR(100),
    CONSTRAINT unique_imported_course UNIQUE (source_id, course_id)
);

CREATE INDEX idx_imported_source_course ON imported_courses(source_id, course_id);
CREATE INDEX idx_imported_curriculum ON imported_courses(curriculum_id);

COMMENT ON TABLE imported_courses IS 'Tracks which external source courses have been imported to UMCF';

-- ============================================================================
-- CURRICULUM LISTS (User Collections)
-- ============================================================================
-- User-created lists for organizing source courses before import

CREATE TABLE curriculum_lists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    is_shared BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_list_name_per_user UNIQUE (user_id, name)
);

CREATE INDEX idx_lists_user ON curriculum_lists(user_id);
CREATE INDEX idx_lists_shared ON curriculum_lists(is_shared) WHERE is_shared = true;

-- Items within a list (source courses, not imported curricula)
CREATE TABLE curriculum_list_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    list_id UUID NOT NULL REFERENCES curriculum_lists(id) ON DELETE CASCADE,
    source_id VARCHAR(100) NOT NULL,
    course_id VARCHAR(255) NOT NULL,
    course_title VARCHAR(500),
    course_thumbnail_url TEXT,
    notes TEXT,
    order_index INTEGER DEFAULT 0,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_course_per_list UNIQUE (list_id, source_id, course_id)
);

CREATE INDEX idx_list_items_list ON curriculum_list_items(list_id);
CREATE INDEX idx_list_items_course ON curriculum_list_items(source_id, course_id);

COMMENT ON TABLE curriculum_lists IS 'User-created lists for organizing source courses';
COMMENT ON TABLE curriculum_list_items IS 'Source courses added to user lists';
