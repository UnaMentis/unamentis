"""
KB service Lambda handler.

Handles question packs, questions, and domains.
This is a placeholder - full implementation in Phase C.
"""

import logging
import os
from typing import Any

import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.response import (
    not_found_response,
    success_response,
)

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Main Lambda handler - placeholder for KB service."""
    http_method = event.get("httpMethod", "")
    path = event.get("path", "")

    logger.info(f"KB service: {http_method} {path}")

    # Placeholder response
    return success_response(
        {
            "message": "KB service placeholder",
            "path": path,
            "method": http_method,
            "status": "not_implemented",
            "note": "Full implementation coming in Phase C",
        }
    )
