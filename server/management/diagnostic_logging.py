#!/usr/bin/env python3
"""
Enhanced Diagnostic Logging for UnaMentis Management Server.

Provides configurable diagnostic logging with:
- Toggle capability (on/off)
- Multiple log levels (DEBUG, INFO, WARNING, ERROR)
- Request/response logging for API calls
- Performance timing
- Multiple output formats for log aggregation compatibility:
  - console: Human-readable format for development
  - json: Structured JSON (one object per line) for Elasticsearch/Splunk
  - gelf: Graylog Extended Log Format
  - syslog: RFC 5424 syslog format
- File and console output options
- Remote syslog support via UDP/TCP

Default: ON (as requested for development phase)

Environment Variables:
  DIAGNOSTIC_LOGGING=true/false       Enable/disable diagnostic logging
  DIAGNOSTIC_LEVEL=DEBUG              Log level (DEBUG, INFO, WARNING, ERROR)
  DIAGNOSTIC_FORMAT=console           Output format (console, json, gelf, syslog)
  DIAGNOSTIC_LOG_FILE=                File path for log output (empty = console only)
  DIAGNOSTIC_LOG_REQUESTS=true        Log HTTP requests
  DIAGNOSTIC_LOG_RESPONSES=true       Log HTTP responses
  DIAGNOSTIC_LOG_TIMING=true          Log operation timing
  DIAGNOSTIC_SYSLOG_HOST=             Remote syslog host (empty = local only)
  DIAGNOSTIC_SYSLOG_PORT=514          Remote syslog port
  DIAGNOSTIC_SYSLOG_PROTOCOL=udp      Syslog protocol (udp, tcp)
  DIAGNOSTIC_APP_NAME=unamentis       Application name for syslog
  DIAGNOSTIC_FACILITY=local0          Syslog facility
"""

import logging
import logging.handlers
import os
import sys
import time
import json
import socket
from datetime import datetime, timezone
from functools import wraps
from typing import Any, Callable, Dict, Optional
from dataclasses import dataclass, asdict
from enum import Enum

from ip_privacy import coarsen_ip

# Query parameter names whose values must never be logged. Browser WebSocket
# clients pass bearer tokens as ?token= (they cannot set upgrade headers), so
# raw query logging would leak live credentials into log aggregation.
SENSITIVE_QUERY_KEYS = frozenset(
    {"token", "key", "secret", "password", "authorization", "api_key", "apikey"}
)


def redact_query(query: Dict[str, Any]) -> Dict[str, Any]:
    """Return a copy of a query dict with sensitive values redacted."""
    return {
        k: ("REDACTED" if k.lower() in SENSITIVE_QUERY_KEYS else v)
        for k, v in query.items()
    }


# =============================================================================
# Configuration
# =============================================================================


class LogFormat(Enum):
    """Supported log output formats."""

    CONSOLE = "console"  # Human-readable for development
    JSON = "json"  # Structured JSON (Elasticsearch, Splunk, etc.)
    GELF = "gelf"  # Graylog Extended Log Format
    SYSLOG = "syslog"  # RFC 5424 syslog


# Configuration via environment variables with defaults
DIAGNOSTIC_ENABLED = os.environ.get("DIAGNOSTIC_LOGGING", "true").lower() == "true"
DIAGNOSTIC_LEVEL = os.environ.get("DIAGNOSTIC_LEVEL", "DEBUG")
DIAGNOSTIC_FORMAT = os.environ.get("DIAGNOSTIC_FORMAT", "console")
DIAGNOSTIC_LOG_FILE = os.environ.get("DIAGNOSTIC_LOG_FILE", "")
DIAGNOSTIC_LOG_REQUESTS = (
    os.environ.get("DIAGNOSTIC_LOG_REQUESTS", "true").lower() == "true"
)
DIAGNOSTIC_LOG_RESPONSES = (
    os.environ.get("DIAGNOSTIC_LOG_RESPONSES", "true").lower() == "true"
)
DIAGNOSTIC_LOG_TIMING = (
    os.environ.get("DIAGNOSTIC_LOG_TIMING", "true").lower() == "true"
)
DIAGNOSTIC_SYSLOG_HOST = os.environ.get("DIAGNOSTIC_SYSLOG_HOST", "")
DIAGNOSTIC_SYSLOG_PORT = int(os.environ.get("DIAGNOSTIC_SYSLOG_PORT", "514"))
DIAGNOSTIC_SYSLOG_PROTOCOL = os.environ.get("DIAGNOSTIC_SYSLOG_PROTOCOL", "udp")
DIAGNOSTIC_APP_NAME = os.environ.get("DIAGNOSTIC_APP_NAME", "unamentis")
DIAGNOSTIC_FACILITY = os.environ.get("DIAGNOSTIC_FACILITY", "local0")


# Syslog facility mapping
SYSLOG_FACILITIES = {
    "kern": 0,
    "user": 1,
    "mail": 2,
    "daemon": 3,
    "auth": 4,
    "syslog": 5,
    "lpr": 6,
    "news": 7,
    "uucp": 8,
    "cron": 9,
    "authpriv": 10,
    "ftp": 11,
    "local0": 16,
    "local1": 17,
    "local2": 18,
    "local3": 19,
    "local4": 20,
    "local5": 21,
    "local6": 22,
    "local7": 23,
}


@dataclass
class DiagnosticConfig:
    """Configuration for diagnostic logging."""

    enabled: bool = DIAGNOSTIC_ENABLED
    level: str = DIAGNOSTIC_LEVEL
    format: str = DIAGNOSTIC_FORMAT
    log_file: str = DIAGNOSTIC_LOG_FILE
    log_requests: bool = DIAGNOSTIC_LOG_REQUESTS
    log_responses: bool = DIAGNOSTIC_LOG_RESPONSES
    log_timing: bool = DIAGNOSTIC_LOG_TIMING
    syslog_host: str = DIAGNOSTIC_SYSLOG_HOST
    syslog_port: int = DIAGNOSTIC_SYSLOG_PORT
    syslog_protocol: str = DIAGNOSTIC_SYSLOG_PROTOCOL
    app_name: str = DIAGNOSTIC_APP_NAME
    facility: str = DIAGNOSTIC_FACILITY

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


# =============================================================================
# Log Formatters
# =============================================================================


class JSONFormatter(logging.Formatter):
    """
    Formats log records as JSON objects (one per line).
    Compatible with Elasticsearch, Splunk, Logstash, etc.
    """

    def __init__(self, app_name: str = "unamentis"):
        super().__init__()
        self.app_name = app_name
        self.hostname = socket.gethostname()

    def format(self, record: logging.LogRecord) -> str:
        log_obj = {
            "@timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "app": self.app_name,
            "host": self.hostname,
            "pid": os.getpid(),
            "thread": record.thread,
            "source": {
                "file": record.filename,
                "line": record.lineno,
                "function": record.funcName,
            },
        }

        # Add extra fields from record
        if hasattr(record, "context") and record.context:
            log_obj["context"] = record.context

        # Add exception info if present
        if record.exc_info:
            log_obj["exception"] = {
                "type": record.exc_info[0].__name__ if record.exc_info[0] else None,
                "message": str(record.exc_info[1]) if record.exc_info[1] else None,
                "stacktrace": self.formatException(record.exc_info),
            }

        return json.dumps(log_obj, default=str)


class GELFFormatter(logging.Formatter):
    """
    Formats log records as GELF (Graylog Extended Log Format).
    https://docs.graylog.org/docs/gelf
    """

    LEVEL_MAP = {
        logging.CRITICAL: 2,  # Critical
        logging.ERROR: 3,  # Error
        logging.WARNING: 4,  # Warning
        logging.INFO: 6,  # Informational
        logging.DEBUG: 7,  # Debug
    }

    def __init__(self, app_name: str = "unamentis"):
        super().__init__()
        self.app_name = app_name
        self.hostname = socket.gethostname()

    def format(self, record: logging.LogRecord) -> str:
        gelf_msg = {
            "version": "1.1",
            "host": self.hostname,
            "short_message": record.getMessage()[:250],  # Max 250 chars
            "full_message": record.getMessage(),
            "timestamp": time.time(),
            "level": self.LEVEL_MAP.get(record.levelno, 6),
            "_app": self.app_name,
            "_logger": record.name,
            "_file": record.filename,
            "_line": record.lineno,
            "_function": record.funcName,
            "_pid": os.getpid(),
        }

        # Add extra fields from context (prefixed with _)
        if hasattr(record, "context") and record.context:
            for key, value in record.context.items():
                # GELF custom fields must start with _
                gelf_key = f"_{key}" if not key.startswith("_") else key
                gelf_msg[gelf_key] = value

        # Add exception info if present
        if record.exc_info:
            gelf_msg["_exception_type"] = (
                record.exc_info[0].__name__ if record.exc_info[0] else None
            )
            gelf_msg["_exception_message"] = (
                str(record.exc_info[1]) if record.exc_info[1] else None
            )
            gelf_msg["_stacktrace"] = self.formatException(record.exc_info)

        return json.dumps(gelf_msg, default=str)


class SyslogFormatter(logging.Formatter):
    """
    Formats log records as RFC 5424 syslog messages.
    https://tools.ietf.org/html/rfc5424
    """

    def __init__(self, app_name: str = "unamentis", facility: str = "local0"):
        super().__init__()
        self.app_name = app_name
        self.facility = SYSLOG_FACILITIES.get(facility.lower(), 16)  # Default local0
        self.hostname = socket.gethostname()
        self.procid = str(os.getpid())

    def format(self, record: logging.LogRecord) -> str:
        # RFC 5424 severity (0-7, lower = more severe)
        severity_map = {
            logging.CRITICAL: 2,
            logging.ERROR: 3,
            logging.WARNING: 4,
            logging.INFO: 6,
            logging.DEBUG: 7,
        }
        severity = severity_map.get(record.levelno, 6)

        # Calculate PRI value: facility * 8 + severity
        pri = self.facility * 8 + severity

        # RFC 5424 timestamp
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

        # Message ID (using logger name)
        msgid = record.name.replace(".", "_")[:32]

        # Structured data (SD-ELEMENT)
        sd = "-"  # NILVALUE if no structured data
        if hasattr(record, "context") and record.context:

            def escape_sd_value(val):
                """Escape value for syslog structured data (RFC 5424)."""
                s = str(val)
                s = s.replace("\\", "\\\\")  # Escape backslashes first
                s = s.replace('"', '\\"')  # Escape quotes
                s = s.replace("]", "\\]")  # Escape closing bracket
                return s

            sd_params = " ".join(
                f'{k}="{escape_sd_value(v)}"' for k, v in record.context.items()
            )
            sd = f"[meta@0 {sd_params}]"

        # RFC 5424 format:
        # <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG
        message = record.getMessage()

        return f"<{pri}>1 {timestamp} {self.hostname} {self.app_name} {self.procid} {msgid} {sd} {message}"


class ConsoleFormatter(logging.Formatter):
    """
    Human-readable console format for development.
    """

    def format(self, record: logging.LogRecord) -> str:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        level = record.levelname

        # Build message
        message = record.getMessage()

        # Add context if present
        context_str = ""
        if hasattr(record, "context") and record.context:
            try:
                context_str = " | " + json.dumps(
                    record.context, default=str, separators=(",", ":")
                )
            except Exception:
                context_str = f" | {record.context}"

        # Add exception if present
        exc_str = ""
        if record.exc_info:
            exc_str = "\n" + self.formatException(record.exc_info)

        return f"{timestamp} [DIAG] [{level}] {message}{context_str}{exc_str}"


# =============================================================================
# Diagnostic Logger
# =============================================================================


class DiagnosticLogger:
    """
    Enhanced diagnostic logger with multiple output format support.

    Supports log aggregation systems like:
    - Graylog (GELF format)
    - Elasticsearch/Logstash (JSON format)
    - Splunk (JSON format)
    - Traditional syslog servers (RFC 5424)

    Usage:
        from diagnostic_logging import diag_logger

        diag_logger.info("Something happened", context={"key": "value"})
        diag_logger.request("POST", "/api/import/jobs", body={...})
        diag_logger.response(200, {"success": True})
        diag_logger.timing("import_job", duration_ms=1234)
    """

    def __init__(self, config: Optional[DiagnosticConfig] = None):
        self.config = config or DiagnosticConfig()
        self._logger = logging.getLogger("diagnostic")
        self._setup_logger()

    def _get_formatter(self) -> logging.Formatter:
        """Get the appropriate formatter based on config."""
        fmt = self.config.format.lower()

        if fmt == "json":
            return JSONFormatter(app_name=self.config.app_name)
        elif fmt == "gelf":
            return GELFFormatter(app_name=self.config.app_name)
        elif fmt == "syslog":
            return SyslogFormatter(
                app_name=self.config.app_name, facility=self.config.facility
            )
        else:  # console (default)
            return ConsoleFormatter()

    def _setup_logger(self):
        """Configure the underlying Python logger with appropriate handlers."""
        level = getattr(logging, self.config.level.upper(), logging.DEBUG)
        self._logger.setLevel(level)

        # Clear existing handlers
        self._logger.handlers = []

        if not self.config.enabled:
            return

        formatter = self._get_formatter()

        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(formatter)
        self._logger.addHandler(console_handler)

        # File handler (optional)
        if self.config.log_file:
            try:
                file_handler = logging.FileHandler(self.config.log_file)
                file_handler.setFormatter(formatter)
                self._logger.addHandler(file_handler)
            except Exception as e:
                print(f"Warning: Could not create log file handler: {e}")

        # Remote syslog handler (optional)
        if self.config.syslog_host:
            try:
                socktype = (
                    socket.SOCK_DGRAM
                    if self.config.syslog_protocol.lower() == "udp"
                    else socket.SOCK_STREAM
                )
                syslog_handler = logging.handlers.SysLogHandler(
                    address=(self.config.syslog_host, self.config.syslog_port),
                    facility=SYSLOG_FACILITIES.get(self.config.facility.lower(), 16),
                    socktype=socktype,
                )
                # For remote syslog, we use the syslog formatter regardless of config
                syslog_handler.setFormatter(
                    SyslogFormatter(
                        app_name=self.config.app_name, facility=self.config.facility
                    )
                )
                self._logger.addHandler(syslog_handler)
            except Exception as e:
                print(f"Warning: Could not create syslog handler: {e}")

        # Prevent propagation to root logger
        self._logger.propagate = False

    def _log_with_context(
        self,
        level: int,
        message: str,
        context: Optional[Dict[str, Any]] = None,
        exc_info: bool = False,
    ):
        """Log a message with optional context dict attached to the record."""
        if not self.config.enabled:
            return

        # Create extra dict with context
        extra = {"context": context} if context else {"context": None}
        self._logger.log(level, message, exc_info=exc_info, extra=extra)

    def update_config(self, **kwargs):
        """Update configuration and reconfigure logger."""
        for key, value in kwargs.items():
            if hasattr(self.config, key):
                setattr(self.config, key, value)
        self._setup_logger()
        self.info("Diagnostic logging config updated", context=self.config.to_dict())

    def enable(self):
        """Enable diagnostic logging."""
        self.update_config(enabled=True)

    def disable(self):
        """Disable diagnostic logging."""
        self.config.enabled = False
        self._logger.handlers = []

    def is_enabled(self) -> bool:
        """Check if diagnostic logging is enabled."""
        return self.config.enabled

    def debug(self, message: str, context: Optional[Dict[str, Any]] = None):
        """Log debug message."""
        self._log_with_context(logging.DEBUG, message, context)

    def info(self, message: str, context: Optional[Dict[str, Any]] = None):
        """Log info message."""
        self._log_with_context(logging.INFO, message, context)

    def warning(self, message: str, context: Optional[Dict[str, Any]] = None):
        """Log warning message."""
        self._log_with_context(logging.WARNING, message, context)

    def error(
        self,
        message: str,
        context: Optional[Dict[str, Any]] = None,
        exc_info: bool = False,
    ):
        """Log error message."""
        self._log_with_context(logging.ERROR, message, context, exc_info=exc_info)

    def exception(self, message: str, context: Optional[Dict[str, Any]] = None):
        """Log exception with traceback."""
        self._log_with_context(logging.ERROR, message, context, exc_info=True)

    def request(
        self,
        method: str,
        path: str,
        body: Any = None,
        headers: Optional[Dict] = None,
        query: Optional[Dict] = None,
        client_ip: str = "",
    ):
        """Log incoming HTTP request."""
        if not self.config.enabled or not self.config.log_requests:
            return

        context = {
            "event_type": "http_request",
            "http_method": method,
            "http_path": path,
            "client_ip": coarsen_ip(client_ip),
        }
        if query:
            context["http_query"] = redact_query(dict(query))
        if body and self.config.log_requests:
            # Truncate large bodies
            body_str = (
                json.dumps(body, default=str) if isinstance(body, dict) else str(body)
            )
            if len(body_str) > 1000:
                body_str = body_str[:1000] + "...[truncated]"
            context["http_body"] = body_str

        self._log_with_context(logging.INFO, f"HTTP Request: {method} {path}", context)

    def response(
        self, status: int, body: Any = None, duration_ms: Optional[float] = None
    ):
        """Log outgoing HTTP response."""
        if not self.config.enabled or not self.config.log_responses:
            return

        context = {
            "event_type": "http_response",
            "http_status": status,
            "http_status_class": f"{status // 100}xx",
        }
        if duration_ms is not None and self.config.log_timing:
            context["duration_ms"] = round(duration_ms, 2)
        if body and self.config.log_responses:
            # Truncate large bodies
            body_str = (
                json.dumps(body, default=str) if isinstance(body, dict) else str(body)
            )
            if len(body_str) > 500:
                body_str = body_str[:500] + "...[truncated]"
            context["http_body"] = body_str

        level = (
            logging.INFO
            if status < 400
            else logging.WARNING
            if status < 500
            else logging.ERROR
        )
        self._log_with_context(level, f"HTTP Response: {status}", context)

    def timing(
        self,
        operation: str,
        duration_ms: float,
        context: Optional[Dict[str, Any]] = None,
    ):
        """Log timing information for an operation."""
        if not self.config.enabled or not self.config.log_timing:
            return

        ctx = {
            "event_type": "timing",
            "operation": operation,
            "duration_ms": round(duration_ms, 2),
        }
        if context:
            ctx.update(context)

        # Categorize by duration
        if duration_ms < 100:
            ctx["duration_category"] = "fast"
        elif duration_ms < 500:
            ctx["duration_category"] = "normal"
        elif duration_ms < 1000:
            ctx["duration_category"] = "slow"
        else:
            ctx["duration_category"] = "very_slow"

        self._log_with_context(
            logging.INFO, f"Timing: {operation} ({duration_ms:.2f}ms)", ctx
        )

    def separator(self, label: str = ""):
        """Log a visual separator for readability (console format only)."""
        if self.config.enabled and self.config.format.lower() == "console":
            if label:
                self._logger.info(f"{'=' * 20} {label} {'=' * 20}")
            else:
                self._logger.info("=" * 50)


# =============================================================================
# Global Instance and Utilities
# =============================================================================

# Global singleton instance
diag_logger = DiagnosticLogger()


def log_request(func: Callable) -> Callable:
    """
    Decorator for aiohttp request handlers that logs request/response.

    Usage:
        @log_request
        async def handle_something(request: web.Request) -> web.Response:
            ...
    """

    @wraps(func)
    async def wrapper(request, *args, **kwargs):
        start_time = time.time()

        # Log request
        try:
            body = None
            if request.can_read_body:
                try:
                    body = await request.json()
                except Exception:
                    body = await request.text() if request.body_exists else None
        except Exception:
            body = None

        diag_logger.request(
            method=request.method,
            path=request.path,
            body=body,
            query=dict(request.query) if request.query else None,
            client_ip=request.remote or "",
        )

        # Execute handler
        try:
            response = await func(request, *args, **kwargs)

            # Log response
            duration_ms = (time.time() - start_time) * 1000
            response_body = None
            if hasattr(response, "text"):
                try:
                    response_body = json.loads(response.text)
                except Exception:
                    response_body = response.text[:200] if response.text else None

            diag_logger.response(
                status=response.status, body=response_body, duration_ms=duration_ms
            )

            return response

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            diag_logger.error(
                f"Handler error: {type(e).__name__}: {e}",
                context={"path": request.path, "duration_ms": duration_ms},
                exc_info=True,
            )
            raise

    return wrapper


class TimingContext:
    """
    Context manager for timing code blocks.

    Usage:
        with TimingContext("database_query"):
            result = await db.query(...)
    """

    def __init__(self, operation: str, context: Optional[Dict[str, Any]] = None):
        self.operation = operation
        self.context = context
        self.start_time: Optional[float] = None

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.start_time:
            duration_ms = (time.time() - self.start_time) * 1000
            ctx = self.context.copy() if self.context else {}
            if exc_type:
                ctx["error"] = str(exc_val)
            diag_logger.timing(self.operation, duration_ms, ctx)
        return False  # Don't suppress exceptions


def get_diagnostic_config() -> Dict[str, Any]:
    """Get current diagnostic logging configuration."""
    return diag_logger.config.to_dict()


def set_diagnostic_config(**kwargs) -> Dict[str, Any]:
    """Update diagnostic logging configuration."""
    diag_logger.update_config(**kwargs)
    return diag_logger.config.to_dict()


# =============================================================================
# Startup
# =============================================================================

if diag_logger.is_enabled():
    diag_logger.separator("DIAGNOSTIC LOGGING INITIALIZED")
    diag_logger.info(
        "Diagnostic logging is ENABLED", context=diag_logger.config.to_dict()
    )
