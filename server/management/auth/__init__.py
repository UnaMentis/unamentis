"""
UnaMentis Authentication Module

This module provides user authentication, device management, and session handling
for the UnaMentis Management API.

Components:
- auth_api: Route handlers for authentication endpoints
- auth_middleware: JWT validation middleware
- token_service: JWT and refresh token management (RFC 9700 compliant)
- password_service: Password hashing with bcrypt
- rate_limiter: Rate limiting for auth endpoints

Extension Points:
- Auth providers can be registered via register_auth_provider()
- Commercial plugins (SAML, OIDC, LDAP) extend the base AuthProviderPlugin class
"""

from .auth_api import AuthAPI, register_auth_routes
from .auth_middleware import (
    auth_middleware,
    require_auth,
    require_role,
    setup_token_service,
)
from .ip_retention import auth_ip_retention_loop, sweep_auth_ip_retention
from .token_service import TokenService, TokenConfig
from .password_service import PasswordService
from .rate_limiter import RateLimiter, rate_limit_middleware

__all__ = [
    "AuthAPI",
    "register_auth_routes",
    "auth_middleware",
    "auth_ip_retention_loop",
    "require_auth",
    "require_role",
    "setup_token_service",
    "sweep_auth_ip_retention",
    "TokenService",
    "TokenConfig",
    "PasswordService",
    "RateLimiter",
    "rate_limit_middleware",
]
