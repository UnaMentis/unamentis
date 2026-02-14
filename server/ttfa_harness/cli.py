"""
UnaMentis TTFA Harness - CLI Entry Point

Run TTFA performance tests from the command line.

Usage:
    python -m ttfa_harness.cli --list-scenarios
    python -m ttfa_harness.cli --suite quick
    python -m ttfa_harness.cli --suite full --create-baseline initial
    python -m ttfa_harness.cli --suite quick --baseline main --fail-on-regression
"""

import argparse
import asyncio
import json
import logging
import sys
import time
from pathlib import Path
from typing import List, Optional

from .baselines import BaselineManager
from .models import (
    AudioPath,
    TTFAEvent,
    TTFAEventType,
    TTFARun,
    TTFAResult,
    TTFAScenario,
    SUITES,
    get_predefined_scenarios,
)
from .parser import events_to_result, parse_log_line
from .simulator import Simulator, SimulatorError

logger = logging.getLogger("ttfa_harness.cli")

# ANSI colors for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"
DIM = "\033[2m"


def setup_logging(verbose: bool = False) -> None:
    """Configure logging for the CLI."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
        datefmt="%H:%M:%S",
    )


# ------------------------------------------------------------------
# Test Runner
# ------------------------------------------------------------------


async def run_scenario(
    sim: Simulator,
    scenario: TTFAScenario,
    repetition: int,
    log_proc: asyncio.subprocess.Process,
    all_events: List[TTFAEvent],
    timeout: float = 15.0,
) -> TTFAResult:
    """
    Execute a single scenario repetition and capture TTFA events.

    1. Execute setup steps (deep links, waits)
    2. Execute trigger action (if any)
    3. Wait for TTFA events from the log stream
    4. Parse events into a result
    """
    logger.info(
        "Running scenario '%s' (rep %d/%d)",
        scenario.name,
        repetition,
        scenario.repetitions,
    )

    # Execute setup steps
    for step in scenario.setup_steps:
        if step.url:
            await sim.open_url(step.url)
        elif step.seconds:
            await asyncio.sleep(step.seconds)
        elif step.x is not None and step.y is not None:
            await sim.tap(step.x, step.y)

    # Execute trigger action
    if scenario.trigger_action:
        action = scenario.trigger_action
        if action.url:
            await sim.open_url(action.url)
        elif action.x is not None and action.y is not None:
            await sim.tap(action.x, action.y)

    # Collect events from log stream for this scenario
    start_time = time.monotonic()
    scenario_events: List[TTFAEvent] = []

    # Read log lines until we see AUDIO_PLAYING or timeout
    if log_proc.stdout:
        while time.monotonic() - start_time < timeout:
            try:
                line_bytes = await asyncio.wait_for(
                    log_proc.stdout.readline(),
                    timeout=1.0,
                )
                if not line_bytes:
                    break  # EOF: log stream process ended
                line = line_bytes.decode("utf-8", errors="replace").strip()
                if not line:
                    continue

                event = parse_log_line(line)
                if event:
                    all_events.append(event)
                    if event.feature_id == scenario.feature_id:
                        scenario_events.append(event)
                        logger.debug(
                            "  %s: %.2fms %s",
                            event.event_type.value,
                            event.elapsed_ms,
                            event.metadata,
                        )
                        # Stop collecting after AUDIO_PLAYING or ERROR
                        if event.event_type in (
                            TTFAEventType.AUDIO_PLAYING,
                            TTFAEventType.ERROR,
                        ):
                            break
            except asyncio.TimeoutError:
                continue

    # Convert events to result
    if scenario_events:
        result = events_to_result(
            scenario_events,
            scenario_id=scenario.id,
            scenario_name=scenario.name,
            audio_path=scenario.audio_path,
            repetition=repetition,
        )
    else:
        result = TTFAResult(
            scenario_id=scenario.id,
            scenario_name=scenario.name,
            audio_path=scenario.audio_path,
            repetition=repetition,
            errors=["No TTFA events captured within timeout"],
        )

    return result


async def run_suite(
    scenario_ids: List[str],
    device_name: str,
    app_path: Optional[str],
    repetitions: Optional[int],
) -> TTFARun:
    """Run a suite of TTFA scenarios and return the results."""
    all_scenarios = get_predefined_scenarios()
    scenarios = [all_scenarios[sid] for sid in scenario_ids if sid in all_scenarios]

    if not scenarios:
        logger.error("No valid scenarios found in: %s", scenario_ids)
        return TTFARun()

    sim = Simulator(device_name=device_name)
    run = TTFARun(device=device_name)
    all_events: List[TTFAEvent] = []
    log_proc: Optional[asyncio.subprocess.Process] = None

    try:
        # Boot simulator
        await sim.boot()

        # Install app if path provided
        if app_path:
            await sim.install_app(app_path)

        # Launch app
        await sim.launch_app()

        # Start log stream
        log_proc = await sim.start_log_stream()

        # Give log stream a moment to stabilize
        await asyncio.sleep(1.0)

        # Run each scenario
        for scenario in scenarios:
            reps = repetitions if repetitions is not None else scenario.repetitions
            for rep in range(1, reps + 1):
                result = await run_scenario(
                    sim=sim,
                    scenario=scenario,
                    repetition=rep,
                    log_proc=log_proc,
                    all_events=all_events,
                )
                run.results.append(result)

                # Brief pause between repetitions
                await asyncio.sleep(1.0)

            # Brief pause between scenarios
            await asyncio.sleep(2.0)

    except SimulatorError as e:
        logger.error("Simulator error: %s", e)
        run.results.append(
            TTFAResult(
                scenario_id="setup",
                scenario_name="Setup",
                audio_path=AudioPath.STREAMING,
                repetition=0,
                errors=[str(e)],
            )
        )
    finally:
        # Always clean up log_proc and app
        if log_proc is not None and log_proc.returncode is None:
            log_proc.terminate()
        await sim.terminate_app()

    run.compute_summary()
    return run


# ------------------------------------------------------------------
# Reporting
# ------------------------------------------------------------------


def print_results_text(run: TTFARun, regressions: Optional[List] = None) -> None:
    """Print results as a formatted text table."""
    print(f"\n{BOLD}TTFA Performance Test Results{RESET}")
    print("=" * 65)
    print(f"Target: < 1000ms | Device: {run.device} | Run: {run.id}")
    print()

    # Group results by scenario and compute medians
    scenario_data: dict = {}
    for r in run.results:
        key = r.scenario_id
        if key not in scenario_data:
            scenario_data[key] = {
                "name": r.scenario_name,
                "path": r.audio_path.value,
                "values": [],
                "errors": [],
            }
        if r.ttfa_ms is not None:
            scenario_data[key]["values"].append(r.ttfa_ms)
        scenario_data[key]["errors"].extend(r.errors)

    # Print header
    print(f"{'Scenario':<32} {'Path':<11} {'Median':>8} {'P99':>8} {'Status':>8}")
    print("-" * 65)

    for sid, data in scenario_data.items():
        values = sorted(data["values"])
        n = len(values)
        if n == 0:
            median_str = "ERR"
            p99_str = "ERR"
            status = f"{RED}ERROR{RESET}"
        else:
            median = values[n // 2]
            p99 = values[int(n * 0.99)]
            median_str = f"{median:.0f}ms"
            p99_str = f"{p99:.0f}ms"
            if median < 1000:
                status = f"{GREEN}PASS{RESET}"
            else:
                status = f"{RED}FAIL{RESET}"

        print(
            f"{data['name']:<32} {data['path']:<11} {median_str:>8} {p99_str:>8} {status:>16}"
        )

    print()
    s = run.summary
    overall = f"{GREEN}PASS{RESET}" if s.all_pass_target else f"{RED}FAIL{RESET}"
    print(
        f"Overall: {s.passed_scenarios}/{s.total_scenarios} {overall} | "
        f"Median: {s.median_ttfa_ms:.0f}ms | P99: {s.p99_ttfa_ms:.0f}ms"
    )

    if regressions:
        print(f"\n{YELLOW}Regressions detected:{RESET}")
        for reg in regressions:
            severity_color = RED if reg.severity.value == "severe" else YELLOW
            print(
                f"  {severity_color}{reg.severity.value.upper()}{RESET}: "
                f"{reg.scenario_id} ({reg.metric}) "
                f"{reg.baseline_value:.0f}ms -> {reg.current_value:.0f}ms "
                f"(+{reg.change_percent:.1f}%)"
            )
    elif regressions is not None:
        print(f"\n{GREEN}Baseline comparison: No regressions detected{RESET}")

    print()


def print_results_json(run: TTFARun, regressions: Optional[List] = None) -> None:
    """Print results as JSON."""
    output = run.to_dict()
    if regressions is not None:
        output["regressions"] = [r.to_dict() for r in regressions]
    print(json.dumps(output, indent=2, default=str))


def print_results_markdown(run: TTFARun, regressions: Optional[List] = None) -> None:
    """Print results as Markdown (for PR comments)."""
    print("## TTFA Performance Test Results\n")
    print(f"**Target**: < 1000ms | **Device**: {run.device}\n")

    # Group and compute medians
    scenario_data: dict = {}
    for r in run.results:
        key = r.scenario_id
        if key not in scenario_data:
            scenario_data[key] = {
                "name": r.scenario_name,
                "path": r.audio_path.value,
                "values": [],
            }
        if r.ttfa_ms is not None:
            scenario_data[key]["values"].append(r.ttfa_ms)

    print("| Scenario | Path | Median | P99 | Status |")
    print("|----------|------|--------|-----|--------|")

    for sid, data in scenario_data.items():
        values = sorted(data["values"])
        n = len(values)
        if n == 0:
            print(f"| {data['name']} | {data['path']} | ERR | ERR | ERROR |")
        else:
            median = values[n // 2]
            p99 = values[int(n * 0.99)]
            status = "PASS" if median < 1000 else "FAIL"
            print(
                f"| {data['name']} | {data['path']} | {median:.0f}ms | {p99:.0f}ms | {status} |"
            )

    s = run.summary
    overall = "PASS" if s.all_pass_target else "FAIL"
    print(
        f"\n**Overall**: {s.passed_scenarios}/{s.total_scenarios} {overall} | Median: {s.median_ttfa_ms:.0f}ms | P99: {s.p99_ttfa_ms:.0f}ms"
    )

    if regressions:
        print("\n### Regressions\n")
        for reg in regressions:
            print(
                f"- **{reg.severity.value.upper()}**: {reg.scenario_id} ({reg.metric}) "
                f"{reg.baseline_value:.0f}ms -> {reg.current_value:.0f}ms (+{reg.change_percent:.1f}%)"
            )


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI argument parser."""
    parser = argparse.ArgumentParser(
        prog="ttfa_harness",
        description="UnaMentis TTFA (Time To First Audio) Performance Test Harness",
    )

    # Mode selection
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--list-scenarios", action="store_true", help="List available test scenarios"
    )
    mode.add_argument(
        "--list-baselines", action="store_true", help="List saved baselines"
    )
    mode.add_argument(
        "--suite", choices=list(SUITES.keys()), help="Run a predefined test suite"
    )
    mode.add_argument("--scenario", help="Run a single scenario by ID")

    # Run configuration
    parser.add_argument(
        "--repetitions", type=int, help="Override repetition count per scenario"
    )
    parser.add_argument(
        "--device", default="iPhone 16 Pro", help="Simulator device name"
    )
    parser.add_argument("--app-path", help="Path to built .app bundle to install")

    # Baseline management
    parser.add_argument("--baseline", help="Compare against a named baseline")
    parser.add_argument(
        "--create-baseline", metavar="NAME", help="Save current run as a named baseline"
    )
    parser.add_argument(
        "--fail-on-regression", action="store_true", help="Exit code 1 on regression"
    )

    # Output
    parser.add_argument(
        "--format",
        choices=["text", "json", "markdown"],
        default="text",
        help="Output format",
    )
    parser.add_argument(
        "--output", help="Write results to file (in addition to stdout)"
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")

    return parser


def main() -> int:
    """CLI entry point. Returns exit code."""
    parser = build_parser()
    args = parser.parse_args()
    setup_logging(args.verbose)

    # List scenarios
    if args.list_scenarios:
        scenarios = get_predefined_scenarios()
        print(f"\n{BOLD}Available TTFA Scenarios{RESET}\n")
        for sid, s in scenarios.items():
            print(f"  {CYAN}{sid:<25}{RESET} {s.name}")
            print(f"  {'':25} Feature: {s.feature_id} | Path: {s.audio_path.value}")
            if s.description:
                print(f"  {'':25} {DIM}{s.description}{RESET}")
            print()
        print(f"{BOLD}Suites:{RESET}")
        for suite_name, ids in SUITES.items():
            print(f"  {suite_name}: {', '.join(ids)}")
        print()
        return 0

    # List baselines
    if args.list_baselines:
        manager = BaselineManager()
        baselines = manager.list_baselines()
        if not baselines:
            print("No baselines saved yet.")
            return 0
        print(f"\n{BOLD}Saved Baselines{RESET}\n")
        for bl in baselines:
            print(
                f"  {CYAN}{bl.name:<20}{RESET} Created: {bl.created_at:%Y-%m-%d %H:%M} | Scenarios: {len(bl.scenario_metrics)}"
            )
        print()
        return 0

    # Determine scenarios to run
    scenario_ids: List[str] = []
    if args.suite:
        scenario_ids = SUITES[args.suite]
    elif args.scenario:
        scenario_ids = [args.scenario]
    else:
        parser.print_help()
        return 0

    # Run tests
    run = asyncio.run(
        run_suite(
            scenario_ids=scenario_ids,
            device_name=args.device,
            app_path=args.app_path,
            repetitions=args.repetitions,
        )
    )

    # Baseline comparison
    regressions = None
    baseline_manager = BaselineManager()
    if args.baseline:
        baseline = baseline_manager.load_baseline(args.baseline)
        if baseline:
            regressions = baseline_manager.check_regression(run, baseline)
        else:
            logger.warning(
                "Baseline '%s' not found, skipping comparison", args.baseline
            )

    # Print results
    if args.format == "json":
        print_results_json(run, regressions)
    elif args.format == "markdown":
        print_results_markdown(run, regressions)
    else:
        print_results_text(run, regressions)

    # Save results to file
    if args.output:
        output_path = Path(args.output)
        output_path.write_text(json.dumps(run.to_dict(), indent=2, default=str))
        logger.info("Results written to %s", output_path)

    # Create baseline if requested
    if args.create_baseline:
        baseline_manager.create_baseline(run, args.create_baseline)
        print(f"{GREEN}Baseline '{args.create_baseline}' saved.{RESET}")

    # Determine exit code
    if args.fail_on_regression and regressions:
        logger.error("Regressions detected, failing")
        return 1
    if not run.summary.all_pass_target:
        logger.error("Some scenarios exceeded the 1000ms target")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
