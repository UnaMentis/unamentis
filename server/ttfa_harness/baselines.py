"""
UnaMentis TTFA Harness - Baseline Management

Saves, loads, and compares TTFA baselines for regression detection.
Baselines are stored as JSON files in the baselines/ directory.
"""

import json
import logging
import statistics
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict

from .models import (
    TTFABaseline,
    TTFARun,
    TTFARegression,
    RegressionSeverity,
    ScenarioBaseline,
)

logger = logging.getLogger("ttfa_harness.baselines")

# Regression thresholds (percentage increase from baseline)
MINOR_THRESHOLD = 0.10  # 10%
MODERATE_THRESHOLD = 0.20  # 20%
SEVERE_THRESHOLD = 0.50  # 50%

# Absolute ceiling: any TTFA above this is an automatic FAIL
ABSOLUTE_CEILING_MS = 1000.0


class BaselineManager:
    """Manages TTFA baselines for regression detection."""

    def __init__(self, baselines_dir: Optional[Path] = None):
        if baselines_dir is None:
            baselines_dir = Path(__file__).parent / "baselines"
        self.baselines_dir = baselines_dir
        self.baselines_dir.mkdir(parents=True, exist_ok=True)

    def list_baselines(self) -> List[TTFABaseline]:
        """List all saved baselines."""
        baselines = []
        for path in sorted(self.baselines_dir.glob("*.json")):
            try:
                data = json.loads(path.read_text())
                baselines.append(TTFABaseline.from_dict(data))
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning("Failed to load baseline %s: %s", path.name, e)
        return baselines

    def load_baseline(self, name: str) -> Optional[TTFABaseline]:
        """Load a baseline by name."""
        # Sanitize name to prevent path traversal
        if "/" in name or "\\" in name or ".." in name:
            logger.error("Invalid baseline name (path traversal rejected): %s", name)
            return None
        path = self.baselines_dir / f"{name}.json"
        if not path.resolve().is_relative_to(self.baselines_dir.resolve()):
            logger.error("Baseline path escapes baselines directory: %s", path)
            return None
        if not path.exists():
            logger.warning("Baseline '%s' not found at %s", name, path)
            return None
        try:
            data = json.loads(path.read_text())
            return TTFABaseline.from_dict(data)
        except (json.JSONDecodeError, KeyError) as e:
            logger.error("Failed to parse baseline '%s': %s", name, e)
            return None

    def create_baseline(self, run: TTFARun, name: str) -> Optional[TTFABaseline]:
        """
        Create a baseline from a completed test run.

        Computes per-scenario median and P99 from the run results.
        """
        # Sanitize name to prevent path traversal
        if "/" in name or "\\" in name or ".." in name:
            logger.error("Invalid baseline name (path traversal rejected): %s", name)
            return None
        target = (self.baselines_dir / f"{name}.json").resolve()
        if not target.is_relative_to(self.baselines_dir.resolve()):
            logger.error("Baseline path escapes baselines directory: %s", target)
            return None

        # Group results by scenario
        scenario_results: Dict[str, List[float]] = {}
        scenario_paths: Dict[str, str] = {}
        for result in run.results:
            if result.ttfa_ms is not None:
                scenario_results.setdefault(result.scenario_id, []).append(
                    result.ttfa_ms
                )
                scenario_paths[result.scenario_id] = result.audio_path.value

        # Compute per-scenario metrics
        scenario_metrics: Dict[str, ScenarioBaseline] = {}
        for scenario_id, values in scenario_results.items():
            sorted_values = sorted(values)
            n = len(sorted_values)
            median = statistics.median(sorted_values) if n > 0 else 0.0
            p99 = sorted_values[int(n * 0.99)] if n > 0 else 0.0
            scenario_metrics[scenario_id] = ScenarioBaseline(
                median_ttfa_ms=median,
                p99_ttfa_ms=p99,
                audio_path=scenario_paths.get(scenario_id, "streaming"),
            )

        baseline = TTFABaseline(
            id=f"bl_{uuid.uuid4().hex[:8]}",
            name=name,
            created_at=datetime.now(),
            run_id=run.id,
            scenario_metrics=scenario_metrics,
        )

        # Save to file
        path = self.baselines_dir / f"{name}.json"
        path.write_text(json.dumps(baseline.to_dict(), indent=2))
        logger.info(
            "Saved baseline '%s' to %s (%d scenarios)",
            name,
            path,
            len(scenario_metrics),
        )

        return baseline

    def check_regression(
        self,
        run: TTFARun,
        baseline: TTFABaseline,
    ) -> List[TTFARegression]:
        """
        Compare a test run against a baseline and detect regressions.

        Returns a list of detected regressions (empty if no regressions).
        """
        regressions: List[TTFARegression] = []

        # Group current results by scenario
        current_medians: Dict[str, float] = {}
        current_p99s: Dict[str, float] = {}
        scenario_results: Dict[str, List[float]] = {}
        for result in run.results:
            if result.ttfa_ms is not None:
                scenario_results.setdefault(result.scenario_id, []).append(
                    result.ttfa_ms
                )

        for scenario_id, values in scenario_results.items():
            sorted_values = sorted(values)
            n = len(sorted_values)
            current_medians[scenario_id] = (
                statistics.median(sorted_values) if n > 0 else 0.0
            )
            current_p99s[scenario_id] = sorted_values[int(n * 0.99)] if n > 0 else 0.0

        # Compare against baseline
        for scenario_id, bl_metrics in baseline.scenario_metrics.items():
            # Check median regression
            if scenario_id in current_medians and bl_metrics.median_ttfa_ms > 0:
                current = current_medians[scenario_id]
                baseline_val = bl_metrics.median_ttfa_ms
                change = (current - baseline_val) / baseline_val

                if change > MINOR_THRESHOLD:
                    severity = RegressionSeverity.MINOR
                    if change > SEVERE_THRESHOLD:
                        severity = RegressionSeverity.SEVERE
                    elif change > MODERATE_THRESHOLD:
                        severity = RegressionSeverity.MODERATE

                    regressions.append(
                        TTFARegression(
                            scenario_id=scenario_id,
                            metric="median",
                            baseline_value=baseline_val,
                            current_value=current,
                            change_percent=change * 100,
                            severity=severity,
                        )
                    )

            # Check P99 regression
            if scenario_id in current_p99s and bl_metrics.p99_ttfa_ms > 0:
                current = current_p99s[scenario_id]
                baseline_val = bl_metrics.p99_ttfa_ms
                change = (current - baseline_val) / baseline_val

                if change > MINOR_THRESHOLD:
                    severity = RegressionSeverity.MINOR
                    if change > SEVERE_THRESHOLD:
                        severity = RegressionSeverity.SEVERE
                    elif change > MODERATE_THRESHOLD:
                        severity = RegressionSeverity.MODERATE

                    regressions.append(
                        TTFARegression(
                            scenario_id=scenario_id,
                            metric="p99",
                            baseline_value=baseline_val,
                            current_value=current,
                            change_percent=change * 100,
                            severity=severity,
                        )
                    )

            # Absolute ceiling check (always a regression regardless of baseline)
            if (
                scenario_id in current_medians
                and current_medians[scenario_id] > ABSOLUTE_CEILING_MS
            ):
                # Only add if not already flagged
                existing = [
                    r
                    for r in regressions
                    if r.scenario_id == scenario_id and r.metric == "median"
                ]
                if not existing:
                    regressions.append(
                        TTFARegression(
                            scenario_id=scenario_id,
                            metric="median",
                            baseline_value=bl_metrics.median_ttfa_ms,
                            current_value=current_medians[scenario_id],
                            change_percent=0.0,
                            severity=RegressionSeverity.SEVERE,
                        )
                    )

        return regressions
