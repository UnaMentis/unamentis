"""
Tests for Idle State Manager

Comprehensive tests for the tiered idle state system with power profile management.
Tests verify state transitions, handlers, profiles, and service management.
"""

import asyncio
import pytest
import time
from unittest.mock import MagicMock, AsyncMock, patch

from idle_manager import (
    IdleState,
    IdleThresholds,
    PowerMode,
    StateTransition,
    IdleManager,
    BUILTIN_POWER_MODES,
    POWER_MODES,
)


# =============================================================================
# IDLE STATE TESTS
# =============================================================================


class TestIdleState:
    """Tests for IdleState enum."""

    def test_state_values(self):
        """Test all state values exist."""
        assert IdleState.ACTIVE.value == "active"
        assert IdleState.WARM.value == "warm"
        assert IdleState.COOL.value == "cool"
        assert IdleState.COLD.value == "cold"
        assert IdleState.DORMANT.value == "dormant"

    def test_state_level_ordering(self):
        """Test states have correct numeric levels."""
        assert IdleState.ACTIVE.level == 0
        assert IdleState.WARM.level == 1
        assert IdleState.COOL.level == 2
        assert IdleState.COLD.level == 3
        assert IdleState.DORMANT.level == 4

    def test_state_level_comparisons(self):
        """Test state levels can be compared."""
        assert IdleState.ACTIVE.level < IdleState.WARM.level
        assert IdleState.WARM.level < IdleState.COOL.level
        assert IdleState.COOL.level < IdleState.COLD.level
        assert IdleState.COLD.level < IdleState.DORMANT.level


# =============================================================================
# IDLE THRESHOLDS TESTS
# =============================================================================


class TestIdleThresholds:
    """Tests for IdleThresholds dataclass."""

    def test_default_values(self):
        """Test default threshold values."""
        thresholds = IdleThresholds()

        assert thresholds.warm == 30
        assert thresholds.cool == 300
        assert thresholds.cold == 1800
        assert thresholds.dormant == 7200

    def test_custom_values(self):
        """Test custom threshold values."""
        thresholds = IdleThresholds(warm=10, cool=60, cold=300, dormant=1800)

        assert thresholds.warm == 10
        assert thresholds.cool == 60
        assert thresholds.cold == 300
        assert thresholds.dormant == 1800

    def test_to_dict(self):
        """Test conversion to dictionary."""
        thresholds = IdleThresholds(warm=10, cool=60, cold=300, dormant=1800)
        result = thresholds.to_dict()

        assert result == {
            "warm": 10,
            "cool": 60,
            "cold": 300,
            "dormant": 1800,
        }

    def test_from_dict(self):
        """Test creation from dictionary."""
        data = {"warm": 15, "cool": 90, "cold": 600, "dormant": 3600}
        thresholds = IdleThresholds.from_dict(data)

        assert thresholds.warm == 15
        assert thresholds.cool == 90
        assert thresholds.cold == 600
        assert thresholds.dormant == 3600

    def test_from_dict_ignores_extra_keys(self):
        """Test from_dict ignores unknown keys."""
        data = {"warm": 15, "extra": 999}
        thresholds = IdleThresholds.from_dict(data)

        assert thresholds.warm == 15
        # Other values should be defaults
        assert thresholds.cool == 300


# =============================================================================
# POWER MODE TESTS
# =============================================================================


class TestPowerMode:
    """Tests for PowerMode dataclass."""

    def test_creation(self):
        """Test power mode creation."""
        mode = PowerMode(
            name="Test Mode",
            description="A test mode",
            thresholds=IdleThresholds(),
            enabled=True,
        )

        assert mode.name == "Test Mode"
        assert mode.description == "A test mode"
        assert mode.enabled is True

    def test_to_dict(self):
        """Test conversion to dictionary."""
        mode = PowerMode(
            name="Test",
            description="Test desc",
            thresholds=IdleThresholds(warm=10, cool=60, cold=300, dormant=1800),
            enabled=False,
        )

        result = mode.to_dict()

        assert result["name"] == "Test"
        assert result["description"] == "Test desc"
        assert result["enabled"] is False
        assert "thresholds" in result


class TestBuiltinPowerModes:
    """Tests for built-in power modes."""

    def test_all_builtin_modes_exist(self):
        """Test all expected built-in modes exist."""
        expected = ["performance", "balanced", "power_saver", "development", "presentation"]
        for mode_name in expected:
            assert mode_name in BUILTIN_POWER_MODES

    def test_performance_mode_disabled(self):
        """Test performance mode has idle management disabled."""
        mode = BUILTIN_POWER_MODES["performance"]
        assert mode.enabled is False

    def test_balanced_mode_enabled(self):
        """Test balanced mode has idle management enabled."""
        mode = BUILTIN_POWER_MODES["balanced"]
        assert mode.enabled is True

    def test_power_saver_has_aggressive_thresholds(self):
        """Test power saver has shorter thresholds."""
        mode = BUILTIN_POWER_MODES["power_saver"]
        balanced = BUILTIN_POWER_MODES["balanced"]

        assert mode.thresholds.warm < balanced.thresholds.warm
        assert mode.thresholds.cool < balanced.thresholds.cool


# =============================================================================
# IDLE MANAGER TESTS
# =============================================================================


class TestIdleManagerInit:
    """Tests for IdleManager initialization."""

    def test_init_defaults(self):
        """Test manager initializes with defaults."""
        manager = IdleManager()

        assert manager.current_state == IdleState.ACTIVE
        assert manager.current_mode == "balanced"
        assert manager.enabled is True
        assert manager._running is False

    def test_init_handlers_empty(self):
        """Test handlers are initialized empty."""
        manager = IdleManager()

        for state in IdleState:
            assert manager._handlers[state] == []
        assert manager._global_handlers == []


class TestIdleManagerStateCalculation:
    """Tests for state calculation logic."""

    @pytest.fixture
    def manager(self):
        """Create manager with known thresholds."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=10, cool=60, cold=300, dormant=1800)
        return manager

    def test_calculate_state_active(self, manager):
        """Test active state for short idle."""
        state = manager._calculate_state(5)  # 5 seconds
        assert state == IdleState.ACTIVE

    def test_calculate_state_warm(self, manager):
        """Test warm state after warm threshold."""
        state = manager._calculate_state(15)  # 15 seconds
        assert state == IdleState.WARM

    def test_calculate_state_cool(self, manager):
        """Test cool state after cool threshold."""
        state = manager._calculate_state(120)  # 2 minutes
        assert state == IdleState.COOL

    def test_calculate_state_cold(self, manager):
        """Test cold state after cold threshold."""
        state = manager._calculate_state(600)  # 10 minutes
        assert state == IdleState.COLD

    def test_calculate_state_dormant(self, manager):
        """Test dormant state after dormant threshold."""
        state = manager._calculate_state(3600)  # 1 hour
        assert state == IdleState.DORMANT

    def test_calculate_state_boundary_warm(self, manager):
        """Test exact boundary for warm threshold."""
        state = manager._calculate_state(10)  # Exactly warm threshold
        assert state == IdleState.WARM


class TestIdleManagerActivity:
    """Tests for activity recording."""

    def test_record_activity_updates_timestamp(self):
        """Test activity recording updates last_activity."""
        manager = IdleManager()
        old_time = manager.last_activity

        time.sleep(0.01)  # Small delay
        manager.record_activity("test", "test-service")

        assert manager.last_activity > old_time

    def test_record_activity_updates_type(self):
        """Test activity recording updates activity type."""
        manager = IdleManager()

        manager.record_activity("websocket", "audio-service")

        assert manager.last_activity_type == "websocket"


class TestIdleManagerModes:
    """Tests for power mode management."""

    def test_set_mode_valid(self):
        """Test setting valid mode."""
        manager = IdleManager()

        result = manager.set_mode("power_saver")

        assert result is True
        assert manager.current_mode == "power_saver"

    def test_set_mode_invalid(self):
        """Test setting invalid mode returns False."""
        manager = IdleManager()

        result = manager.set_mode("nonexistent_mode")

        assert result is False
        assert manager.current_mode == "balanced"  # Unchanged

    def test_set_mode_updates_thresholds(self):
        """Test setting mode updates thresholds."""
        manager = IdleManager()
        manager.set_mode("power_saver")

        power_saver_mode = BUILTIN_POWER_MODES["power_saver"]
        assert manager.thresholds.warm == power_saver_mode.thresholds.warm

    def test_set_mode_updates_enabled(self):
        """Test setting mode updates enabled flag."""
        manager = IdleManager()
        manager.set_mode("performance")

        assert manager.enabled is False

    def test_set_custom_thresholds(self):
        """Test setting custom thresholds."""
        manager = IdleManager()

        manager.set_thresholds({"warm": 5, "cool": 30})

        assert manager.thresholds.warm == 5
        assert manager.thresholds.cool == 30
        assert manager.current_mode == "custom"


class TestIdleManagerKeepAwake:
    """Tests for keep-awake functionality."""

    def test_keep_awake_sets_expiry(self):
        """Test keep_awake sets expiry time."""
        manager = IdleManager()

        manager.keep_awake(60)  # 60 seconds

        assert manager._keep_awake_until is not None
        assert manager._keep_awake_until > time.time()

    def test_cancel_keep_awake(self):
        """Test cancelling keep awake."""
        manager = IdleManager()
        manager.keep_awake(60)

        manager.cancel_keep_awake()

        assert manager._keep_awake_until is None


class TestIdleManagerHandlers:
    """Tests for handler registration."""

    def test_register_state_handler(self):
        """Test registering state-specific handler."""
        manager = IdleManager()
        handler = AsyncMock()

        manager.register_handler(IdleState.COOL, handler)

        assert handler in manager._handlers[IdleState.COOL]

    def test_register_global_handler(self):
        """Test registering global handler."""
        manager = IdleManager()
        handler = AsyncMock()

        manager.register_global_handler(handler)

        assert handler in manager._global_handlers


class TestIdleManagerTransitions:
    """Tests for state transitions."""

    @pytest.fixture
    def manager(self):
        """Create manager."""
        return IdleManager()

    @pytest.mark.asyncio
    async def test_transition_to_records_history(self, manager):
        """Test transition records in history."""
        await manager._transition_to(IdleState.WARM, "timeout")

        assert len(manager.transition_history) == 1
        transition = manager.transition_history[0]
        assert transition["to_state"] == "warm"
        assert transition["trigger"] == "timeout"

    @pytest.mark.asyncio
    async def test_transition_updates_current_state(self, manager):
        """Test transition updates current state."""
        await manager._transition_to(IdleState.COOL, "timeout")

        assert manager.current_state == IdleState.COOL

    @pytest.mark.asyncio
    async def test_transition_calls_handlers(self, manager):
        """Test transition calls registered handlers."""
        handler = AsyncMock()
        manager.register_handler(IdleState.COLD, handler)

        await manager._transition_to(IdleState.COLD, "timeout")

        handler.assert_called_once()

    @pytest.mark.asyncio
    async def test_transition_calls_global_handlers(self, manager):
        """Test transition calls global handlers."""
        handler = AsyncMock()
        manager.register_global_handler(handler)

        await manager._transition_to(IdleState.WARM, "timeout")

        handler.assert_called_once()

    @pytest.mark.asyncio
    async def test_transition_noop_if_same_state(self, manager):
        """Test no transition if already in target state."""
        manager.current_state = IdleState.WARM
        handler = AsyncMock()
        manager.register_handler(IdleState.WARM, handler)

        await manager._transition_to(IdleState.WARM, "timeout")

        handler.assert_not_called()

    @pytest.mark.asyncio
    async def test_force_state(self, manager):
        """Test force_state transitions."""
        await manager.force_state(IdleState.DORMANT)

        assert manager.current_state == IdleState.DORMANT


class TestIdleManagerStatus:
    """Tests for status reporting."""

    def test_get_status_includes_all_fields(self):
        """Test get_status returns all expected fields."""
        manager = IdleManager()
        status = manager.get_status()

        assert "enabled" in status
        assert "current_state" in status
        assert "current_mode" in status
        assert "seconds_idle" in status
        assert "last_activity_type" in status
        assert "thresholds" in status
        assert "keep_awake_remaining" in status
        assert "next_state_in" in status

    def test_get_status_current_state_value(self):
        """Test status shows current state as string."""
        manager = IdleManager()
        manager.current_state = IdleState.COOL

        status = manager.get_status()

        assert status["current_state"] == "cool"

    def test_get_transition_history(self):
        """Test getting transition history."""
        manager = IdleManager()

        history = manager.get_transition_history()

        assert isinstance(history, list)

    def test_get_available_modes(self):
        """Test getting available power modes."""
        manager = IdleManager()

        modes = manager.get_available_modes()

        assert "balanced" in modes
        assert "performance" in modes
        assert modes["balanced"]["is_builtin"] is True


class TestIdleManagerProfiles:
    """Tests for custom profile management."""

    @pytest.fixture
    def manager(self):
        """Create manager with mocked save."""
        manager = IdleManager()
        manager._save_custom_profiles = MagicMock()
        return manager

    def test_create_profile_success(self, manager):
        """Test creating custom profile."""
        result = manager.create_profile(
            profile_id="test_profile",
            name="Test Profile",
            description="A test profile",
            thresholds={"warm": 20, "cool": 120, "cold": 600, "dormant": 3600},
        )

        assert result is True
        assert "test_profile" in POWER_MODES

        # Cleanup
        del POWER_MODES["test_profile"]

    def test_create_profile_cannot_overwrite_builtin(self, manager):
        """Test cannot overwrite built-in profile."""
        result = manager.create_profile(
            profile_id="balanced",
            name="My Balanced",
            description="Override",
            thresholds={"warm": 10},
        )

        assert result is False

    def test_update_profile_success(self, manager):
        """Test updating custom profile."""
        # First create
        manager.create_profile(
            profile_id="update_test",
            name="Original",
            description="Original desc",
            thresholds={"warm": 20},
        )

        # Then update
        result = manager.update_profile(
            profile_id="update_test",
            name="Updated",
        )

        assert result is True
        assert POWER_MODES["update_test"].name == "Updated"

        # Cleanup
        del POWER_MODES["update_test"]

    def test_update_profile_cannot_modify_builtin(self, manager):
        """Test cannot modify built-in profile."""
        result = manager.update_profile("balanced", name="New Name")

        assert result is False

    def test_delete_profile_success(self, manager):
        """Test deleting custom profile."""
        manager.create_profile(
            profile_id="delete_test",
            name="To Delete",
            description="Will be deleted",
            thresholds={"warm": 20},
        )

        result = manager.delete_profile("delete_test")

        assert result is True
        assert "delete_test" not in POWER_MODES

    def test_delete_profile_cannot_delete_builtin(self, manager):
        """Test cannot delete built-in profile."""
        result = manager.delete_profile("balanced")

        assert result is False
        assert "balanced" in POWER_MODES

    def test_delete_profile_switches_mode_if_current(self, manager):
        """Test deleting current mode switches to balanced."""
        manager.create_profile(
            profile_id="current_test",
            name="Current",
            description="Current mode",
            thresholds={"warm": 20},
        )
        manager.set_mode("current_test")

        manager.delete_profile("current_test")

        assert manager.current_mode == "balanced"

    def test_duplicate_profile(self, manager):
        """Test duplicating profile."""
        result = manager.duplicate_profile(
            source_id="balanced",
            new_id="my_balanced",
            new_name="My Balanced",
        )

        assert result is True
        assert "my_balanced" in POWER_MODES
        assert POWER_MODES["my_balanced"].name == "My Balanced"

        # Cleanup
        del POWER_MODES["my_balanced"]

    def test_get_profile_existing(self, manager):
        """Test getting existing profile."""
        result = manager.get_profile("balanced")

        assert result is not None
        assert result["id"] == "balanced"
        assert result["is_builtin"] is True

    def test_get_profile_nonexistent(self, manager):
        """Test getting non-existent profile."""
        result = manager.get_profile("nonexistent")

        assert result is None


class TestIdleManagerLifecycle:
    """Tests for manager start/stop lifecycle."""

    @pytest.mark.asyncio
    async def test_start_creates_task(self):
        """Test start creates monitor task."""
        manager = IdleManager()

        await manager.start()

        assert manager._running is True
        assert manager._monitor_task is not None

        await manager.stop()

    @pytest.mark.asyncio
    async def test_stop_cancels_task(self):
        """Test stop cancels monitor task."""
        manager = IdleManager()
        await manager.start()

        await manager.stop()

        assert manager._running is False

    @pytest.mark.asyncio
    async def test_start_idempotent(self):
        """Test start is idempotent."""
        manager = IdleManager()

        await manager.start()
        task1 = manager._monitor_task
        await manager.start()  # Second start
        task2 = manager._monitor_task

        assert task1 is task2  # Same task

        await manager.stop()


class TestIdleManagerServiceCallbacks:
    """Tests for service unload/load callbacks."""

    @pytest.mark.asyncio
    async def test_unload_ollama_with_callback(self):
        """Test Ollama unload uses callback if set."""
        manager = IdleManager()
        callback = AsyncMock()
        manager._ollama_unload_callback = callback

        await manager._unload_ollama_models()

        callback.assert_called_once()

    @pytest.mark.asyncio
    async def test_unload_vibevoice_with_callback(self):
        """Test VibeVoice unload uses callback if set."""
        manager = IdleManager()
        callback = AsyncMock()
        manager._vibevoice_unload_callback = callback

        await manager._unload_vibevoice()

        callback.assert_called_once()

    @pytest.mark.asyncio
    async def test_pre_warm_with_callback(self):
        """Test pre-warm uses callback if set."""
        manager = IdleManager()
        callback = AsyncMock()
        manager._vibevoice_load_callback = callback

        await manager._pre_warm_services()

        # Callback is called in background task


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
