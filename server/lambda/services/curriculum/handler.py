"""
Curriculum service Lambda handler.

Handles curriculum metadata and progress.
This is a placeholder - full implementation in Phase D.
"""

import logging
import os
from typing import Any

import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from shared.response import success_response

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Main Lambda handler - placeholder for Curriculum service."""
    http_method = event.get("httpMethod", "")
    path = event.get("path", "")

    logger.info(f"Curriculum service: {http_method} {path}")

    return success_response(
        {
            "message": "Curriculum service placeholder",
            "path": path,
            "method": http_method,
            "status": "not_implemented",
            "note": "Full implementation coming in Phase D",
        }
    )
