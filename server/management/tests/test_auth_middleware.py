"""
Tests for Authentication Middleware

Comprehensive tests for JWT validation middleware and decorators.
"""

import pytest
from unittest.mock import MagicMock, AsyncMock
from aiohttp import web
import jwt

from auth.auth_middleware import (
    PUBLIC_ROUTES,
    PUBLIC_PREFIXES,
    is_public_route,
    auth_middleware,
    require_auth,
    require_role,
    require_permission,
    require_org_membership,
    setup_token_service,
)
from auth.token_service import TokenService, TokenConfig


@pytest.fixture
def token_config():
    """Create a test token configuration."""
    return TokenConfig(
        secret_key="test-secret-key-for-jwt-signing-2024",
        algorithm="HS256",
        issuer="unamentis",
        audience="unamentis-api",
    )


@pytest.fixture
def token_service(token_config):
    """Create a test token service."""
    return TokenService(token_config)


class TestPublicRoutes:
    """Tests for PUBLIC_ROUTES and PUBLIC_PREFIXES."""

    def test_public_routes_contains_health(self):
        """Test that health endpoints are public."""
        assert "/health" in PUBLIC_ROUTES
        assert "/api/health" in PUBLIC_ROUTES

    def test_public_routes_contains_auth_endpoints(self):
        """Test that auth endpoints are public."""
        assert "/api/auth/login" in PUBLIC_ROUTES
        assert "/api/auth/register" in PUBLIC_ROUTES
        assert "/api/auth/refresh" in PUBLIC_ROUTES

    def test_public_prefixes_contains_oauth(self):
        """Test that OAuth prefixes are public."""
        assert "/api/auth/oauth/" in PUBLIC_PREFIXES

    def test_admin_prefix_is_not_public(self):
        """Admin routes must NOT be public: the API is default-deny."""
        assert "/api/admin/" not in PUBLIC_PREFIXES

    def test_dangerous_namespaces_not_public(self):
        """Mutating and administrative namespaces must require authentication."""
        for prefix in (
            "/api/admin/",
            "/api/curricula",
            "/api/tts",
            "/api/plugins",
            "/api/deployments",
            "/api/import/",
            "/api/system/",
            "/api/models",
            "/api/services",
            "/api/kb",
            "/api/modules",
            "/api/sessions",
            "/ws",
        ):
            assert prefix not in PUBLIC_PREFIXES


class TestIsPublicRoute:
    """Tests for is_public_route function (default-deny model)."""

    def test_exact_match_public_route(self):
        """Test exact match for public routes."""
        assert is_public_route("/health") is True
        assert is_public_route("/api/health") is True
        assert is_public_route("/api/auth/login") is True

    def test_oauth_prefix_is_public(self):
        """OAuth callback subpaths remain public."""
        assert is_public_route("/api/auth/oauth/google/authorize") is True
        assert is_public_route("/api/auth/oauth/apple/callback") is True

    def test_admin_and_mutating_routes_not_public(self):
        """Default-deny: admin and mutating routes require auth."""
        assert is_public_route("/api/admin/users") is False
        assert is_public_route("/api/curricula/list") is False
        assert is_public_route("/api/sessions/123/data") is False
        assert is_public_route("/api/services/status") is False
        assert is_public_route("/api/tts/cache") is False
        assert is_public_route("/api/stats") is False

    def test_non_public_route(self):
        """Test that non-public routes return False."""
        assert is_public_route("/api/protected/resource") is False
        assert is_public_route("/api/user/profile") is False

    def test_prefix_boundary_matching(self):
        """Prefix matching respects slash boundaries (OAuth prefix)."""
        # '/api/auth/oauth' matches '/api/auth/oauth/google'
        assert is_public_route("/api/auth/oauth/google") is True
        # but a lookalike path must not be treated as the oauth prefix
        assert is_public_route("/api/auth/oauthX") is False

    def test_websocket_routes_not_public(self):
        """WebSocket routes now require authentication."""
        assert is_public_route("/ws") is False
        assert is_public_route("/ws/audio") is False

    def test_telemetry_intake_is_method_scoped(self):
        """POST telemetry intake is public; reads/clears of the same path require auth."""
        assert is_public_route("/api/logs", "POST") is True
        assert is_public_route("/api/metrics", "POST") is True
        assert is_public_route("/api/logs", "GET") is False
        assert is_public_route("/api/logs", "DELETE") is False


class TestAuthMiddleware:
    """Tests for auth_middleware."""

    @pytest.mark.asyncio
    async def test_public_route_bypasses_auth(self, token_service):
        """Test that public routes bypass authentication."""
        request = MagicMock(spec=web.Request)
        request.path = "/health"
        request.app = {"token_service": token_service}

        handler = AsyncMock(return_value=web.Response(text="ok"))

        await auth_middleware(request, handler)
        handler.assert_called_once_with(request)

    @pytest.mark.asyncio
    async def test_missing_token_service_returns_500(self):
        """Test that missing token service returns 500."""
        request = MagicMock(spec=web.Request)
        request.path = "/api/protected"
        request.app = {}  # No token_service

        handler = AsyncMock()  # ALLOWED: test double for the aiohttp handler boundary in a middleware unit test

        with pytest.raises(web.HTTPInternalServerError):
            await auth_middleware(request, handler)

    @pytest.mark.asyncio
    async def test_missing_auth_header_returns_401(self, token_service):
        """Test that missing Authorization header returns 401."""
        request = MagicMock(spec=web.Request)
        request.path = "/api/protected"
        request.app = {"token_service": token_service}
        request.headers = {}

        handler = AsyncMock()  # ALLOWED: test double for the aiohttp handler boundary in a middleware unit test

        with pytest.raises(web.HTTPUnauthorized):
            await auth_middleware(request, handler)

    @pytest.mark.asyncio
    async def test_invalid_auth_header_format_returns_401(self, token_service):
        """Test that invalid Authorization header format returns 401."""
        request = MagicMock(spec=web.Request)
        request.path = "/api/protected"
        request.app = {"token_service": token_service}
        request.headers = {"Authorization": "Basic some-credentials"}

        handler = AsyncMock()  # ALLOWED: test double for the aiohttp handler boundary in a middleware unit test

        with pytest.raises(web.HTTPUnauthorized):
            await auth_middleware(request, handler)

    @pytest.mark.asyncio
    async def test_valid_token_sets_request_context(self, token_service):
        """Test that valid token sets request context."""
        token, _ = token_service.generate_access_token(
            user_id="user-123",
            email="test@example.com",
            role="admin",
            device_id="device-456",
            organization_id="org-789",
            permissions=["read", "write"],
        )

        request = MagicMock(spec=web.Request)
        request.path = "/api/protected"
        request.app = {"token_service": token_service}
        request.headers = {"Authorization": f"Bearer {token}"}
        request.__setitem__ = MagicMock()  # ALLOWED: captures context injected onto the aiohttp request in a middleware unit test

        handler = AsyncMock(return_value=web.Response(text="ok"))

        await auth_middleware(request, handler)

        # Verify context was set
        set_calls = {
            call[0][0]: call[0][1] for call in request.__setitem__.call_args_list
        }
        assert "user_id" in set_calls
        assert set_calls["user_id"] == "user-123"
        assert "role" in set_calls
        assert set_calls["role"] == "admin"
        assert "org_id" in set_calls
        assert set_calls["org_id"] == "org-789"
        assert "device_id" in set_calls
        assert set_calls["device_id"] == "device-456"
        assert "permissions" in set_calls

    @pytest.mark.asyncio
    async def test_expired_token_returns_401(self, token_service, token_config):
        """Test that expired token returns 401."""
        from datetime import datetime, timedelta, timezone

        # Create an expired token manually
        now = datetime.now(timezone.utc)
        payload = {
            "iss": token_config.issuer,
            "sub": "user-123",
            "aud": token_config.audience,
            "exp": now - timedelta(hours=1),
            "iat": now - timedelta(hours=2),
            "jti": "test-id",
            "email": "test@example.com",
            "role": "user",
            "device_id": "device-456",
            "permissions": [],
        }
        expired_token = jwt.encode(
            payload, token_config.secret_key, algorithm=token_config.algorithm
        )

        request = MagicMock(spec=web.Request)
        request.path = "/api/protected"
        request.app = {"token_service": token_service}
        request.headers = {"Authorization": f"Bearer {expired_token}"}

        handler = AsyncMock()  # ALLOWED: test double for the aiohttp handler boundary in a middleware unit test

        with pytest.raises(web.HTTPUnauthorized):
            await auth_middleware(request, handler)

    @pytest.mark.asyncio
    async def test_invalid_token_returns_401(self, token_service):
        """Test that invalid token returns 401."""
        request = MagicMock(spec=web.Request)
        request.path = "/api/protected"
        request.app = {"token_service": token_service}
        request.headers = {"Authorization": "Bearer invalid-jwt-token"}

        handler = AsyncMock()  # ALLOWED: test double for the aiohttp handler boundary in a middleware unit test

        with pytest.raises(web.HTTPUnauthorized):
            await auth_middleware(request, handler)


class TestRequireAuth:
    """Tests for require_auth decorator."""

    @pytest.mark.asyncio
    async def test_require_auth_with_user(self):
        """Test that authenticated requests pass through."""

        @require_auth
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key == "user_id"
        request.__getitem__ = lambda self, key: "user-123" if key == "user_id" else None

        response = await handler(request)
        assert response.status == 200

    @pytest.mark.asyncio
    async def test_require_auth_without_user(self):
        """Test that unauthenticated requests return 401."""

        @require_auth
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: False

        with pytest.raises(web.HTTPUnauthorized):
            await handler(request)


class TestRequireRole:
    """Tests for require_role decorator."""

    @pytest.mark.asyncio
    async def test_require_role_with_correct_role(self):
        """Test that correct role passes through."""

        @require_role("admin", "super_admin")
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key in ["user_id", "role"]
        request.get = lambda key, default=None: "admin" if key == "role" else "user-123"

        response = await handler(request)
        assert response.status == 200

    @pytest.mark.asyncio
    async def test_require_role_with_wrong_role(self):
        """Test that wrong role returns 403."""

        @require_role("admin")
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key in ["user_id", "role"]
        request.get = lambda key, default=None: "user" if key == "role" else "user-123"

        with pytest.raises(web.HTTPForbidden):
            await handler(request)

    @pytest.mark.asyncio
    async def test_require_role_without_auth(self):
        """Test that unauthenticated returns 401."""

        @require_role("admin")
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: False

        with pytest.raises(web.HTTPUnauthorized):
            await handler(request)


class TestRequirePermission:
    """Tests for require_permission decorator."""

    @pytest.mark.asyncio
    async def test_require_permission_all_present(self):
        """Test with all required permissions present."""

        @require_permission("users:read", "users:write")
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key in ["user_id", "permissions"]
        request.get = (
            lambda key, default=None: ["users:read", "users:write", "extra"]
            if key == "permissions"
            else "user-123"
        )

        response = await handler(request)
        assert response.status == 200

    @pytest.mark.asyncio
    async def test_require_permission_missing_one(self):
        """Test with one required permission missing."""

        @require_permission("users:read", "users:delete")
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key in ["user_id", "permissions"]
        request.get = (
            lambda key, default=None: ["users:read"]
            if key == "permissions"
            else "user-123"
        )

        with pytest.raises(web.HTTPForbidden):
            await handler(request)

    @pytest.mark.asyncio
    async def test_require_permission_any_mode(self):
        """Test require_any mode (any one permission is sufficient)."""

        @require_permission("users:read", "users:write", require_all=False)
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key in ["user_id", "permissions"]
        request.get = (
            lambda key, default=None: ["users:read"]
            if key == "permissions"
            else "user-123"
        )

        response = await handler(request)
        assert response.status == 200

    @pytest.mark.asyncio
    async def test_require_permission_without_auth(self):
        """Test that unauthenticated returns 401."""

        @require_permission("users:read")
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: False

        with pytest.raises(web.HTTPUnauthorized):
            await handler(request)


class TestRequireOrgMembership:
    """Tests for require_org_membership decorator."""

    @pytest.mark.asyncio
    async def test_require_org_with_org(self):
        """Test with organization membership."""

        @require_org_membership
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key in ["user_id", "org_id"]
        request.get = (
            lambda key, default=None: "org-123" if key == "org_id" else "user-123"
        )

        response = await handler(request)
        assert response.status == 200

    @pytest.mark.asyncio
    async def test_require_org_without_org(self):
        """Test without organization membership returns 403."""

        @require_org_membership
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: key == "user_id"
        request.get = lambda key, default=None: None if key == "org_id" else "user-123"

        with pytest.raises(web.HTTPForbidden):
            await handler(request)

    @pytest.mark.asyncio
    async def test_require_org_without_auth(self):
        """Test that unauthenticated returns 401."""

        @require_org_membership
        async def handler(request):
            return web.Response(text="ok")

        request = MagicMock(spec=web.Request)
        request.__contains__ = lambda self, key: False

        with pytest.raises(web.HTTPUnauthorized):
            await handler(request)


class TestSetupTokenService:
    """Tests for setup_token_service function."""

    def test_setup_creates_token_service(self):
        """Test that setup creates a token service."""
        app = web.Application()
        service = setup_token_service(app, "test-secret-key")
        assert isinstance(service, TokenService)
        assert app["token_service"] is service

    def test_setup_with_custom_config(self):
        """Test setup with custom configuration."""
        app = web.Application()
        service = setup_token_service(
            app,
            "test-secret-key",
            access_token_lifetime_minutes=30,
        )
        assert service.config.access_token_lifetime_minutes == 30


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
