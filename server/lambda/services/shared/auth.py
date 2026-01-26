"""
Authentication utilities for Lambda functions.

Provides:
- Beta token validation (Tier 1: Client auth)
- JWT validation (for authenticated endpoints)
- Cloudflare Access header validation (Tier 2: Admin auth)
"""

import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import wraps
from typing import Any, Callable

import jwt

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


class AuthError(Exception):
    """Custom exception for authentication errors."""

    def __init__(self, message: str, status_code: int = 401):
        super().__init__(message)
        self.status_code = status_code


@dataclass
class User:
    """Authenticated user context."""

    id: str
    email: str
    is_admin: bool = False
    tenant_id: str | None = None
    session_id: str | None = None


def _get_beta_tokens() -> set[str]:
    """Get valid beta tokens from environment."""
    tokens_str = os.environ.get("BETA_TOKENS", "")
    if not tokens_str:
        return set()
    return {t.strip() for t in tokens_str.split(",") if t.strip()}


def _get_jwt_secret() -> str:
    """Get JWT secret from environment."""
    secret = os.environ.get("JWT_SECRET", "")
    if not secret:
        logger.warning("JWT_SECRET not set, using insecure default for development")
        return "insecure-dev-secret-do-not-use-in-prod"
    return secret


def validate_beta_token(token: str) -> bool:
    """
    Validate a beta token.

    Args:
        token: The token to validate (without "Bearer " prefix)

    Returns:
        True if token is valid, False otherwise
    """
    valid_tokens = _get_beta_tokens()

    # In development, allow any token if no tokens are configured
    if not valid_tokens:
        logger.warning("No beta tokens configured, allowing all tokens in dev mode")
        return bool(token)

    return token in valid_tokens


def validate_jwt(token: str) -> dict[str, Any]:
    """
    Validate and decode a JWT token.

    Args:
        token: The JWT token to validate (without "Bearer " prefix)

    Returns:
        Decoded token payload

    Raises:
        AuthError: If token is invalid or expired
    """
    try:
        payload = jwt.decode(
            token,
            _get_jwt_secret(),
            algorithms=["HS256"],
            options={"require": ["exp", "sub"]},
        )
        return payload
    except jwt.ExpiredSignatureError:
        raise AuthError("Token has expired")
    except jwt.InvalidTokenError as e:
        raise AuthError(f"Invalid token: {e}")


def get_current_user(event: dict[str, Any]) -> User | None:
    """
    Extract the current user from a Lambda event.

    Checks for:
    1. JWT in Authorization header
    2. Beta token in Authorization header
    3. Cloudflare Access headers (for admin)

    Args:
        event: Lambda event dict

    Returns:
        User object if authenticated, None otherwise
    """
    headers = event.get("headers", {}) or {}

    # Normalize header keys to lowercase
    headers = {k.lower(): v for k, v in headers.items()}

    # Check for Cloudflare Access (admin)
    cf_email = headers.get("cf-access-authenticated-user-email")
    if cf_email:
        return User(
            id=f"cf:{cf_email}",
            email=cf_email,
            is_admin=True,
        )

    # Check Authorization header
    auth_header = headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        return None

    token = auth_header[7:]  # Remove "Bearer " prefix

    # Try JWT first
    try:
        payload = validate_jwt(token)
        return User(
            id=payload.get("sub", ""),
            email=payload.get("email", ""),
            is_admin=payload.get("is_admin", False),
            tenant_id=payload.get("tenant_id"),
            session_id=payload.get("session_id"),
        )
    except AuthError:
        pass

    # Fall back to beta token
    if validate_beta_token(token):
        # Beta tokens create an anonymous user
        return User(
            id="beta:anonymous",
            email="beta@unamentis.net",
            is_admin=False,
        )

    return None


def require_auth(handler: Callable) -> Callable:
    """
    Decorator to require authentication on a Lambda handler.

    Usage:
        @require_auth
        def my_handler(event, context, user):
            return {"statusCode": 200, "body": f"Hello {user.email}"}
    """
    from .response import unauthorized_response

    @wraps(handler)
    def wrapper(event: dict[str, Any], context: Any) -> dict[str, Any]:
        user = get_current_user(event)
        if not user:
            return unauthorized_response("Authentication required")
        return handler(event, context, user)

    return wrapper


def require_admin(handler: Callable) -> Callable:
    """
    Decorator to require admin authentication on a Lambda handler.

    Usage:
        @require_admin
        def admin_handler(event, context, user):
            return {"statusCode": 200, "body": "Admin access granted"}
    """
    from .response import forbidden_response, unauthorized_response

    @wraps(handler)
    def wrapper(event: dict[str, Any], context: Any) -> dict[str, Any]:
        user = get_current_user(event)
        if not user:
            return unauthorized_response("Authentication required")
        if not user.is_admin:
            return forbidden_response("Admin access required")
        return handler(event, context, user)

    return wrapper


def validate_cloudflare_request(event: dict[str, Any]) -> bool:
    """
    Validate that a request came through Cloudflare.

    Checks:
    1. CF-Connecting-IP header is present
    2. Source IP is in Cloudflare IP ranges (optional, for production)

    Args:
        event: Lambda event dict

    Returns:
        True if request appears to come from Cloudflare
    """
    headers = event.get("headers", {}) or {}
    headers = {k.lower(): v for k, v in headers.items()}

    # Check for Cloudflare headers
    cf_ip = headers.get("cf-connecting-ip")
    if not cf_ip:
        logger.warning("Request missing CF-Connecting-IP header")
        # In development, allow requests without CF headers
        if os.environ.get("ENVIRONMENT") == "dev":
            return True
        return False

    return True


def create_jwt(
    user_id: str,
    email: str,
    is_admin: bool = False,
    tenant_id: str | None = None,
    expires_in_seconds: int = 3600,
) -> str:
    """
    Create a new JWT token.

    Args:
        user_id: User ID to encode in token
        email: User email
        is_admin: Whether user has admin privileges
        tenant_id: Tenant ID for multi-tenancy
        expires_in_seconds: Token expiration time

    Returns:
        Encoded JWT token string
    """
    now = datetime.now(timezone.utc)
    exp = int(now.timestamp()) + expires_in_seconds

    payload = {
        "sub": user_id,
        "email": email,
        "is_admin": is_admin,
        "exp": exp,
        "iat": int(now.timestamp()),
    }

    if tenant_id:
        payload["tenant_id"] = tenant_id

    return jwt.encode(payload, _get_jwt_secret(), algorithm="HS256")
