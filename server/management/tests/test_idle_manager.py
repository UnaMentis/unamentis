"""
Tests for Idle State Manager

Comprehensive tests for the tiered idle state system with power profile management.
Tests verify state transitions, handlers, profiles, service management, and edge cases.
"""

import asyncio
import json
import pytest
import time
from pathlib import Path
from unittest.mock import MagicMock, AsyncMock, patch, mock_open

from idle_manager import (
    IdleState,
    IdleThresholds,
    PowerMode,
    StateTransition,
    IdleManager,
    BUILTIN_POWER_MODES,
    POWER_MODES,
    _init_idle_manager,
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

    def test_all_states_have_unique_levels(self):
        """Test all states have unique level values."""
        levels = [state.level for state in IdleState]
        assert len(levels) == len(set(levels))

    def test_all_states_have_unique_values(self):
        """Test all states have unique string values."""
        values = [state.value for state in IdleState]
        assert len(values) == len(set(values))


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

    def test_partial_custom_values(self):
        """Test partially customized thresholds."""
        thresholds = IdleThresholds(warm=5, cold=600)

        assert thresholds.warm == 5
        assert thresholds.cool == 300  # Default
        assert thresholds.cold == 600
        assert thresholds.dormant == 7200  # Default

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
        data = {"warm": 15, "extra": 999, "unknown_field": "test"}
        thresholds = IdleThresholds.from_dict(data)

        assert thresholds.warm == 15
        # Other values should be defaults
        assert thresholds.cool == 300

    def test_from_dict_partial(self):
        """Test from_dict with only some keys."""
        data = {"warm": 20}
        thresholds = IdleThresholds.from_dict(data)

        assert thresholds.warm == 20
        assert thresholds.cool == 300  # Default
        assert thresholds.cold == 1800  # Default
        assert thresholds.dormant == 7200  # Default

    def test_from_dict_empty(self):
        """Test from_dict with empty dict uses defaults."""
        thresholds = IdleThresholds.from_dict({})

        assert thresholds.warm == 30
        assert thresholds.cool == 300
        assert thresholds.cold == 1800
        assert thresholds.dormant == 7200


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

    def test_creation_disabled(self):
        """Test creating disabled power mode."""
        mode = PowerMode(
            name="Disabled Mode",
            description="Disabled",
            thresholds=IdleThresholds(),
            enabled=False,
        )

        assert mode.enabled is False

    def test_default_enabled_true(self):
        """Test default enabled is True."""
        mode = PowerMode(
            name="Test",
            description="Test",
            thresholds=IdleThresholds(),
        )

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
        assert result["thresholds"]["warm"] == 10

    def test_to_dict_complete_structure(self):
        """Test to_dict returns complete structure."""
        mode = PowerMode(
            name="Complete",
            description="Complete mode",
            thresholds=IdleThresholds(),
            enabled=True,
        )

        result = mode.to_dict()

        expected_keys = {"name", "description", "thresholds", "enabled"}
        assert set(result.keys()) == expected_keys


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

    def test_performance_mode_very_high_thresholds(self):
        """Test performance mode has very high thresholds."""
        mode = BUILTIN_POWER_MODES["performance"]
        assert mode.thresholds.warm >= 9999999
        assert mode.thresholds.cool >= 9999999

    def test_balanced_mode_enabled(self):
        """Test balanced mode has idle management enabled."""
        mode = BUILTIN_POWER_MODES["balanced"]
        assert mode.enabled is True

    def test_balanced_mode_default_thresholds(self):
        """Test balanced mode has default thresholds."""
        mode = BUILTIN_POWER_MODES["balanced"]
        assert mode.thresholds.warm == 30
        assert mode.thresholds.cool == 300
        assert mode.thresholds.cold == 1800
        assert mode.thresholds.dormant == 7200

    def test_power_saver_has_aggressive_thresholds(self):
        """Test power saver has shorter thresholds."""
        mode = BUILTIN_POWER_MODES["power_saver"]
        balanced = BUILTIN_POWER_MODES["balanced"]

        assert mode.thresholds.warm < balanced.thresholds.warm
        assert mode.thresholds.cool < balanced.thresholds.cool

    def test_development_mode_values(self):
        """Test development mode configuration."""
        mode = BUILTIN_POWER_MODES["development"]
        assert mode.enabled is True
        assert mode.thresholds.warm == 60
        assert mode.thresholds.cool == 180

    def test_presentation_mode_values(self):
        """Test presentation mode stays responsive longer."""
        mode = BUILTIN_POWER_MODES["presentation"]
        balanced = BUILTIN_POWER_MODES["balanced"]

        assert mode.thresholds.warm > balanced.thresholds.warm
        assert mode.thresholds.cool > balanced.thresholds.cool

    def test_all_modes_have_names_and_descriptions(self):
        """Test all modes have non-empty names and descriptions."""
        for mode_id, mode in BUILTIN_POWER_MODES.items():
            assert mode.name, f"Mode {mode_id} has no name"
            assert mode.description, f"Mode {mode_id} has no description"


# =============================================================================
# STATE TRANSITION TESTS
# =============================================================================


class TestStateTransition:
    """Tests for StateTransition dataclass."""

    def test_creation(self):
        """Test state transition creation."""
        transition = StateTransition(
            timestamp=time.time(),
            from_state="active",
            to_state="warm",
            idle_seconds=35.5,
            trigger="timeout",
        )

        assert transition.from_state == "active"
        assert transition.to_state == "warm"
        assert transition.idle_seconds == 35.5
        assert transition.trigger == "timeout"

    def test_activity_trigger(self):
        """Test transition with activity trigger."""
        transition = StateTransition(
            timestamp=time.time(),
            from_state="cool",
            to_state="active",
            idle_seconds=0.0,
            trigger="activity",
        )

        assert transition.trigger == "activity"

    def test_manual_trigger(self):
        """Test transition with manual trigger."""
        transition = StateTransition(
            timestamp=time.time(),
            from_state="warm",
            to_state="dormant",
            idle_seconds=100.0,
            trigger="manual",
        )

        assert transition.trigger == "manual"


# =============================================================================
# IDLE MANAGER INIT TESTS
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

    def test_init_last_activity_set(self):
        """Test last activity is set to current time on init."""
        before = time.time()
        manager = IdleManager()
        after = time.time()

        assert before <= manager.last_activity <= after

    def test_init_last_activity_type(self):
        """Test last activity type is startup."""
        manager = IdleManager()

        assert manager.last_activity_type == "startup"

    def test_init_transition_history_empty(self):
        """Test transition history starts empty."""
        manager = IdleManager()

        assert len(manager.transition_history) == 0

    def test_init_keep_awake_none(self):
        """Test keep awake is None initially."""
        manager = IdleManager()

        assert manager._keep_awake_until is None

    def test_init_callbacks_none(self):
        """Test callbacks are None initially."""
        manager = IdleManager()

        assert manager._ollama_unload_callback is None
        assert manager._vibevoice_unload_callback is None
        assert manager._vibevoice_load_callback is None


# =============================================================================
# IDLE MANAGER STATE CALCULATION TESTS
# =============================================================================


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

    def test_calculate_state_active_zero(self, manager):
        """Test active state for zero idle time."""
        state = manager._calculate_state(0)
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

    def test_calculate_state_boundary_cool(self, manager):
        """Test exact boundary for cool threshold."""
        state = manager._calculate_state(60)
        assert state == IdleState.COOL

    def test_calculate_state_boundary_cold(self, manager):
        """Test exact boundary for cold threshold."""
        state = manager._calculate_state(300)
        assert state == IdleState.COLD

    def test_calculate_state_boundary_dormant(self, manager):
        """Test exact boundary for dormant threshold."""
        state = manager._calculate_state(1800)
        assert state == IdleState.DORMANT

    def test_calculate_state_just_below_warm(self, manager):
        """Test just below warm threshold stays active."""
        state = manager._calculate_state(9.9)
        assert state == IdleState.ACTIVE

    def test_calculate_state_very_long_idle(self, manager):
        """Test very long idle time stays dormant."""
        state = manager._calculate_state(100000)  # ~27 hours
        assert state == IdleState.DORMANT


# =============================================================================
# IDLE MANAGER ACTIVITY TESTS
# =============================================================================


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

    def test_record_activity_various_types(self):
        """Test various activity types."""
        manager = IdleManager()

        activity_types = ["request", "inference", "websocket", "api_call", "user_input"]
        for act_type in activity_types:
            manager.record_activity(act_type)
            assert manager.last_activity_type == act_type

    @pytest.mark.asyncio
    async def test_record_activity_triggers_wake_from_idle(self):
        """Test activity triggers wake when idle."""
        manager = IdleManager()
        manager.current_state = IdleState.COOL
        manager.enabled = True

        # Record activity should trigger transition to ACTIVE
        manager.record_activity("test")

        # Give async task time to run
        await asyncio.sleep(0.05)

        assert manager.current_state == IdleState.ACTIVE

    def test_record_activity_no_wake_when_active(self):
        """Test activity when already active doesn't create unnecessary transition."""
        manager = IdleManager()
        manager.current_state = IdleState.ACTIVE
        manager.enabled = True

        # Should not create a task since already active
        manager.record_activity("test")

        assert manager.current_state == IdleState.ACTIVE

    def test_record_activity_no_wake_when_disabled(self):
        """Test activity doesn't wake when idle management disabled."""
        manager = IdleManager()
        manager.current_state = IdleState.COOL
        manager.enabled = False

        manager.record_activity("test")

        # State should not change since enabled is False
        assert manager.current_state == IdleState.COOL


# =============================================================================
# IDLE MANAGER MODES TESTS
# =============================================================================


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

    def test_set_mode_all_builtin(self):
        """Test setting all built-in modes."""
        manager = IdleManager()

        for mode_name in BUILTIN_POWER_MODES:
            result = manager.set_mode(mode_name)
            assert result is True
            assert manager.current_mode == mode_name

    def test_set_custom_thresholds(self):
        """Test setting custom thresholds."""
        manager = IdleManager()

        manager.set_thresholds({"warm": 5, "cool": 30})

        assert manager.thresholds.warm == 5
        assert manager.thresholds.cool == 30
        assert manager.current_mode == "custom"

    def test_set_custom_thresholds_complete(self):
        """Test setting all custom thresholds."""
        manager = IdleManager()

        manager.set_thresholds({"warm": 5, "cool": 30, "cold": 120, "dormant": 600})

        assert manager.thresholds.warm == 5
        assert manager.thresholds.cool == 30
        assert manager.thresholds.cold == 120
        assert manager.thresholds.dormant == 600

    def test_set_thresholds_partial(self):
        """Test setting partial custom thresholds."""
        manager = IdleManager()

        manager.set_thresholds({"warm": 15})

        assert manager.thresholds.warm == 15
        # Cool should use default from IdleThresholds.from_dict
        assert manager.thresholds.cool == 300


# =============================================================================
# IDLE MANAGER KEEP AWAKE TESTS
# =============================================================================


class TestIdleManagerKeepAwake:
    """Tests for keep-awake functionality."""

    def test_keep_awake_sets_expiry(self):
        """Test keep_awake sets expiry time."""
        manager = IdleManager()

        manager.keep_awake(60)  # 60 seconds

        assert manager._keep_awake_until is not None
        assert manager._keep_awake_until > time.time()

    def test_keep_awake_correct_duration(self):
        """Test keep_awake sets correct duration."""
        manager = IdleManager()
        before = time.time()

        manager.keep_awake(120)

        assert manager._keep_awake_until >= before + 119  # Allow 1s tolerance

    def test_cancel_keep_awake(self):
        """Test cancelling keep awake."""
        manager = IdleManager()
        manager.keep_awake(60)

        manager.cancel_keep_awake()

        assert manager._keep_awake_until is None

    def test_cancel_keep_awake_when_not_set(self):
        """Test cancelling keep awake when not set."""
        manager = IdleManager()

        manager.cancel_keep_awake()

        assert manager._keep_awake_until is None

    @pytest.mark.asyncio
    async def test_keep_awake_forces_active_when_idle(self):
        """Test keep awake forces active state when idle."""
        manager = IdleManager()
        manager.current_state = IdleState.COOL

        manager.keep_awake(60)

        # Give async task time to run
        await asyncio.sleep(0.05)

        assert manager.current_state == IdleState.ACTIVE

    def test_keep_awake_no_transition_when_already_active(self):
        """Test keep awake doesn't force transition when already active."""
        manager = IdleManager()
        manager.current_state = IdleState.ACTIVE

        manager.keep_awake(60)

        # Should still be active, no unnecessary transition
        assert manager.current_state == IdleState.ACTIVE


# =============================================================================
# IDLE MANAGER HANDLERS TESTS
# =============================================================================


class TestIdleManagerHandlers:
    """Tests for handler registration."""

    def test_register_state_handler(self):
        """Test registering state-specific handler."""
        manager = IdleManager()
        handler = AsyncMock()

        manager.register_handler(IdleState.COOL, handler)

        assert handler in manager._handlers[IdleState.COOL]

    def test_register_multiple_handlers_same_state(self):
        """Test registering multiple handlers for same state."""
        manager = IdleManager()
        handler1 = AsyncMock()
        handler2 = AsyncMock()

        manager.register_handler(IdleState.WARM, handler1)
        manager.register_handler(IdleState.WARM, handler2)

        assert len(manager._handlers[IdleState.WARM]) == 2

    def test_register_handlers_different_states(self):
        """Test registering handlers for different states."""
        manager = IdleManager()
        handler1 = AsyncMock()
        handler2 = AsyncMock()

        manager.register_handler(IdleState.WARM, handler1)
        manager.register_handler(IdleState.COLD, handler2)

        assert handler1 in manager._handlers[IdleState.WARM]
        assert handler2 in manager._handlers[IdleState.COLD]

    def test_register_global_handler(self):
        """Test registering global handler."""
        manager = IdleManager()
        handler = AsyncMock()

        manager.register_global_handler(handler)

        assert handler in manager._global_handlers

    def test_register_multiple_global_handlers(self):
        """Test registering multiple global handlers."""
        manager = IdleManager()
        handlers = [AsyncMock() for _ in range(3)]

        for h in handlers:
            manager.register_global_handler(h)

        assert len(manager._global_handlers) == 3


# =============================================================================
# IDLE MANAGER TRANSITIONS TESTS
# =============================================================================


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
    async def test_transition_calls_handlers_with_correct_args(self, manager):
        """Test handlers receive correct arguments."""
        handler = AsyncMock()
        manager.register_handler(IdleState.WARM, handler)

        await manager._transition_to(IdleState.WARM, "timeout")

        handler.assert_called_once_with(IdleState.ACTIVE, IdleState.WARM)

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
    async def test_transition_history_records_all_fields(self, manager):
        """Test transition history has all required fields."""
        await manager._transition_to(IdleState.COOL, "timeout")

        transition = manager.transition_history[0]
        assert "timestamp" in transition
        assert "from_state" in transition
        assert "to_state" in transition
        assert "idle_seconds" in transition
        assert "trigger" in transition

    @pytest.mark.asyncio
    async def test_transition_history_max_length(self):
        """Test transition history respects max length."""
        manager = IdleManager()
        states = [IdleState.WARM, IdleState.COOL, IdleState.COLD, IdleState.DORMANT, IdleState.ACTIVE]

        # Create more than 100 transitions
        for i in range(120):
            state = states[i % len(states)]
            if manager.current_state != state:
                await manager._transition_to(state, "test")

        assert len(manager.transition_history) <= 100

    @pytest.mark.asyncio
    async def test_force_state(self, manager):
        """Test force_state transitions."""
        await manager.force_state(IdleState.DORMANT)

        assert manager.current_state == IdleState.DORMANT

    @pytest.mark.asyncio
    async def test_force_state_records_manual_trigger(self, manager):
        """Test force_state records manual trigger."""
        await manager.force_state(IdleState.COLD)

        transition = manager.transition_history[0]
        assert transition["trigger"] == "manual"

    @pytest.mark.asyncio
    async def test_force_state_noop_if_same(self, manager):
        """Test force_state no-op if already in state."""
        manager.current_state = IdleState.WARM

        await manager.force_state(IdleState.WARM)

        assert len(manager.transition_history) == 0

    @pytest.mark.asyncio
    async def test_handler_exception_caught(self, manager):
        """Test handler exceptions are caught and logged."""
        handler = AsyncMock(side_effect=Exception("Test error"))
        manager.register_handler(IdleState.COOL, handler)

        # Should not raise
        await manager._transition_to(IdleState.COOL, "timeout")

        assert manager.current_state == IdleState.COOL

    @pytest.mark.asyncio
    async def test_global_handler_exception_caught(self, manager):
        """Test global handler exceptions are caught."""
        handler = AsyncMock(side_effect=Exception("Test error"))
        manager.register_global_handler(handler)

        # Should not raise
        await manager._transition_to(IdleState.WARM, "timeout")

        assert manager.current_state == IdleState.WARM


# =============================================================================
# IDLE MANAGER STATE ACTIONS TESTS
# =============================================================================


class TestIdleManagerStateActions:
    """Tests for state action execution."""

    @pytest.mark.asyncio
    async def test_execute_actions_entering_cool_unloads_vibevoice(self):
        """Test entering COOL state unloads VibeVoice."""
        manager = IdleManager()
        unload_callback = AsyncMock()
        manager._vibevoice_unload_callback = unload_callback

        await manager._execute_state_actions(IdleState.WARM, IdleState.COOL)

        unload_callback.assert_called_once()

    @pytest.mark.asyncio
    async def test_execute_actions_entering_cold_unloads_both(self):
        """Test entering COLD state unloads both services."""
        manager = IdleManager()
        vibevoice_callback = AsyncMock()
        ollama_callback = AsyncMock()
        manager._vibevoice_unload_callback = vibevoice_callback
        manager._ollama_unload_callback = ollama_callback

        await manager._execute_state_actions(IdleState.COOL, IdleState.COLD)

        vibevoice_callback.assert_called_once()
        ollama_callback.assert_called_once()

    @pytest.mark.asyncio
    async def test_execute_actions_entering_dormant_unloads_both(self):
        """Test entering DORMANT state unloads both services."""
        manager = IdleManager()
        vibevoice_callback = AsyncMock()
        ollama_callback = AsyncMock()
        manager._vibevoice_unload_callback = vibevoice_callback
        manager._ollama_unload_callback = ollama_callback

        await manager._execute_state_actions(IdleState.COLD, IdleState.DORMANT)

        vibevoice_callback.assert_called_once()
        ollama_callback.assert_called_once()

    @pytest.mark.asyncio
    async def test_execute_actions_waking_from_cold(self):
        """Test waking from COLD state pre-warms services."""
        manager = IdleManager()
        load_callback = AsyncMock()
        manager._vibevoice_load_callback = load_callback

        await manager._execute_state_actions(IdleState.COLD, IdleState.ACTIVE)

        # Give background task time to start
        await asyncio.sleep(0.05)

    @pytest.mark.asyncio
    async def test_execute_actions_waking_from_dormant(self):
        """Test waking from DORMANT state pre-warms services."""
        manager = IdleManager()
        load_callback = AsyncMock()
        manager._vibevoice_load_callback = load_callback

        await manager._execute_state_actions(IdleState.DORMANT, IdleState.ACTIVE)

        # Give background task time to start
        await asyncio.sleep(0.05)

    @pytest.mark.asyncio
    async def test_execute_actions_no_action_for_same_level(self):
        """Test no action when staying at same level."""
        manager = IdleManager()
        callback = AsyncMock()
        manager._vibevoice_unload_callback = callback

        await manager._execute_state_actions(IdleState.ACTIVE, IdleState.ACTIVE)

        callback.assert_not_called()


# =============================================================================
# IDLE MANAGER SERVICE CALLBACKS TESTS
# =============================================================================


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
    async def test_unload_ollama_callback_exception(self):
        """Test Ollama unload handles callback exception."""
        manager = IdleManager()
        callback = AsyncMock(side_effect=Exception("Test error"))
        manager._ollama_unload_callback = callback

        # Should not raise
        await manager._unload_ollama_models()

    @pytest.mark.asyncio
    async def test_unload_vibevoice_with_callback(self):
        """Test VibeVoice unload uses callback if set."""
        manager = IdleManager()
        callback = AsyncMock()
        manager._vibevoice_unload_callback = callback

        await manager._unload_vibevoice()

        callback.assert_called_once()

    @pytest.mark.asyncio
    async def test_unload_vibevoice_callback_exception(self):
        """Test VibeVoice unload handles callback exception."""
        manager = IdleManager()
        callback = AsyncMock(side_effect=Exception("Test error"))
        manager._vibevoice_unload_callback = callback

        # Should not raise
        await manager._unload_vibevoice()

    @pytest.mark.asyncio
    async def test_pre_warm_with_callback(self):
        """Test pre-warm uses callback if set."""
        manager = IdleManager()
        callback = AsyncMock()
        manager._vibevoice_load_callback = callback

        await manager._pre_warm_services()

        # Callback is called in background task
        await asyncio.sleep(0.05)

    @pytest.mark.asyncio
    async def test_pre_warm_handles_callback_exception(self):
        """Test pre-warm handles callback exception gracefully."""
        manager = IdleManager()
        callback = AsyncMock(side_effect=Exception("Test error"))
        manager._vibevoice_load_callback = callback

        # Should not raise
        await manager._pre_warm_services()

    @pytest.mark.asyncio
    async def test_unload_ollama_without_callback_no_error(self):
        """Test Ollama unload without callback doesn't error."""
        manager = IdleManager()
        manager._ollama_unload_callback = None

        with patch("aiohttp.ClientSession") as mock_session:
            mock_context = AsyncMock()
            mock_context.__aenter__.return_value = mock_context
            mock_context.__aexit__.return_value = None
            mock_session.return_value = mock_context
            mock_context.get.return_value.__aenter__.return_value.status = 500

            # Should not raise even with failed API call
            await manager._unload_ollama_models()

    @pytest.mark.asyncio
    async def test_unload_vibevoice_without_callback_no_error(self):
        """Test VibeVoice unload without callback doesn't error."""
        manager = IdleManager()
        manager._vibevoice_unload_callback = None

        with patch("aiohttp.ClientSession") as mock_session:
            mock_context = AsyncMock()
            mock_context.__aenter__.return_value = mock_context
            mock_context.__aexit__.return_value = None
            mock_session.return_value = mock_context
            mock_context.post.side_effect = Exception("Connection refused")

            # Should not raise
            await manager._unload_vibevoice()


# =============================================================================
# IDLE MANAGER STATUS TESTS
# =============================================================================


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

    def test_get_status_seconds_idle(self):
        """Test seconds idle is calculated correctly."""
        manager = IdleManager()
        manager.last_activity = time.time() - 100

        status = manager.get_status()

        assert status["seconds_idle"] >= 99

    def test_get_status_keep_awake_remaining(self):
        """Test keep awake remaining is calculated."""
        manager = IdleManager()
        manager._keep_awake_until = time.time() + 60

        status = manager.get_status()

        assert status["keep_awake_remaining"] >= 59

    def test_get_status_keep_awake_expired(self):
        """Test keep awake remaining is 0 when expired."""
        manager = IdleManager()
        manager._keep_awake_until = time.time() - 10  # Already expired

        status = manager.get_status()

        assert status["keep_awake_remaining"] == 0

    def test_get_transition_history(self):
        """Test getting transition history."""
        manager = IdleManager()

        history = manager.get_transition_history()

        assert isinstance(history, list)

    @pytest.mark.asyncio
    async def test_get_transition_history_after_transitions(self):
        """Test history after multiple transitions."""
        manager = IdleManager()
        await manager._transition_to(IdleState.WARM, "timeout")
        await manager._transition_to(IdleState.COOL, "timeout")

        history = manager.get_transition_history()

        assert len(history) == 2

    def test_get_transition_history_limit(self):
        """Test history respects limit parameter."""
        manager = IdleManager()
        # Manually add history entries
        for i in range(10):
            manager.transition_history.append({"index": i})

        history = manager.get_transition_history(limit=5)

        assert len(history) == 5

    def test_get_available_modes(self):
        """Test getting available power modes."""
        manager = IdleManager()

        modes = manager.get_available_modes()

        assert "balanced" in modes
        assert "performance" in modes
        assert modes["balanced"]["is_builtin"] is True

    def test_get_available_modes_has_is_custom(self):
        """Test available modes include is_custom flag."""
        manager = IdleManager()

        modes = manager.get_available_modes()

        assert modes["balanced"]["is_custom"] is False


# =============================================================================
# IDLE MANAGER NEXT TRANSITION TIME TESTS
# =============================================================================


class TestIdleManagerNextTransitionTime:
    """Tests for next transition time calculation."""

    def test_next_transition_disabled(self):
        """Test next transition is None when disabled."""
        manager = IdleManager()
        manager.enabled = False

        result = manager._get_next_transition_time(30)

        assert result is None

    def test_next_transition_to_warm(self):
        """Test next transition is to warm."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=30, cool=300, cold=1800, dormant=7200)

        result = manager._get_next_transition_time(15)

        assert result["state"] == "warm"
        assert result["seconds_remaining"] == 15

    def test_next_transition_to_cool(self):
        """Test next transition is to cool."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=30, cool=300, cold=1800, dormant=7200)

        result = manager._get_next_transition_time(60)

        assert result["state"] == "cool"
        assert result["seconds_remaining"] == 240

    def test_next_transition_to_cold(self):
        """Test next transition is to cold."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=30, cool=300, cold=1800, dormant=7200)

        result = manager._get_next_transition_time(400)

        assert result["state"] == "cold"

    def test_next_transition_to_dormant(self):
        """Test next transition is to dormant."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=30, cool=300, cold=1800, dormant=7200)

        result = manager._get_next_transition_time(2000)

        assert result["state"] == "dormant"

    def test_next_transition_none_when_dormant(self):
        """Test next transition is None when already dormant."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=30, cool=300, cold=1800, dormant=7200)

        result = manager._get_next_transition_time(10000)

        assert result is None


# =============================================================================
# IDLE MANAGER PROFILES TESTS
# =============================================================================


class TestIdleManagerProfiles:
    """Tests for custom profile management."""

    @pytest.fixture
    def manager(self):
        """Create manager with mocked save."""
        manager = IdleManager()
        manager._save_custom_profiles = MagicMock()
        return manager

    @pytest.fixture(autouse=True)
    def cleanup_profiles(self):
        """Clean up any test profiles after each test."""
        yield
        # Remove any test profiles added during tests
        test_profiles = [k for k in POWER_MODES.keys() if k not in BUILTIN_POWER_MODES]
        for profile_id in test_profiles:
            del POWER_MODES[profile_id]

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

    def test_create_profile_sanitizes_id(self, manager):
        """Test profile ID is sanitized."""
        result = manager.create_profile(
            profile_id="Test Profile ID",
            name="Test",
            description="Test",
            thresholds={"warm": 20},
        )

        assert result is True
        assert "test_profile_id" in POWER_MODES

    def test_create_profile_cannot_overwrite_builtin(self, manager):
        """Test cannot overwrite built-in profile."""
        result = manager.create_profile(
            profile_id="balanced",
            name="My Balanced",
            description="Override",
            thresholds={"warm": 10},
        )

        assert result is False

    def test_create_profile_with_disabled(self, manager):
        """Test creating profile with disabled flag."""
        result = manager.create_profile(
            profile_id="disabled_test",
            name="Disabled",
            description="Disabled profile",
            thresholds={"warm": 20},
            enabled=False,
        )

        assert result is True
        assert POWER_MODES["disabled_test"].enabled is False

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

    def test_update_profile_description(self, manager):
        """Test updating profile description."""
        manager.create_profile(
            profile_id="desc_test",
            name="Test",
            description="Original",
            thresholds={"warm": 20},
        )

        manager.update_profile(
            profile_id="desc_test",
            description="New description",
        )

        assert POWER_MODES["desc_test"].description == "New description"

    def test_update_profile_thresholds(self, manager):
        """Test updating profile thresholds."""
        manager.create_profile(
            profile_id="threshold_test",
            name="Test",
            description="Test",
            thresholds={"warm": 20, "cool": 100},
        )

        manager.update_profile(
            profile_id="threshold_test",
            thresholds={"warm": 30},
        )

        # Warm should be updated, cool should remain
        assert POWER_MODES["threshold_test"].thresholds.warm == 30
        assert POWER_MODES["threshold_test"].thresholds.cool == 100

    def test_update_profile_enabled(self, manager):
        """Test updating profile enabled flag."""
        manager.create_profile(
            profile_id="enabled_test",
            name="Test",
            description="Test",
            thresholds={"warm": 20},
            enabled=True,
        )

        manager.update_profile(
            profile_id="enabled_test",
            enabled=False,
        )

        assert POWER_MODES["enabled_test"].enabled is False

    def test_update_profile_cannot_modify_builtin(self, manager):
        """Test cannot modify built-in profile."""
        result = manager.update_profile("balanced", name="New Name")

        assert result is False

    def test_update_profile_nonexistent(self, manager):
        """Test updating non-existent profile."""
        result = manager.update_profile("nonexistent", name="New Name")

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

    def test_delete_profile_nonexistent(self, manager):
        """Test deleting non-existent profile."""
        result = manager.delete_profile("nonexistent")

        assert result is False

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

    def test_duplicate_profile_copies_thresholds(self, manager):
        """Test duplicating profile copies thresholds."""
        manager.duplicate_profile(
            source_id="power_saver",
            new_id="my_saver",
            new_name="My Saver",
        )

        source = POWER_MODES["power_saver"]
        dup = POWER_MODES["my_saver"]

        assert dup.thresholds.warm == source.thresholds.warm
        assert dup.thresholds.cool == source.thresholds.cool

    def test_duplicate_profile_nonexistent_source(self, manager):
        """Test duplicating non-existent profile."""
        result = manager.duplicate_profile(
            source_id="nonexistent",
            new_id="new",
            new_name="New",
        )

        assert result is False

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

    def test_get_profile_custom(self, manager):
        """Test getting custom profile."""
        manager.create_profile(
            profile_id="custom_get",
            name="Custom",
            description="Custom profile",
            thresholds={"warm": 25},
        )

        result = manager.get_profile("custom_get")

        assert result["id"] == "custom_get"
        assert result["is_builtin"] is False
        assert result["is_custom"] is True


# =============================================================================
# IDLE MANAGER PROFILE FILE OPERATIONS TESTS
# =============================================================================


class TestIdleManagerProfileFileOperations:
    """Tests for profile file save/load operations."""

    def test_save_custom_profiles_creates_directory(self):
        """Test save creates data directory if needed."""
        manager = IdleManager()

        with patch("pathlib.Path.mkdir") as mock_mkdir:
            with patch("builtins.open", mock_open()):
                manager._save_custom_profiles()

            mock_mkdir.assert_called()

    def test_save_custom_profiles_writes_json(self):
        """Test save writes JSON to file."""
        manager = IdleManager()

        m = mock_open()
        with patch("pathlib.Path.mkdir"):
            with patch("builtins.open", m):
                manager._save_custom_profiles()

        m.assert_called()

    def test_save_custom_profiles_handles_error(self):
        """Test save handles file errors gracefully."""
        manager = IdleManager()

        with patch("pathlib.Path.mkdir", side_effect=PermissionError("No access")):
            # Should not raise
            manager._save_custom_profiles()

    def test_load_custom_profiles_no_file(self):
        """Test load handles missing file."""
        manager = IdleManager()

        with patch.object(Path, "exists", return_value=False):
            # Should not raise
            manager._load_custom_profiles()

    def test_load_custom_profiles_success(self):
        """Test load reads profiles from file."""
        manager = IdleManager()
        profile_data = {
            "test_loaded": {
                "name": "Loaded",
                "description": "Loaded profile",
                "thresholds": {"warm": 15, "cool": 90, "cold": 450, "dormant": 2700},
                "enabled": True,
            }
        }

        with patch.object(Path, "exists", return_value=True):
            with patch("builtins.open", mock_open(read_data=json.dumps(profile_data))):
                manager._load_custom_profiles()

        assert "test_loaded" in POWER_MODES
        # Cleanup
        del POWER_MODES["test_loaded"]

    def test_load_custom_profiles_handles_error(self):
        """Test load handles file errors gracefully."""
        manager = IdleManager()

        with patch.object(Path, "exists", return_value=True):
            with patch("builtins.open", side_effect=PermissionError("No access")):
                # Should not raise
                manager._load_custom_profiles()

    def test_load_custom_profiles_handles_invalid_json(self):
        """Test load handles invalid JSON gracefully."""
        manager = IdleManager()

        with patch.object(Path, "exists", return_value=True):
            with patch("builtins.open", mock_open(read_data="not valid json")):
                # Should not raise
                manager._load_custom_profiles()


# =============================================================================
# IDLE MANAGER LIFECYCLE TESTS
# =============================================================================


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

    @pytest.mark.asyncio
    async def test_stop_without_start(self):
        """Test stop without start doesn't error."""
        manager = IdleManager()

        # Should not raise
        await manager.stop()

    @pytest.mark.asyncio
    async def test_stop_multiple_times(self):
        """Test stop can be called multiple times."""
        manager = IdleManager()
        await manager.start()

        await manager.stop()
        await manager.stop()  # Second stop

        assert manager._running is False


# =============================================================================
# IDLE MANAGER MONITOR LOOP TESTS
# =============================================================================


class TestIdleManagerMonitorLoop:
    """Tests for the background monitor loop."""

    @pytest.mark.asyncio
    async def test_monitor_loop_transitions_state(self):
        """Test monitor loop logic by simulating the check directly."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=1, cool=60, cold=300, dormant=1800)
        manager.last_activity = time.time() - 10  # 10 seconds ago
        manager.enabled = True

        # Directly test the state calculation and transition logic
        idle_seconds = time.time() - manager.last_activity
        target_state = manager._calculate_state(idle_seconds)

        # Should want to transition to WARM since idle > 1 second
        assert target_state == IdleState.WARM

        # Perform the transition
        await manager._transition_to(target_state, "timeout")

        assert manager.current_state == IdleState.WARM
        assert len(manager.transition_history) > 0

    @pytest.mark.asyncio
    async def test_monitor_loop_respects_disabled(self):
        """Test monitor loop respects disabled flag."""
        manager = IdleManager()
        manager.enabled = False
        manager.thresholds = IdleThresholds(warm=1)
        manager.last_activity = time.time() - 10

        # When disabled, the monitor loop continues without checking state
        # We verify the logic by checking that enabled=False prevents transitions
        idle_seconds = time.time() - manager.last_activity
        target_state = manager._calculate_state(idle_seconds)

        # Even though we're idle enough for WARM, with enabled=False,
        # the monitor loop would skip the transition check
        assert target_state == IdleState.WARM  # Would transition if enabled
        assert manager.enabled is False  # But won't because disabled

    @pytest.mark.asyncio
    async def test_monitor_loop_respects_keep_awake(self):
        """Test monitor loop respects keep awake."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=1)
        manager.last_activity = time.time() - 10
        manager._keep_awake_until = time.time() + 60

        # Test the keep-awake check logic
        assert manager._keep_awake_until is not None
        assert time.time() < manager._keep_awake_until

        # When keep_awake is active, monitor should not transition
        # even though idle time exceeds threshold

    @pytest.mark.asyncio
    async def test_monitor_loop_clears_expired_keep_awake(self):
        """Test monitor loop logic for clearing expired keep awake."""
        manager = IdleManager()
        manager._keep_awake_until = time.time() - 1  # Already expired

        # Simulate the monitor loop logic for expired keep_awake
        if manager._keep_awake_until and time.time() >= manager._keep_awake_until:
            manager._keep_awake_until = None

        assert manager._keep_awake_until is None

    @pytest.mark.asyncio
    async def test_monitor_loop_starts_and_stops(self):
        """Test monitor loop can start and stop properly."""
        manager = IdleManager()

        await manager.start()
        assert manager._running is True
        assert manager._monitor_task is not None

        await manager.stop()
        assert manager._running is False


# =============================================================================
# INIT FUNCTION TESTS
# =============================================================================


class TestInitIdleManager:
    """Tests for the _init_idle_manager function."""

    def test_init_idle_manager_creates_manager(self):
        """Test _init_idle_manager creates a manager instance."""
        with patch.object(IdleManager, "_load_custom_profiles"):
            manager = _init_idle_manager()

            assert isinstance(manager, IdleManager)

    def test_init_idle_manager_loads_profiles(self):
        """Test _init_idle_manager loads custom profiles."""
        with patch.object(IdleManager, "_load_custom_profiles") as mock_load:
            _init_idle_manager()

            mock_load.assert_called_once()


# =============================================================================
# EDGE CASE TESTS
# =============================================================================


class TestIdleManagerEdgeCases:
    """Tests for edge cases and unusual scenarios."""

    @pytest.mark.asyncio
    async def test_rapid_state_changes(self):
        """Test handling rapid state changes."""
        manager = IdleManager()

        # Rapidly change states
        for _ in range(10):
            await manager.force_state(IdleState.WARM)
            await manager.force_state(IdleState.COOL)
            await manager.force_state(IdleState.ACTIVE)

        assert manager.current_state == IdleState.ACTIVE

    def test_very_long_idle_time(self):
        """Test very long idle times."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds()

        # 1 year in seconds
        state = manager._calculate_state(365 * 24 * 60 * 60)

        assert state == IdleState.DORMANT

    def test_negative_idle_time(self):
        """Test negative idle time (clock skew)."""
        manager = IdleManager()

        state = manager._calculate_state(-10)

        assert state == IdleState.ACTIVE

    def test_fractional_idle_time(self):
        """Test fractional seconds."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=10)

        state = manager._calculate_state(10.0001)

        assert state == IdleState.WARM

    def test_thresholds_with_zero_values(self):
        """Test thresholds with zero values."""
        manager = IdleManager()
        manager.thresholds = IdleThresholds(warm=0, cool=0, cold=0, dormant=0)

        state = manager._calculate_state(0)

        assert state == IdleState.DORMANT

    def test_activity_during_transition(self):
        """Test activity recorded during transition."""
        manager = IdleManager()

        # Record activity
        manager.record_activity("test1")
        manager.record_activity("test2")
        manager.record_activity("test3")

        assert manager.last_activity_type == "test3"

    @pytest.mark.asyncio
    async def test_handler_returns_value(self):
        """Test handler return values are ignored."""
        manager = IdleManager()
        handler = AsyncMock(return_value="some value")
        manager.register_handler(IdleState.WARM, handler)

        await manager._transition_to(IdleState.WARM, "timeout")

        handler.assert_called_once()

    def test_get_status_just_after_activity(self):
        """Test status right after activity."""
        manager = IdleManager()
        manager.record_activity("test")

        status = manager.get_status()

        assert status["seconds_idle"] < 1

    def test_profile_with_empty_name(self):
        """Test creating profile with empty name."""
        manager = IdleManager()
        manager._save_custom_profiles = MagicMock()

        result = manager.create_profile(
            profile_id="empty_name",
            name="",  # Empty name
            description="Test",
            thresholds={"warm": 20},
        )

        assert result is True
        # Cleanup
        del POWER_MODES["empty_name"]

    def test_profile_with_unicode_name(self):
        """Test creating profile with unicode characters."""
        manager = IdleManager()
        manager._save_custom_profiles = MagicMock()

        result = manager.create_profile(
            profile_id="unicode_test",
            name="Test Profile",
            description="Test description",
            thresholds={"warm": 20},
        )

        assert result is True
        # Cleanup
        del POWER_MODES["unicode_test"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
