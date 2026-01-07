"""
UnaMentis Latency Test Harness - Results Analyzer

Statistical analysis and reporting for test results.
"""

import statistics
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Optional

from .models import (
    TestResult,
    TestRun,
    AnalysisReport,
    SummaryStatistics,
    RankedConfiguration,
    LatencyBreakdown,
    NetworkMeetsTarget,
    NetworkProjection,
    Regression,
    RegressionSeverity,
    NetworkProfile,
)


def percentile(data: List[float], p: int) -> float:
    """Calculate the p-th percentile of a list."""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    k = (len(sorted_data) - 1) * p / 100
    f = int(k)
    c = f + 1 if f + 1 < len(sorted_data) else f
    return sorted_data[f] + (k - f) * (sorted_data[c] - sorted_data[f])


class ResultsAnalyzer:
    """
    Analyzes latency test results and generates insights.

    Features:
    - Per-configuration statistics (median, P99, stddev)
    - Network-adjusted projections
    - Configuration ranking
    - Regression detection against baselines
    - Recommendations generation
    """

    def __init__(self, baselines: Optional[Dict[str, Dict[str, float]]] = None):
        """
        Initialize the analyzer.

        Args:
            baselines: Optional dict of config_id -> {metric: value} for regression detection
        """
        self.baselines = baselines or {}

    def analyze(self, run: TestRun) -> AnalysisReport:
        """
        Analyze a test run and generate a comprehensive report.

        Args:
            run: The test run to analyze

        Returns:
            AnalysisReport with statistics, rankings, and recommendations
        """
        results = run.results

        # Filter to successful results
        successful_results = [r for r in results if r.is_success]

        if not successful_results:
            return self._empty_report(run.id)

        # Compute statistics
        summary = self._compute_summary(run, successful_results)
        ranked_configs = self._rank_configurations(successful_results)
        network_projections = self._compute_network_projections(successful_results)
        regressions = self._detect_regressions(successful_results)
        recommendations = self._generate_recommendations(
            ranked_configs, network_projections, regressions
        )

        return AnalysisReport(
            run_id=run.id,
            generated_at=datetime.now(),
            summary=summary,
            best_configurations=ranked_configs,
            network_projections=network_projections,
            regressions=regressions,
            recommendations=recommendations,
        )

    def _compute_summary(
        self, run: TestRun, results: List[TestResult]
    ) -> SummaryStatistics:
        """Compute overall summary statistics."""
        e2e_latencies = [r.e2e_latency_ms for r in results]
        stt_latencies = [r.stt_latency_ms for r in results if r.stt_latency_ms]
        llm_ttfb = [r.llm_ttfb_ms for r in results]
        llm_completion = [r.llm_completion_ms for r in results]
        tts_ttfb = [r.tts_ttfb_ms for r in results]
        tts_completion = [r.tts_completion_ms for r in results]

        # Group by config to count unique configurations
        by_config = defaultdict(list)
        for r in results:
            by_config[r.config_id].append(r)

        return SummaryStatistics(
            total_configurations=len(by_config),
            total_tests=len(run.results),
            successful_tests=len(results),
            failed_tests=len(run.results) - len(results),
            overall_median_e2e_ms=statistics.median(e2e_latencies),
            overall_p99_e2e_ms=percentile(e2e_latencies, 99),
            overall_min_e2e_ms=min(e2e_latencies),
            overall_max_e2e_ms=max(e2e_latencies),
            median_stt_ms=statistics.median(stt_latencies) if stt_latencies else None,
            median_llm_ttfb_ms=statistics.median(llm_ttfb),
            median_llm_completion_ms=statistics.median(llm_completion),
            median_tts_ttfb_ms=statistics.median(tts_ttfb),
            median_tts_completion_ms=statistics.median(tts_completion),
            test_duration_minutes=run.elapsed_time / 60,
        )

    def _rank_configurations(
        self, results: List[TestResult]
    ) -> List[RankedConfiguration]:
        """Rank configurations by E2E latency performance."""
        # Group by config
        by_config: Dict[str, List[TestResult]] = defaultdict(list)
        for r in results:
            by_config[r.config_id].append(r)

        ranked = []
        for config_id, config_results in by_config.items():
            e2e = [r.e2e_latency_ms for r in config_results]
            stt = [r.stt_latency_ms for r in config_results if r.stt_latency_ms]
            llm_ttfb = [r.llm_ttfb_ms for r in config_results]
            llm_completion = [r.llm_completion_ms for r in config_results]
            tts_ttfb = [r.tts_ttfb_ms for r in config_results]
            tts_completion = [r.tts_completion_ms for r in config_results]

            breakdown = LatencyBreakdown(
                stt_ms=statistics.median(stt) if stt else None,
                llm_ttfb_ms=statistics.median(llm_ttfb),
                llm_completion_ms=statistics.median(llm_completion),
                tts_ttfb_ms=statistics.median(tts_ttfb),
                tts_completion_ms=statistics.median(tts_completion),
            )

            # Calculate network projections for this config
            network_projections = {}
            first_result = config_results[0]

            # Determine which stages require network
            stt_requires = first_result.stt_config and first_result.stt_config.get(
                "provider"
            ) not in ["apple", "glm-asr-ondevice", "web-speech"]
            llm_requires = first_result.llm_config and first_result.llm_config.get(
                "provider"
            ) not in ["mlx"]
            tts_requires = first_result.tts_config and first_result.tts_config.get(
                "provider"
            ) not in ["apple", "web-speech"]

            median_e2e = statistics.median(e2e)

            for profile in NetworkProfile:
                projected = median_e2e
                if stt_requires:
                    projected += profile.added_latency_ms
                if llm_requires:
                    projected += profile.added_latency_ms
                if tts_requires:
                    projected += profile.added_latency_ms

                network_projections[profile.value] = NetworkMeetsTarget(
                    e2e_ms=projected,
                    meets_500ms=projected < 500,
                    meets_1000ms=projected < 1000,
                )

            # Estimate cost (placeholder - would use actual provider costs)
            estimated_cost = self._estimate_cost(first_result)

            ranked.append(
                RankedConfiguration(
                    rank=0,  # Will be set after sorting
                    config_id=config_id,
                    median_e2e_ms=median_e2e,
                    p99_e2e_ms=percentile(e2e, 99),
                    stddev_ms=statistics.stdev(e2e) if len(e2e) > 1 else 0,
                    sample_count=len(config_results),
                    breakdown=breakdown,
                    network_projections=network_projections,
                    estimated_cost_per_hour=estimated_cost,
                )
            )

        # Sort by median E2E (lower is better)
        ranked.sort(key=lambda x: x.median_e2e_ms)

        # Assign ranks
        for i, config in enumerate(ranked):
            ranked[i] = RankedConfiguration(
                rank=i + 1,
                config_id=config.config_id,
                median_e2e_ms=config.median_e2e_ms,
                p99_e2e_ms=config.p99_e2e_ms,
                stddev_ms=config.stddev_ms,
                sample_count=config.sample_count,
                breakdown=config.breakdown,
                network_projections=config.network_projections,
                estimated_cost_per_hour=config.estimated_cost_per_hour,
            )

        return ranked

    def _compute_network_projections(
        self, results: List[TestResult]
    ) -> List[NetworkProjection]:
        """Compute aggregate network projections."""
        # Group by config for unique configs count
        by_config: Dict[str, List[TestResult]] = defaultdict(list)
        for r in results:
            by_config[r.config_id].append(r)

        total_configs = len(by_config)

        projections = []
        for profile in NetworkProfile:
            # Collect projected E2E for this network profile
            projected_values = []

            for r in results:
                if r.network_projections and profile.value in r.network_projections:
                    projected_values.append(r.network_projections[profile.value])
                else:
                    # Calculate on the fly
                    projected = r.e2e_latency_ms

                    stt_requires = r.stt_config and r.stt_config.get(
                        "provider"
                    ) not in ["apple", "glm-asr-ondevice", "web-speech"]
                    llm_requires = r.llm_config and r.llm_config.get(
                        "provider"
                    ) not in ["mlx"]
                    tts_requires = r.tts_config and r.tts_config.get(
                        "provider"
                    ) not in ["apple", "web-speech"]

                    if stt_requires:
                        projected += profile.added_latency_ms
                    if llm_requires:
                        projected += profile.added_latency_ms
                    if tts_requires:
                        projected += profile.added_latency_ms

                    projected_values.append(projected)

            if not projected_values:
                continue

            median_projected = statistics.median(projected_values)
            configs_meeting = sum(1 for v in projected_values if v < 500)

            projections.append(
                NetworkProjection(
                    network=profile.value,
                    added_latency_ms=profile.added_latency_ms,
                    projected_median_ms=median_projected,
                    projected_p99_ms=percentile(projected_values, 99),
                    meets_target=median_projected < 500,
                    configs_meeting_target=configs_meeting,
                    total_configs=total_configs,
                )
            )

        return projections

    def _detect_regressions(self, results: List[TestResult]) -> List[Regression]:
        """Detect regressions against baselines."""
        if not self.baselines:
            return []

        regressions = []

        # Group by config
        by_config: Dict[str, List[TestResult]] = defaultdict(list)
        for r in results:
            by_config[r.config_id].append(r)

        for config_id, config_results in by_config.items():
            if config_id not in self.baselines:
                continue

            baseline = self.baselines[config_id]

            # Check E2E latency
            if "e2e_median_ms" in baseline:
                current_median = statistics.median(
                    [r.e2e_latency_ms for r in config_results]
                )
                baseline_value = baseline["e2e_median_ms"]

                change_percent = (
                    (current_median - baseline_value) / baseline_value * 100
                )

                if change_percent > 10:  # More than 10% regression
                    severity = RegressionSeverity.MINOR
                    if change_percent > 50:
                        severity = RegressionSeverity.SEVERE
                    elif change_percent > 20:
                        severity = RegressionSeverity.MODERATE

                    regressions.append(
                        Regression(
                            config_id=config_id,
                            metric="e2e_median_ms",
                            baseline_value=baseline_value,
                            current_value=current_median,
                            change_percent=change_percent,
                            severity=severity,
                        )
                    )

        return regressions

    def _generate_recommendations(
        self,
        ranked_configs: List[RankedConfiguration],
        network_projections: List[NetworkProjection],
        regressions: List[Regression],
    ) -> List[str]:
        """Generate actionable recommendations."""
        recommendations = []

        if not ranked_configs:
            recommendations.append("No successful test results to analyze")
            return recommendations

        # Best configuration
        best = ranked_configs[0]
        recommendations.append(
            f"Best configuration: {best.config_id} with "
            f"{best.median_e2e_ms:.0f}ms median E2E latency"
        )

        # Target achievement
        localhost_projection = next(
            (p for p in network_projections if p.network == "localhost"), None
        )
        if localhost_projection and localhost_projection.meets_target:
            recommendations.append(
                "Target of <500ms median E2E achieved on localhost"
            )

        # Network analysis
        cellular_projection = next(
            (p for p in network_projections if p.network == "cellular_us"), None
        )
        if cellular_projection:
            if cellular_projection.meets_target:
                recommendations.append(
                    f"Target achieved on cellular network "
                    f"({cellular_projection.projected_median_ms:.0f}ms projected)"
                )
            else:
                gap = cellular_projection.projected_median_ms - 500
                recommendations.append(
                    f"Cellular network exceeds target by {gap:.0f}ms - "
                    f"consider on-device providers to reduce network hops"
                )

        # Self-hosted vs cloud comparison
        self_hosted_configs = [
            c for c in ranked_configs
            if "selfhosted" in c.config_id or "mlx" in c.config_id
        ]
        cloud_configs = [
            c for c in ranked_configs
            if c not in self_hosted_configs
        ]

        if self_hosted_configs and cloud_configs:
            best_self_hosted = min(self_hosted_configs, key=lambda x: x.median_e2e_ms)
            best_cloud = min(cloud_configs, key=lambda x: x.median_e2e_ms)

            if best_self_hosted.median_e2e_ms < best_cloud.median_e2e_ms:
                savings = best_cloud.median_e2e_ms - best_self_hosted.median_e2e_ms
                recommendations.append(
                    f"Self-hosted stack saves {savings:.0f}ms vs best cloud option"
                )

        # Regressions
        if regressions:
            severe = [r for r in regressions if r.severity == RegressionSeverity.SEVERE]
            if severe:
                recommendations.append(
                    f"ALERT: {len(severe)} severe regressions detected - investigate immediately"
                )

        return recommendations

    def _estimate_cost(self, result: TestResult) -> float:
        """Estimate hourly cost for a configuration."""
        # Placeholder - would use actual provider costs
        cost = 0.0

        if result.llm_config:
            provider = result.llm_config.get("provider", "")
            if provider == "anthropic":
                cost += 0.50  # Rough estimate per hour
            elif provider == "openai":
                cost += 0.40
            # Self-hosted and MLX are free

        if result.stt_config:
            provider = result.stt_config.get("provider", "")
            if provider == "deepgram":
                cost += 0.26
            elif provider == "assemblyai":
                cost += 0.37
            # Apple and on-device are free

        if result.tts_config:
            provider = result.tts_config.get("provider", "")
            if provider in ["elevenlabs-flash", "elevenlabs-turbo"]:
                cost += 0.30
            # Chatterbox, Piper, VibeVoice are self-hosted (free)

        return cost

    def _empty_report(self, run_id: str) -> AnalysisReport:
        """Return an empty report when no results are available."""
        return AnalysisReport(
            run_id=run_id,
            generated_at=datetime.now(),
            summary=SummaryStatistics(
                total_configurations=0,
                total_tests=0,
                successful_tests=0,
                failed_tests=0,
                overall_median_e2e_ms=0,
                overall_p99_e2e_ms=0,
                overall_min_e2e_ms=0,
                overall_max_e2e_ms=0,
                median_stt_ms=None,
                median_llm_ttfb_ms=0,
                median_llm_completion_ms=0,
                median_tts_ttfb_ms=0,
                median_tts_completion_ms=0,
                test_duration_minutes=0,
            ),
            best_configurations=[],
            network_projections=[],
            regressions=[],
            recommendations=["No successful test results to analyze"],
        )

    def compare_runs(
        self, run1: TestRun, run2: TestRun
    ) -> Dict[str, any]:
        """
        Compare two test runs.

        Returns a comparison summary highlighting:
        - Performance changes by configuration
        - New/removed configurations
        - Statistical significance of changes
        """
        report1 = self.analyze(run1)
        report2 = self.analyze(run2)

        # Find common configurations
        configs1 = {c.config_id for c in report1.best_configurations}
        configs2 = {c.config_id for c in report2.best_configurations}

        common = configs1 & configs2
        added = configs2 - configs1
        removed = configs1 - configs2

        # Compare common configurations
        changes = []
        for config_id in common:
            cfg1 = next(c for c in report1.best_configurations if c.config_id == config_id)
            cfg2 = next(c for c in report2.best_configurations if c.config_id == config_id)

            change_pct = (cfg2.median_e2e_ms - cfg1.median_e2e_ms) / cfg1.median_e2e_ms * 100

            changes.append({
                "config_id": config_id,
                "run1_median_ms": cfg1.median_e2e_ms,
                "run2_median_ms": cfg2.median_e2e_ms,
                "change_percent": change_pct,
                "improved": change_pct < -5,
                "regressed": change_pct > 5,
            })

        return {
            "run1_id": run1.id,
            "run2_id": run2.id,
            "common_configurations": len(common),
            "added_configurations": list(added),
            "removed_configurations": list(removed),
            "changes": sorted(changes, key=lambda x: x["change_percent"]),
            "summary": {
                "run1_overall_median": report1.summary.overall_median_e2e_ms,
                "run2_overall_median": report2.summary.overall_median_e2e_ms,
                "overall_change_percent": (
                    (report2.summary.overall_median_e2e_ms - report1.summary.overall_median_e2e_ms)
                    / report1.summary.overall_median_e2e_ms * 100
                    if report1.summary.overall_median_e2e_ms > 0 else 0
                ),
            },
        }
