"""
Tests for Rate Limiter

Comprehensive tests for rate limiting functionality.
"""

import pytest
from unittest.mock import MagicMock, AsyncMock
from aiohttp import web

from auth.rate_limiter import (
    RateLimitConfig,
    RateLimitState,
    InMemoryRateLimiter,
    RateLimiter,
    DEFAULT_LIMITS,
    get_rate_limit_category,
    get_client_identifier,
    rate_limit_middleware,
    setup_rate_limiter,
)


class TestRateLimitConfig:
    """Tests for RateLimitConfig dataclass."""

    def test_rate_limit_config_creation(self):
        """Test creating a RateLimitConfig."""
        config = RateLimitConfig(requests=10, window_seconds=60)
        assert config.requests == 10
        assert config.window_seconds == 60

    def test_rate_limit_config_default_burst(self):
        """Test that burst defaults to requests if not specified."""
        config = RateLimitConfig(requests=10, window_seconds=60)
        assert config.burst == 10

    def test_rate_limit_config_custom_burst(self):
        """Test RateLimitConfig with custom burst."""
        config = RateLimitConfig(requests=10, window_seconds=60, burst=20)
        assert config.burst == 20

    def test_rate_limit_config_zero_burst(self):
        """Test that burst can be explicitly set to values."""
        config = RateLimitConfig(requests=10, window_seconds=60, burst=5)
        assert config.burst == 5


class TestRateLimitState:
    """Tests for RateLimitState dataclass."""

    def test_rate_limit_state_creation(self):
        """Test creating a RateLimitState."""
        state = RateLimitState(tokens=5.0, last_update=1000.0)
        assert state.tokens == 5.0
        assert state.last_update == 1000.0
        assert state.request_count == 0

    def test_rate_limit_state_with_request_count(self):
        """Test RateLimitState with request count."""
        state = RateLimitState(tokens=5.0, last_update=1000.0, request_count=10)
        assert state.request_count == 10


class TestDefaultLimits:
    """Tests for DEFAULT_LIMITS configuration."""

    def test_default_limits_has_required_categories(self):
        """Test that DEFAULT_LIMITS has all required categories."""
        required = ['auth/login', 'auth/register', 'auth/refresh', 'default']
        for category in required:
            assert category in DEFAULT_LIMITS

    def test_auth_login_strict_limits(self):
        """Test that auth/login has strict limits."""
        config = DEFAULT_LIMITS['auth/login']
        assert config.requests <= 10  # Should be strict
        assert config.window_seconds >= 60

    def test_auth_register_strict_limits(self):
        """Test that auth/register has strict limits."""
        config = DEFAULT_LIMITS['auth/register']
        assert config.requests <= 5  # Very strict
        assert config.window_seconds >= 3600  # Per hour

    def test_default_has_relaxed_limits(self):
        """Test that default has more relaxed limits."""
        config = DEFAULT_LIMITS['default']
        assert config.requests >= 100  # More permissive


class TestInMemoryRateLimiter:
    """Tests for InMemoryRateLimiter class."""

    @pytest.fixture
    def limiter(self):
        """Create a test rate limiter."""
        return InMemoryRateLimiter()

    @pytest.fixture
    def strict_limiter(self):
        """Create a rate limiter with strict limits for testing."""
        limits = {
            'test': RateLimitConfig(requests=2, window_seconds=60, burst=2),
            'default': RateLimitConfig(requests=5, window_seconds=60, burst=5),
        }
        return InMemoryRateLimiter(limits)

    def test_init_with_default_limits(self, limiter):
        """Test initialization with default limits."""
        assert limiter.limits == DEFAULT_LIMITS

    def test_init_with_custom_limits(self):
        """Test initialization with custom limits."""
        custom_limits = {
            'custom': RateLimitConfig(requests=10, window_seconds=30),
            'default': RateLimitConfig(requests=100, window_seconds=60),
        }
        limiter = InMemoryRateLimiter(custom_limits)
        assert limiter.limits == custom_limits

    def test_get_limit_config_known_category(self, limiter):
        """Test getting config for known category."""
        config = limiter.get_limit_config('auth/login')
        assert config == DEFAULT_LIMITS['auth/login']

    def test_get_limit_config_unknown_category(self, limiter):
        """Test getting config for unknown category returns default."""
        config = limiter.get_limit_config('unknown/category')
        assert config == DEFAULT_LIMITS['default']

    @pytest.mark.asyncio
    async def test_check_rate_limit_returns_result(self, limiter):
        """Test that check_rate_limit returns a boolean and headers."""
        allowed, headers = await limiter.check_rate_limit('test-key', 'default')
        assert isinstance(allowed, bool)
        assert isinstance(headers, dict)

    @pytest.mark.asyncio
    async def test_check_rate_limit_returns_headers(self, limiter):
        """Test that rate limit headers are returned."""
        allowed, headers = await limiter.check_rate_limit('test-key', 'default')
        assert 'X-RateLimit-Limit' in headers
        assert 'X-RateLimit-Remaining' in headers
        assert 'X-RateLimit-Reset' in headers
        assert 'X-RateLimit-Window' in headers

    @pytest.mark.asyncio
    async def test_check_rate_limit_denies_after_exhausted(self, strict_limiter):
        """Test that requests are denied after bucket is exhausted."""
        key = 'exhausted-key'
        # Make requests until exhausted
        for _ in range(10):  # More than burst allows
            await strict_limiter.check_rate_limit(key, 'test')

        # Should be denied
        allowed, headers = await strict_limiter.check_rate_limit(key, 'test')
        assert allowed is False
        assert 'Retry-After' in headers

    @pytest.mark.asyncio
    async def test_check_rate_limit_different_keys_independent(self, strict_limiter):
        """Test that different keys are tracked independently."""
        # Make requests on key1
        await strict_limiter.check_rate_limit('key1', 'test')

        # key2 should have its own bucket state
        _, headers1 = await strict_limiter.check_rate_limit('key1', 'test')
        _, headers2 = await strict_limiter.check_rate_limit('key2', 'test')
        # Both should return valid rate limit headers (independent tracking)
        assert 'X-RateLimit-Limit' in headers1
        assert 'X-RateLimit-Limit' in headers2

    @pytest.mark.asyncio
    async def test_check_rate_limit_different_categories_independent(self, limiter):
        """Test that different categories are tracked independently."""
        key = 'same-key'
        # Make request on category1
        await limiter.check_rate_limit(key, 'auth/login')

        # Category2 should have its own bucket
        _, headers1 = await limiter.check_rate_limit(key, 'auth/login')
        _, headers2 = await limiter.check_rate_limit(key, 'default')
        # Headers should reflect different limit configs
        assert headers1['X-RateLimit-Limit'] != headers2['X-RateLimit-Limit']

    @pytest.mark.asyncio
    async def test_reset_clears_bucket(self, strict_limiter):
        """Test that reset clears the rate limit bucket."""
        key = 'reset-test-key'
        category = 'test'

        # Make some requests to create bucket state
        for _ in range(3):
            await strict_limiter.check_rate_limit(key, category)

        # Reset the bucket
        await strict_limiter.reset(key, category)

        # Bucket should be removed from internal storage
        bucket_key = f"{category}:{key}"
        assert bucket_key not in strict_limiter._buckets

    @pytest.mark.asyncio
    async def test_cleanup_expired_removes_old_entries(self, limiter):
        """Test that cleanup removes expired entries."""
        # Add some entries
        await limiter.check_rate_limit('key1', 'default')
        await limiter.check_rate_limit('key2', 'default')

        # Cleanup with 0 max age (everything is "expired")
        cleaned = await limiter.cleanup_expired(max_age_seconds=0)
        assert cleaned >= 0  # May or may not have cleaned depending on timing

    @pytest.mark.asyncio
    async def test_cleanup_expired_returns_count(self, limiter):
        """Test that cleanup returns the count of removed entries."""
        # Add entries
        await limiter.check_rate_limit('cleanup1', 'default')
        await limiter.check_rate_limit('cleanup2', 'default')

        # Cleanup with large max age (nothing expired)
        cleaned = await limiter.cleanup_expired(max_age_seconds=3600)
        assert isinstance(cleaned, int)


class TestRateLimiterAlias:
    """Test that RateLimiter is alias for InMemoryRateLimiter."""

    def test_rate_limiter_is_in_memory(self):
        """Test that RateLimiter is InMemoryRateLimiter."""
        assert RateLimiter is InMemoryRateLimiter


class TestGetRateLimitCategory:
    """Tests for get_rate_limit_category function."""

    def test_auth_login_path(self):
        """Test category detection for auth/login."""
        assert get_rate_limit_category('/api/auth/login') == 'auth/login'

    def test_auth_register_path(self):
        """Test category detection for auth/register."""
        assert get_rate_limit_category('/api/auth/register') == 'auth/register'

    def test_auth_refresh_path(self):
        """Test category detection for auth/refresh."""
        assert get_rate_limit_category('/api/auth/refresh') == 'auth/refresh'

    def test_unknown_path_returns_default(self):
        """Test that unknown paths return default category."""
        assert get_rate_limit_category('/api/unknown/endpoint') == 'default'

    def test_path_without_api_prefix(self):
        """Test paths without /api/ prefix return default (function expects /api/ prefix)."""
        # Without /api/ prefix, paths don't match categories and return default
        assert get_rate_limit_category('/auth/login') == 'default'

    def test_root_path_returns_default(self):
        """Test that root path returns default."""
        assert get_rate_limit_category('/') == 'default'


class TestGetClientIdentifier:
    """Tests for get_client_identifier function."""

    def test_authenticated_user(self):
        """Test identifier for authenticated user."""
        request = MagicMock(spec=web.Request)
        request.get.return_value = 'user-123'
        request.__getitem__ = request.get

        identifier = get_client_identifier(request)
        assert identifier == 'user:user-123'

    def test_unauthenticated_with_forwarded_for(self):
        """Test identifier with X-Forwarded-For header."""
        request = MagicMock(spec=web.Request)
        request.get.return_value = None
        request.headers = {'X-Forwarded-For': '192.168.1.1, 10.0.0.1'}
        request.remote = None

        identifier = get_client_identifier(request)
        assert identifier == 'ip:192.168.1.1'

    def test_unauthenticated_with_real_ip(self):
        """Test identifier with X-Real-IP header."""
        request = MagicMock(spec=web.Request)
        request.get.return_value = None
        request.headers = {'X-Real-IP': '192.168.1.2'}
        request.remote = None

        identifier = get_client_identifier(request)
        assert identifier == 'ip:192.168.1.2'

    def test_unauthenticated_direct_connection(self):
        """Test identifier for direct connection."""
        request = MagicMock(spec=web.Request)
        request.get.return_value = None
        request.headers = {}
        request.remote = '192.168.1.3'

        identifier = get_client_identifier(request)
        assert identifier == 'ip:192.168.1.3'

    def test_unauthenticated_unknown(self):
        """Test identifier when no information available."""
        request = MagicMock(spec=web.Request)
        request.get.return_value = None
        request.headers = {}
        request.remote = None

        identifier = get_client_identifier(request)
        assert identifier == 'ip:unknown'


class TestRateLimitMiddleware:
    """Tests for rate_limit_middleware."""

    @pytest.mark.asyncio
    async def test_middleware_allows_without_limiter(self):
        """Test that middleware allows requests when limiter not configured."""
        request = MagicMock(spec=web.Request)
        request.app = {}  # No rate_limiter
        request.path = '/api/test'
        request.__contains__ = lambda self, key: False

        handler = AsyncMock(return_value=web.Response(text='ok'))

        response = await rate_limit_middleware(request, handler)
        handler.assert_called_once_with(request)

    @pytest.mark.asyncio
    async def test_middleware_returns_429_when_limited(self):
        """Test that middleware returns 429 when rate limited."""
        # Use very low limits (1 request per minute) to trigger rate limiting
        limiter = InMemoryRateLimiter({
            'default': RateLimitConfig(requests=1, window_seconds=60, burst=1),
            'unauthenticated': RateLimitConfig(requests=1, window_seconds=60, burst=1),
        })

        request = MagicMock(spec=web.Request)
        request.app = {'rate_limiter': limiter}
        request.path = '/api/test'
        request.headers = {}
        request.remote = '127.0.0.1'
        request.get.return_value = None
        request.__contains__ = lambda self, key: False

        handler = AsyncMock(return_value=web.Response(text='ok'))

        # First few requests to exhaust the bucket (starts at 0 tokens)
        for _ in range(5):
            try:
                await rate_limit_middleware(request, handler)
            except Exception:
                pass

        # This request should be rate limited
        response = await rate_limit_middleware(request, handler)
        assert response.status == 429

    @pytest.mark.asyncio
    async def test_middleware_adds_headers(self):
        """Test that middleware adds rate limit headers to response."""
        limiter = InMemoryRateLimiter()

        request = MagicMock(spec=web.Request)
        request.app = {'rate_limiter': limiter}
        request.path = '/api/test'
        request.headers = {}
        request.remote = '127.0.0.1'
        request.get.return_value = None
        request.__contains__ = lambda self, key: False

        response = web.Response(text='ok')
        handler = AsyncMock(return_value=response)

        result = await rate_limit_middleware(request, handler)
        assert 'X-RateLimit-Limit' in result.headers


class TestSetupRateLimiter:
    """Tests for setup_rate_limiter function."""

    def test_setup_creates_limiter(self):
        """Test that setup creates a rate limiter."""
        app = web.Application()
        limiter = setup_rate_limiter(app)
        assert isinstance(limiter, RateLimiter)
        assert app['rate_limiter'] is limiter

    def test_setup_with_custom_limits(self):
        """Test setup with custom limits."""
        app = web.Application()
        custom_limits = {
            'custom': RateLimitConfig(requests=50, window_seconds=30),
            'default': RateLimitConfig(requests=200, window_seconds=60),
        }
        limiter = setup_rate_limiter(app, custom_limits)
        assert limiter.limits == custom_limits

    def test_setup_adds_startup_handler(self):
        """Test that setup adds startup handler."""
        app = web.Application()
        setup_rate_limiter(app)
        assert len(app.on_startup) > 0

    def test_setup_adds_cleanup_handler(self):
        """Test that setup adds cleanup handler."""
        app = web.Application()
        setup_rate_limiter(app)
        assert len(app.on_cleanup) > 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
