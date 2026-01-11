"""
Rate Limiter

Provides rate limiting for authentication endpoints using a token bucket algorithm.
Supports both in-memory (development) and Redis (production) backends.
"""

import asyncio
import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Callable, Dict, Optional, Tuple

from aiohttp import web

logger = logging.getLogger(__name__)


@dataclass
class RateLimitConfig:
    """Configuration for a rate limit."""
    requests: int  # Maximum requests allowed
    window_seconds: int  # Time window in seconds
    burst: Optional[int] = None  # Optional burst allowance

    def __post_init__(self):
        if self.burst is None:
            self.burst = self.requests


@dataclass
class RateLimitState:
    """State for tracking rate limits."""
    tokens: float
    last_update: float
    request_count: int = 0


# Default rate limit configurations per endpoint category
DEFAULT_LIMITS: Dict[str, RateLimitConfig] = {
    # Strict limits for auth endpoints
    'auth/login': RateLimitConfig(requests=5, window_seconds=60, burst=5),
    'auth/register': RateLimitConfig(requests=3, window_seconds=3600, burst=3),
    'auth/forgot-password': RateLimitConfig(requests=3, window_seconds=3600, burst=3),
    'auth/reset-password': RateLimitConfig(requests=5, window_seconds=3600, burst=5),
    'auth/refresh': RateLimitConfig(requests=60, window_seconds=60, burst=10),

    # Default for authenticated API calls
    'default': RateLimitConfig(requests=1000, window_seconds=60, burst=100),

    # Default for unauthenticated calls (relaxed for development)
    'unauthenticated': RateLimitConfig(requests=500, window_seconds=60, burst=100),
}


class InMemoryRateLimiter:
    """
    In-memory rate limiter using token bucket algorithm.
    Suitable for development and single-instance deployments.

    For production with multiple instances, use Redis-backed rate limiting.
    """

    def __init__(self, limits: Optional[Dict[str, RateLimitConfig]] = None):
        self.limits = limits or DEFAULT_LIMITS
        self._buckets: Dict[str, RateLimitState] = defaultdict(
            lambda: RateLimitState(tokens=0, last_update=time.time())
        )
        self._lock = asyncio.Lock()

    def get_limit_config(self, category: str) -> RateLimitConfig:
        """Get rate limit config for a category."""
        return self.limits.get(category, self.limits['default'])

    async def check_rate_limit(
        self,
        key: str,
        category: str = 'default'
    ) -> Tuple[bool, Dict[str, int]]:
        """
        Check if a request is within rate limits.

        Args:
            key: Unique identifier (e.g., IP address, user ID)
            category: Rate limit category (e.g., 'auth/login')

        Returns:
            Tuple of (allowed, headers_dict)
            - allowed: True if request should be allowed
            - headers_dict: Rate limit headers to include in response
        """
        config = self.get_limit_config(category)
        bucket_key = f"{category}:{key}"

        async with self._lock:
            now = time.time()
            state = self._buckets[bucket_key]

            # Calculate tokens to add based on time passed
            time_passed = now - state.last_update
            refill_rate = config.requests / config.window_seconds
            tokens_to_add = time_passed * refill_rate

            # Update bucket
            state.tokens = min(config.burst, state.tokens + tokens_to_add)
            state.last_update = now

            # Check if we have tokens available
            if state.tokens >= 1:
                state.tokens -= 1
                state.request_count += 1
                allowed = True
            else:
                allowed = False

            # Calculate headers
            remaining = max(0, int(state.tokens))
            reset_time = int(now + (config.window_seconds - (now % config.window_seconds)))

            headers = {
                'X-RateLimit-Limit': config.requests,
                'X-RateLimit-Remaining': remaining,
                'X-RateLimit-Reset': reset_time,
                'X-RateLimit-Window': config.window_seconds,
            }

            if not allowed:
                # Calculate retry-after
                tokens_needed = 1 - state.tokens
                retry_after = int(tokens_needed / refill_rate) + 1
                headers['Retry-After'] = retry_after

            return allowed, headers

    async def reset(self, key: str, category: str = 'default') -> None:
        """Reset rate limit for a key (e.g., after successful auth)."""
        bucket_key = f"{category}:{key}"
        async with self._lock:
            if bucket_key in self._buckets:
                del self._buckets[bucket_key]

    async def cleanup_expired(self, max_age_seconds: int = 3600) -> int:
        """Remove expired bucket entries to free memory."""
        now = time.time()
        expired_keys = []

        async with self._lock:
            for key, state in self._buckets.items():
                if now - state.last_update > max_age_seconds:
                    expired_keys.append(key)

            for key in expired_keys:
                del self._buckets[key]

        return len(expired_keys)


# Alias for backwards compatibility
RateLimiter = InMemoryRateLimiter


def get_rate_limit_category(path: str) -> str:
    """
    Determine rate limit category from request path.

    Args:
        path: The request path (e.g., '/api/auth/login')

    Returns:
        The rate limit category
    """
    # Remove /api/ prefix if present
    if path.startswith('/api/'):
        path = path[5:]

    # Check for known categories
    for category in DEFAULT_LIMITS.keys():
        if category != 'default' and category != 'unauthenticated':
            if path.startswith(category):
                return category

    return 'default'


def get_client_identifier(request: web.Request) -> str:
    """
    Get a unique identifier for rate limiting.
    Uses user ID if authenticated, otherwise IP address.

    Args:
        request: The aiohttp request

    Returns:
        A string identifier for rate limiting
    """
    # Use user ID if authenticated
    user_id = request.get('user_id')
    if user_id:
        return f"user:{user_id}"

    # Fall back to IP address
    # Check for forwarded headers (behind proxy)
    forwarded = request.headers.get('X-Forwarded-For')
    if forwarded:
        # Take the first IP (client IP)
        return f"ip:{forwarded.split(',')[0].strip()}"

    real_ip = request.headers.get('X-Real-IP')
    if real_ip:
        return f"ip:{real_ip}"

    # Direct connection
    if request.remote:
        return f"ip:{request.remote}"

    return "ip:unknown"


@web.middleware
async def rate_limit_middleware(request: web.Request, handler: Callable) -> web.Response:
    """
    Middleware to apply rate limiting to requests.

    Adds rate limit headers to all responses and returns 429 if limit exceeded.
    """
    rate_limiter: Optional[RateLimiter] = request.app.get('rate_limiter')
    if not rate_limiter:
        # Rate limiting not configured, allow all requests
        return await handler(request)

    # Determine category and identifier
    category = get_rate_limit_category(request.path)

    # Use different category for unauthenticated requests
    if 'user_id' not in request and category == 'default':
        category = 'unauthenticated'

    identifier = get_client_identifier(request)

    # Check rate limit
    allowed, headers = await rate_limiter.check_rate_limit(identifier, category)

    if not allowed:
        logger.warning(
            f"Rate limit exceeded: {identifier} on {request.path} (category: {category})"
        )
        response = web.json_response(
            {
                "error": "Rate limit exceeded",
                "code": "RATE_LIMIT_EXCEEDED",
                "retry_after": headers.get('Retry-After', 60)
            },
            status=429
        )
        for header, value in headers.items():
            response.headers[header] = str(value)
        return response

    # Process request
    response = await handler(request)

    # Add rate limit headers to response
    for header, value in headers.items():
        response.headers[header] = str(value)

    return response


def setup_rate_limiter(
    app: web.Application,
    limits: Optional[Dict[str, RateLimitConfig]] = None
) -> RateLimiter:
    """
    Set up rate limiting for an aiohttp application.

    Args:
        app: The aiohttp application
        limits: Optional custom rate limit configurations

    Returns:
        The configured RateLimiter instance
    """
    rate_limiter = RateLimiter(limits)
    app['rate_limiter'] = rate_limiter

    # Schedule periodic cleanup
    async def cleanup_task():
        while True:
            await asyncio.sleep(300)  # Every 5 minutes
            try:
                cleaned = await rate_limiter.cleanup_expired()
                if cleaned > 0:
                    logger.debug(f"Cleaned up {cleaned} expired rate limit entries")
            except Exception as e:
                logger.error(f"Error in rate limit cleanup: {e}")

    async def start_cleanup(app):
        app['rate_limit_cleanup_task'] = asyncio.create_task(cleanup_task())

    async def stop_cleanup(app):
        task = app.get('rate_limit_cleanup_task')
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

    app.on_startup.append(start_cleanup)
    app.on_cleanup.append(stop_cleanup)

    return rate_limiter
