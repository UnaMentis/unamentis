"""
Feature Flag Guard - Route-level middleware for the management server.

Provides a decorator that blocks requests to an entire API module when its
corresponding feature flag is disabled in Unleash. When Unleash is unavailable,
falls back to the defaults defined in feature_flag_keys.FLAG_DEFAULTS.
"""

from __future__ import annotations

import functools
import logging
from typing import Callable

from aiohttp import web

from feature_flag_keys import FLAG_DEFAULTS

logger = logging.getLogger(__name__)

# Lazy import to avoid circular dependency with server.py.
# server.py defines is_flag_enabled() and initialises the UnleashClient.
_is_flag_enabled: Callable | None = None


def _get_is_flag_enabled() -> Callable:
    """Lazily resolve is_flag_enabled from server module."""
    global _is_flag_enabled
    if _is_flag_enabled is None:
        try:
            from server import is_flag_enabled

            _is_flag_enabled = is_flag_enabled
        except ImportError:
            logger.error(
                "Failed to import is_flag_enabled from server module. "
                "All feature flag checks will use defaults from FLAG_DEFAULTS."
            )

            def _fallback(flag_name: str, default: bool = False) -> bool:
                return FLAG_DEFAULTS.get(flag_name, default)

            _is_flag_enabled = _fallback
    return _is_flag_enabled


def flag_guard(flag_name: str) -> Callable:
    """Decorator that gates an aiohttp handler behind a feature flag.

    When the flag is disabled the handler returns 503 with a JSON body
    identifying the flag that blocked the request. When Unleash is
    unavailable, the default from FLAG_DEFAULTS is used.

    Usage::

        @flag_guard(FlagKeys.TTS_LAB)
        async def handle_generate_test_audio(request):
            ...

    Or applied to an entire module at registration time::

        def register_foo_routes(app):
            guard = flag_guard(FlagKeys.FOO)
            app.router.add_get("/api/foo", guard(handle_list))
            app.router.add_post("/api/foo", guard(handle_create))
    """
    default = FLAG_DEFAULTS.get(flag_name)
    if default is None:
        logger.warning("Unknown feature flag %s; defaulting to disabled", flag_name)
        default = False

    def decorator(handler: Callable) -> Callable:
        @functools.wraps(handler)
        async def wrapper(request: web.Request) -> web.StreamResponse:
            check = _get_is_flag_enabled()
            if not check(flag_name, default=default):
                logger.info(
                    "Request blocked by feature flag %s: %s %s",
                    flag_name,
                    request.method,
                    request.path,
                )
                return web.json_response(
                    {
                        "error": "This feature is currently disabled",
                        "flag": flag_name,
                    },
                    status=503,
                )
            return await handler(request)

        return wrapper

    return decorator


def guarded_routes(
    app: web.Application,
    flag_name: str,
) -> "GuardedRouter":
    """Return a router-like object that applies a flag guard to every route.

    Usage::

        def register_foo_routes(app):
            router = guarded_routes(app, FlagKeys.FOO)
            router.add_get("/api/foo", handle_list)
            router.add_post("/api/foo", handle_create)

    This is syntactic sugar so existing registration functions only need to
    swap ``app`` for ``router`` and add one line.
    """
    return GuardedRouter(app, flag_name)


class GuardedRouter:
    """Thin wrapper that applies a flag_guard to every route added through it."""

    def __init__(self, app: web.Application, flag_name: str) -> None:
        self._app = app
        self._guard = flag_guard(flag_name)

    def _wrap(self, handler: Callable) -> Callable:
        return self._guard(handler)

    def add_get(self, path: str, handler: Callable, **kw):
        return self._app.router.add_get(path, self._wrap(handler), **kw)

    def add_post(self, path: str, handler: Callable, **kw):
        return self._app.router.add_post(path, self._wrap(handler), **kw)

    def add_put(self, path: str, handler: Callable, **kw):
        return self._app.router.add_put(path, self._wrap(handler), **kw)

    def add_delete(self, path: str, handler: Callable, **kw):
        return self._app.router.add_delete(path, self._wrap(handler), **kw)

    def add_patch(self, path: str, handler: Callable, **kw):
        return self._app.router.add_patch(path, self._wrap(handler), **kw)
