"""
Authentication Middleware

Provides JWT validation middleware for protected API routes.
"""

import functools
import logging
from typing import Callable, List, Optional, Set

from aiohttp import web
import jwt

from .token_service import TokenService, TokenConfig, AccessTokenPayload

logger = logging.getLogger(__name__)

# Public routes that don't require authentication
PUBLIC_ROUTES: Set[str] = {
    '/health',
    '/api/health',
    '/api/auth/login',
    '/api/auth/register',
    '/api/auth/refresh',
    '/api/auth/forgot-password',
    '/api/auth/reset-password',
    '/api/auth/oauth/google/authorize',
    '/api/auth/oauth/google/callback',
    '/api/auth/oauth/apple/authorize',
    '/api/auth/oauth/apple/callback',
    '/api/auth/oauth/github/authorize',
    '/api/auth/oauth/github/callback',
}

# Routes that start with these prefixes are public
# Note: Management console routes are public as they run on internal/trusted networks
PUBLIC_PREFIXES: List[str] = [
    '/api/auth/oauth/',
    '/api/admin/',          # Admin management console routes
    '/api/stats',           # Dashboard stats
    '/api/metrics',         # Dashboard metrics
    '/api/logs',            # Dashboard logs
    '/api/clients',         # Dashboard clients
    '/api/servers',         # Dashboard servers
    '/api/curricula',       # Curriculum management
    '/api/system/',         # System configuration
    '/api/import/',         # Import management
    '/api/sources',         # Source management
    '/api/plugins',         # Plugin management
    '/api/models',          # Model management
    '/ws',                  # WebSocket connections
]


def is_public_route(path: str) -> bool:
    """Check if a route is public (doesn't require auth)."""
    if path in PUBLIC_ROUTES:
        return True
    for prefix in PUBLIC_PREFIXES:
        if path.startswith(prefix):
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
    # Skip auth for public routes
    if is_public_route(request.path):
        return await handler(request)

    # Get token service from app
    token_service: Optional[TokenService] = request.app.get('token_service')
    if not token_service:
        logger.error("Token service not configured")
        raise web.HTTPInternalServerError(
            text='{"error": "Authentication not configured"}',
            content_type='application/json'
        )

    # Extract token from Authorization header
    auth_header = request.headers.get('Authorization', '')
    if not auth_header.startswith('Bearer '):
        raise web.HTTPUnauthorized(
            text='{"error": "Missing or invalid Authorization header", "code": "AUTH_REQUIRED"}',
            content_type='application/json',
            headers={'WWW-Authenticate': 'Bearer realm="unamentis"'}
        )

    token = auth_header[7:]  # Remove 'Bearer ' prefix

    try:
        # Validate token
        payload = token_service.validate_access_token(token)

        # Inject user context into request
        request['user'] = payload
        request['user_id'] = payload.user_id
        request['org_id'] = payload.organization_id
        request['role'] = payload.role
        request['device_id'] = payload.device_id
        request['permissions'] = payload.permissions

    except jwt.ExpiredSignatureError:
        raise web.HTTPUnauthorized(
            text='{"error": "Token expired", "code": "TOKEN_EXPIRED"}',
            content_type='application/json',
            headers={'WWW-Authenticate': 'Bearer realm="unamentis", error="invalid_token", error_description="Token expired"'}
        )
    except jwt.InvalidTokenError as e:
        logger.warning(f"Invalid token: {e}")
        raise web.HTTPUnauthorized(
            text='{"error": "Invalid token", "code": "TOKEN_INVALID"}',
            content_type='application/json',
            headers={'WWW-Authenticate': 'Bearer realm="unamentis", error="invalid_token"'}
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
        if 'user_id' not in request:
            raise web.HTTPUnauthorized(
                text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                content_type='application/json'
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
            if 'user_id' not in request:
                raise web.HTTPUnauthorized(
                    text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                    content_type='application/json'
                )

            user_role = request.get('role', 'user')
            if user_role not in allowed_roles:
                raise web.HTTPForbidden(
                    text=f'{{"error": "Insufficient permissions", "code": "FORBIDDEN", "required_roles": {list(allowed_roles)}}}',
                    content_type='application/json'
                )

            return await handler(request)
        return wrapper
    return decorator


def require_permission(*required_permissions: str, require_all: bool = True) -> Callable:
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
            if 'user_id' not in request:
                raise web.HTTPUnauthorized(
                    text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                    content_type='application/json'
                )

            user_permissions = set(request.get('permissions', []))

            if require_all:
                has_permission = all(p in user_permissions for p in required_permissions)
            else:
                has_permission = any(p in user_permissions for p in required_permissions)

            if not has_permission:
                raise web.HTTPForbidden(
                    text=f'{{"error": "Insufficient permissions", "code": "FORBIDDEN", "required_permissions": {list(required_permissions)}}}',
                    content_type='application/json'
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
        if 'user_id' not in request:
            raise web.HTTPUnauthorized(
                text='{"error": "Authentication required", "code": "AUTH_REQUIRED"}',
                content_type='application/json'
            )

        if not request.get('org_id'):
            raise web.HTTPForbidden(
                text='{"error": "Organization membership required", "code": "ORG_REQUIRED"}',
                content_type='application/json'
            )

        return await handler(request)
    return wrapper


def setup_token_service(app: web.Application, secret_key: str, **kwargs) -> TokenService:
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
    app['token_service'] = token_service
    return token_service
