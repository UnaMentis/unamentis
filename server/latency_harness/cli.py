#!/usr/bin/env python3
"""
Latency Test Harness CLI

Command-line tool for running latency tests in CI/CD or local development.

Usage:
    # Run quick validation (CI mode)
    python -m latency_harness.cli --suite quick_validation --timeout 120

    # Run with mock client (no real test execution)
    python -m latency_harness.cli --suite quick_validation --mock

    # List available suites
    python -m latency_harness.cli --list-suites

    # Check for regressions against baseline
    python -m latency_harness.cli --suite quick_validation --baseline baseline_id --regression-threshold 0.2
"""

import argparse
import asyncio
import json
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from latency_harness.orchestrator import LatencyTestOrchestrator
from latency_harness.storage import FileBasedLatencyStorage, create_latency_storage
from latency_harness.analyzer import ResultsAnalyzer
from latency_harness.models import (
    ClientType,
    ClientCapabilities,
    RunStatus,
    create_quick_validation_suite,
    create_provider_comparison_suite,
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class LatencyTestCLI:
    """CLI runner for latency tests."""

    def __init__(self, data_dir: Optional[Path] = None):
        self.data_dir = data_dir or Path(__file__).parent.parent / "data" / "latency_harness"
        self.storage: Optional[FileBasedLatencyStorage] = None
        self.orchestrator: Optional[LatencyTestOrchestrator] = None

    async def initialize(self):
        """Initialize storage and orchestrator."""
        self.storage = create_latency_storage(storage_type="file", data_dir=self.data_dir)
        await self.storage.initialize()

        self.orchestrator = LatencyTestOrchestrator(storage=self.storage)
        await self.orchestrator.start()

        # Register default suites
        await self.orchestrator.register_suite(create_quick_validation_suite())
        await self.orchestrator.register_suite(create_provider_comparison_suite())

    async def shutdown(self):
        """Shutdown orchestrator."""
        if self.orchestrator:
            await self.orchestrator.stop()

    async def list_suites(self) -> list:
        """List available test suites."""
        return self.orchestrator.list_suites()

    async def run_test(
        self,
        suite_id: str,
        timeout: int = 300,
        use_mock: bool = True,
    ) -> dict:
        """
        Run a test suite and return results.

        Args:
            suite_id: ID of the test suite to run
            timeout: Maximum time to wait for test completion (seconds)
            use_mock: If True, use mock client (no real tests)

        Returns:
            dict with test results and analysis
        """
        suite = self.orchestrator.get_suite(suite_id)
        if not suite:
            raise ValueError(f"Suite not found: {suite_id}")

        # Register a mock client if needed
        if use_mock:
            capabilities = ClientCapabilities(
                supported_stt_providers=["deepgram", "assemblyai", "apple", "web-speech"],
                supported_llm_providers=["anthropic", "openai", "selfhosted"],
                supported_tts_providers=["chatterbox", "vibevoice", "apple", "web-speech"],
                has_high_precision_timing=True,
                has_device_metrics=True,
                has_on_device_ml=False,
                max_concurrent_tests=1,
            )
            await self.orchestrator.register_client(
                client_id="cli_mock_client",
                client_type=ClientType.IOS_SIMULATOR,
                capabilities=capabilities,
            )

        # Start the test run
        run = await self.orchestrator.start_test_run(suite_id=suite_id)
        logger.info(f"Started test run: {run.id}")

        # Wait for completion with timeout
        start_time = datetime.now()
        while run.status == RunStatus.RUNNING:
            elapsed = (datetime.now() - start_time).total_seconds()
            if elapsed > timeout:
                await self.orchestrator.cancel_run(run.id)
                raise TimeoutError(f"Test run timed out after {timeout} seconds")

            await asyncio.sleep(0.5)
            run = self.orchestrator.get_run(run.id)
            if run:
                logger.info(f"Progress: {run.completed_configurations}/{run.total_configurations} "
                           f"({run.progress_percent:.1f}%)")

        # Refresh run data
        run = self.orchestrator.get_run(run.id)

        if run.status == RunStatus.FAILED:
            raise RuntimeError(f"Test run failed: {run.id}")

        if run.status == RunStatus.CANCELLED:
            raise RuntimeError(f"Test run was cancelled: {run.id}")

        # Analyze results
        analyzer = ResultsAnalyzer()
        report = analyzer.analyze(run)

        return {
            "run_id": run.id,
            "suite_name": run.suite_name,
            "status": run.status.value,
            "total_configurations": run.total_configurations,
            "completed_configurations": run.completed_configurations,
            "elapsed_seconds": run.elapsed_time,
            "results_count": len(run.results),
            "summary": {
                "median_e2e_ms": report.summary.overall_median_e2e_ms,
                "p99_e2e_ms": report.summary.overall_p99_e2e_ms,
                "min_e2e_ms": report.summary.overall_min_e2e_ms,
                "max_e2e_ms": report.summary.overall_max_e2e_ms,
                "success_rate": (
                    report.summary.successful_tests / report.summary.total_tests * 100
                    if report.summary.total_tests > 0 else 0
                ),
            },
            "recommendations": report.recommendations,
        }

    async def check_regression(
        self,
        run_id: str,
        baseline_id: str,
        threshold: float = 0.2,
    ) -> dict:
        """
        Check for regressions against a baseline.

        Args:
            run_id: ID of the test run to check
            baseline_id: ID of the baseline to compare against
            threshold: Regression threshold (0.2 = 20%)

        Returns:
            dict with regression analysis
        """
        run = self.orchestrator.get_run(run_id)
        if not run:
            raise ValueError(f"Run not found: {run_id}")

        baseline = await self.storage.get_baseline(baseline_id)
        if not baseline:
            raise ValueError(f"Baseline not found: {baseline_id}")

        analyzer = ResultsAnalyzer()
        report = analyzer.analyze(run, baseline=baseline, regression_threshold=threshold)

        has_regressions = len(report.regressions) > 0
        severe_regressions = [r for r in report.regressions if r.severity.value == "severe"]

        return {
            "run_id": run_id,
            "baseline_id": baseline_id,
            "has_regressions": has_regressions,
            "regression_count": len(report.regressions),
            "severe_regression_count": len(severe_regressions),
            "regressions": [
                {
                    "config_id": r.config_id,
                    "metric": r.metric,
                    "baseline_value": r.baseline_value,
                    "current_value": r.current_value,
                    "change_percent": r.change_percent,
                    "severity": r.severity.value,
                }
                for r in report.regressions
            ],
            "pass": not has_regressions,
        }


async def main():
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Latency Test Harness CLI",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    parser.add_argument(
        "--suite",
        help="Test suite ID to run (e.g., quick_validation)",
    )
    parser.add_argument(
        "--list-suites",
        action="store_true",
        help="List available test suites",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="Test timeout in seconds (default: 300)",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        default=True,
        help="Use mock client (default: True)",
    )
    parser.add_argument(
        "--no-mock",
        action="store_true",
        help="Disable mock client - requires real test client",
    )
    parser.add_argument(
        "--baseline",
        help="Baseline ID for regression checking",
    )
    parser.add_argument(
        "--regression-threshold",
        type=float,
        default=0.2,
        help="Regression threshold (default: 0.2 = 20%%)",
    )
    parser.add_argument(
        "--output",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        help="Data directory for storage",
    )

    # CI-specific options
    parser.add_argument(
        "--ci",
        action="store_true",
        help="CI mode - exit with non-zero code on failure",
    )
    parser.add_argument(
        "--fail-on-regression",
        action="store_true",
        help="Exit with non-zero code if regressions detected",
    )

    args = parser.parse_args()

    # Initialize CLI
    cli = LatencyTestCLI(data_dir=args.data_dir)
    exit_code = 0

    try:
        await cli.initialize()

        if args.list_suites:
            # List available suites
            suites = await cli.list_suites()
            if args.output == "json":
                print(json.dumps([
                    {
                        "id": s.id,
                        "name": s.name,
                        "description": s.description,
                        "total_tests": s.total_test_count,
                    }
                    for s in suites
                ], indent=2))
            else:
                print("\nAvailable Test Suites:")
                print("-" * 60)
                for suite in suites:
                    print(f"  {suite.id}")
                    print(f"    Name: {suite.name}")
                    print(f"    Tests: {suite.total_test_count}")
                    print(f"    Description: {suite.description}")
                    print()

        elif args.suite:
            # Run test suite
            use_mock = args.mock and not args.no_mock
            result = await cli.run_test(
                suite_id=args.suite,
                timeout=args.timeout,
                use_mock=use_mock,
            )

            if args.output == "json":
                print(json.dumps(result, indent=2))
            else:
                print("\n" + "=" * 60)
                print(f"Test Run Complete: {result['run_id']}")
                print("=" * 60)
                print(f"Suite: {result['suite_name']}")
                print(f"Status: {result['status']}")
                print(f"Configurations: {result['completed_configurations']}/{result['total_configurations']}")
                print(f"Duration: {result['elapsed_seconds']:.1f}s")
                print()
                print("Latency Summary:")
                print(f"  Median E2E: {result['summary']['median_e2e_ms']:.1f}ms")
                print(f"  P99 E2E: {result['summary']['p99_e2e_ms']:.1f}ms")
                print(f"  Min E2E: {result['summary']['min_e2e_ms']:.1f}ms")
                print(f"  Max E2E: {result['summary']['max_e2e_ms']:.1f}ms")
                print(f"  Success Rate: {result['summary']['success_rate']:.1f}%")
                print()

                if result['recommendations']:
                    print("Recommendations:")
                    for rec in result['recommendations']:
                        print(f"  - {rec}")
                    print()

            # Check for regressions if baseline specified
            if args.baseline:
                regression_result = await cli.check_regression(
                    run_id=result['run_id'],
                    baseline_id=args.baseline,
                    threshold=args.regression_threshold,
                )

                if args.output == "json":
                    print(json.dumps(regression_result, indent=2))
                else:
                    print("\nRegression Analysis:")
                    print("-" * 40)
                    if regression_result['has_regressions']:
                        print(f"REGRESSIONS DETECTED: {regression_result['regression_count']}")
                        print(f"Severe: {regression_result['severe_regression_count']}")
                        for r in regression_result['regressions']:
                            print(f"  [{r['severity'].upper()}] {r['config_id']}: "
                                  f"{r['metric']} {r['change_percent']:+.1f}% "
                                  f"({r['baseline_value']:.1f}ms -> {r['current_value']:.1f}ms)")
                    else:
                        print("No regressions detected")
                    print()

                if args.fail_on_regression and regression_result['has_regressions']:
                    exit_code = 1

            # Check success rate for CI mode
            if args.ci and result['summary']['success_rate'] < 100:
                logger.warning(f"Success rate below 100%: {result['summary']['success_rate']:.1f}%")
                exit_code = 1

        else:
            parser.print_help()

    except TimeoutError as e:
        logger.error(f"Timeout: {e}")
        exit_code = 2
    except ValueError as e:
        logger.error(f"Error: {e}")
        exit_code = 1
    except Exception as e:
        logger.exception(f"Unexpected error: {e}")
        exit_code = 1
    finally:
        await cli.shutdown()

    sys.exit(exit_code)


if __name__ == "__main__":
    asyncio.run(main())
