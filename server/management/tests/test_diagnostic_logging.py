"""
Tests for Diagnostic Logging

Comprehensive tests for the diagnostic logging system.
"""

import pytest
import logging
import json

from diagnostic_logging import (
    LogFormat,
    DiagnosticConfig,
    JSONFormatter,
    GELFFormatter,
    SyslogFormatter,
    DiagnosticLogger,
    get_diagnostic_config,
    set_diagnostic_config,
    diag_logger,
)


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

    def test_to_dict(self):
        """Test to_dict method."""
        config = DiagnosticConfig(enabled=True, level="INFO")
        result = config.to_dict()
        assert isinstance(result, dict)
        assert result["enabled"] is True
        assert result["level"] == "INFO"

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
        assert "source" in parsed
        assert parsed["source"]["line"] == 42

    def test_format_with_exception(self, formatter):
        """Test formatting a record with exception."""
        try:
            raise ValueError("Test error")
        except ValueError:
            import sys
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


class TestGELFFormatter:
    """Tests for GELFFormatter class."""

    @pytest.fixture
    def formatter(self):
        """Create a GELF formatter."""
        return GELFFormatter(app_name="test-app")

    def test_init(self, formatter):
        """Test formatter initialization."""
        assert formatter.app_name == "test-app"

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
        assert "_app" in parsed


class TestSyslogFormatter:
    """Tests for SyslogFormatter class."""

    @pytest.fixture
    def formatter(self):
        """Create a Syslog formatter."""
        return SyslogFormatter(app_name="test-app", facility="local0")

    def test_init(self, formatter):
        """Test formatter initialization."""
        assert formatter.app_name == "test-app"

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
        # Should be RFC 5424 format
        assert "test-app" in result
        assert "Test message" in result


class TestDiagnosticLogger:
    """Tests for DiagnosticLogger class."""

    @pytest.fixture
    def logger(self):
        """Create a diagnostic logger."""
        config = DiagnosticConfig(
            enabled=True,
            level="DEBUG",
            format="console",
        )
        return DiagnosticLogger(config)

    def test_init(self, logger):
        """Test logger initialization."""
        assert logger.config.enabled is True
        assert logger.config.level == "DEBUG"

    def test_is_enabled(self, logger):
        """Test is_enabled method."""
        assert logger.is_enabled() is True

    def test_disable(self, logger):
        """Test disable method."""
        logger.disable()
        assert logger.is_enabled() is False

    def test_enable(self, logger):
        """Test enable method."""
        logger.disable()
        logger.enable()
        assert logger.is_enabled() is True

    def test_log_debug(self, logger):
        """Test debug logging."""
        # Should not raise
        logger.debug("Debug message")

    def test_log_info(self, logger):
        """Test info logging."""
        # Should not raise
        logger.info("Info message")

    def test_log_warning(self, logger):
        """Test warning logging."""
        # Should not raise
        logger.warning("Warning message")

    def test_log_error(self, logger):
        """Test error logging."""
        # Should not raise
        logger.error("Error message")

    def test_log_with_context(self, logger):
        """Test logging with context."""
        # Should not raise
        logger.info("Message with context", context={"key": "value"})


class TestConfigFunctions:
    """Tests for configuration getter/setter functions."""

    def test_get_diagnostic_config(self):
        """Test getting diagnostic config (returns dict)."""
        config = get_diagnostic_config()
        assert isinstance(config, dict)
        assert "enabled" in config
        assert "level" in config

    def test_set_diagnostic_config(self):
        """Test setting diagnostic config via kwargs."""
        # Set config returns the updated config dict
        result = set_diagnostic_config(level="WARNING")
        assert isinstance(result, dict)

    def test_global_diag_logger_exists(self):
        """Test that global diag_logger exists."""
        assert diag_logger is not None
        assert isinstance(diag_logger, DiagnosticLogger)


class TestDisabledLogging:
    """Tests for disabled logging behavior."""

    def test_disabled_logger_skips_logging(self):
        """Test that disabled logger skips logging operations."""
        config = DiagnosticConfig(enabled=False)
        logger = DiagnosticLogger(config)

        # These should not raise and should be no-ops
        logger.debug("Should be skipped")
        logger.info("Should be skipped")
        logger.warning("Should be skipped")
        logger.error("Should be skipped")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
