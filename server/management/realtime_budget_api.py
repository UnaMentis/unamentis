#!/usr/bin/env python3
"""
Realtime token budget API.

The web client's realtime token route mints paid upstream sessions. Its
in-process guards (per-identity throttle, per-instance daily cap) reset on
every deploy and multiply across instances, so this module provides the
durable counters behind them: a daily spend ceiling and a per-IP daily quota
persisted in the telemetry store's daily_counters table.

The token route reserves a slot here before minting and falls back to its
in-memory guards when this API is unreachable.

Environment:
  REALTIME_DAILY_TOKEN_BUDGET   Max mints per UTC day across all callers
                                (default 200, conservative).
  REALTIME_IP_DAILY_QUOTA       Max mints per UTC day per coarsened client IP
                                (default 50).
"""

from __future__ import annotations

import logging
import os

from aiohttp import web

from ip_privacy import coarsen_ip

logger = logging.getLogger(__name__)

DEFAULT_DAILY_TOKEN_BUDGET = 200
DEFAULT_IP_DAILY_QUOTA = 50

TOTAL_COUNTER = "realtime:mints"
IP_COUNTER_PREFIX = "realtime:ip:"


def _env_int(name: str, default: int) -> int:
    """Read a positive int from the environment, falling back to default."""
    try:
        value = int(os.environ.get(name, default))
        return value if value > 0 else default
    except (TypeError, ValueError):
        return default


def get_daily_token_budget() -> int:
    return _env_int("REALTIME_DAILY_TOKEN_BUDGET", DEFAULT_DAILY_TOKEN_BUDGET)


def get_ip_daily_quota() -> int:
    return _env_int("REALTIME_IP_DAILY_QUOTA", DEFAULT_IP_DAILY_QUOTA)


async def handle_reserve_budget(request: web.Request) -> web.Response:
    """Reserve one realtime token mint against the daily budget.

    Body (optional JSON): {"clientIp": "<end-client ip>"} forwarded by the
    token route; falls back to the connection peer. The IP is coarsened
    before use as a counter key (privacy, audit finding B10).

    Responses:
      200 {"allowed": true, "totalToday": n, "ipToday": m}
      429 {"allowed": false, "reason": "..."} when a ceiling is hit
      503 when the durable store is unavailable
    """
    store = request.app.get("telemetry_store")
    if store is None:
        return web.json_response(
            {"allowed": False, "reason": "budget store unavailable"}, status=503
        )

    client_ip = ""
    try:
        if request.can_read_body:
            data = await request.json()
            if isinstance(data, dict):
                client_ip = str(data.get("clientIp", ""))[:64]
    except Exception:
        client_ip = ""
    if not client_ip:
        client_ip = request.remote or "unknown"
    ip_key = IP_COUNTER_PREFIX + coarsen_ip(client_ip)

    try:
        # Per-IP quota first: a single abusive source trips its own quota
        # without consuming the shared daily budget.
        ip_allowed, ip_count = await store.increment_daily_counter(
            ip_key, limit=get_ip_daily_quota()
        )
        if not ip_allowed:
            logger.warning(
                f"Realtime budget: per-IP daily quota tripped for {ip_key} "
                f"({ip_count}/{get_ip_daily_quota()})"
            )
            return web.json_response(
                {"allowed": False, "reason": "per-ip daily quota exceeded"},
                status=429,
            )

        allowed, total = await store.increment_daily_counter(
            TOTAL_COUNTER, limit=get_daily_token_budget()
        )
        if not allowed:
            logger.warning(
                f"Realtime budget: daily token budget tripped "
                f"({total}/{get_daily_token_budget()})"
            )
            return web.json_response(
                {"allowed": False, "reason": "daily token budget exceeded"},
                status=429,
            )

        return web.json_response(
            {"allowed": True, "totalToday": total, "ipToday": ip_count}
        )
    except Exception as e:
        logger.error(f"Realtime budget reservation failed: {e}")
        return web.json_response(
            {"allowed": False, "reason": "budget store error"}, status=503
        )


async def handle_budget_status(request: web.Request) -> web.Response:
    """Return today's mint count against the configured budget."""
    store = request.app.get("telemetry_store")
    if store is None:
        return web.json_response({"error": "budget store unavailable"}, status=503)
    try:
        total = await store.get_daily_counter(TOTAL_COUNTER)
        return web.json_response(
            {
                "totalToday": total,
                "dailyBudget": get_daily_token_budget(),
                "ipDailyQuota": get_ip_daily_quota(),
                "remaining": max(get_daily_token_budget() - total, 0),
            }
        )
    except Exception as e:
        logger.error(f"Realtime budget status failed: {e}")
        return web.json_response({"error": "budget store error"}, status=503)


def register_realtime_budget_routes(app: web.Application) -> None:
    """Register realtime budget routes on the application."""
    app.router.add_post("/api/realtime/budget/reserve", handle_reserve_budget)
    app.router.add_get("/api/realtime/budget", handle_budget_status)
