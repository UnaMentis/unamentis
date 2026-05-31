"""
Authentication Middleware

Provides JWT validation middleware for protected API routes.
"""

import functools
import logging
from typing import Callable, List, Optional, Set

from aiohttp import web
import jwt

from .token_service import TokenService, TokenConfig

logger = logging.getLogger(__name__)

# Public routes that don't require authentication
PUBLIC_ROUTES: Set[str] = {
    "/health",
    "/api/health",
    "/api/auth/login",
    "/api/auth/register",
    "/api/auth/refresh",
    "/api/auth/forgot-password",
    "/api/auth/reset-password",
    "/api/auth/oauth/google/authorize",
    "/api/auth/oauth/google/callback",
    "/api/auth/oauth/apple/authorize",
    "/api/auth/oauth/apple/callback",
    "/api/auth/oauth/github/authorize",
    "/api/auth/oauth/github/callback",
}

# Routes that start with these prefixes are public.
#
# The API is DEFAULT-DENY: this list is kept deliberately minimal. OAuth callback
# subpaths are the only namespace that needs prefix matching. Every other
# namespace (admin, curricula, tts, plugins, deployments, import, sources,
# system, models, services, kb, modules, sessions, fov, ws, stats, clients,
# servers) now requires a valid access token. Mutating and administrative
# handlers additionally enforce require_role('admin'/'super_admin').
#
# The previous "internal/trusted networks" assumption was false: the server can
# bind non-loopback and is documented to be exposed via tunnels, so leaving these
# namespaces public made every mutating endpoint reachable unauthenticated.
PUBLIC_PREFIXES: List[str] = [
    "/api/auth/oauth/",
]

# Paths that are public for specific HTTP methods only. Used for unauthenticated
# client telemetry intake; reading or clearing the same path still requires auth
# (e.g. POST /api/logs is intake, DELETE /api/logs clears and stays protected).
PUBLIC_METHOD_ROUTES: dict = {
    "/api/logs": {"POST"},
    "/api/metrics": {"POST"},
}


def is_public_route(path: str, method: str = "GET") -> bool:
    """Check if a route is public (doesn't require auth).

    Uses strict prefix matching to avoid matching unintended paths.
    For example, '/api/auth/oauth' should match '/api/auth/oauth/google'
    but not '/api/auth/oauthX'. Method-specific public routes (telemetry
    intake) are honored only for their allowed methods.
    """
    if path in PUBLIC_ROUTES:
        return True
    allowed_methods = PUBLIC_METHOD_ROUTES.get(path)
    if allowed_methods and method.upper() in allowed_methods:
        return True
    for prefix in PUBLIC_PREFIXES:
        # Require exact match or slash-delimited boundary
        normalized_prefix = prefix.rstrip("/")
        if path == normalized_prefix or path.startswith(normalized_prefix + "/"):
            return True
    return False


@web.middleware
async def auth_middleware(request: web.Request, handler: Callable) -> web.Response:
    """
    Middleware to validate JWT access tokens on protected routes.

    Extracts the token from the Authorization header, validates it,
    and injects user context into the request.

    Request attributes set:
        - request['user']: AccessTokenPayload with user info
        - request['user_id']: User UUID string
        - request['org_id']: Organization UUID string (or None)
        - request['role']: User role string
        - request['device_id']: Device UUID string
        - request['permissions']: List of permission strings
    """
    # Skip auth for public routes (method-aware for telemetry intake)
    if is_public_route(request.path, request.method):
        return await handler(request)

    # Get token service from app
    token_service: Optional[TokenService] = request.app.get("token_service")
    if not token_service:
        logger.error("Token service not configured")
        raise web.HTTPInternalServerError(
            text='{"error": "Authentication not configured"}',
            content_type="application/json",
        )

    # Extract token from Authorization header
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise web.HTTPUnauthorized(
            text='{"error": "Missing or invalid Authorization header", "code": "AUTH_REQUIRED"}',
            content_type="application/json",
            headers={"WWW-Authenticate": 'Bearer realm="unamentis"'},
        )

    token = auth_header[7:]  # Remove 'Bearer ' prefix

    try:
        # Validate token
        payload = token_service.validate_access_token(token)

        # Inject user context into request
        request["user"] = payload
        request["user_id"] = payload.user_id
        request["org_id"] = payload.organization_id
        request["role"] = payload.role
        request["device_id"] = payload.device_id
        request["permissions"] = payload.permissions

    except jwt.ExpiredSignatureError:
        raise web.HTTPUnauthorized(
            text='{"error": "Token expired", "code": "TOKEN_EXPIRED"}',
            content_type="application/json",
            headers={
                "WWW-Authenticate": 'Bearer realm="unamentis", error="invalid_token", error_description="Token expired"'
            },
        )
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid token: {e}")
        raise web.HTTPUnauthorized(
            text='{"error": "Invalid token", "code": "TOKEN_INVALID"}',
            content_type="application/json",
            headers={
                "WWW-Authenticate": 'Bearer realm="unamentis", error="invalid_token"'
            },
        )

    return await handler(request)


def require_auth(handler: Callable) -> Callable:
    """
    Decorator to require authentication for a specific handler.
    Use this for routes that need explicit auth checking.

    Usage:
        @require_auth
        async def my_handler(request):
            user_id = request['user_id']
            ...
    """

    @functools.wraps(handler)
    async def wrapper(request: web.Request) -> web.Response:
        if "user_id" not in request:
            raise web.HTTPUnauthorized(
                text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                content_type="application/json",
            )
        return await handler(request)

    return wrapper


def require_role(*allowed_roles: str) -> Callable:
    """
    Decorator to require specific roles for a handler.

    Usage:
        @require_role('admin', 'super_admin')
        async def admin_only_handler(request):
            ...
    """

    def decorator(handler: Callable) -> Callable:
        @functools.wraps(handler)
        async def wrapper(request: web.Request) -> web.Response:
            if "user_id" not in request:
                raise web.HTTPUnauthorized(
                    text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                    content_type="application/json",
                )

            user_role = request.get("role", "user")
            if user_role not in allowed_roles:
                raise web.HTTPForbidden(
                    text=f'{{"error": "Insufficient permissions", "code": "FORBIDDEN", "required_roles": {list(allowed_roles)}}}',
                    content_type="application/json",
                )

            return await handler(request)

        return wrapper

    return decorator


def require_permission(
    *required_permissions: str, require_all: bool = True
) -> Callable:
    """
    Decorator to require specific permissions for a handler.

    Args:
        *required_permissions: Permission strings to check
        require_all: If True, all permissions required. If False, any one is sufficient.

    Usage:
        @require_permission('users:read', 'users:write')
        async def user_management_handler(request):
            ...
    """

    def decorator(handler: Callable) -> Callable:
        @functools.wraps(handler)
        async def wrapper(request: web.Request) -> web.Response:
            if "user_id" not in request:
                raise web.HTTPUnauthorized(
                    text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                    content_type="application/json",
                )

            user_permissions = set(request.get("permissions", []))

            if require_all:
                has_permission = all(
                    p in user_permissions for p in required_permissions
                )
            else:
                has_permission = any(
                    p in user_permissions for p in required_permissions
                )

            if not has_permission:
                raise web.HTTPForbidden(
                    text=f'{{"error": "Insufficient permissions", "code": "FORBIDDEN", "required_permissions": {list(required_permissions)}}}',
                    content_type="application/json",
                )

            return await handler(request)

        return wrapper

    return decorator


def require_org_membership(handler: Callable) -> Callable:
    """
    Decorator to require that the user belongs to an organization.

    Usage:
        @require_org_membership
        async def org_resource_handler(request):
            org_id = request['org_id']  # Guaranteed to be set
            ...
    """

    @functools.wraps(handler)
    async def wrapper(request: web.Request) -> web.Response:
        if "user_id" not in request:
            raise web.HTTPUnauthorized(
                text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                content_type="application/json",
            )

        if not request.get("org_id"):
            raise web.HTTPForbidden(
                text='{"error": "Organization membership required", "code": "ORG_REQUIRED"}',
                content_type="application/json",
            )

        return await handler(request)

    return wrapper


def setup_token_service(
    app: web.Application, secret_key: str, **kwargs
) -> TokenService:
    """
    Set up the token service for an aiohttp application.

    Args:
        app: The aiohttp application
        secret_key: The secret key for JWT signing
        **kwargs: Additional TokenConfig parameters

    Returns:
        The configured TokenService
    """
    config = TokenConfig(secret_key=secret_key, **kwargs)
    token_service = TokenService(config)
    app["token_service"] = token_service
    return token_service
