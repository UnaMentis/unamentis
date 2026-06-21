-- ============================================================================
-- Consent Records: allow registration-time consent categories
-- ============================================================================
--
-- B9 registration consent writes consent_records rows for the 13+ age
-- attestation and the versioned Terms of Service / Privacy Policy acceptance
-- (auth/auth_api.py register()), but the consent_records.consent_category
-- CHECK constraint did not list those values. This migration recreates the
-- constraint with the new values added (PostgreSQL cannot extend a CHECK
-- constraint in place).
--
-- Apply with: psql $DATABASE_URL < migrations/005_consent_registration_categories.sql
--
-- ============================================================================

ALTER TABLE consent_records
    DROP CONSTRAINT IF EXISTS consent_records_consent_category_check;

ALTER TABLE consent_records
    ADD CONSTRAINT consent_records_consent_category_check CHECK (consent_category IN (
        'core_tutoring', 'progress_tracking', 'analytics',
        'progress_sharing', 'third_party_ai', 'marketing',
        'age_attestation', 'terms_of_service', 'privacy_policy'
    ));
