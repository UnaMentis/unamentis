-- ============================================================================
-- Auth Audit Log: allow the 'age_attestation' event type
-- ============================================================================
--
-- The B9 13+ age-gate records an `age_attestation` audit event on registration
-- (auth/auth_api.py), but the auth_audit_log.event_type CHECK constraint did not
-- list that value, so registration failed on real PostgreSQL with a
-- CheckViolationError. This migration recreates the constraint with the new
-- value added (PostgreSQL cannot extend a CHECK constraint in place).
--
-- Apply with: psql $DATABASE_URL < migrations/004_auth_audit_age_attestation.sql
--
-- ============================================================================

ALTER TABLE auth_audit_log
    DROP CONSTRAINT IF EXISTS auth_audit_log_event_type_check;

ALTER TABLE auth_audit_log
    ADD CONSTRAINT auth_audit_log_event_type_check CHECK (event_type IN (
        'login', 'login_failed', 'logout', 'token_refresh', 'token_revoked',
        'password_change', 'password_reset_request', 'password_reset_complete',
        'mfa_enabled', 'mfa_disabled', 'mfa_verified', 'mfa_failed',
        'device_registered', 'device_removed', 'device_trusted',
        'session_created', 'session_terminated',
        'user_created', 'user_updated', 'user_deleted',
        'role_changed', 'permission_changed',
        'data_export', 'data_deletion',
        'age_attestation'
    ));
