"""
Feature Flag Guard Tests

Tests for the feature_flag_guard module: flag_guard decorator,
GuardedRouter, and the /api/feature-flags endpoint in server.py.

TESTING PHILOSOPHY: Real Over Mock
- Uses REAL aiohttp test utilities
- Only mocks the external Unleash client (is_flag_enabled)
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock  # ALLOWED: UnleashClient is external service

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from aiohttp import web
from aiohttp.test_utils import make_mocked_request

from feature_flag_keys import FlagKeys, FLAG_DEFAULTS
from feature_flag_guard import flag_guard, guarded_routes, GuardedRouter


# =============================================================================
# Test FlagKeys & FLAG_DEFAULTS
# =============================================================================


class TestFlagKeys:
    """Tests for the FlagKeys constants and FLAG_DEFAULTS map."""

    def test_all_flag_keys_have_defaults(self):
        """Every key in FlagKeys should appear in FLAG_DEFAULTS."""
        flag_attrs = [
            attr
            for attr in dir(FlagKeys)
            if not attr.startswith("_") and isinstance(getattr(FlagKeys, attr), str)
        ]
        for attr in flag_attrs:
            flag_name = getattr(FlagKeys, attr)
            assert flag_name in FLAG_DEFAULTS, (
                f"FlagKeys.{attr} = '{flag_name}' is missing from FLAG_DEFAULTS"
            )

    def test_no_extra_defaults(self):
        """FLAG_DEFAULTS should not contain keys absent from FlagKeys."""
        flag_values = {
            getattr(FlagKeys, attr)
            for attr in dir(FlagKeys)
            if not attr.startswith("_") and isinstance(getattr(FlagKeys, attr), str)
        }
        for name in FLAG_DEFAULTS:
            assert name in flag_values, (
                f"FLAG_DEFAULTS contains '{name}' which has no FlagKeys constant"
            )

    def test_ops_kill_switches_default_off(self):
        """Kill-switch ops flags should default to False (safe)."""
        assert FLAG_DEFAULTS[FlagKeys.MAINTENANCE_MODE] is False
        assert FLAG_DEFAULTS[FlagKeys.BUDGET_CAP_REACHED] is False

    def test_dev_tools_default_off(self):
        """Dev-only services should default to False."""
        assert FLAG_DEFAULTS[FlagKeys.TTS_LAB] is False
        assert FLAG_DEFAULTS[FlagKeys.LATENCY_TESTING] is False

    def test_production_services_default_on(self):
        """Production services should default to True so nothing breaks."""
        production_flags = [
            FlagKeys.IMPORT_ENABLED,
            FlagKeys.REPROCESSING_ENABLED,
            FlagKeys.TTS_GENERATION_ENABLED,
            FlagKeys.MEDIA_GENERATION_ENABLED,
            FlagKeys.KB_PACKS,
            FlagKeys.DEPLOYMENT,
            FlagKeys.LISTS,
            FlagKeys.FOV_CONTEXT,
            FlagKeys.PLUGIN_SYSTEM,
            FlagKeys.SPECIALIZED_MODULES,
        ]
        for flag in production_flags:
            assert FLAG_DEFAULTS[flag] is True, f"{flag} should default ON"

    def test_naming_conventions(self):
        """Flag names should follow {category}_ naming convention."""
        for name in FLAG_DEFAULTS:
            parts = name.split("_", 1)
            assert len(parts) >= 2, f"Flag '{name}' missing category prefix"
            category = parts[0]
            assert category in ("ops", "service", "feature"), (
                f"Flag '{name}' has unexpected category prefix '{category}'"
            )


# =============================================================================
# Test flag_guard decorator
# =============================================================================


class TestFlagGuard:
    """Tests for the flag_guard decorator."""

    @pytest.fixture
    def mock_handler(self):
        """Create a simple async handler."""

        async def handler(request):
            return web.json_response({"ok": True})

        return handler

    def test_allows_when_flag_enabled(self, mock_handler):
        """Handler should execute when flag is enabled."""
        import asyncio

        guarded = flag_guard("test_flag")(mock_handler)

        with patch("feature_flag_guard._is_flag_enabled", None):
            with patch("feature_flag_guard._get_is_flag_enabled") as mock_get:
                mock_fn = MagicMock(
                    return_value=True
                )  # ALLOWED: external config service
                mock_get.return_value = mock_fn

                request = make_mocked_request("GET", "/api/test")
                response = asyncio.run(guarded(request))
                assert response.status == 200

    def test_blocks_when_flag_disabled(self, mock_handler):
        """Handler should return 503 when flag is disabled."""
        import asyncio

        guarded = flag_guard("test_flag")(mock_handler)

        with patch("feature_flag_guard._is_flag_enabled", None):
            with patch("feature_flag_guard._get_is_flag_enabled") as mock_get:
                mock_fn = MagicMock(
                    return_value=False
                )  # ALLOWED: external config service
                mock_get.return_value = mock_fn

                request = make_mocked_request("GET", "/api/test")
                response = asyncio.run(guarded(request))
                assert response.status == 503
                assert response.headers.get("Retry-After") == "60"

    def test_503_body_does_not_leak_flag_name(self, mock_handler):
        """The 503 response must not expose the internal flag name."""
        import asyncio
        import json

        guarded = flag_guard("service_tts_lab")(mock_handler)

        with patch("feature_flag_guard._is_flag_enabled", None):
            with patch("feature_flag_guard._get_is_flag_enabled") as mock_get:
                mock_fn = MagicMock(
                    return_value=False
                )  # ALLOWED: external config service
                mock_get.return_value = mock_fn

                request = make_mocked_request("GET", "/api/tts-lab/models")
                response = asyncio.run(guarded(request))
                body = json.loads(response.body)
                assert "flag" not in body  # Internal flag names must not leak
                assert "disabled" in body["error"].lower()

    def test_uses_flag_defaults(self, mock_handler):
        """Guard should use FLAG_DEFAULTS for the default value."""
        import asyncio

        # TTS_LAB defaults to False, so without Unleash it should block
        guarded = flag_guard(FlagKeys.TTS_LAB)(mock_handler)

        with patch("feature_flag_guard._is_flag_enabled", None):
            with patch("feature_flag_guard._get_is_flag_enabled") as mock_get:
                # Simulate is_flag_enabled returning the default
                def check(name, default=False):
                    return default

                mock_get.return_value = check

                request = make_mocked_request("GET", "/api/tts-lab/models")
                response = asyncio.run(guarded(request))
                assert response.status == 503

    def test_unknown_flag_defaults_to_disabled(self, mock_handler):
        """Unknown flags not in FLAG_DEFAULTS should block requests."""
        import asyncio

        guarded = flag_guard("nonexistent_flag_xyz")(mock_handler)

        with patch("feature_flag_guard._is_flag_enabled", None):
            with patch("feature_flag_guard._get_is_flag_enabled") as mock_get:
                # Simulate is_flag_enabled returning the default
                def check(name, default=False):
                    return default

                mock_get.return_value = check

                request = make_mocked_request("GET", "/api/test")
                response = asyncio.run(guarded(request))
                assert response.status == 503

    def test_preserves_handler_name(self, mock_handler):
        """Decorated handler should preserve the original function name."""
        guarded = flag_guard("test_flag")(mock_handler)
        assert guarded.__name__ == "handler"


# =============================================================================
# Test GuardedRouter
# =============================================================================


class TestGuardedRouter:
    """Tests for the GuardedRouter class."""

    def test_registers_routes_on_app(self):
        """GuardedRouter should register routes on the actual app."""
        app = web.Application()

        async def handler(request):
            return web.Response(text="ok")

        router = GuardedRouter(app, "test_flag")
        router.add_get("/test", handler)

        # Route should be registered
        routes = [r for r in app.router.routes() if r.method == "GET"]
        assert len(routes) >= 1

    def test_all_methods_supported(self):
        """GuardedRouter should support GET, POST, PUT, DELETE, PATCH."""
        app = web.Application()

        async def handler(request):
            return web.Response(text="ok")

        router = GuardedRouter(app, "test_flag")
        router.add_get("/get", handler)
        router.add_post("/post", handler)
        router.add_put("/put", handler)
        router.add_delete("/delete", handler)
        router.add_patch("/patch", handler)

        methods = {r.method for r in app.router.routes()}
        assert {"GET", "POST", "PUT", "DELETE", "PATCH"}.issubset(methods)

    def test_guarded_routes_helper(self):
        """The guarded_routes() helper should return a GuardedRouter."""
        app = web.Application()
        router = guarded_routes(app, "test_flag")
        assert isinstance(router, GuardedRouter)


# =============================================================================
# Test is_flag_enabled with FLAG_DEFAULTS integration
# =============================================================================

# server.py has a deep import chain (auth -> jwt -> cryptography) that may
# not be available in all environments (e.g., CI containers). These tests
# are skipped when the server module cannot be imported.
try:
    from server import is_flag_enabled, handle_get_feature_flags

    _server_available = True
except Exception:
    _server_available = False
    is_flag_enabled = None
    handle_get_feature_flags = None

_skip_server = pytest.mark.skipif(
    not _server_available,
    reason="server module unavailable (missing cryptography/jwt dependencies)",
)


@_skip_server
class TestIsFlagEnabledDefaults:
    """Tests for is_flag_enabled using FLAG_DEFAULTS."""

    def test_uses_flag_defaults_when_no_explicit_default(self):
        """is_flag_enabled should consult FLAG_DEFAULTS when default is None."""
        with patch("server.feature_flags", None):
            # MAINTENANCE_MODE defaults False in FLAG_DEFAULTS
            assert is_flag_enabled(FlagKeys.MAINTENANCE_MODE) is False
            # IMPORT_ENABLED defaults True in FLAG_DEFAULTS
            assert is_flag_enabled(FlagKeys.IMPORT_ENABLED) is True

    def test_explicit_default_overrides_flag_defaults(self):
        """An explicit default= parameter should override FLAG_DEFAULTS."""
        with patch("server.feature_flags", None):
            # IMPORT_ENABLED defaults True in FLAG_DEFAULTS, but explicit False wins
            assert is_flag_enabled(FlagKeys.IMPORT_ENABLED, default=False) is False

    def test_unknown_flag_defaults_to_false(self):
        """A flag not in FLAG_DEFAULTS should default to False."""
        with patch("server.feature_flags", None):
            assert is_flag_enabled("nonexistent_flag") is False


# =============================================================================
# Test /api/feature-flags endpoint
# =============================================================================


@_skip_server
class TestFeatureFlagsEndpoint:
    """Tests for the GET /api/feature-flags endpoint."""

    def test_returns_all_flags_with_defaults_source(self):
        """When Unleash is down, source should be 'defaults'."""
        import asyncio
        import json

        with patch("server.feature_flags", None):
            request = make_mocked_request("GET", "/api/feature-flags")
            response = asyncio.run(handle_get_feature_flags(request))

            body = json.loads(response.body)
            assert body["source"] == "defaults"
            assert "flags" in body
            assert len(body["flags"]) == len(FLAG_DEFAULTS)

    def test_returns_unleash_source_when_connected(self):
        """When Unleash is running, source should be 'unleash'."""
        import asyncio
        import json

        mock_client = MagicMock()  # ALLOWED: UnleashClient is external service
        mock_client.is_enabled.return_value = True

        with patch("server.feature_flags", mock_client):
            request = make_mocked_request("GET", "/api/feature-flags")
            response = asyncio.run(handle_get_feature_flags(request))

            body = json.loads(response.body)
            assert body["source"] == "unleash"

    def test_flag_values_match_defaults_when_unleash_down(self):
        """Flag values should match FLAG_DEFAULTS when Unleash is unavailable."""
        import asyncio
        import json

        with patch("server.feature_flags", None):
            request = make_mocked_request("GET", "/api/feature-flags")
            response = asyncio.run(handle_get_feature_flags(request))

            body = json.loads(response.body)
            for flag_name, expected in FLAG_DEFAULTS.items():
                assert body["flags"][flag_name] == expected, (
                    f"Flag {flag_name}: expected {expected}, got {body['flags'][flag_name]}"
                )
