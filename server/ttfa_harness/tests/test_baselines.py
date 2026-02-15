"""
Tests for the TTFA harness baseline management.
"""

import json

import pytest

from ttfa_harness.baselines import (
    ABSOLUTE_CEILING_MS,
    MINOR_THRESHOLD,
    MODERATE_THRESHOLD,
    SEVERE_THRESHOLD,
    BaselineManager,
)
from ttfa_harness.models import (
    AudioPath,
    RegressionSeverity,
    ScenarioBaseline,
    TTFABaseline,
    TTFAResult,
    TTFARun,
)


@pytest.fixture
def tmp_baselines_dir(tmp_path):
    """Create a temporary baselines directory."""
    baselines_dir = tmp_path / "baselines"
    baselines_dir.mkdir()
    return baselines_dir


@pytest.fixture
def manager(tmp_baselines_dir):
    """Create a BaselineManager with a temporary directory."""
    return BaselineManager(baselines_dir=tmp_baselines_dir)


def _make_result(scenario_id, ttfa_ms, audio_path=AudioPath.STREAMING):
    return TTFAResult(
        scenario_id=scenario_id,
        scenario_name=scenario_id,
        audio_path=audio_path,
        repetition=1,
        activate_to_audio_playing_ms=ttfa_ms,
    )


def _make_run(results):
    run = TTFARun()
    run.results = results
    run.compute_summary()
    return run


# ============================================================================
# BaselineManager: create and load
# ============================================================================


class TestBaselineCreateAndLoad:
    """Tests for creating and loading baselines."""

    def test_create_baseline(self, manager):
        run = _make_run(
            [
                _make_result("scenario-a", 200.0),
                _make_result("scenario-a", 250.0),
                _make_result("scenario-a", 300.0),
                _make_result("scenario-b", 100.0),
            ]
        )
        baseline = manager.create_baseline(run, "test-baseline")

        assert baseline.name == "test-baseline"
        assert len(baseline.scenario_metrics) == 2
        assert "scenario-a" in baseline.scenario_metrics
        assert "scenario-b" in baseline.scenario_metrics

        # Check median calculation for scenario-a
        metrics_a = baseline.scenario_metrics["scenario-a"]
        assert metrics_a.median_ttfa_ms == 250.0  # median of [200, 250, 300]

    def test_load_baseline(self, manager):
        run = _make_run([_make_result("s1", 300.0)])
        manager.create_baseline(run, "my-baseline")

        loaded = manager.load_baseline("my-baseline")
        assert loaded is not None
        assert loaded.name == "my-baseline"
        assert "s1" in loaded.scenario_metrics

    def test_load_nonexistent_baseline(self, manager):
        result = manager.load_baseline("nonexistent")
        assert result is None

    def test_list_baselines(self, manager):
        run1 = _make_run([_make_result("s1", 100.0)])
        run2 = _make_run([_make_result("s2", 200.0)])
        manager.create_baseline(run1, "baseline-a")
        manager.create_baseline(run2, "baseline-b")

        baselines = manager.list_baselines()
        assert len(baselines) == 2
        names = {b.name for b in baselines}
        assert "baseline-a" in names
        assert "baseline-b" in names

    def test_list_baselines_empty(self, manager):
        baselines = manager.list_baselines()
        assert baselines == []

    def test_create_saves_json(self, manager, tmp_baselines_dir):
        run = _make_run([_make_result("s1", 250.0)])
        manager.create_baseline(run, "json-test")

        path = tmp_baselines_dir / "json-test.json"
        assert path.exists()

        data = json.loads(path.read_text())
        assert data["name"] == "json-test"
        assert "scenario_metrics" in data

    def test_load_corrupted_json(self, manager, tmp_baselines_dir):
        path = tmp_baselines_dir / "corrupt.json"
        path.write_text("{ invalid json")
        result = manager.load_baseline("corrupt")
        assert result is None

    def test_list_skips_corrupted_files(self, manager, tmp_baselines_dir):
        # Create one valid and one corrupt baseline
        run = _make_run([_make_result("s1", 100.0)])
        manager.create_baseline(run, "valid")
        (tmp_baselines_dir / "corrupt.json").write_text("not json")

        baselines = manager.list_baselines()
        assert len(baselines) == 1
        assert baselines[0].name == "valid"


# ============================================================================
# Path Traversal Protection
# ============================================================================


class TestPathTraversalProtection:
    """Tests for path traversal prevention in load_baseline."""

    def test_rejects_path_with_slash(self, manager):
        result = manager.load_baseline("../../etc/passwd")
        assert result is None

    def test_rejects_path_with_backslash(self, manager):
        result = manager.load_baseline("..\\..\\windows\\system32")
        assert result is None

    def test_rejects_path_with_dotdot(self, manager):
        result = manager.load_baseline("..secret")
        assert result is None

    def test_accepts_normal_name(self, manager):
        # Should not raise even if file doesn't exist
        result = manager.load_baseline("normal-name")
        assert result is None  # File doesn't exist, but no error

    def test_accepts_name_with_hyphen_and_underscore(self, manager):
        run = _make_run([_make_result("s1", 100.0)])
        manager.create_baseline(run, "my-baseline_v2")
        result = manager.load_baseline("my-baseline_v2")
        assert result is not None


# ============================================================================
# Regression Detection
# ============================================================================


class TestRegressionDetection:
    """Tests for comparing runs against baselines."""

    def _make_baseline(self, scenario_metrics):
        return TTFABaseline(
            id="bl_test",
            name="test",
            scenario_metrics={
                sid: ScenarioBaseline(
                    median_ttfa_ms=metrics["median"],
                    p99_ttfa_ms=metrics["p99"],
                    audio_path="streaming",
                )
                for sid, metrics in scenario_metrics.items()
            },
        )

    def test_no_regression_within_threshold(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        # 5% increase (within 10% minor threshold)
        run = _make_run([_make_result("s1", 210.0)])
        regressions = manager.check_regression(run, baseline)
        assert len(regressions) == 0

    def test_minor_regression(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        # 15% increase
        run = _make_run([_make_result("s1", 230.0)])
        regressions = manager.check_regression(run, baseline)
        assert len(regressions) >= 1
        assert any(r.severity == RegressionSeverity.MINOR for r in regressions)

    def test_moderate_regression(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        # 30% increase
        run = _make_run([_make_result("s1", 260.0)])
        regressions = manager.check_regression(run, baseline)
        assert len(regressions) >= 1
        assert any(r.severity == RegressionSeverity.MODERATE for r in regressions)

    def test_severe_regression(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        # 60% increase
        run = _make_run([_make_result("s1", 320.0)])
        regressions = manager.check_regression(run, baseline)
        assert len(regressions) >= 1
        assert any(r.severity == RegressionSeverity.SEVERE for r in regressions)

    def test_performance_improvement_no_regression(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        # Performance improved
        run = _make_run([_make_result("s1", 100.0)])
        regressions = manager.check_regression(run, baseline)
        assert len(regressions) == 0

    def test_absolute_ceiling_regression(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 900.0, "p99": 950.0},
            }
        )
        # Above absolute ceiling of 1000ms, but only 12% increase (minor by %)
        run = _make_run([_make_result("s1", 1010.0)])
        regressions = manager.check_regression(run, baseline)
        # Should have regression due to either percentage or ceiling
        assert len(regressions) >= 1

    def test_absolute_ceiling_always_severe(self, manager):
        """Any TTFA above 1000ms should be flagged even if percentage is low."""
        baseline = self._make_baseline(
            {
                "s1": {"median": 990.0, "p99": 995.0},
            }
        )
        # Just above ceiling, tiny percentage increase
        run = _make_run([_make_result("s1", 1001.0)])
        regressions = manager.check_regression(run, baseline)
        severe = [r for r in regressions if r.severity == RegressionSeverity.SEVERE]
        assert len(severe) >= 1

    def test_multiple_scenarios(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
                "s2": {"median": 100.0, "p99": 150.0},
            }
        )
        run = _make_run(
            [
                _make_result("s1", 200.0),  # No change
                _make_result("s2", 200.0),  # 100% increase
            ]
        )
        regressions = manager.check_regression(run, baseline)
        # Only s2 should have regression
        regressed_scenarios = {r.scenario_id for r in regressions}
        assert "s2" in regressed_scenarios
        # s1 should NOT be in regressions (0% change)
        s1_regressions = [r for r in regressions if r.scenario_id == "s1"]
        assert len(s1_regressions) == 0

    def test_new_scenario_not_in_baseline(self, manager):
        """A scenario not in the baseline should not generate regression."""
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        run = _make_run(
            [
                _make_result("s1", 200.0),
                _make_result("new-scenario", 500.0),  # Not in baseline
            ]
        )
        regressions = manager.check_regression(run, baseline)
        # new-scenario should not generate a regression
        new_regressions = [r for r in regressions if r.scenario_id == "new-scenario"]
        assert len(new_regressions) == 0

    def test_regression_includes_change_percent(self, manager):
        baseline = self._make_baseline(
            {
                "s1": {"median": 200.0, "p99": 300.0},
            }
        )
        run = _make_run([_make_result("s1", 300.0)])  # 50% increase
        regressions = manager.check_regression(run, baseline)
        assert len(regressions) >= 1
        median_reg = [r for r in regressions if r.metric == "median"]
        assert len(median_reg) >= 1
        assert median_reg[0].change_percent == pytest.approx(50.0)
        assert median_reg[0].baseline_value == 200.0
        assert median_reg[0].current_value == 300.0

    def test_zero_baseline_no_divide_by_zero(self, manager):
        """Scenarios with 0ms baseline should not cause division by zero."""
        baseline = self._make_baseline(
            {
                "s1": {"median": 0.0, "p99": 0.0},
            }
        )
        run = _make_run([_make_result("s1", 500.0)])
        # Should not raise
        regressions = manager.check_regression(run, baseline)
        # 0ms baseline is skipped (guard in code: bl_metrics.median_ttfa_ms > 0)
        median_regressions = [r for r in regressions if r.metric == "median"]
        assert len(median_regressions) == 0


# ============================================================================
# Threshold Constants
# ============================================================================


class TestThresholdConstants:
    """Verify threshold values match documented expectations."""

    def test_minor_threshold(self):
        assert MINOR_THRESHOLD == 0.10

    def test_moderate_threshold(self):
        assert MODERATE_THRESHOLD == 0.20

    def test_severe_threshold(self):
        assert SEVERE_THRESHOLD == 0.50

    def test_absolute_ceiling(self):
        assert ABSOLUTE_CEILING_MS == 1000.0

    def test_thresholds_are_ordered(self):
        assert MINOR_THRESHOLD < MODERATE_THRESHOLD < SEVERE_THRESHOLD
