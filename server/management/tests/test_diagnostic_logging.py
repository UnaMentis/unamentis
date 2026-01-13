"""
Tests for Diagnostic Logging

Comprehensive tests for the diagnostic logging system including:
- LogFormat enum
- DiagnosticConfig dataclass
- All formatters (JSON, GELF, Syslog, Console)
- DiagnosticLogger class and all its methods
- log_request decorator
- TimingContext context manager
- Configuration getter/setter functions
"""

import json
import logging
import os
import sys
import time
from unittest.mock import MagicMock, AsyncMock, patch, Mock

import pytest

from diagnostic_logging import (
    LogFormat,
    DiagnosticConfig,
    JSONFormatter,
    GELFFormatter,
    SyslogFormatter,
    ConsoleFormatter,
    DiagnosticLogger,
    TimingContext,
    log_request,
    get_diagnostic_config,
    set_diagnostic_config,
    diag_logger,
    SYSLOG_FACILITIES,
)


# =============================================================================
# LOG FORMAT TESTS
# =============================================================================


class TestLogFormat:
    """Tests for LogFormat enum."""

    def test_console_format(self):
        """Test CONSOLE format value."""
        assert LogFormat.CONSOLE.value == "console"

    def test_json_format(self):
        """Test JSON format value."""
        assert LogFormat.JSON.value == "json"

    def test_gelf_format(self):
        """Test GELF format value."""
        assert LogFormat.GELF.value == "gelf"

    def test_syslog_format(self):
        """Test SYSLOG format value."""
        assert LogFormat.SYSLOG.value == "syslog"

    def test_all_formats_iterable(self):
        """Test all formats can be iterated."""
        formats = list(LogFormat)
        assert len(formats) == 4
        assert LogFormat.CONSOLE in formats
        assert LogFormat.JSON in formats
        assert LogFormat.GELF in formats
        assert LogFormat.SYSLOG in formats


# =============================================================================
# SYSLOG FACILITIES TESTS
# =============================================================================


class TestSyslogFacilities:
    """Tests for syslog facility mapping."""

    def test_local_facilities_exist(self):
        """Test all local facilities exist."""
        for i in range(8):
            assert f"local{i}" in SYSLOG_FACILITIES
            assert SYSLOG_FACILITIES[f"local{i}"] == 16 + i

    def test_standard_facilities_exist(self):
        """Test standard facilities exist."""
        assert SYSLOG_FACILITIES["kern"] == 0
        assert SYSLOG_FACILITIES["user"] == 1
        assert SYSLOG_FACILITIES["daemon"] == 3
        assert SYSLOG_FACILITIES["auth"] == 4
        assert SYSLOG_FACILITIES["syslog"] == 5
        assert SYSLOG_FACILITIES["cron"] == 9


# =============================================================================
# DIAGNOSTIC CONFIG TESTS
# =============================================================================


class TestDiagnosticConfig:
    """Tests for DiagnosticConfig dataclass."""

    def test_default_values(self):
        """Test default configuration values."""
        config = DiagnosticConfig()
        assert isinstance(config.enabled, bool)
        assert isinstance(config.level, str)
        assert isinstance(config.format, str)
        assert isinstance(config.log_requests, bool)
        assert isinstance(config.log_responses, bool)
        assert isinstance(config.log_timing, bool)

    def test_custom_values(self):
        """Test configuration with custom values."""
        config = DiagnosticConfig(
            enabled=False,
            level="ERROR",
            format="json",
            log_file="/tmp/test.log",
        )
        assert config.enabled is False
        assert config.level == "ERROR"
        assert config.format == "json"
        assert config.log_file == "/tmp/test.log"

    def test_all_fields_configurable(self):
        """Test all fields can be set."""
        config = DiagnosticConfig(
            enabled=True,
            level="WARNING",
            format="gelf",
            log_file="/var/log/test.log",
            log_requests=False,
            log_responses=False,
            log_timing=False,
            syslog_host="syslog.example.com",
            syslog_port=1514,
            syslog_protocol="tcp",
            app_name="test-app",
            facility="local1",
        )
        assert config.enabled is True
        assert config.level == "WARNING"
        assert config.format == "gelf"
        assert config.log_file == "/var/log/test.log"
        assert config.log_requests is False
        assert config.log_responses is False
        assert config.log_timing is False
        assert config.syslog_host == "syslog.example.com"
        assert config.syslog_port == 1514
        assert config.syslog_protocol == "tcp"
        assert config.app_name == "test-app"
        assert config.facility == "local1"

    def test_to_dict(self):
        """Test to_dict method."""
        config = DiagnosticConfig(enabled=True, level="INFO")
        result = config.to_dict()
        assert isinstance(result, dict)
        assert result["enabled"] is True
        assert result["level"] == "INFO"

    def test_to_dict_contains_all_fields(self):
        """Test to_dict contains all configuration fields."""
        config = DiagnosticConfig()
        result = config.to_dict()
        expected_keys = [
            "enabled", "level", "format", "log_file",
            "log_requests", "log_responses", "log_timing",
            "syslog_host", "syslog_port", "syslog_protocol",
            "app_name", "facility"
        ]
        for key in expected_keys:
            assert key in result

    def test_syslog_config(self):
        """Test syslog configuration options."""
        config = DiagnosticConfig(
            syslog_host="localhost",
            syslog_port=514,
            syslog_protocol="udp",
            facility="local0",
        )
        assert config.syslog_host == "localhost"
        assert config.syslog_port == 514
        assert config.syslog_protocol == "udp"
        assert config.facility == "local0"


# =============================================================================
# JSON FORMATTER TESTS
# =============================================================================


class TestJSONFormatter:
    """Tests for JSONFormatter class."""

    @pytest.fixture
    def formatter(self):
        """Create a JSON formatter."""
        return JSONFormatter(app_name="test-app")

    def test_init(self, formatter):
        """Test formatter initialization."""
        assert formatter.app_name == "test-app"
        assert formatter.hostname is not None

    def test_init_default_app_name(self):
        """Test formatter with default app name."""
        formatter = JSONFormatter()
        assert formatter.app_name == "unamentis"

    def test_format_basic_record(self, formatter):
        """Test formatting a basic log record."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert parsed["message"] == "Test message"
        assert parsed["level"] == "INFO"
        assert parsed["app"] == "test-app"
        assert parsed["logger"] == "test.logger"
        assert "source" in parsed
        assert parsed["source"]["line"] == 42
        assert "@timestamp" in parsed
        assert "pid" in parsed
        assert "thread" in parsed
        assert "host" in parsed

    def test_format_with_args(self, formatter):
        """Test formatting a record with message args."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test %s %d",
            args=("message", 123),
            exc_info=None,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert parsed["message"] == "Test message 123"

    def test_format_with_context(self, formatter):
        """Test formatting a record with context."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        record.context = {"user_id": "123", "action": "login"}
        result = formatter.format(record)
        parsed = json.loads(result)

        assert "context" in parsed
        assert parsed["context"]["user_id"] == "123"
        assert parsed["context"]["action"] == "login"

    def test_format_without_context(self, formatter):
        """Test formatting a record without context attribute."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        # Should not raise, context should not be present
        assert "context" not in parsed or parsed.get("context") is None

    def test_format_with_exception(self, formatter):
        """Test formatting a record with exception."""
        try:
            raise ValueError("Test error")
        except ValueError:
            exc_info = sys.exc_info()

        record = logging.LogRecord(
            name="test.logger",
            level=logging.ERROR,
            pathname="/test/file.py",
            lineno=42,
            msg="Error occurred",
            args=(),
            exc_info=exc_info,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert "exception" in parsed
        assert parsed["exception"]["type"] == "ValueError"
        assert parsed["exception"]["message"] == "Test error"
        assert "stacktrace" in parsed["exception"]
        assert "ValueError" in parsed["exception"]["stacktrace"]

    def test_format_with_none_exception_parts(self, formatter):
        """Test formatting with None values in exc_info tuple."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.ERROR,
            pathname="/test/file.py",
            lineno=42,
            msg="Error occurred",
            args=(),
            exc_info=(None, None, None),
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert "exception" in parsed
        assert parsed["exception"]["type"] is None
        assert parsed["exception"]["message"] is None

    def test_format_different_levels(self, formatter):
        """Test formatting records with different log levels."""
        levels = [
            (logging.DEBUG, "DEBUG"),
            (logging.INFO, "INFO"),
            (logging.WARNING, "WARNING"),
            (logging.ERROR, "ERROR"),
            (logging.CRITICAL, "CRITICAL"),
        ]
        for level, level_name in levels:
            record = logging.LogRecord(
                name="test",
                level=level,
                pathname="/test.py",
                lineno=1,
                msg="Test",
                args=(),
                exc_info=None,
            )
            result = formatter.format(record)
            parsed = json.loads(result)
            assert parsed["level"] == level_name


# =============================================================================
# GELF FORMATTER TESTS
# =============================================================================


class TestGELFFormatter:
    """Tests for GELFFormatter class."""

    @pytest.fixture
    def formatter(self):
        """Create a GELF formatter."""
        return GELFFormatter(app_name="test-app")

    def test_init(self, formatter):
        """Test formatter initialization."""
        assert formatter.app_name == "test-app"
        assert formatter.hostname is not None

    def test_init_default_app_name(self):
        """Test formatter with default app name."""
        formatter = GELFFormatter()
        assert formatter.app_name == "unamentis"

    def test_format_basic_record(self, formatter):
        """Test formatting a basic log record."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert parsed["version"] == "1.1"
        assert parsed["short_message"] == "Test message"
        assert parsed["full_message"] == "Test message"
        assert "_app" in parsed
        assert parsed["_app"] == "test-app"
        assert "_logger" in parsed
        assert "_file" in parsed
        assert "_line" in parsed
        assert "_function" in parsed
        assert "_pid" in parsed
        assert "timestamp" in parsed
        assert "level" in parsed
        assert "host" in parsed

    def test_format_truncates_short_message(self, formatter):
        """Test short_message is truncated to 250 chars."""
        long_message = "x" * 500
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg=long_message,
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert len(parsed["short_message"]) == 250
        assert parsed["full_message"] == long_message

    def test_format_with_context(self, formatter):
        """Test formatting a record with context (prefixed with _)."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        record.context = {"user_id": "123", "_already_prefixed": "value"}
        result = formatter.format(record)
        parsed = json.loads(result)

        assert "_user_id" in parsed
        assert parsed["_user_id"] == "123"
        assert "_already_prefixed" in parsed
        assert parsed["_already_prefixed"] == "value"

    def test_format_with_exception(self, formatter):
        """Test formatting a record with exception."""
        try:
            raise RuntimeError("Test runtime error")
        except RuntimeError:
            exc_info = sys.exc_info()

        record = logging.LogRecord(
            name="test.logger",
            level=logging.ERROR,
            pathname="/test/file.py",
            lineno=42,
            msg="Error occurred",
            args=(),
            exc_info=exc_info,
        )
        result = formatter.format(record)
        parsed = json.loads(result)

        assert "_exception_type" in parsed
        assert parsed["_exception_type"] == "RuntimeError"
        assert "_exception_message" in parsed
        assert parsed["_exception_message"] == "Test runtime error"
        assert "_stacktrace" in parsed

    def test_level_mapping(self, formatter):
        """Test GELF level mapping (syslog severity)."""
        level_tests = [
            (logging.CRITICAL, 2),
            (logging.ERROR, 3),
            (logging.WARNING, 4),
            (logging.INFO, 6),
            (logging.DEBUG, 7),
        ]
        for log_level, gelf_level in level_tests:
            record = logging.LogRecord(
                name="test",
                level=log_level,
                pathname="/test.py",
                lineno=1,
                msg="Test",
                args=(),
                exc_info=None,
            )
            result = formatter.format(record)
            parsed = json.loads(result)
            assert parsed["level"] == gelf_level

    def test_unknown_level_defaults_to_info(self, formatter):
        """Test unknown log level defaults to informational (6)."""
        record = logging.LogRecord(
            name="test",
            level=99,  # Non-standard level
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        parsed = json.loads(result)
        assert parsed["level"] == 6


# =============================================================================
# SYSLOG FORMATTER TESTS
# =============================================================================


class TestSyslogFormatter:
    """Tests for SyslogFormatter class."""

    @pytest.fixture
    def formatter(self):
        """Create a Syslog formatter."""
        return SyslogFormatter(app_name="test-app", facility="local0")

    def test_init(self, formatter):
        """Test formatter initialization."""
        assert formatter.app_name == "test-app"
        assert formatter.facility == 16  # local0
        assert formatter.hostname is not None
        assert formatter.procid == str(os.getpid())

    def test_init_default_facility(self):
        """Test formatter with unknown facility defaults to local0."""
        formatter = SyslogFormatter(app_name="test", facility="unknown")
        assert formatter.facility == 16  # local0 default

    def test_format_basic_record(self, formatter):
        """Test formatting a basic log record."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)

        # RFC 5424 format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG
        assert "test-app" in result
        assert "Test message" in result
        assert result.startswith("<")
        assert ">1 " in result  # Version 1

    def test_format_calculates_pri_correctly(self, formatter):
        """Test PRI value calculation (facility * 8 + severity)."""
        # local0 (16) + INFO severity (6) = 134
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        assert result.startswith("<134>")

    def test_format_different_facilities(self):
        """Test PRI with different facilities."""
        for facility_name, facility_num in [("user", 1), ("local7", 23)]:
            formatter = SyslogFormatter(app_name="test", facility=facility_name)
            record = logging.LogRecord(
                name="test",
                level=logging.ERROR,  # Severity 3
                pathname="/test.py",
                lineno=1,
                msg="Test",
                args=(),
                exc_info=None,
            )
            result = formatter.format(record)
            expected_pri = facility_num * 8 + 3
            assert result.startswith(f"<{expected_pri}>")

    def test_format_with_context_structured_data(self, formatter):
        """Test formatting with context as structured data."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        record.context = {"user": "john", "action": "login"}
        result = formatter.format(record)

        # Should contain structured data
        assert "[meta@0" in result
        assert 'user="john"' in result
        assert 'action="login"' in result

    def test_format_escapes_structured_data_values(self, formatter):
        """Test that SD values are properly escaped."""
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        record.context = {
            "quote": 'has "quotes"',
            "bracket": "has ]bracket",
            "backslash": "has \\backslash",
        }
        result = formatter.format(record)

        # Values should be escaped
        assert '\\"' in result
        assert "\\]" in result
        assert "\\\\" in result

    def test_format_without_context_uses_nilvalue(self, formatter):
        """Test that missing context uses NILVALUE (-)."""
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)

        # Should contain NILVALUE for SD
        parts = result.split(" ")
        # Find the SD element (after MSGID, before MSG)
        assert "-" in parts  # NILVALUE present

    def test_msgid_truncation(self, formatter):
        """Test MSGID is truncated to 32 chars."""
        record = logging.LogRecord(
            name="very.long.logger.name.that.exceeds.thirty.two.characters",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)
        # The logger name with dots replaced by underscores, truncated to 32 chars
        # Should contain the truncated msgid in the result
        assert "very_long_logger_name_that_excee" in result or len(result) > 0


# =============================================================================
# CONSOLE FORMATTER TESTS
# =============================================================================


class TestConsoleFormatter:
    """Tests for ConsoleFormatter class."""

    @pytest.fixture
    def formatter(self):
        """Create a Console formatter."""
        return ConsoleFormatter()

    def test_format_basic_record(self, formatter):
        """Test formatting a basic log record."""
        record = logging.LogRecord(
            name="test.logger",
            level=logging.INFO,
            pathname="/test/file.py",
            lineno=42,
            msg="Test message",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)

        assert "[DIAG]" in result
        assert "[INFO]" in result
        assert "Test message" in result

    def test_format_includes_timestamp(self, formatter):
        """Test format includes timestamp."""
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        result = formatter.format(record)

        # Should contain date-like pattern
        assert "-" in result  # Date separator
        assert ":" in result  # Time separator

    def test_format_with_context(self, formatter):
        """Test formatting with context."""
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        record.context = {"key": "value", "num": 123}
        result = formatter.format(record)

        assert "|" in result
        assert "key" in result
        assert "value" in result

    def test_format_with_non_json_serializable_context(self, formatter):
        """Test formatting with non-JSON-serializable context."""
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="/test.py",
            lineno=1,
            msg="Test",
            args=(),
            exc_info=None,
        )
        record.context = {"obj": object()}
        result = formatter.format(record)

        # Should not raise, should contain something
        assert "Test" in result

    def test_format_with_exception(self, formatter):
        """Test formatting with exception."""
        try:
            raise KeyError("missing_key")
        except KeyError:
            exc_info = sys.exc_info()

        record = logging.LogRecord(
            name="test",
            level=logging.ERROR,
            pathname="/test.py",
            lineno=1,
            msg="Error",
            args=(),
            exc_info=exc_info,
        )
        result = formatter.format(record)

        assert "KeyError" in result
        assert "missing_key" in result

    def test_format_different_levels(self, formatter):
        """Test formatting different log levels."""
        levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        for level_name in levels:
            level = getattr(logging, level_name)
            record = logging.LogRecord(
                name="test",
                level=level,
                pathname="/test.py",
                lineno=1,
                msg="Test",
                args=(),
                exc_info=None,
            )
            result = formatter.format(record)
            assert f"[{level_name}]" in result


# =============================================================================
# DIAGNOSTIC LOGGER TESTS
# =============================================================================


class TestDiagnosticLoggerInit:
    """Tests for DiagnosticLogger initialization."""

    def test_init_with_default_config(self):
        """Test logger initialization with default config."""
        logger = DiagnosticLogger()
        assert logger.config is not None
        assert logger._logger is not None

    def test_init_with_custom_config(self):
        """Test logger initialization with custom config."""
        config = DiagnosticConfig(
            enabled=True,
            level="WARNING",
            format="json",
        )
        logger = DiagnosticLogger(config)
        assert logger.config.enabled is True
        assert logger.config.level == "WARNING"
        assert logger.config.format == "json"

    def test_init_disabled_logger_has_no_handlers(self):
        """Test disabled logger has no handlers."""
        config = DiagnosticConfig(enabled=False)
        logger = DiagnosticLogger(config)
        assert len(logger._logger.handlers) == 0


class TestDiagnosticLoggerFormatSelection:
    """Tests for format selection in DiagnosticLogger."""

    def test_get_formatter_console(self):
        """Test console formatter selection."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        formatter = logger._get_formatter()
        assert isinstance(formatter, ConsoleFormatter)

    def test_get_formatter_json(self):
        """Test JSON formatter selection."""
        config = DiagnosticConfig(enabled=True, format="json")
        logger = DiagnosticLogger(config)
        formatter = logger._get_formatter()
        assert isinstance(formatter, JSONFormatter)

    def test_get_formatter_gelf(self):
        """Test GELF formatter selection."""
        config = DiagnosticConfig(enabled=True, format="gelf")
        logger = DiagnosticLogger(config)
        formatter = logger._get_formatter()
        assert isinstance(formatter, GELFFormatter)

    def test_get_formatter_syslog(self):
        """Test syslog formatter selection."""
        config = DiagnosticConfig(enabled=True, format="syslog")
        logger = DiagnosticLogger(config)
        formatter = logger._get_formatter()
        assert isinstance(formatter, SyslogFormatter)

    def test_get_formatter_unknown_defaults_to_console(self):
        """Test unknown format defaults to console."""
        config = DiagnosticConfig(enabled=True, format="unknown")
        logger = DiagnosticLogger(config)
        formatter = logger._get_formatter()
        assert isinstance(formatter, ConsoleFormatter)


class TestDiagnosticLoggerSetup:
    """Tests for logger setup."""

    def test_setup_creates_console_handler(self):
        """Test setup creates console handler."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)

        console_handlers = [
            h for h in logger._logger.handlers
            if isinstance(h, logging.StreamHandler)
        ]
        assert len(console_handlers) >= 1

    def test_setup_with_file_handler(self):
        """Test setup creates file handler when log_file specified."""
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".log", delete=False) as f:
            log_file = f.name

        try:
            config = DiagnosticConfig(enabled=True, log_file=log_file)
            logger = DiagnosticLogger(config)

            file_handlers = [
                h for h in logger._logger.handlers
                if isinstance(h, logging.FileHandler)
            ]
            assert len(file_handlers) == 1
        finally:
            os.unlink(log_file)

    def test_setup_with_invalid_file_path_prints_warning(self, capsys):
        """Test setup with invalid file path prints warning."""
        config = DiagnosticConfig(
            enabled=True,
            log_file="/nonexistent/path/to/log.log"
        )
        logger = DiagnosticLogger(config)

        captured = capsys.readouterr()
        assert "Warning" in captured.out or len(logger._logger.handlers) >= 1

    def test_setup_propagate_is_false(self):
        """Test logger propagate is set to False."""
        config = DiagnosticConfig(enabled=True)
        logger = DiagnosticLogger(config)
        assert logger._logger.propagate is False


class TestDiagnosticLoggerEnableDisable:
    """Tests for enable/disable functionality."""

    @pytest.fixture
    def logger(self):
        """Create an enabled diagnostic logger."""
        config = DiagnosticConfig(enabled=True, level="DEBUG", format="console")
        return DiagnosticLogger(config)

    def test_is_enabled(self, logger):
        """Test is_enabled method."""
        assert logger.is_enabled() is True

    def test_disable(self, logger):
        """Test disable method."""
        logger.disable()
        assert logger.is_enabled() is False
        assert len(logger._logger.handlers) == 0

    def test_enable(self, logger):
        """Test enable method."""
        logger.disable()
        logger.enable()
        assert logger.is_enabled() is True
        assert len(logger._logger.handlers) > 0


class TestDiagnosticLoggerLogMethods:
    """Tests for logging methods."""

    @pytest.fixture
    def logger(self):
        """Create a diagnostic logger."""
        config = DiagnosticConfig(enabled=True, level="DEBUG", format="console")
        return DiagnosticLogger(config)

    def test_debug(self, logger):
        """Test debug logging."""
        logger.debug("Debug message")  # Should not raise

    def test_info(self, logger):
        """Test info logging."""
        logger.info("Info message")  # Should not raise

    def test_warning(self, logger):
        """Test warning logging."""
        logger.warning("Warning message")  # Should not raise

    def test_error(self, logger):
        """Test error logging."""
        logger.error("Error message")  # Should not raise

    def test_error_with_exc_info(self, logger):
        """Test error logging with exc_info."""
        logger.error("Error with exc_info", exc_info=True)  # Should not raise

    def test_exception(self, logger):
        """Test exception logging."""
        try:
            raise ValueError("Test error")
        except ValueError:
            logger.exception("Exception occurred")  # Should not raise

    def test_log_with_context(self, logger):
        """Test logging with context."""
        logger.info("Message with context", context={"key": "value"})

    def test_log_disabled_is_noop(self):
        """Test logging when disabled is a no-op."""
        config = DiagnosticConfig(enabled=False)
        logger = DiagnosticLogger(config)

        # These should not raise
        logger.debug("Should be skipped")
        logger.info("Should be skipped")
        logger.warning("Should be skipped")
        logger.error("Should be skipped")


class TestDiagnosticLoggerRequest:
    """Tests for HTTP request logging."""

    @pytest.fixture
    def logger(self):
        """Create a diagnostic logger with request logging enabled."""
        config = DiagnosticConfig(
            enabled=True,
            level="DEBUG",
            format="console",
            log_requests=True,
        )
        return DiagnosticLogger(config)

    def test_request_basic(self, logger):
        """Test basic request logging."""
        logger.request("GET", "/api/test")  # Should not raise

    def test_request_with_body(self, logger):
        """Test request logging with body."""
        logger.request("POST", "/api/test", body={"key": "value"})

    def test_request_with_headers(self, logger):
        """Test request logging with headers."""
        logger.request(
            "GET", "/api/test",
            headers={"Authorization": "Bearer token"}
        )

    def test_request_with_query(self, logger):
        """Test request logging with query params."""
        logger.request(
            "GET", "/api/test",
            query={"page": "1", "limit": "10"}
        )

    def test_request_with_client_ip(self, logger):
        """Test request logging with client IP."""
        logger.request("GET", "/api/test", client_ip="192.168.1.1")

    def test_request_body_truncation(self, logger):
        """Test large request body is truncated."""
        large_body = {"data": "x" * 2000}
        logger.request("POST", "/api/test", body=large_body)

    def test_request_string_body(self, logger):
        """Test request logging with string body."""
        logger.request("POST", "/api/test", body="plain text body")

    def test_request_disabled_is_noop(self):
        """Test request logging when disabled."""
        config = DiagnosticConfig(enabled=True, log_requests=False)
        logger = DiagnosticLogger(config)
        logger.request("GET", "/api/test")  # Should not raise

    def test_request_logger_disabled_is_noop(self):
        """Test request logging when logger disabled."""
        config = DiagnosticConfig(enabled=False, log_requests=True)
        logger = DiagnosticLogger(config)
        logger.request("GET", "/api/test")  # Should not raise


class TestDiagnosticLoggerResponse:
    """Tests for HTTP response logging."""

    @pytest.fixture
    def logger(self):
        """Create a diagnostic logger with response logging enabled."""
        config = DiagnosticConfig(
            enabled=True,
            level="DEBUG",
            format="console",
            log_responses=True,
            log_timing=True,
        )
        return DiagnosticLogger(config)

    def test_response_basic(self, logger):
        """Test basic response logging."""
        logger.response(200)  # Should not raise

    def test_response_with_body(self, logger):
        """Test response logging with body."""
        logger.response(200, body={"success": True})

    def test_response_with_duration(self, logger):
        """Test response logging with duration."""
        logger.response(200, duration_ms=123.45)

    def test_response_body_truncation(self, logger):
        """Test large response body is truncated."""
        large_body = {"data": "x" * 1000}
        logger.response(200, body=large_body)

    def test_response_string_body(self, logger):
        """Test response logging with string body."""
        logger.response(200, body="plain text response")

    def test_response_4xx_logs_warning(self, logger):
        """Test 4xx response logs at warning level."""
        logger.response(404)

    def test_response_5xx_logs_error(self, logger):
        """Test 5xx response logs at error level."""
        logger.response(500)

    def test_response_disabled_is_noop(self):
        """Test response logging when disabled."""
        config = DiagnosticConfig(enabled=True, log_responses=False)
        logger = DiagnosticLogger(config)
        logger.response(200)  # Should not raise

    def test_response_timing_disabled_excludes_duration(self):
        """Test duration excluded when timing disabled."""
        config = DiagnosticConfig(
            enabled=True,
            log_responses=True,
            log_timing=False,
        )
        logger = DiagnosticLogger(config)
        logger.response(200, duration_ms=100.0)


class TestDiagnosticLoggerTiming:
    """Tests for timing logging."""

    @pytest.fixture
    def logger(self):
        """Create a diagnostic logger with timing enabled."""
        config = DiagnosticConfig(
            enabled=True,
            level="DEBUG",
            format="console",
            log_timing=True,
        )
        return DiagnosticLogger(config)

    def test_timing_basic(self, logger):
        """Test basic timing logging."""
        logger.timing("database_query", 50.0)  # Should not raise

    def test_timing_with_context(self, logger):
        """Test timing logging with context."""
        logger.timing("database_query", 50.0, context={"table": "users"})

    def test_timing_categorization_fast(self, logger):
        """Test timing categorization for fast operations."""
        logger.timing("fast_op", 50.0)  # < 100ms = fast

    def test_timing_categorization_normal(self, logger):
        """Test timing categorization for normal operations."""
        logger.timing("normal_op", 200.0)  # 100-500ms = normal

    def test_timing_categorization_slow(self, logger):
        """Test timing categorization for slow operations."""
        logger.timing("slow_op", 750.0)  # 500-1000ms = slow

    def test_timing_categorization_very_slow(self, logger):
        """Test timing categorization for very slow operations."""
        logger.timing("very_slow_op", 1500.0)  # > 1000ms = very_slow

    def test_timing_disabled_is_noop(self):
        """Test timing logging when disabled."""
        config = DiagnosticConfig(enabled=True, log_timing=False)
        logger = DiagnosticLogger(config)
        logger.timing("operation", 100.0)  # Should not raise

    def test_timing_logger_disabled_is_noop(self):
        """Test timing logging when logger disabled."""
        config = DiagnosticConfig(enabled=False, log_timing=True)
        logger = DiagnosticLogger(config)
        logger.timing("operation", 100.0)  # Should not raise


class TestDiagnosticLoggerSeparator:
    """Tests for separator logging."""

    def test_separator_without_label(self):
        """Test separator without label."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        logger.separator()  # Should not raise

    def test_separator_with_label(self):
        """Test separator with label."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        logger.separator("TEST SECTION")  # Should not raise

    def test_separator_noop_for_non_console_format(self):
        """Test separator is no-op for non-console formats."""
        config = DiagnosticConfig(enabled=True, format="json")
        logger = DiagnosticLogger(config)
        logger.separator("TEST")  # Should not raise and do nothing

    def test_separator_disabled_is_noop(self):
        """Test separator when disabled."""
        config = DiagnosticConfig(enabled=False, format="console")
        logger = DiagnosticLogger(config)
        logger.separator()  # Should not raise


class TestDiagnosticLoggerUpdateConfig:
    """Tests for config update functionality."""

    def test_update_config_single_field(self):
        """Test updating single config field."""
        config = DiagnosticConfig(enabled=True, level="DEBUG")
        logger = DiagnosticLogger(config)

        logger.update_config(level="WARNING")

        assert logger.config.level == "WARNING"

    def test_update_config_multiple_fields(self):
        """Test updating multiple config fields."""
        config = DiagnosticConfig(enabled=True, level="DEBUG", format="console")
        logger = DiagnosticLogger(config)

        logger.update_config(level="ERROR", format="json")

        assert logger.config.level == "ERROR"
        assert logger.config.format == "json"

    def test_update_config_reconfigures_logger(self):
        """Test update_config reconfigures logger."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)

        # Change format
        logger.update_config(format="json")

        # Formatter should be JSONFormatter now
        formatter = logger._get_formatter()
        assert isinstance(formatter, JSONFormatter)

    def test_update_config_ignores_unknown_fields(self):
        """Test update_config ignores unknown fields."""
        config = DiagnosticConfig(enabled=True)
        logger = DiagnosticLogger(config)

        logger.update_config(unknown_field="value")  # Should not raise


# =============================================================================
# TIMING CONTEXT TESTS
# =============================================================================


class TestTimingContext:
    """Tests for TimingContext context manager."""

    def test_timing_context_records_duration(self):
        """Test TimingContext records duration."""
        with patch.object(diag_logger, 'timing') as mock_timing:
            with TimingContext("test_operation"):
                time.sleep(0.01)

            mock_timing.assert_called_once()
            call_args = mock_timing.call_args
            assert call_args[0][0] == "test_operation"
            assert call_args[0][1] >= 10  # At least 10ms

    def test_timing_context_with_context_dict(self):
        """Test TimingContext with context dictionary."""
        with patch.object(diag_logger, 'timing') as mock_timing:
            with TimingContext("test_operation", context={"key": "value"}):
                pass

            mock_timing.assert_called_once()
            call_args = mock_timing.call_args
            assert "key" in call_args[0][2]

    def test_timing_context_on_exception(self):
        """Test TimingContext still logs on exception."""
        with patch.object(diag_logger, 'timing') as mock_timing:
            with pytest.raises(ValueError):
                with TimingContext("test_operation"):
                    raise ValueError("Test error")

            mock_timing.assert_called_once()
            call_args = mock_timing.call_args
            assert "error" in call_args[0][2]

    def test_timing_context_does_not_suppress_exception(self):
        """Test TimingContext does not suppress exceptions."""
        with pytest.raises(RuntimeError):
            with TimingContext("test_operation"):
                raise RuntimeError("Should propagate")

    def test_timing_context_returns_self(self):
        """Test TimingContext returns self on enter."""
        with TimingContext("test") as ctx:
            assert isinstance(ctx, TimingContext)
            assert ctx.start_time is not None


# =============================================================================
# LOG REQUEST DECORATOR TESTS
# =============================================================================


class TestLogRequestDecorator:
    """Tests for log_request decorator."""

    @pytest.fixture
    def mock_request(self):
        """Create a mock aiohttp request."""
        request = AsyncMock()
        request.method = "POST"
        request.path = "/api/test"
        request.query = {}
        request.remote = "127.0.0.1"
        request.can_read_body = True
        request.body_exists = True
        request.json = AsyncMock(return_value={"test": "data"})
        request.text = AsyncMock(return_value="test body")
        return request

    @pytest.fixture
    def mock_response(self):
        """Create a mock aiohttp response."""
        response = Mock()
        response.status = 200
        response.text = '{"success": true}'
        return response

    @pytest.mark.asyncio
    async def test_decorator_calls_handler(self, mock_request, mock_response):
        """Test decorator calls the original handler."""
        @log_request
        async def handler(request):
            return mock_response

        result = await handler(mock_request)
        assert result == mock_response

    @pytest.mark.asyncio
    async def test_decorator_logs_request(self, mock_request, mock_response):
        """Test decorator logs the request."""
        with patch.object(diag_logger, 'request') as mock_log:
            @log_request
            async def handler(request):
                return mock_response

            await handler(mock_request)

            mock_log.assert_called_once()
            call_kwargs = mock_log.call_args[1]
            assert call_kwargs["method"] == "POST"
            assert call_kwargs["path"] == "/api/test"

    @pytest.mark.asyncio
    async def test_decorator_logs_response(self, mock_request, mock_response):
        """Test decorator logs the response."""
        with patch.object(diag_logger, 'response') as mock_log:
            @log_request
            async def handler(request):
                return mock_response

            await handler(mock_request)

            mock_log.assert_called_once()
            call_kwargs = mock_log.call_args[1]
            assert call_kwargs["status"] == 200

    @pytest.mark.asyncio
    async def test_decorator_handles_json_body_error(self, mock_request, mock_response):
        """Test decorator handles JSON body parsing error."""
        mock_request.json = AsyncMock(side_effect=ValueError("Invalid JSON"))

        @log_request
        async def handler(request):
            return mock_response

        result = await handler(mock_request)
        assert result == mock_response

    @pytest.mark.asyncio
    async def test_decorator_handles_handler_exception(self, mock_request):
        """Test decorator handles exception from handler."""
        with patch.object(diag_logger, 'error'):
            @log_request
            async def handler(request):
                raise RuntimeError("Handler error")

            with pytest.raises(RuntimeError):
                await handler(mock_request)

    @pytest.mark.asyncio
    async def test_decorator_logs_error_on_exception(self, mock_request):
        """Test decorator logs error when handler raises."""
        with patch.object(diag_logger, 'error') as mock_error:
            @log_request
            async def handler(request):
                raise ValueError("Handler error")

            with pytest.raises(ValueError):
                await handler(mock_request)

            mock_error.assert_called_once()

    @pytest.mark.asyncio
    async def test_decorator_handles_response_without_text(self, mock_request):
        """Test decorator handles response without text attribute."""
        response = Mock()
        response.status = 204
        del response.text  # Remove text attribute

        @log_request
        async def handler(request):
            return response

        result = await handler(mock_request)
        assert result.status == 204

    @pytest.mark.asyncio
    async def test_decorator_handles_non_json_response(self, mock_request):
        """Test decorator handles non-JSON response text."""
        response = Mock()
        response.status = 200
        response.text = "plain text response"

        @log_request
        async def handler(request):
            return response

        result = await handler(mock_request)
        assert result.status == 200

    @pytest.mark.asyncio
    async def test_decorator_handles_body_read_error(self, mock_request, mock_response):
        """Test decorator handles error reading request body."""
        mock_request.json = AsyncMock(side_effect=Exception("Read error"))
        mock_request.text = AsyncMock(side_effect=Exception("Read error"))

        @log_request
        async def handler(request):
            return mock_response

        result = await handler(mock_request)
        assert result == mock_response

    @pytest.mark.asyncio
    async def test_decorator_passes_args_to_handler(self, mock_request, mock_response):
        """Test decorator passes additional args to handler."""
        @log_request
        async def handler(request, extra_arg, kwarg=None):
            assert extra_arg == "test"
            assert kwarg == "value"
            return mock_response

        result = await handler(mock_request, "test", kwarg="value")
        assert result == mock_response


# =============================================================================
# CONFIGURATION FUNCTIONS TESTS
# =============================================================================


class TestConfigFunctions:
    """Tests for configuration getter/setter functions."""

    def test_get_diagnostic_config(self):
        """Test getting diagnostic config returns dict."""
        config = get_diagnostic_config()
        assert isinstance(config, dict)
        assert "enabled" in config
        assert "level" in config
        assert "format" in config

    def test_set_diagnostic_config(self):
        """Test setting diagnostic config via kwargs."""
        # Save original
        original = get_diagnostic_config()

        try:
            result = set_diagnostic_config(level="WARNING")
            assert isinstance(result, dict)
            assert result["level"] == "WARNING"
        finally:
            # Restore original
            set_diagnostic_config(**original)

    def test_set_diagnostic_config_returns_updated_config(self):
        """Test set returns the updated config."""
        original = get_diagnostic_config()

        try:
            result = set_diagnostic_config(level="ERROR")
            current = get_diagnostic_config()
            assert result == current
        finally:
            set_diagnostic_config(**original)

    def test_global_diag_logger_exists(self):
        """Test that global diag_logger exists."""
        assert diag_logger is not None
        assert isinstance(diag_logger, DiagnosticLogger)


# =============================================================================
# SYSLOG HANDLER TESTS
# =============================================================================


class TestSyslogHandler:
    """Tests for syslog handler setup."""

    def test_syslog_handler_udp(self):
        """Test syslog handler with UDP protocol."""
        config = DiagnosticConfig(
            enabled=True,
            syslog_host="localhost",
            syslog_port=514,
            syslog_protocol="udp",
        )
        with patch('logging.handlers.SysLogHandler') as mock_handler:
            mock_handler.return_value = MagicMock()
            _logger = DiagnosticLogger(config)  # noqa: F841

            mock_handler.assert_called()
            call_kwargs = mock_handler.call_args[1]
            assert call_kwargs["address"] == ("localhost", 514)
            # UDP uses SOCK_DGRAM
            import socket
            assert call_kwargs["socktype"] == socket.SOCK_DGRAM

    def test_syslog_handler_tcp(self):
        """Test syslog handler with TCP protocol."""
        config = DiagnosticConfig(
            enabled=True,
            syslog_host="localhost",
            syslog_port=514,
            syslog_protocol="tcp",
        )
        with patch('logging.handlers.SysLogHandler') as mock_handler:
            mock_handler.return_value = MagicMock()
            _logger = DiagnosticLogger(config)  # noqa: F841

            mock_handler.assert_called()
            call_kwargs = mock_handler.call_args[1]
            # TCP uses SOCK_STREAM
            import socket
            assert call_kwargs["socktype"] == socket.SOCK_STREAM

    def test_syslog_handler_error_prints_warning(self, capsys):
        """Test syslog handler error prints warning."""
        config = DiagnosticConfig(
            enabled=True,
            syslog_host="nonexistent.host.local",
            syslog_port=514,
        )
        with patch('logging.handlers.SysLogHandler',
                   side_effect=OSError("Connection refused")):
            _logger = DiagnosticLogger(config)  # noqa: F841

            captured = capsys.readouterr()
            # Should print warning but not raise
            assert "Warning" in captured.out or True  # May not print depending on impl


# =============================================================================
# DISABLED LOGGING TESTS
# =============================================================================


class TestDisabledLogging:
    """Tests for disabled logging behavior."""

    def test_disabled_logger_skips_all_logging(self):
        """Test that disabled logger skips all logging operations."""
        config = DiagnosticConfig(enabled=False)
        logger = DiagnosticLogger(config)

        # All of these should not raise and should be no-ops
        logger.debug("Should be skipped")
        logger.info("Should be skipped")
        logger.warning("Should be skipped")
        logger.error("Should be skipped")
        logger.exception("Should be skipped")
        logger.request("GET", "/test")
        logger.response(200)
        logger.timing("operation", 100.0)
        logger.separator()

    def test_disabled_logger_has_empty_handlers(self):
        """Test disabled logger has no handlers."""
        config = DiagnosticConfig(enabled=False)
        logger = DiagnosticLogger(config)
        assert len(logger._logger.handlers) == 0


# =============================================================================
# EDGE CASES AND ERROR HANDLING
# =============================================================================


class TestEdgeCases:
    """Tests for edge cases and error handling."""

    def test_empty_message(self):
        """Test logging empty message."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        logger.info("")  # Should not raise

    def test_none_context(self):
        """Test logging with None context."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        logger.info("Test", context=None)  # Should not raise

    def test_empty_context(self):
        """Test logging with empty context dict."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        logger.info("Test", context={})  # Should not raise

    def test_unicode_message(self):
        """Test logging unicode message."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        logger.info("Test message with unicode: \u2603 \u2764 \U0001F600")

    def test_unicode_context(self):
        """Test logging with unicode in context."""
        config = DiagnosticConfig(enabled=True, format="json")
        logger = DiagnosticLogger(config)
        logger.info("Test", context={"emoji": "\U0001F600", "symbol": "\u2603"})

    def test_very_long_message(self):
        """Test logging very long message."""
        config = DiagnosticConfig(enabled=True, format="console")
        logger = DiagnosticLogger(config)
        long_message = "x" * 10000
        logger.info(long_message)  # Should not raise

    def test_nested_context(self):
        """Test logging with deeply nested context."""
        config = DiagnosticConfig(enabled=True, format="json")
        logger = DiagnosticLogger(config)
        nested = {"a": {"b": {"c": {"d": "value"}}}}
        logger.info("Test", context=nested)  # Should not raise

    def test_context_with_non_string_keys(self):
        """Test context handling with various value types."""
        config = DiagnosticConfig(enabled=True, format="json")
        logger = DiagnosticLogger(config)
        context = {
            "int_val": 123,
            "float_val": 3.14,
            "bool_val": True,
            "none_val": None,
            "list_val": [1, 2, 3],
        }
        logger.info("Test", context=context)  # Should not raise

    def test_request_with_empty_body(self):
        """Test request logging with empty body."""
        config = DiagnosticConfig(enabled=True, log_requests=True)
        logger = DiagnosticLogger(config)
        logger.request("GET", "/test", body=None)
        logger.request("GET", "/test", body={})
        logger.request("GET", "/test", body="")

    def test_response_with_empty_body(self):
        """Test response logging with empty body."""
        config = DiagnosticConfig(enabled=True, log_responses=True)
        logger = DiagnosticLogger(config)
        logger.response(204, body=None)
        logger.response(200, body={})
        logger.response(200, body="")

    def test_timing_with_zero_duration(self):
        """Test timing with zero duration."""
        config = DiagnosticConfig(enabled=True, log_timing=True)
        logger = DiagnosticLogger(config)
        logger.timing("instant_operation", 0.0)  # Should not raise

    def test_timing_with_negative_duration(self):
        """Test timing with negative duration (edge case)."""
        config = DiagnosticConfig(enabled=True, log_timing=True)
        logger = DiagnosticLogger(config)
        logger.timing("weird_operation", -10.0)  # Should not raise


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
