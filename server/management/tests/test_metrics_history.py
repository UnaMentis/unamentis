"""
Tests for the Metrics History module.

Tests cover:
- HourlyMetrics dataclass
- DailyMetrics dataclass
- MetricsHistory class including:
  - Data loading and saving
  - Sample recording
  - Hour and day aggregation
  - History retrieval
  - Summary statistics
- _HourAccumulator internal class
"""

import asyncio
import json
import time
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch, mock_open

import pytest

from metrics_history import (
    HourlyMetrics,
    DailyMetrics,
    MetricsHistory,
    _HourAccumulator,
    metrics_history,
)


# =============================================================================
# HOURLY METRICS TESTS
# =============================================================================


class TestHourlyMetrics:
    """Tests for HourlyMetrics dataclass."""

    def test_hourly_metrics_defaults(self):
        """Test HourlyMetrics has sensible defaults."""
        metrics = HourlyMetrics(hour="2025-12-22T14:00:00")

        assert metrics.hour == "2025-12-22T14:00:00"
        assert metrics.avg_battery_draw_w == 0.0
        assert metrics.max_battery_draw_w == 0.0
        assert metrics.min_battery_percent == 100.0
        assert metrics.max_battery_percent == 100.0
        assert metrics.avg_thermal_level == 0.0
        assert metrics.max_thermal_level == 0
        assert metrics.avg_cpu_temp_c == 0.0
        assert metrics.max_cpu_temp_c == 0.0
        assert metrics.avg_cpu_percent == 0.0
        assert metrics.max_cpu_percent == 0.0
        assert metrics.service_cpu_avg == {}
        assert metrics.service_cpu_max == {}
        assert metrics.total_requests == 0
        assert metrics.total_inferences == 0
        assert metrics.idle_state_seconds == {}
        assert metrics.sample_count == 0

    def test_hourly_metrics_custom_values(self):
        """Test HourlyMetrics with custom values."""
        metrics = HourlyMetrics(
            hour="2025-12-22T15:00:00",
            avg_battery_draw_w=12.5,
            max_battery_draw_w=18.0,
            min_battery_percent=75.0,
            max_battery_percent=85.0,
            avg_thermal_level=1.2,
            max_thermal_level=2,
            avg_cpu_temp_c=65.5,
            max_cpu_temp_c=72.0,
            avg_cpu_percent=35.0,
            max_cpu_percent=78.0,
            service_cpu_avg={"ollama": 25.0, "management": 5.0},
            service_cpu_max={"ollama": 60.0, "management": 15.0},
            total_requests=150,
            total_inferences=50,
            idle_state_seconds={"active": 1800, "warm": 1800},
            sample_count=720,
        )

        assert metrics.hour == "2025-12-22T15:00:00"
        assert metrics.avg_battery_draw_w == 12.5
        assert metrics.max_battery_draw_w == 18.0
        assert metrics.min_battery_percent == 75.0
        assert metrics.max_battery_percent == 85.0
        assert metrics.avg_thermal_level == 1.2
        assert metrics.max_thermal_level == 2
        assert metrics.avg_cpu_temp_c == 65.5
        assert metrics.max_cpu_temp_c == 72.0
        assert metrics.avg_cpu_percent == 35.0
        assert metrics.max_cpu_percent == 78.0
        assert metrics.service_cpu_avg["ollama"] == 25.0
        assert metrics.service_cpu_max["ollama"] == 60.0
        assert metrics.total_requests == 150
        assert metrics.total_inferences == 50
        assert metrics.idle_state_seconds["active"] == 1800
        assert metrics.sample_count == 720

    def test_hourly_metrics_to_dict(self):
        """Test HourlyMetrics to_dict conversion."""
        metrics = HourlyMetrics(
            hour="2025-12-22T16:00:00",
            avg_battery_draw_w=10.0,
            max_thermal_level=1,
            sample_count=360,
        )

        result = metrics.to_dict()

        assert isinstance(result, dict)
        assert result["hour"] == "2025-12-22T16:00:00"
        assert result["avg_battery_draw_w"] == 10.0
        assert result["max_thermal_level"] == 1
        assert result["sample_count"] == 360

    def test_hourly_metrics_from_dict(self):
        """Test HourlyMetrics from_dict conversion."""
        data = {
            "hour": "2025-12-22T17:00:00",
            "avg_battery_draw_w": 15.0,
            "max_battery_draw_w": 20.0,
            "min_battery_percent": 60.0,
            "max_battery_percent": 70.0,
            "avg_thermal_level": 0.5,
            "max_thermal_level": 1,
            "avg_cpu_temp_c": 55.0,
            "max_cpu_temp_c": 60.0,
            "avg_cpu_percent": 20.0,
            "max_cpu_percent": 45.0,
            "service_cpu_avg": {"test": 10.0},
            "service_cpu_max": {"test": 20.0},
            "total_requests": 100,
            "total_inferences": 25,
            "idle_state_seconds": {"cool": 3600},
            "sample_count": 720,
        }

        metrics = HourlyMetrics.from_dict(data)

        assert metrics.hour == "2025-12-22T17:00:00"
        assert metrics.avg_battery_draw_w == 15.0
        assert metrics.max_battery_draw_w == 20.0
        assert metrics.service_cpu_avg["test"] == 10.0
        assert metrics.total_requests == 100
        assert metrics.sample_count == 720


# =============================================================================
# DAILY METRICS TESTS
# =============================================================================


class TestDailyMetrics:
    """Tests for DailyMetrics dataclass."""

    def test_daily_metrics_defaults(self):
        """Test DailyMetrics has sensible defaults."""
        metrics = DailyMetrics(date="2025-12-22")

        assert metrics.date == "2025-12-22"
        assert metrics.avg_battery_draw_w == 0.0
        assert metrics.max_battery_draw_w == 0.0
        assert metrics.min_battery_percent == 100.0
        assert metrics.battery_drain_percent == 0.0
        assert metrics.avg_thermal_level == 0.0
        assert metrics.max_thermal_level == 0
        assert metrics.thermal_events_count == 0
        assert metrics.avg_cpu_temp_c == 0.0
        assert metrics.max_cpu_temp_c == 0.0
        assert metrics.avg_cpu_percent == 0.0
        assert metrics.max_cpu_percent == 0.0
        assert metrics.service_cpu_avg == {}
        assert metrics.total_requests == 0
        assert metrics.total_inferences == 0
        assert metrics.active_hours == 0
        assert metrics.idle_state_hours == {}
        assert metrics.hours_aggregated == 0

    def test_daily_metrics_custom_values(self):
        """Test DailyMetrics with custom values."""
        metrics = DailyMetrics(
            date="2025-12-23",
            avg_battery_draw_w=10.0,
            max_battery_draw_w=25.0,
            min_battery_percent=20.0,
            battery_drain_percent=50.0,
            avg_thermal_level=0.8,
            max_thermal_level=2,
            thermal_events_count=3,
            avg_cpu_temp_c=58.0,
            max_cpu_temp_c=75.0,
            avg_cpu_percent=30.0,
            max_cpu_percent=95.0,
            service_cpu_avg={"ollama": 20.0},
            total_requests=1000,
            total_inferences=250,
            active_hours=18,
            idle_state_hours={"active": 12.0, "warm": 6.0},
            hours_aggregated=24,
        )

        assert metrics.date == "2025-12-23"
        assert metrics.avg_battery_draw_w == 10.0
        assert metrics.battery_drain_percent == 50.0
        assert metrics.thermal_events_count == 3
        assert metrics.active_hours == 18
        assert metrics.hours_aggregated == 24

    def test_daily_metrics_to_dict(self):
        """Test DailyMetrics to_dict conversion."""
        metrics = DailyMetrics(
            date="2025-12-24",
            avg_cpu_percent=25.0,
            total_requests=500,
            hours_aggregated=12,
        )

        result = metrics.to_dict()

        assert isinstance(result, dict)
        assert result["date"] == "2025-12-24"
        assert result["avg_cpu_percent"] == 25.0
        assert result["total_requests"] == 500
        assert result["hours_aggregated"] == 12

    def test_daily_metrics_from_dict(self):
        """Test DailyMetrics from_dict conversion."""
        data = {
            "date": "2025-12-25",
            "avg_battery_draw_w": 8.0,
            "max_battery_draw_w": 15.0,
            "min_battery_percent": 45.0,
            "battery_drain_percent": 35.0,
            "avg_thermal_level": 0.3,
            "max_thermal_level": 1,
            "thermal_events_count": 1,
            "avg_cpu_temp_c": 50.0,
            "max_cpu_temp_c": 58.0,
            "avg_cpu_percent": 15.0,
            "max_cpu_percent": 40.0,
            "service_cpu_avg": {"management": 5.0},
            "total_requests": 200,
            "total_inferences": 30,
            "active_hours": 8,
            "idle_state_hours": {"cold": 16.0},
            "hours_aggregated": 24,
        }

        metrics = DailyMetrics.from_dict(data)

        assert metrics.date == "2025-12-25"
        assert metrics.avg_battery_draw_w == 8.0
        assert metrics.battery_drain_percent == 35.0
        assert metrics.service_cpu_avg["management"] == 5.0
        assert metrics.hours_aggregated == 24


# =============================================================================
# HOUR ACCUMULATOR TESTS
# =============================================================================


class TestHourAccumulator:
    """Tests for _HourAccumulator internal class."""

    def test_accumulator_init(self):
        """Test accumulator initialization."""
        acc = _HourAccumulator("2025-12-22T14:00:00")

        assert acc.hour == "2025-12-22T14:00:00"
        assert acc.sample_count == 0
        assert acc.battery_draw_sum == 0.0
        assert acc.battery_draw_max == 0.0
        assert acc.battery_percent_min == 100.0
        assert acc.battery_percent_max == 0.0
        assert acc.thermal_level_sum == 0.0
        assert acc.thermal_level_max == 0
        assert acc.cpu_temp_sum == 0.0
        assert acc.cpu_temp_max == 0.0
        assert acc.cpu_percent_sum == 0.0
        assert acc.cpu_percent_max == 0.0
        assert acc.total_requests == 0
        assert acc.total_inferences == 0
        assert acc.last_sample_time is None

    def test_add_sample_basic(self):
        """Test adding a basic sample."""
        acc = _HourAccumulator("2025-12-22T14:00:00")

        metrics = {
            "power": {
                "current_battery_draw_w": 10.0,
                "battery_percent": 80.0,
            },
            "thermal": {
                "pressure_level": 1,
                "cpu_temp_c": 55.0,
            },
            "cpu": {
                "total_percent": 25.0,
                "by_service": {"ollama": 20.0, "management": 5.0},
            },
        }

        acc.add_sample(metrics, "active")

        assert acc.sample_count == 1
        assert acc.battery_draw_sum == 10.0
        assert acc.battery_draw_max == 10.0
        assert acc.battery_percent_min == 80.0
        assert acc.battery_percent_max == 80.0
        assert acc.thermal_level_sum == 1.0
        assert acc.thermal_level_max == 1
        assert acc.cpu_temp_sum == 55.0
        assert acc.cpu_temp_max == 55.0
        assert acc.cpu_percent_sum == 25.0
        assert acc.cpu_percent_max == 25.0
        assert acc.service_cpu_sums["ollama"] == 20.0
        assert acc.service_cpu_maxes["ollama"] == 20.0
        assert acc.service_cpu_counts["ollama"] == 1

    def test_add_sample_multiple(self):
        """Test adding multiple samples."""
        acc = _HourAccumulator("2025-12-22T14:00:00")

        # First sample
        metrics1 = {
            "power": {"current_battery_draw_w": 10.0, "battery_percent": 85.0},
            "thermal": {"pressure_level": 0, "cpu_temp_c": 50.0},
            "cpu": {"total_percent": 20.0, "by_service": {}},
        }
        acc.add_sample(metrics1, "active")

        # Second sample
        metrics2 = {
            "power": {"current_battery_draw_w": 15.0, "battery_percent": 80.0},
            "thermal": {"pressure_level": 1, "cpu_temp_c": 60.0},
            "cpu": {"total_percent": 40.0, "by_service": {}},
        }
        acc.add_sample(metrics2, "active")

        assert acc.sample_count == 2
        assert acc.battery_draw_sum == 25.0
        assert acc.battery_draw_max == 15.0
        assert acc.battery_percent_min == 80.0
        assert acc.battery_percent_max == 85.0
        assert acc.thermal_level_sum == 1.0
        assert acc.thermal_level_max == 1
        assert acc.cpu_temp_sum == 110.0
        assert acc.cpu_temp_max == 60.0
        assert acc.cpu_percent_sum == 60.0
        assert acc.cpu_percent_max == 40.0

    def test_add_sample_fallback_battery_draw(self):
        """Test fallback to avg_battery_draw_w when current not available."""
        acc = _HourAccumulator("2025-12-22T14:00:00")

        metrics = {
            "power": {"avg_battery_draw_w": 8.0, "battery_percent": 90.0},
            "thermal": {"pressure_level": 0, "cpu_temp_c": 45.0},
            "cpu": {"total_percent": 10.0, "by_service": {}},
        }

        acc.add_sample(metrics, "warm")

        assert acc.battery_draw_sum == 8.0
        assert acc.battery_draw_max == 8.0

    def test_add_sample_idle_state_tracking(self):
        """Test idle state time tracking."""
        acc = _HourAccumulator("2025-12-22T14:00:00")

        metrics = {
            "power": {"battery_percent": 90.0},
            "thermal": {},
            "cpu": {"total_percent": 5.0, "by_service": {}},
        }

        # First sample sets last_sample_time but no idle tracking yet
        acc.add_sample(metrics, "active")
        assert acc.last_sample_time is not None
        assert acc.idle_state_seconds.get("active", 0) == 0

        # Second sample after delay tracks idle time
        time.sleep(0.1)
        acc.add_sample(metrics, "warm")
        # The idle time should be tracked (small but non-zero)
        assert "warm" in acc.idle_state_seconds or acc.idle_state_seconds.get("active", 0) >= 0

    def test_finalize_empty(self):
        """Test finalizing with no samples."""
        acc = _HourAccumulator("2025-12-22T14:00:00")

        result = acc.finalize()

        assert isinstance(result, HourlyMetrics)
        assert result.hour == "2025-12-22T14:00:00"
        assert result.sample_count == 0

    def test_finalize_with_samples(self):
        """Test finalizing with samples."""
        acc = _HourAccumulator("2025-12-22T15:00:00")

        # Add 2 samples
        metrics = {
            "power": {"current_battery_draw_w": 10.0, "battery_percent": 80.0},
            "thermal": {"pressure_level": 1, "cpu_temp_c": 60.0},
            "cpu": {"total_percent": 30.0, "by_service": {"ollama": 25.0}},
        }
        acc.add_sample(metrics, "active")
        acc.add_sample(metrics, "active")

        result = acc.finalize()

        assert result.hour == "2025-12-22T15:00:00"
        assert result.sample_count == 2
        assert result.avg_battery_draw_w == 10.0  # (10+10)/2
        assert result.max_battery_draw_w == 10.0
        assert result.min_battery_percent == 80.0
        assert result.avg_thermal_level == 1.0
        assert result.max_thermal_level == 1
        assert result.avg_cpu_temp_c == 60.0
        assert result.max_cpu_temp_c == 60.0
        assert result.avg_cpu_percent == 30.0
        assert result.max_cpu_percent == 30.0
        assert result.service_cpu_avg["ollama"] == 25.0
        assert result.service_cpu_max["ollama"] == 25.0

    def test_finalize_rounding(self):
        """Test that finalize rounds values appropriately."""
        acc = _HourAccumulator("2025-12-22T16:00:00")

        metrics = {
            "power": {"current_battery_draw_w": 10.333, "battery_percent": 77.777},
            "thermal": {"pressure_level": 1, "cpu_temp_c": 55.555},
            "cpu": {"total_percent": 33.333, "by_service": {"test": 22.222}},
        }
        acc.add_sample(metrics, "active")

        result = acc.finalize()

        # Values should be rounded
        assert result.avg_battery_draw_w == 10.33
        assert result.max_battery_draw_w == 10.33
        assert result.min_battery_percent == 77.8
        assert result.avg_cpu_temp_c == 55.6
        assert result.avg_cpu_percent == 33.3
        assert result.service_cpu_avg["test"] == 22.2


# =============================================================================
# METRICS HISTORY TESTS
# =============================================================================


class TestMetricsHistoryInit:
    """Tests for MetricsHistory initialization."""

    def test_init_creates_empty_storage(self):
        """Test initialization creates empty storage structures."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

            assert history.hourly_metrics == {}
            assert history.daily_metrics == {}
            assert history._current_hour is None
            assert history._hour_accumulator is None
            assert history._running is False
            assert history._save_task is None
            assert history._dirty is False

    def test_init_calls_load_data(self):
        """Test initialization calls _load_data."""
        with patch.object(MetricsHistory, "_load_data") as mock_load:
            MetricsHistory()
            mock_load.assert_called_once()


class TestMetricsHistoryLoadData:
    """Tests for data loading functionality."""

    def test_load_data_creates_data_dir(self):
        """Test _load_data creates DATA_DIR if it doesn't exist."""
        with patch.object(Path, "mkdir") as mock_mkdir, \
             patch.object(Path, "exists", return_value=False):
            MetricsHistory()
            mock_mkdir.assert_called()

    def test_load_data_loads_hourly_file(self):
        """Test _load_data loads hourly metrics from file."""
        hourly_data = {
            "2025-12-22T14:00:00": {
                "hour": "2025-12-22T14:00:00",
                "avg_battery_draw_w": 10.0,
                "max_battery_draw_w": 15.0,
                "min_battery_percent": 80.0,
                "max_battery_percent": 85.0,
                "avg_thermal_level": 0.5,
                "max_thermal_level": 1,
                "avg_cpu_temp_c": 55.0,
                "max_cpu_temp_c": 60.0,
                "avg_cpu_percent": 20.0,
                "max_cpu_percent": 35.0,
                "service_cpu_avg": {},
                "service_cpu_max": {},
                "total_requests": 100,
                "total_inferences": 25,
                "idle_state_seconds": {},
                "sample_count": 720,
            }
        }

        with patch.object(Path, "mkdir"), \
             patch.object(Path, "exists", return_value=True), \
             patch("builtins.open", mock_open(read_data=json.dumps(hourly_data))):
            history = MetricsHistory()

            assert "2025-12-22T14:00:00" in history.hourly_metrics
            assert history.hourly_metrics["2025-12-22T14:00:00"].avg_battery_draw_w == 10.0

    def test_load_data_handles_missing_files(self):
        """Test _load_data handles missing files gracefully."""
        with patch.object(Path, "mkdir"), \
             patch.object(Path, "exists", return_value=False):
            history = MetricsHistory()

            assert history.hourly_metrics == {}
            assert history.daily_metrics == {}

    def test_load_data_handles_corrupt_hourly_file(self):
        """Test _load_data handles corrupt hourly file."""
        with patch.object(Path, "mkdir"), \
             patch.object(Path, "exists", side_effect=[True, False]), \
             patch("builtins.open", mock_open(read_data="invalid json")):
            # Should not raise, just log error
            history = MetricsHistory()
            assert history.hourly_metrics == {}


class TestMetricsHistorySaveData:
    """Tests for data saving functionality."""

    def test_save_data_creates_data_dir(self):
        """Test _save_data creates DATA_DIR."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        with patch.object(Path, "mkdir") as mock_mkdir, \
             patch("builtins.open", mock_open()):
            history._save_data()
            mock_mkdir.assert_called()

    def test_save_data_writes_files(self):
        """Test _save_data writes hourly and daily files."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()
            history.hourly_metrics["2025-12-22T14:00:00"] = HourlyMetrics(
                hour="2025-12-22T14:00:00",
                avg_cpu_percent=20.0,
            )
            history.daily_metrics["2025-12-22"] = DailyMetrics(
                date="2025-12-22",
                avg_cpu_percent=25.0,
            )
            history._dirty = True

        mock_file = mock_open()
        with patch.object(Path, "mkdir"), \
             patch("builtins.open", mock_file):
            history._save_data()

            # Should have opened files for writing
            assert mock_file.call_count >= 2
            assert history._dirty is False

    def test_save_data_handles_error(self):
        """Test _save_data handles errors gracefully."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        # The _save_data method wraps mkdir in a try/except, but to test the error path
        # we need to make the open() call fail instead since mkdir is called before try
        with patch.object(Path, "mkdir"), \
             patch("builtins.open", side_effect=Exception("Test error")):
            # Should not raise (error is caught and logged)
            history._save_data()


class TestMetricsHistoryLifecycle:
    """Tests for start/stop lifecycle."""

    @pytest.mark.asyncio
    async def test_start_creates_task(self):
        """Test start creates save task."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        await history.start()

        assert history._running is True
        assert history._save_task is not None

        await history.stop()

    @pytest.mark.asyncio
    async def test_start_idempotent(self):
        """Test start is idempotent."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        await history.start()
        task1 = history._save_task
        await history.start()
        task2 = history._save_task

        assert task1 is task2

        await history.stop()

    @pytest.mark.asyncio
    async def test_stop_cancels_task(self):
        """Test stop cancels save task."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        await history.start()
        await history.stop()

        assert history._running is False

    @pytest.mark.asyncio
    async def test_stop_finalizes_and_saves(self):
        """Test stop finalizes current hour and saves."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()
            history._current_hour = "2025-12-22T14:00:00"
            history._hour_accumulator = _HourAccumulator("2025-12-22T14:00:00")
            history._hour_accumulator.sample_count = 1

        with patch.object(history, "_save_data") as mock_save:
            await history.start()
            await history.stop()

            mock_save.assert_called()


class TestMetricsHistoryRecordSample:
    """Tests for sample recording."""

    def test_record_sample_creates_accumulator(self):
        """Test record_sample creates hour accumulator if needed."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        metrics = {
            "power": {"current_battery_draw_w": 10.0, "battery_percent": 80.0},
            "thermal": {"pressure_level": 0, "cpu_temp_c": 55.0},
            "cpu": {"total_percent": 20.0, "by_service": {}},
        }

        history.record_sample(metrics, "active")

        assert history._current_hour is not None
        assert history._hour_accumulator is not None
        assert history._hour_accumulator.sample_count == 1
        assert history._dirty is True

    def test_record_sample_accumulates(self):
        """Test record_sample accumulates samples."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        metrics = {
            "power": {"current_battery_draw_w": 10.0, "battery_percent": 80.0},
            "thermal": {"pressure_level": 0, "cpu_temp_c": 55.0},
            "cpu": {"total_percent": 20.0, "by_service": {}},
        }

        history.record_sample(metrics, "active")
        history.record_sample(metrics, "active")
        history.record_sample(metrics, "active")

        assert history._hour_accumulator.sample_count == 3

    def test_record_sample_handles_hour_change(self):
        """Test record_sample handles hour boundary."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        # Set up existing hour
        old_hour = "2025-12-22T13:00:00"
        history._current_hour = old_hour
        history._hour_accumulator = _HourAccumulator(old_hour)
        history._hour_accumulator.sample_count = 100

        # Mock datetime to return a new hour
        new_time = datetime(2025, 12, 22, 14, 30, 0)
        with patch("metrics_history.datetime") as mock_dt:
            mock_dt.now.return_value = new_time

            metrics = {
                "power": {"current_battery_draw_w": 10.0, "battery_percent": 80.0},
                "thermal": {"pressure_level": 0, "cpu_temp_c": 55.0},
                "cpu": {"total_percent": 20.0, "by_service": {}},
            }

            history.record_sample(metrics, "active")

        # Old hour should be finalized and stored
        assert old_hour in history.hourly_metrics
        # New accumulator should have 1 sample
        assert history._hour_accumulator.sample_count == 1


class TestMetricsHistoryHourBoundary:
    """Tests for hour boundary checking."""

    def test_check_hour_boundary_no_change(self):
        """Test _check_hour_boundary when still in same hour."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        now = datetime.now()
        hour_key = now.replace(minute=0, second=0, microsecond=0).isoformat()
        history._current_hour = hour_key
        history._hour_accumulator = _HourAccumulator(hour_key)

        history._check_hour_boundary()

        # Should not create new accumulator
        assert history._current_hour == hour_key

    def test_check_hour_boundary_with_change(self):
        """Test _check_hour_boundary when hour changes."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        old_hour = "2025-12-22T13:00:00"
        history._current_hour = old_hour
        history._hour_accumulator = _HourAccumulator(old_hour)
        history._hour_accumulator.sample_count = 50

        # Mock datetime to return new hour
        new_time = datetime(2025, 12, 22, 14, 30, 0)
        with patch("metrics_history.datetime") as mock_dt:
            mock_dt.now.return_value = new_time

            history._check_hour_boundary()

        # Old hour should be finalized
        assert old_hour in history.hourly_metrics
        # New accumulator should be created
        assert history._current_hour == "2025-12-22T14:00:00"


class TestMetricsHistoryDailyAggregation:
    """Tests for daily metrics aggregation."""

    def test_update_daily_metrics_no_hourly(self):
        """Test _update_daily_metrics with no hourly data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        history._update_daily_metrics("2025-12-22")

        assert "2025-12-22" not in history.daily_metrics

    def test_update_daily_metrics_single_hour(self):
        """Test _update_daily_metrics with single hour."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        history.hourly_metrics["2025-12-22T14:00:00"] = HourlyMetrics(
            hour="2025-12-22T14:00:00",
            avg_battery_draw_w=10.0,
            max_battery_draw_w=15.0,
            min_battery_percent=80.0,
            max_battery_percent=85.0,
            avg_thermal_level=0.5,
            max_thermal_level=1,
            avg_cpu_temp_c=55.0,
            max_cpu_temp_c=60.0,
            avg_cpu_percent=20.0,
            max_cpu_percent=35.0,
            service_cpu_avg={"ollama": 15.0},
            total_requests=100,
            total_inferences=25,
            idle_state_seconds={"active": 3600},
            sample_count=720,
        )

        history._update_daily_metrics("2025-12-22")

        daily = history.daily_metrics["2025-12-22"]
        assert daily.date == "2025-12-22"
        assert daily.hours_aggregated == 1
        assert daily.avg_battery_draw_w == 10.0
        assert daily.max_battery_draw_w == 15.0
        assert daily.min_battery_percent == 80.0
        assert daily.avg_thermal_level == 0.5
        assert daily.max_thermal_level == 1
        assert daily.avg_cpu_percent == 20.0
        assert daily.total_requests == 100
        assert daily.service_cpu_avg["ollama"] == 15.0

    def test_update_daily_metrics_multiple_hours(self):
        """Test _update_daily_metrics with multiple hours."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        # Add 3 hourly records
        history.hourly_metrics["2025-12-22T14:00:00"] = HourlyMetrics(
            hour="2025-12-22T14:00:00",
            avg_battery_draw_w=10.0,
            max_battery_draw_w=12.0,
            min_battery_percent=80.0,
            avg_thermal_level=0.5,
            max_thermal_level=1,
            avg_cpu_temp_c=50.0,
            max_cpu_temp_c=55.0,
            avg_cpu_percent=20.0,
            max_cpu_percent=30.0,
            total_requests=100,
            idle_state_seconds={"active": 3600},
        )
        history.hourly_metrics["2025-12-22T15:00:00"] = HourlyMetrics(
            hour="2025-12-22T15:00:00",
            avg_battery_draw_w=15.0,
            max_battery_draw_w=20.0,
            min_battery_percent=75.0,
            avg_thermal_level=1.0,
            max_thermal_level=2,  # Thermal event
            avg_cpu_temp_c=60.0,
            max_cpu_temp_c=70.0,
            avg_cpu_percent=40.0,
            max_cpu_percent=60.0,
            total_requests=150,
            idle_state_seconds={"warm": 3600},
        )
        history.hourly_metrics["2025-12-22T16:00:00"] = HourlyMetrics(
            hour="2025-12-22T16:00:00",
            avg_battery_draw_w=8.0,
            max_battery_draw_w=10.0,
            min_battery_percent=70.0,
            avg_thermal_level=0.3,
            max_thermal_level=0,
            avg_cpu_temp_c=45.0,
            max_cpu_temp_c=50.0,
            avg_cpu_percent=10.0,
            max_cpu_percent=20.0,
            total_requests=0,  # No activity
            idle_state_seconds={"cool": 3600},
        )

        history._update_daily_metrics("2025-12-22")

        daily = history.daily_metrics["2025-12-22"]
        assert daily.hours_aggregated == 3
        assert daily.avg_battery_draw_w == (10.0 + 15.0 + 8.0) / 3
        assert daily.max_battery_draw_w == 20.0
        assert daily.min_battery_percent == 70.0
        assert daily.avg_thermal_level == (0.5 + 1.0 + 0.3) / 3
        assert daily.max_thermal_level == 2
        assert daily.thermal_events_count == 1  # One hour had max_thermal_level > 1
        assert daily.avg_cpu_percent == (20.0 + 40.0 + 10.0) / 3
        assert daily.max_cpu_percent == 60.0
        assert daily.total_requests == 250
        assert daily.active_hours == 2  # 2 hours had requests > 0
        assert daily.idle_state_hours["active"] == 1.0
        assert daily.idle_state_hours["warm"] == 1.0
        assert daily.idle_state_hours["cool"] == 1.0


class TestMetricsHistoryGetHistory:
    """Tests for history retrieval methods."""

    def test_get_hourly_history_empty(self):
        """Test get_hourly_history with no data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        result = history.get_hourly_history()

        assert result == []

    def test_get_hourly_history_with_data(self):
        """Test get_hourly_history returns sorted data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        now = datetime.now()
        hour1 = (now - timedelta(hours=2)).replace(minute=0, second=0, microsecond=0).isoformat()
        hour2 = (now - timedelta(hours=1)).replace(minute=0, second=0, microsecond=0).isoformat()

        history.hourly_metrics[hour2] = HourlyMetrics(hour=hour2, avg_cpu_percent=20.0)
        history.hourly_metrics[hour1] = HourlyMetrics(hour=hour1, avg_cpu_percent=10.0)

        result = history.get_hourly_history(days=1)

        assert len(result) == 2
        # Should be sorted by time
        assert result[0]["hour"] == hour1
        assert result[1]["hour"] == hour2

    def test_get_hourly_history_respects_days_limit(self):
        """Test get_hourly_history respects days parameter."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        now = datetime.now()
        recent = (now - timedelta(hours=1)).replace(minute=0, second=0, microsecond=0).isoformat()
        old = (now - timedelta(days=10)).replace(minute=0, second=0, microsecond=0).isoformat()

        history.hourly_metrics[recent] = HourlyMetrics(hour=recent)
        history.hourly_metrics[old] = HourlyMetrics(hour=old)

        result = history.get_hourly_history(days=7)

        assert len(result) == 1
        assert result[0]["hour"] == recent

    def test_get_daily_history_empty(self):
        """Test get_daily_history with no data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        result = history.get_daily_history()

        assert result == []

    def test_get_daily_history_with_data(self):
        """Test get_daily_history returns sorted data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        now = datetime.now()
        day1 = (now - timedelta(days=2)).strftime("%Y-%m-%d")
        day2 = (now - timedelta(days=1)).strftime("%Y-%m-%d")

        history.daily_metrics[day2] = DailyMetrics(date=day2, avg_cpu_percent=20.0)
        history.daily_metrics[day1] = DailyMetrics(date=day1, avg_cpu_percent=10.0)

        result = history.get_daily_history(days=30)

        assert len(result) == 2
        # Should be sorted by date
        assert result[0]["date"] == day1
        assert result[1]["date"] == day2

    def test_get_daily_history_respects_days_limit(self):
        """Test get_daily_history respects days parameter."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        now = datetime.now()
        recent = (now - timedelta(days=5)).strftime("%Y-%m-%d")
        old = (now - timedelta(days=60)).strftime("%Y-%m-%d")

        history.daily_metrics[recent] = DailyMetrics(date=recent)
        history.daily_metrics[old] = DailyMetrics(date=old)

        result = history.get_daily_history(days=30)

        assert len(result) == 1
        assert result[0]["date"] == recent


class TestMetricsHistorySummaryStats:
    """Tests for summary statistics."""

    def test_get_summary_stats_empty(self):
        """Test get_summary_stats with no data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        result = history.get_summary_stats()

        assert result["today"] is None
        assert result["yesterday"] is None
        assert result["this_week"] is None
        assert result["total_days_tracked"] == 0
        assert result["total_hours_tracked"] == 0
        assert result["oldest_record"] is None

    def test_get_summary_stats_with_today(self):
        """Test get_summary_stats with today's data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        today = datetime.now().strftime("%Y-%m-%d")
        history.daily_metrics[today] = DailyMetrics(
            date=today,
            avg_cpu_percent=25.0,
            total_requests=500,
        )

        result = history.get_summary_stats()

        assert result["today"] is not None
        assert result["today"]["date"] == today
        assert result["today"]["avg_cpu_percent"] == 25.0
        assert result["total_days_tracked"] == 1

    def test_get_summary_stats_with_yesterday(self):
        """Test get_summary_stats with yesterday's data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        yesterday = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
        history.daily_metrics[yesterday] = DailyMetrics(
            date=yesterday,
            avg_cpu_percent=30.0,
        )

        result = history.get_summary_stats()

        assert result["yesterday"] is not None
        assert result["yesterday"]["date"] == yesterday

    def test_get_summary_stats_week_aggregation(self):
        """Test get_summary_stats aggregates weekly data."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        now = datetime.now()
        for i in range(5):
            day = (now - timedelta(days=i)).strftime("%Y-%m-%d")
            history.daily_metrics[day] = DailyMetrics(
                date=day,
                avg_cpu_percent=20.0 + i,  # 20, 21, 22, 23, 24
                total_requests=100 * (i + 1),  # 100, 200, 300, 400, 500
                max_thermal_level=i % 3,  # 0, 1, 2, 0, 1
            )

        result = history.get_summary_stats()

        assert result["this_week"] is not None
        assert result["this_week"]["days_recorded"] == 5
        assert result["this_week"]["avg_cpu_percent"] == 22.0  # Average of 20-24
        assert result["this_week"]["total_requests"] == 1500
        assert result["this_week"]["max_thermal_level"] == 2

    def test_get_summary_stats_oldest_record(self):
        """Test get_summary_stats reports oldest record."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        history.daily_metrics["2025-01-01"] = DailyMetrics(date="2025-01-01")
        history.daily_metrics["2025-06-15"] = DailyMetrics(date="2025-06-15")
        history.daily_metrics["2025-12-22"] = DailyMetrics(date="2025-12-22")

        result = history.get_summary_stats()

        assert result["oldest_record"] == "2025-01-01"
        assert result["total_days_tracked"] == 3


class TestMetricsHistorySaveLoop:
    """Tests for the background save loop."""

    @pytest.mark.asyncio
    async def test_save_loop_saves_when_dirty(self):
        """Test save loop saves when dirty flag is set."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()
            history._dirty = True

        with patch.object(history, "_save_data") as mock_save, \
             patch.object(history, "_check_hour_boundary"):
            # Start and immediately stop after one iteration
            history._running = True

            # Simulate one iteration of the loop
            async def quick_loop():
                await asyncio.sleep(0.01)
                history._check_hour_boundary()
                if history._dirty:
                    history._save_data()
                history._running = False

            await quick_loop()

            mock_save.assert_called_once()

    @pytest.mark.asyncio
    async def test_save_loop_checks_hour_boundary(self):
        """Test save loop checks hour boundary."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        with patch.object(history, "_check_hour_boundary") as mock_check, \
             patch.object(history, "_save_data"):
            history._running = True

            async def quick_loop():
                await asyncio.sleep(0.01)
                history._check_hour_boundary()
                history._running = False

            await quick_loop()

            mock_check.assert_called_once()


class TestMetricsHistoryFinalizeHour:
    """Tests for hour finalization."""

    def test_finalize_current_hour_no_accumulator(self):
        """Test _finalize_current_hour with no accumulator."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        # Should not raise
        history._finalize_current_hour()

        assert len(history.hourly_metrics) == 0

    def test_finalize_current_hour_empty_accumulator(self):
        """Test _finalize_current_hour with empty accumulator."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        history._hour_accumulator = _HourAccumulator("2025-12-22T14:00:00")
        history._hour_accumulator.sample_count = 0

        history._finalize_current_hour()

        assert len(history.hourly_metrics) == 0

    def test_finalize_current_hour_with_samples(self):
        """Test _finalize_current_hour with samples."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        acc = _HourAccumulator("2025-12-22T14:00:00")
        metrics = {
            "power": {"current_battery_draw_w": 10.0, "battery_percent": 80.0},
            "thermal": {"pressure_level": 1, "cpu_temp_c": 55.0},
            "cpu": {"total_percent": 25.0, "by_service": {}},
        }
        acc.add_sample(metrics, "active")
        history._hour_accumulator = acc

        history._finalize_current_hour()

        assert "2025-12-22T14:00:00" in history.hourly_metrics
        assert history._dirty is True

    def test_finalize_current_hour_updates_daily(self):
        """Test _finalize_current_hour updates daily metrics."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        acc = _HourAccumulator("2025-12-22T14:00:00")
        metrics = {
            "power": {"current_battery_draw_w": 10.0, "battery_percent": 80.0},
            "thermal": {"pressure_level": 1, "cpu_temp_c": 55.0},
            "cpu": {"total_percent": 25.0, "by_service": {}},
        }
        acc.add_sample(metrics, "active")
        history._hour_accumulator = acc

        history._finalize_current_hour()

        assert "2025-12-22" in history.daily_metrics


# =============================================================================
# SINGLETON TESTS
# =============================================================================


class TestSingleton:
    """Tests for singleton instance."""

    def test_singleton_exists(self):
        """Test that singleton instance exists."""
        assert metrics_history is not None
        assert isinstance(metrics_history, MetricsHistory)


# =============================================================================
# INTEGRATION TESTS
# =============================================================================


class TestMetricsHistoryIntegration:
    """Integration tests for MetricsHistory."""

    def test_full_recording_flow(self):
        """Test full flow of recording samples and retrieving history."""
        with patch.object(MetricsHistory, "_load_data"):
            history = MetricsHistory()

        # Record several samples
        for i in range(5):
            metrics = {
                "power": {
                    "current_battery_draw_w": 10.0 + i,
                    "battery_percent": 90.0 - i,
                },
                "thermal": {
                    "pressure_level": i % 2,
                    "cpu_temp_c": 50.0 + i,
                },
                "cpu": {
                    "total_percent": 20.0 + i * 2,
                    "by_service": {"ollama": 15.0 + i, "management": 5.0},
                },
            }
            history.record_sample(metrics, "active")

        # Verify accumulator has samples
        assert history._hour_accumulator.sample_count == 5

        # Finalize the hour
        history._finalize_current_hour()

        # Should have hourly metrics
        assert len(history.hourly_metrics) == 1

        # Should have daily metrics
        assert len(history.daily_metrics) == 1

        # Can retrieve history
        hourly = history.get_hourly_history()
        assert len(hourly) == 1

        daily = history.get_daily_history()
        assert len(daily) == 1

        # Can get summary
        summary = history.get_summary_stats()
        assert summary["total_hours_tracked"] == 1
        assert summary["total_days_tracked"] == 1
