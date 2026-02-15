"""
Tests for the TTFA harness data models.
"""

from datetime import datetime

from ttfa_harness.models import (
    AudioPath,
    RegressionSeverity,
    ScenarioBaseline,
    SimAction,
    SimActionType,
    SUITES,
    TTFABaseline,
    TTFAEvent,
    TTFAEventType,
    TTFARegression,
    TTFAResult,
    TTFARun,
    TTFASummary,
    TTFAScenario,
    get_predefined_scenarios,
)


# ============================================================================
# Enum Tests
# ============================================================================


class TestEnums:
    """Verify enum values match Swift instrumentation format."""

    def test_audio_path_values(self):
        assert AudioPath.CACHED.value == "cached"
        assert AudioPath.STREAMING.value == "streaming"
        assert AudioPath.PRE_BUFFERED.value == "pre_buffered"

    def test_event_type_values_match_swift(self):
        """Event type values must match the Swift TTFAEventType enum."""
        assert TTFAEventType.ACTIVATE.value == "ACTIVATE"
        assert TTFAEventType.TTS_FIRST.value == "TTS_FIRST"
        assert TTFAEventType.AUDIO_SCHEDULED.value == "AUDIO_SCHEDULED"
        assert TTFAEventType.AUDIO_PLAYING.value == "AUDIO_PLAYING"
        assert TTFAEventType.CACHED_HIT.value == "CACHED_HIT"
        assert TTFAEventType.ERROR.value == "ERROR"

    def test_regression_severity_values(self):
        assert RegressionSeverity.MINOR.value == "minor"
        assert RegressionSeverity.MODERATE.value == "moderate"
        assert RegressionSeverity.SEVERE.value == "severe"

    def test_sim_action_type_values(self):
        assert SimActionType.DEEP_LINK.value == "deep_link"
        assert SimActionType.TAP.value == "tap"
        assert SimActionType.WAIT.value == "wait"
        assert SimActionType.SWIPE.value == "swipe"


# ============================================================================
# SimAction
# ============================================================================


class TestSimAction:
    """Tests for SimAction dataclass and factory methods."""

    def test_deep_link_factory(self):
        action = SimAction.deep_link("unamentis://chat")
        assert action.action_type == SimActionType.DEEP_LINK
        assert action.url == "unamentis://chat"
        assert action.x is None

    def test_tap_factory(self):
        action = SimAction.tap_at(100, 200)
        assert action.action_type == SimActionType.TAP
        assert action.x == 100
        assert action.y == 200

    def test_wait_factory(self):
        action = SimAction.wait_for(2.5)
        assert action.action_type == SimActionType.WAIT
        assert action.seconds == 2.5

    def test_roundtrip_deep_link(self):
        original = SimAction.deep_link("unamentis://lesson?id=test")
        restored = SimAction.from_dict(original.to_dict())
        assert restored.action_type == original.action_type
        assert restored.url == original.url

    def test_roundtrip_tap(self):
        original = SimAction.tap_at(50, 300)
        restored = SimAction.from_dict(original.to_dict())
        assert restored.x == 50
        assert restored.y == 300

    def test_roundtrip_wait(self):
        original = SimAction.wait_for(1.5)
        restored = SimAction.from_dict(original.to_dict())
        assert restored.seconds == 1.5

    def test_to_dict_excludes_none_fields(self):
        action = SimAction.deep_link("unamentis://chat")
        d = action.to_dict()
        assert "x" not in d
        assert "y" not in d
        assert "seconds" not in d


# ============================================================================
# TTFAScenario
# ============================================================================


class TestTTFAScenario:
    """Tests for TTFAScenario dataclass."""

    def test_default_target(self):
        scenario = TTFAScenario(
            id="test",
            name="Test",
            feature_id="session.chat",
            audio_path=AudioPath.STREAMING,
        )
        assert scenario.target_ms == 1000.0

    def test_default_repetitions(self):
        scenario = TTFAScenario(
            id="test",
            name="Test",
            feature_id="session.chat",
            audio_path=AudioPath.STREAMING,
        )
        assert scenario.repetitions == 3

    def test_roundtrip(self):
        original = TTFAScenario(
            id="test-scenario",
            name="Test Scenario",
            feature_id="kb.oral",
            audio_path=AudioPath.CACHED,
            setup_steps=[
                SimAction.deep_link("unamentis://learning"),
                SimAction.wait_for(2.0),
            ],
            trigger_action=SimAction.tap_at(100, 200),
            target_ms=500.0,
            repetitions=5,
            requires_server=True,
            description="A test scenario",
        )
        restored = TTFAScenario.from_dict(original.to_dict())
        assert restored.id == original.id
        assert restored.name == original.name
        assert restored.feature_id == original.feature_id
        assert restored.audio_path == original.audio_path
        assert len(restored.setup_steps) == 2
        assert restored.trigger_action is not None
        assert restored.target_ms == 500.0
        assert restored.repetitions == 5
        assert restored.requires_server is True
        assert restored.description == "A test scenario"

    def test_roundtrip_no_trigger(self):
        original = TTFAScenario(
            id="no-trigger",
            name="No Trigger",
            feature_id="session.chat",
            audio_path=AudioPath.STREAMING,
        )
        restored = TTFAScenario.from_dict(original.to_dict())
        assert restored.trigger_action is None


# ============================================================================
# TTFAEvent
# ============================================================================


class TestTTFAEvent:
    """Tests for TTFAEvent dataclass."""

    def test_roundtrip(self):
        original = TTFAEvent(
            event_type=TTFAEventType.ACTIVATE,
            feature_id="session.chat",
            elapsed_ms=0.0,
            metadata="cold start",
            wall_timestamp=datetime(2024, 1, 15, 10, 30, 0),
        )
        restored = TTFAEvent.from_dict(original.to_dict())
        assert restored.event_type == original.event_type
        assert restored.feature_id == original.feature_id
        assert restored.elapsed_ms == original.elapsed_ms
        assert restored.metadata == original.metadata
        assert restored.wall_timestamp == original.wall_timestamp

    def test_roundtrip_no_optional_fields(self):
        original = TTFAEvent(
            event_type=TTFAEventType.TTS_FIRST,
            feature_id="kb.oral",
            elapsed_ms=150.0,
        )
        restored = TTFAEvent.from_dict(original.to_dict())
        assert restored.metadata == ""
        assert restored.wall_timestamp is None


# ============================================================================
# TTFAResult
# ============================================================================


class TestTTFAResult:
    """Tests for TTFAResult dataclass."""

    def test_ttfa_ms_property(self):
        result = TTFAResult(
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
            activate_to_audio_playing_ms=300.0,
        )
        assert result.ttfa_ms == 300.0

    def test_ttfa_ms_none_when_no_audio_playing(self):
        result = TTFAResult(
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.ttfa_ms is None

    def test_passes_target_true(self):
        result = TTFAResult(
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
            activate_to_audio_playing_ms=500.0,
        )
        assert result.passes_target is True

    def test_passes_target_false_above_1000(self):
        result = TTFAResult(
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
            activate_to_audio_playing_ms=1500.0,
        )
        assert result.passes_target is False

    def test_passes_target_false_when_none(self):
        result = TTFAResult(
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
        )
        assert result.passes_target is False

    def test_roundtrip(self):
        original = TTFAResult(
            scenario_id="session-cold-start",
            scenario_name="Session Cold Start",
            audio_path=AudioPath.STREAMING,
            repetition=2,
            activate_to_tts_first_ms=150.0,
            activate_to_audio_scheduled_ms=200.0,
            activate_to_audio_playing_ms=210.0,
            was_cached=False,
            errors=[],
        )
        restored = TTFAResult.from_dict(original.to_dict())
        assert restored.scenario_id == original.scenario_id
        assert restored.audio_path == original.audio_path
        assert restored.activate_to_tts_first_ms == 150.0
        assert restored.activate_to_audio_playing_ms == 210.0

    def test_roundtrip_with_errors(self):
        original = TTFAResult(
            scenario_id="test",
            scenario_name="Test",
            audio_path=AudioPath.STREAMING,
            repetition=1,
            errors=["TTS timeout", "Network failure"],
        )
        restored = TTFAResult.from_dict(original.to_dict())
        assert restored.errors == ["TTS timeout", "Network failure"]


# ============================================================================
# TTFARun and TTFASummary
# ============================================================================


class TestTTFARun:
    """Tests for TTFARun and summary computation."""

    def _make_result(self, scenario_id, ttfa_ms=None, errors=None):
        return TTFAResult(
            scenario_id=scenario_id,
            scenario_name=scenario_id,
            audio_path=AudioPath.STREAMING,
            repetition=1,
            activate_to_audio_playing_ms=ttfa_ms,
            errors=errors or [],
        )

    def test_compute_summary_all_pass(self):
        run = TTFARun()
        run.results = [
            self._make_result("a", ttfa_ms=200.0),
            self._make_result("b", ttfa_ms=300.0),
            self._make_result("c", ttfa_ms=400.0),
        ]
        run.compute_summary()
        assert run.summary.total_scenarios == 3
        assert run.summary.passed_scenarios == 3
        assert run.summary.failed_scenarios == 0
        assert run.summary.error_scenarios == 0
        assert run.summary.all_pass_target is True
        assert run.summary.median_ttfa_ms == 300.0

    def test_compute_summary_with_failure(self):
        run = TTFARun()
        run.results = [
            self._make_result("fast", ttfa_ms=200.0),
            self._make_result("slow", ttfa_ms=1500.0),
        ]
        run.compute_summary()
        assert run.summary.passed_scenarios == 1
        assert run.summary.failed_scenarios == 1
        assert run.summary.all_pass_target is False

    def test_compute_summary_with_errors(self):
        run = TTFARun()
        run.results = [
            self._make_result("good", ttfa_ms=200.0),
            self._make_result("error", errors=["TTS timeout"]),
        ]
        run.compute_summary()
        assert run.summary.passed_scenarios == 1
        assert run.summary.error_scenarios == 1
        assert run.summary.all_pass_target is False

    def test_compute_summary_empty_results(self):
        run = TTFARun()
        run.compute_summary()
        assert run.summary.total_scenarios == 0
        assert run.summary.all_pass_target is False

    def test_compute_summary_worst_scenario(self):
        run = TTFARun()
        run.results = [
            self._make_result("fast", ttfa_ms=100.0),
            self._make_result("medium", ttfa_ms=500.0),
            self._make_result("slowest", ttfa_ms=800.0),
        ]
        run.compute_summary()
        assert run.summary.worst_scenario == "slowest"
        assert run.summary.worst_ttfa_ms == 800.0

    def test_roundtrip(self):
        run = TTFARun(device="iPhone 17 Pro", app_build="1.0.0")
        run.results = [
            self._make_result("test", ttfa_ms=250.0),
        ]
        run.compute_summary()

        data = run.to_dict()
        restored = TTFARun.from_dict(data)
        assert restored.id == run.id
        assert restored.device == "iPhone 17 Pro"
        assert restored.app_build == "1.0.0"
        assert len(restored.results) == 1
        assert restored.summary.total_scenarios == 1

    def test_summary_roundtrip(self):
        summary = TTFASummary(
            total_scenarios=5,
            passed_scenarios=4,
            failed_scenarios=1,
            median_ttfa_ms=250.0,
            p99_ttfa_ms=800.0,
            worst_scenario="slow-test",
            worst_ttfa_ms=900.0,
            all_pass_target=False,
        )
        restored = TTFASummary.from_dict(summary.to_dict())
        assert restored.total_scenarios == 5
        assert restored.passed_scenarios == 4
        assert restored.worst_scenario == "slow-test"

    def test_p99_calculation(self):
        """P99 should pick the value at the 99th percentile index."""
        run = TTFARun()
        # Create 100 results with incrementing TTFA
        for i in range(100):
            run.results.append(self._make_result(f"s{i}", ttfa_ms=float(i + 1)))
        run.compute_summary()
        # With 100 values, index int(100 * 0.99) = 99, which is the 100th value = 100.0
        assert run.summary.p99_ttfa_ms == 100.0


# ============================================================================
# Baseline Models
# ============================================================================


class TestBaselineModels:
    """Tests for ScenarioBaseline, TTFABaseline, TTFARegression models."""

    def test_scenario_baseline_roundtrip(self):
        original = ScenarioBaseline(
            median_ttfa_ms=250.0,
            p99_ttfa_ms=400.0,
            audio_path="streaming",
        )
        restored = ScenarioBaseline.from_dict(original.to_dict())
        assert restored.median_ttfa_ms == 250.0
        assert restored.p99_ttfa_ms == 400.0
        assert restored.audio_path == "streaming"

    def test_ttfa_baseline_roundtrip(self):
        original = TTFABaseline(
            id="bl_abc123",
            name="initial",
            run_id="ttfa_xyz",
            scenario_metrics={
                "session-cold-start": ScenarioBaseline(
                    median_ttfa_ms=300.0,
                    p99_ttfa_ms=500.0,
                    audio_path="streaming",
                ),
                "reading-cached": ScenarioBaseline(
                    median_ttfa_ms=10.0,
                    p99_ttfa_ms=25.0,
                    audio_path="cached",
                ),
            },
        )
        restored = TTFABaseline.from_dict(original.to_dict())
        assert restored.id == "bl_abc123"
        assert restored.name == "initial"
        assert len(restored.scenario_metrics) == 2
        assert restored.scenario_metrics["session-cold-start"].median_ttfa_ms == 300.0
        assert restored.scenario_metrics["reading-cached"].p99_ttfa_ms == 25.0

    def test_ttfa_regression_roundtrip(self):
        original = TTFARegression(
            scenario_id="session-cold-start",
            metric="median",
            baseline_value=300.0,
            current_value=450.0,
            change_percent=50.0,
            severity=RegressionSeverity.SEVERE,
        )
        restored = TTFARegression.from_dict(original.to_dict())
        assert restored.scenario_id == "session-cold-start"
        assert restored.metric == "median"
        assert restored.severity == RegressionSeverity.SEVERE


# ============================================================================
# Predefined Scenarios
# ============================================================================


class TestPredefinedScenarios:
    """Tests for predefined scenario definitions and suites."""

    def test_all_scenarios_have_required_fields(self):
        scenarios = get_predefined_scenarios()
        assert len(scenarios) >= 9

        for sid, s in scenarios.items():
            assert s.id == sid
            assert s.name
            assert s.feature_id
            assert isinstance(s.audio_path, AudioPath)
            assert s.target_ms == 1000.0
            assert s.repetitions >= 1

    def test_feature_ids_match_swift_enum(self):
        """Feature IDs in scenarios must match Swift TTFAFeature enum rawValues."""
        valid_features = {
            "session.chat",
            "session.curriculum",
            "kb.oral",
            "kb.written",
            "kb.drill",
            "kb.rebound",
            "kb.conference",
            "reading.play",
            "reading.resume",
        }
        scenarios = get_predefined_scenarios()
        for sid, s in scenarios.items():
            assert s.feature_id in valid_features, (
                f"Scenario {sid} has invalid feature_id: {s.feature_id}"
            )

    def test_quick_suite_is_subset_of_full(self):
        assert set(SUITES["quick"]).issubset(set(SUITES["full"]))

    def test_quick_suite_has_mix_of_paths(self):
        """Quick suite should test both cached and streaming paths."""
        scenarios = get_predefined_scenarios()
        quick_paths = {scenarios[sid].audio_path for sid in SUITES["quick"]}
        assert AudioPath.CACHED in quick_paths
        assert AudioPath.STREAMING in quick_paths

    def test_suite_scenario_ids_all_exist(self):
        scenarios = get_predefined_scenarios()
        for suite_name, ids in SUITES.items():
            for sid in ids:
                assert sid in scenarios, (
                    f"Suite '{suite_name}' references nonexistent scenario: {sid}"
                )

    def test_each_scenario_has_setup_steps(self):
        """Every scenario should have at least one setup step."""
        scenarios = get_predefined_scenarios()
        for sid, s in scenarios.items():
            assert len(s.setup_steps) > 0, f"Scenario {sid} has no setup steps"

    def test_scenario_descriptions_not_empty(self):
        scenarios = get_predefined_scenarios()
        for sid, s in scenarios.items():
            assert s.description, f"Scenario {sid} has no description"
