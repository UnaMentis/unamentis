"""
Auth service Lambda handler.

Routes:
- GET  /api/health              - Health check (public)
- POST /api/auth/register       - User registration
- POST /api/auth/login          - User login
- POST /api/auth/refresh        - Token refresh
- POST /api/auth/logout         - User logout
- GET  /api/auth/me             - Get current user
- POST /api/auth/forgot-password - Password reset request
- POST /api/auth/reset-password  - Password reset confirm
- GET  /api/auth/verify-email   - Email verification
- POST /api/auth/resend-verification - Resend verification
- GET  /api/auth/sessions       - List sessions
- DELETE /api/auth/sessions/{sessionId} - Revoke session
"""

import logging
import os
from typing import Any

# Add shared module to path
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared import db
from shared.auth import (
    create_jwt,
    get_current_user,
    require_auth,
    validate_beta_token,
)
from shared.response import (
    created_response,
    error_response,
    get_path_parameter,
    internal_error_response,
    no_content_response,
    not_found_response,
    parse_body,
    success_response,
    unauthorized_response,
    validation_error_response,
)

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Main Lambda handler - routes requests to appropriate functions.
    """
    http_method = event.get("httpMethod", "")
    path = event.get("path", "")

    logger.info(f"Auth service: {http_method} {path}")

    try:
        # Health check (public)
        if path == "/api/health" and http_method == "GET":
            return handle_health(event, context)

        # Auth routes
        if path == "/api/auth/register" and http_method == "POST":
            return handle_register(event, context)

        if path == "/api/auth/login" and http_method == "POST":
            return handle_login(event, context)

        if path == "/api/auth/refresh" and http_method == "POST":
            return handle_refresh(event, context)

        if path == "/api/auth/logout" and http_method == "POST":
            return handle_logout(event, context)

        if path == "/api/auth/me" and http_method == "GET":
            return handle_get_me(event, context)

        if path == "/api/auth/forgot-password" and http_method == "POST":
            return handle_forgot_password(event, context)

        if path == "/api/auth/reset-password" and http_method == "POST":
            return handle_reset_password(event, context)

        if path == "/api/auth/verify-email" and http_method == "GET":
            return handle_verify_email(event, context)

        if path == "/api/auth/resend-verification" and http_method == "POST":
            return handle_resend_verification(event, context)

        if path == "/api/auth/sessions" and http_method == "GET":
            return handle_list_sessions(event, context)

        if path.startswith("/api/auth/sessions/") and http_method == "DELETE":
            return handle_revoke_session(event, context)

        # Not found
        return not_found_response(f"Route not found: {http_method} {path}")

    except Exception as e:
        logger.exception(f"Unhandled error: {e}")
        return internal_error_response(
            "An internal error occurred",
            request_id=context.aws_request_id if context else None,
        )


def handle_health(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Health check endpoint."""
    health = db.check_health()
    return success_response(
        {
            "status": "healthy",
            "service": "auth",
            "version": "1.0.0",
            "database": health,
        }
    )


def handle_register(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """User registration endpoint."""
    try:
        body = parse_body(event)
    except ValueError as e:
        return validation_error_response(str(e))

    email = body.get("email", "").strip().lower()
    password = body.get("password", "")
    name = body.get("name", "").strip()

    # Validation
    errors = {}
    if not email:
        errors["email"] = ["Email is required"]
    elif "@" not in email:
        errors["email"] = ["Invalid email format"]

    if not password:
        errors["password"] = ["Password is required"]
    elif len(password) < 8:
        errors["password"] = ["Password must be at least 8 characters"]

    if errors:
        return validation_error_response("Validation failed", errors)

    # TODO: Implement actual registration logic
    # For now, return a placeholder response
    logger.info(f"Registration attempt for: {email}")

    return created_response(
        {
            "user_id": "placeholder-user-id",
            "email": email,
            "name": name,
            "message": "Registration successful. Please verify your email.",
        },
        "User registered successfully",
    )


def handle_login(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """User login endpoint."""
    try:
        body = parse_body(event)
    except ValueError as e:
        return validation_error_response(str(e))

    email = body.get("email", "").strip().lower()
    password = body.get("password", "")

    if not email or not password:
        return validation_error_response(
            "Validation failed",
            {"credentials": ["Email and password are required"]},
        )

    # TODO: Implement actual login logic
    # For now, return a placeholder response with a token
    logger.info(f"Login attempt for: {email}")

    # Create a placeholder JWT
    token = create_jwt(
        user_id="placeholder-user-id",
        email=email,
        is_admin=False,
        expires_in_seconds=3600,
    )

    return success_response(
        {
            "access_token": token,
            "token_type": "Bearer",
            "expires_in": 3600,
            "user": {
                "id": "placeholder-user-id",
                "email": email,
            },
        },
        "Login successful",
    )


def handle_refresh(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Token refresh endpoint."""
    user = get_current_user(event)
    if not user:
        return unauthorized_response("Valid token required for refresh")

    # Create a new token
    token = create_jwt(
        user_id=user.id,
        email=user.email,
        is_admin=user.is_admin,
        tenant_id=user.tenant_id,
        expires_in_seconds=3600,
    )

    return success_response(
        {
            "access_token": token,
            "token_type": "Bearer",
            "expires_in": 3600,
        },
        "Token refreshed",
    )


def handle_logout(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """User logout endpoint."""
    user = get_current_user(event)
    if not user:
        return unauthorized_response()

    # TODO: Implement session invalidation
    logger.info(f"Logout for user: {user.email}")

    return success_response(message="Logged out successfully")


def handle_get_me(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Get current user endpoint."""
    user = get_current_user(event)
    if not user:
        return unauthorized_response()

    return success_response(
        {
            "id": user.id,
            "email": user.email,
            "is_admin": user.is_admin,
            "tenant_id": user.tenant_id,
        }
    )


def handle_forgot_password(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Password reset request endpoint."""
    try:
        body = parse_body(event)
    except ValueError as e:
        return validation_error_response(str(e))

    email = body.get("email", "").strip().lower()

    if not email:
        return validation_error_response(
            "Validation failed",
            {"email": ["Email is required"]},
        )

    # TODO: Implement password reset logic
    logger.info(f"Password reset requested for: {email}")

    # Always return success to prevent email enumeration
    return success_response(
        message="If the email exists, a reset link has been sent"
    )


def handle_reset_password(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Password reset confirmation endpoint."""
    try:
        body = parse_body(event)
    except ValueError as e:
        return validation_error_response(str(e))

    token = body.get("token", "")
    new_password = body.get("password", "")

    if not token or not new_password:
        return validation_error_response(
            "Validation failed",
            {"credentials": ["Token and password are required"]},
        )

    if len(new_password) < 8:
        return validation_error_response(
            "Validation failed",
            {"password": ["Password must be at least 8 characters"]},
        )

    # TODO: Implement password reset logic
    logger.info("Password reset attempted")

    return success_response(message="Password reset successful")


def handle_verify_email(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Email verification endpoint."""
    from shared.response import get_query_parameter

    token = get_query_parameter(event, "token")

    if not token:
        return validation_error_response(
            "Validation failed",
            {"token": ["Verification token is required"]},
        )

    # TODO: Implement email verification logic
    logger.info("Email verification attempted")

    return success_response(message="Email verified successfully")


def handle_resend_verification(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Resend email verification endpoint."""
    user = get_current_user(event)
    if not user:
        return unauthorized_response()

    # TODO: Implement resend logic
    logger.info(f"Verification resend for: {user.email}")

    return success_response(message="Verification email sent")


def handle_list_sessions(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """List user sessions endpoint."""
    user = get_current_user(event)
    if not user:
        return unauthorized_response()

    # TODO: Implement session listing logic
    return success_response(
        {
            "sessions": [
                {
                    "id": "current-session",
                    "created_at": "2025-01-25T00:00:00Z",
                    "last_active": "2025-01-25T00:00:00Z",
                    "user_agent": "UnaMentis iOS/1.0",
                    "is_current": True,
                }
            ]
        }
    )


def handle_revoke_session(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Revoke a user session endpoint."""
    user = get_current_user(event)
    if not user:
        return unauthorized_response()

    session_id = get_path_parameter(event, "sessionId")
    if not session_id:
        return validation_error_response(
            "Validation failed",
            {"sessionId": ["Session ID is required"]},
        )

    # TODO: Implement session revocation logic
    logger.info(f"Session revoked: {session_id}")

    return no_content_response()
