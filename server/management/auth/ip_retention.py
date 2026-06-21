"""Auth-path IP retention sweep.

The auth path intentionally stores the exact client IP (auth_audit_log and
refresh_tokens) because account-security forensics, such as credential-stuffing
and token-theft investigation, need to distinguish individual hosts; a
coarsened /24 cannot tell an attacker from a victim on the same network. That
retention is time-bounded: this sweep deletes (nulls) the stored IP once it is
no longer operationally useful, which reconciles the auth path with the
privacy posture documented in docs/PRIVACY_PRESERVING_USER_DATA.md and
disclosed on the web client's /privacy page.

Sweep rules:
- auth_audit_log: null ip_address on rows older than the retention window.
- refresh_tokens: null ip_address on rows that are expired or revoked and
  were issued more than the retention window ago. Live tokens keep their IP
  so active sessions remain auditable.

The sweep runs at startup and then once per 24 hours (see
auth_ip_retention_loop, wired in server.py on_startup).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone

logger = logging.getLogger(__name__)

# Exact IPs on account-security events are kept for 90 days, then deleted.
# This window is disclosed on the public /privacy page; change both together.
AUTH_IP_RETENTION_DAYS = 90

# How often the background loop re-runs the sweep.
SWEEP_INTERVAL_SECONDS = 24 * 60 * 60


def _parse_update_count(status: str) -> int:
    """Parse the row count from an asyncpg command status like 'UPDATE 3'."""
    try:
        return int(status.rsplit(" ", 1)[-1])
    except (ValueError, AttributeError):
        return 0


async def sweep_auth_ip_retention(
    db_pool, retention_days: int = AUTH_IP_RETENTION_DAYS
) -> dict:
    """Null stored IPs on auth records older than the retention window.

    Returns a dict with the number of rows scrubbed per table:
    {"auth_audit_log": n, "refresh_tokens": m}.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=retention_days)

    async with db_pool.acquire() as conn:
        audit_status = await conn.execute(
            """
            UPDATE auth_audit_log
            SET ip_address = NULL
            WHERE ip_address IS NOT NULL AND created_at < $1
            """,
            cutoff,
        )

        token_status = await conn.execute(
            """
            UPDATE refresh_tokens
            SET ip_address = NULL
            WHERE ip_address IS NOT NULL
              AND issued_at < $1
              AND (is_revoked OR expires_at < NOW())
            """,
            cutoff,
        )

    counts = {
        "auth_audit_log": _parse_update_count(audit_status),
        "refresh_tokens": _parse_update_count(token_status),
    }
    if counts["auth_audit_log"] or counts["refresh_tokens"]:
        logger.info(
            "[AuthIPRetention] Scrubbed IPs: %d auth_audit_log rows, "
            "%d refresh_tokens rows (older than %d days)",
            counts["auth_audit_log"],
            counts["refresh_tokens"],
            retention_days,
        )
    return counts


async def auth_ip_retention_loop(
    db_pool,
    retention_days: int = AUTH_IP_RETENTION_DAYS,
    interval_seconds: float = SWEEP_INTERVAL_SECONDS,
) -> None:
    """Run the retention sweep at startup and then once per interval.

    Follows the _metrics_recording_loop pattern in server.py: errors are
    logged and the loop continues; cancellation exits cleanly.
    """
    logger.info(
        "[AuthIPRetention] Starting retention loop (%d-day window)", retention_days
    )
    while True:
        try:
            await sweep_auth_ip_retention(db_pool, retention_days)
        except asyncio.CancelledError:
            break
        except Exception as e:
            logger.error(f"[AuthIPRetention] Sweep failed: {e}")
        try:
            await asyncio.sleep(interval_seconds)
        except asyncio.CancelledError:
            break
