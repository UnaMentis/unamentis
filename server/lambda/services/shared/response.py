"""
Standard API response utilities for Lambda functions.

Provides consistent response formatting across all endpoints.
"""

import json
from typing import Any


def _make_response(
    status_code: int,
    body: dict[str, Any] | list[Any] | None = None,
    headers: dict[str, str] | None = None,
) -> dict[str, Any]:
    """
    Create a standard Lambda response.

    Args:
        status_code: HTTP status code
        body: Response body (will be JSON encoded)
        headers: Additional headers

    Returns:
        Lambda response dict
    """
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Client-Platform,X-Client-Version",
        "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
    }

    if headers:
        default_headers.update(headers)

    response = {
        "statusCode": status_code,
        "headers": default_headers,
    }

    if body is not None:
        response["body"] = json.dumps(body, default=str)
    else:
        response["body"] = ""

    return response


def success_response(
    data: dict[str, Any] | list[Any] | None = None,
    message: str | None = None,
) -> dict[str, Any]:
    """
    Create a 200 OK response.

    Args:
        data: Response data
        message: Optional success message

    Returns:
        Lambda response dict
    """
    body: dict[str, Any] = {"success": True}
    if data is not None:
        body["data"] = data
    if message:
        body["message"] = message
    return _make_response(200, body)


def created_response(
    data: dict[str, Any] | None = None,
    message: str = "Resource created successfully",
) -> dict[str, Any]:
    """
    Create a 201 Created response.

    Args:
        data: Created resource data
        message: Success message

    Returns:
        Lambda response dict
    """
    body: dict[str, Any] = {"success": True, "message": message}
    if data is not None:
        body["data"] = data
    return _make_response(201, body)


def no_content_response() -> dict[str, Any]:
    """
    Create a 204 No Content response.

    Returns:
        Lambda response dict
    """
    return _make_response(204)


def error_response(
    message: str,
    status_code: int = 400,
    error_code: str | None = None,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Create an error response.

    Args:
        message: Error message
        status_code: HTTP status code (default 400)
        error_code: Machine-readable error code
        details: Additional error details

    Returns:
        Lambda response dict
    """
    body: dict[str, Any] = {
        "success": False,
        "error": message,
    }
    if error_code:
        body["error_code"] = error_code
    if details:
        body["details"] = details
    return _make_response(status_code, body)


def unauthorized_response(
    message: str = "Authentication required",
) -> dict[str, Any]:
    """
    Create a 401 Unauthorized response.

    Args:
        message: Error message

    Returns:
        Lambda response dict
    """
    return error_response(message, 401, "UNAUTHORIZED")


def forbidden_response(
    message: str = "Access denied",
) -> dict[str, Any]:
    """
    Create a 403 Forbidden response.

    Args:
        message: Error message

    Returns:
        Lambda response dict
    """
    return error_response(message, 403, "FORBIDDEN")


def not_found_response(
    message: str = "Resource not found",
    resource_type: str | None = None,
    resource_id: str | None = None,
) -> dict[str, Any]:
    """
    Create a 404 Not Found response.

    Args:
        message: Error message
        resource_type: Type of resource not found
        resource_id: ID of resource not found

    Returns:
        Lambda response dict
    """
    details = {}
    if resource_type:
        details["resource_type"] = resource_type
    if resource_id:
        details["resource_id"] = resource_id

    return error_response(
        message,
        404,
        "NOT_FOUND",
        details if details else None,
    )


def validation_error_response(
    message: str = "Validation failed",
    errors: dict[str, list[str]] | list[str] | None = None,
) -> dict[str, Any]:
    """
    Create a 422 Validation Error response.

    Args:
        message: Error message
        errors: Validation errors (field -> messages mapping or list)

    Returns:
        Lambda response dict
    """
    details = {}
    if errors:
        details["validation_errors"] = errors

    return error_response(
        message,
        422,
        "VALIDATION_ERROR",
        details if details else None,
    )


def internal_error_response(
    message: str = "An internal error occurred",
    request_id: str | None = None,
) -> dict[str, Any]:
    """
    Create a 500 Internal Server Error response.

    Args:
        message: Error message
        request_id: Request ID for debugging

    Returns:
        Lambda response dict
    """
    details = {}
    if request_id:
        details["request_id"] = request_id

    return error_response(
        message,
        500,
        "INTERNAL_ERROR",
        details if details else None,
    )


def rate_limit_response(
    message: str = "Rate limit exceeded",
    retry_after: int | None = None,
) -> dict[str, Any]:
    """
    Create a 429 Too Many Requests response.

    Args:
        message: Error message
        retry_after: Seconds until rate limit resets

    Returns:
        Lambda response dict
    """
    headers = {}
    if retry_after:
        headers["Retry-After"] = str(retry_after)

    body = {
        "success": False,
        "error": message,
        "error_code": "RATE_LIMIT_EXCEEDED",
    }
    if retry_after:
        body["retry_after"] = retry_after

    return _make_response(429, body, headers)


def parse_body(event: dict[str, Any]) -> dict[str, Any]:
    """
    Parse the request body from a Lambda event.

    Args:
        event: Lambda event dict

    Returns:
        Parsed body dict

    Raises:
        ValueError: If body is not valid JSON
    """
    body = event.get("body", "")
    if not body:
        return {}

    try:
        return json.loads(body)
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in request body: {e}") from e


def get_path_parameter(event: dict[str, Any], name: str) -> str | None:
    """
    Get a path parameter from a Lambda event.

    Args:
        event: Lambda event dict
        name: Parameter name

    Returns:
        Parameter value or None
    """
    params = event.get("pathParameters", {}) or {}
    return params.get(name)


def get_query_parameter(
    event: dict[str, Any],
    name: str,
    default: str | None = None,
) -> str | None:
    """
    Get a query string parameter from a Lambda event.

    Args:
        event: Lambda event dict
        name: Parameter name
        default: Default value if not present

    Returns:
        Parameter value or default
    """
    params = event.get("queryStringParameters", {}) or {}
    return params.get(name, default)


def get_query_parameters(event: dict[str, Any]) -> dict[str, str]:
    """
    Get all query string parameters from a Lambda event.

    Args:
        event: Lambda event dict

    Returns:
        Dict of parameter names to values
    """
    return event.get("queryStringParameters", {}) or {}
