"""
Shared utilities for UnaMentis Lambda functions.

This package provides common functionality used across all Lambda services:
- Database connections (db.py)
- Authentication middleware (auth.py)
- Standard API responses (response.py)
"""

from .auth import (
    validate_beta_token,
    validate_jwt,
    get_current_user,
    require_auth,
    AuthError,
)
from .db import get_db_connection, execute_query, DatabaseError
from .response import (
    success_response,
    error_response,
    created_response,
    no_content_response,
    unauthorized_response,
    forbidden_response,
    not_found_response,
    validation_error_response,
)

__all__ = [
    # Auth
    "validate_beta_token",
    "validate_jwt",
    "get_current_user",
    "require_auth",
    "AuthError",
    # Database
    "get_db_connection",
    "execute_query",
    "DatabaseError",
    # Response
    "success_response",
    "error_response",
    "created_response",
    "no_content_response",
    "unauthorized_response",
    "forbidden_response",
    "not_found_response",
    "validation_error_response",
]
