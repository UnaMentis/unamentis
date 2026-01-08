"""
UnaMentis Latency Test Harness - REST API

Endpoints for managing latency tests, clients, and results.
"""

import json
import logging
import os
import statistics
import uuid
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, List

from aiohttp import web

# Import the harness components
import sys
sys.path.insert(0, str(Path(__file__).parent.parent / "latency_harness"))

from latency_harness.orchestrator import LatencyTestOrchestrator
from latency_harness.analyzer import ResultsAnalyzer
from latency_harness.storage import create_latency_storage, FileBasedLatencyStorage
from latency_harness.models import (
    TestSuiteDefinition,
    TestRun,
    TestResult,
    ClientType,
    ClientCapabilities,
    ClientStatus,
    RunStatus,
    NetworkProfile,
    PerformanceBaseline,
    BaselineMetrics,
    create_quick_validation_suite,
    create_provider_comparison_suite,
)

logger = logging.getLogger(__name__)

# Global orchestrator and storage instances
_orchestrator: Optional[LatencyTestOrchestrator] = None
_storage: Optional[FileBasedLatencyStorage] = None

# WebSocket connections for latency harness
_latency_websockets: set = set()


def get_orchestrator() -> LatencyTestOrchestrator:
    """Get the global orchestrator instance."""
    global _orchestrator
    if _orchestrator is None:
        _orchestrator = LatencyTestOrchestrator()
    return _orchestrator


async def broadcast_latency_update(msg_type: str, data: dict):
    """Broadcast a latency test update to all connected WebSocket clients."""
    if not _latency_websockets:
        return

    message = json.dumps({
        "type": msg_type,
        "data": data,
        "timestamp": datetime.now().isoformat()
    })

    # Send to all connected clients
    disconnected = set()
    for ws in _latency_websockets:
        try:
            await ws.send_str(message)
        except Exception as e:
            logger.warning(f"Failed to send to WebSocket: {e}")
            disconnected.add(ws)

    # Remove disconnected clients
    _latency_websockets.difference_update(disconnected)


def _on_progress(run_id: str, completed: int, total: int):
    """Callback for test progress updates."""
    import asyncio
    asyncio.create_task(broadcast_latency_update("test_progress", {
        "runId": run_id,
        "completedConfigurations": completed,
        "totalConfigurations": total,
        "progressPercent": (completed / total * 100) if total > 0 else 0,
    }))


def _on_result(run_id: str, result: TestResult):
    """Callback for individual test results."""
    import asyncio
    asyncio.create_task(broadcast_latency_update("test_result", {
        "runId": run_id,
        "result": result.to_dict(),
    }))


def _on_run_complete(run: TestRun):
    """Callback for test run completion."""
    import asyncio
    asyncio.create_task(broadcast_latency_update("run_complete", {
        "runId": run.id,
        "status": run.status.value,
        "completedConfigurations": run.completed_configurations,
        "totalConfigurations": run.total_configurations,
        "elapsedTimeSeconds": run.elapsed_time,
    }))


async def init_latency_harness():
    """Initialize the latency test harness."""
    global _orchestrator, _storage

    # Create storage backend
    storage_type = os.environ.get("LATENCY_STORAGE_TYPE", "file")
    data_dir = Path(__file__).parent.parent / "data" / "latency_harness"

    try:
        _storage = create_latency_storage(storage_type=storage_type, data_dir=data_dir)
    except Exception as e:
        logger.error("Failed to create latency storage: %s", e)
        raise

    # Initialize file-based storage
    try:
        if hasattr(_storage, 'initialize'):
            await _storage.initialize()
        elif hasattr(_storage, 'connect'):
            await _storage.connect()
            await _storage.initialize_schema()
    except Exception as e:
        logger.error("Failed to initialize storage backend: %s", e)
        raise

    # Create orchestrator with storage
    try:
        _orchestrator = LatencyTestOrchestrator(storage=_storage)

        # Set up callbacks for real-time updates
        _orchestrator.on_progress = _on_progress
        _orchestrator.on_result = _on_result
        _orchestrator.on_run_complete = _on_run_complete

        await _orchestrator.start()
    except Exception as e:
        logger.error("Failed to start latency test orchestrator: %s", e)
        raise

    # Register default test suites if not already in storage
    try:
        if not _orchestrator.suites.get("quick_validation"):
            await _orchestrator.register_suite(create_quick_validation_suite())
        if not _orchestrator.suites.get("provider_comparison"):
            await _orchestrator.register_suite(create_provider_comparison_suite())
    except Exception as e:
        logger.warning("Failed to register default test suites: %s", e)
        # Non-fatal: continue without default suites

    logger.info("Latency test harness initialized with %s storage", storage_type)


async def shutdown_latency_harness():
    """Shutdown the latency test harness."""
    global _orchestrator, _storage

    if _orchestrator:
        await _orchestrator.stop()
        logger.info("Latency test harness stopped")

    if _storage:
        if hasattr(_storage, 'close'):
            await _storage.close()
        logger.info("Latency storage closed")


# =============================================================================
# Test Suite Endpoints
# =============================================================================

async def handle_list_suites(request: web.Request) -> web.Response:
    """GET /api/latency-tests/suites - List all test suites."""
    orchestrator = get_orchestrator()
    suites = orchestrator.list_suites()

    return web.json_response({
        "suites": [
            {
                "id": s.id,
                "name": s.name,
                "description": s.description,
                "scenarioCount": len(s.scenarios),
                "totalTestCount": s.total_test_count,
                "networkProfiles": [p.value for p in s.network_profiles],
            }
            for s in suites
        ]
    })


async def handle_get_suite(request: web.Request) -> web.Response:
    """GET /api/latency-tests/suites/{suite_id} - Get suite details."""
    suite_id = request.match_info["suite_id"]
    orchestrator = get_orchestrator()
    suite = orchestrator.get_suite(suite_id)

    if not suite:
        return web.json_response(
            {"error": f"Suite not found: {suite_id}"},
            status=404
        )

    return web.json_response({
        "id": suite.id,
        "name": suite.name,
        "description": suite.description,
        "scenarios": [s.to_dict() for s in suite.scenarios],
        "networkProfiles": [p.value for p in suite.network_profiles],
        "parameterSpace": {
            "sttConfigs": [c.to_dict() for c in suite.parameter_space.stt_configs],
            "llmConfigs": [c.to_dict() for c in suite.parameter_space.llm_configs],
            "ttsConfigs": [c.to_dict() for c in suite.parameter_space.tts_configs],
            "audioConfigs": [c.to_dict() for c in suite.parameter_space.audio_configs],
        },
        "totalTestCount": suite.total_test_count,
    })


async def handle_upload_suite(request: web.Request) -> web.Response:
    """POST /api/latency-tests/suites - Upload a test suite definition."""
    try:
        data = await request.json()

        # Parse and validate the suite definition
        # For now, return a placeholder - full implementation would parse YAML/JSON
        return web.json_response({
            "message": "Suite upload not yet implemented",
            "received": data,
        }, status=501)

    except json.JSONDecodeError:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )


async def handle_delete_suite(request: web.Request) -> web.Response:
    """DELETE /api/latency-tests/suites/{suite_id} - Delete a test suite."""
    suite_id = request.match_info["suite_id"]

    # Don't allow deleting built-in suites
    if suite_id in ["quick_validation", "provider_comparison"]:
        return web.json_response(
            {"error": "Cannot delete built-in suite"},
            status=400
        )

    # TODO: Implement suite deletion
    return web.json_response({"message": f"Suite {suite_id} deleted"})


# =============================================================================
# Test Run Endpoints
# =============================================================================

async def handle_start_run(request: web.Request) -> web.Response:
    """POST /api/latency-tests/runs - Start a new test run."""
    try:
        data = await request.json()
        suite_id = data.get("suiteId")
        client_id = data.get("clientId")
        client_type_str = data.get("clientType")

        if not suite_id:
            return web.json_response(
                {"error": "suiteId is required"},
                status=400
            )

        orchestrator = get_orchestrator()

        # Parse client type if provided
        client_type = None
        if client_type_str:
            try:
                client_type = ClientType(client_type_str)
            except ValueError:
                return web.json_response(
                    {"error": f"Invalid clientType: {client_type_str}"},
                    status=400
                )

        # Start the test run
        try:
            run = await orchestrator.start_test_run(
                suite_id=suite_id,
                client_id=client_id,
                client_type=client_type,
            )
            return web.json_response({
                "runId": run.id,
                "status": run.status.value,
                "totalConfigurations": run.total_configurations,
                "message": f"Test run started on client {run.client_id}",
            })
        except ValueError as e:
            return web.json_response(
                {"error": str(e)},
                status=400
            )

    except json.JSONDecodeError:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )


async def handle_list_runs(request: web.Request) -> web.Response:
    """GET /api/latency-tests/runs - List test runs."""
    orchestrator = get_orchestrator()

    # Parse query parameters
    status_filter = request.query.get("status")
    limit = int(request.query.get("limit", "50"))

    status = None
    if status_filter:
        try:
            status = RunStatus(status_filter)
        except ValueError:
            pass

    runs = orchestrator.list_runs(status=status, limit=limit)

    return web.json_response({
        "runs": [run.to_dict() for run in runs]
    })


async def handle_get_run(request: web.Request) -> web.Response:
    """GET /api/latency-tests/runs/{run_id} - Get run details."""
    run_id = request.match_info["run_id"]
    orchestrator = get_orchestrator()
    run = orchestrator.get_run(run_id)

    if not run:
        return web.json_response(
            {"error": f"Run not found: {run_id}"},
            status=404
        )

    return web.json_response(run.to_dict())


async def handle_get_run_results(request: web.Request) -> web.Response:
    """GET /api/latency-tests/runs/{run_id}/results - Get run results."""
    run_id = request.match_info["run_id"]
    orchestrator = get_orchestrator()
    run = orchestrator.get_run(run_id)

    if not run:
        return web.json_response(
            {"error": f"Run not found: {run_id}"},
            status=404
        )

    return web.json_response({
        "runId": run.id,
        "status": run.status.value,
        "completedConfigurations": run.completed_configurations,
        "totalConfigurations": run.total_configurations,
        "results": [r.to_dict() for r in run.results],
    })


async def handle_cancel_run(request: web.Request) -> web.Response:
    """DELETE /api/latency-tests/runs/{run_id} - Cancel a test run."""
    run_id = request.match_info["run_id"]
    orchestrator = get_orchestrator()

    await orchestrator.cancel_run(run_id)

    return web.json_response({
        "message": f"Run {run_id} cancelled"
    })


# =============================================================================
# Analysis Endpoints
# =============================================================================

async def handle_get_analysis(request: web.Request) -> web.Response:
    """GET /api/latency-tests/runs/{run_id}/analysis - Get analysis report."""
    run_id = request.match_info["run_id"]
    orchestrator = get_orchestrator()
    run = orchestrator.get_run(run_id)

    if not run:
        return web.json_response(
            {"error": f"Run not found: {run_id}"},
            status=404
        )

    analyzer = ResultsAnalyzer()
    report = analyzer.analyze(run)

    return web.json_response({
        "runId": report.run_id,
        "generatedAt": report.generated_at.isoformat(),
        "summary": {
            "totalConfigurations": report.summary.total_configurations,
            "totalTests": report.summary.total_tests,
            "successfulTests": report.summary.successful_tests,
            "failedTests": report.summary.failed_tests,
            "overallMedianE2EMs": report.summary.overall_median_e2e_ms,
            "overallP99E2EMs": report.summary.overall_p99_e2e_ms,
            "overallMinE2EMs": report.summary.overall_min_e2e_ms,
            "overallMaxE2EMs": report.summary.overall_max_e2e_ms,
            "medianSTTMs": report.summary.median_stt_ms,
            "medianLLMTTFBMs": report.summary.median_llm_ttfb_ms,
            "medianLLMCompletionMs": report.summary.median_llm_completion_ms,
            "medianTTSTTFBMs": report.summary.median_tts_ttfb_ms,
            "medianTTSCompletionMs": report.summary.median_tts_completion_ms,
            "testDurationMinutes": report.summary.test_duration_minutes,
        },
        "bestConfigurations": [
            {
                "rank": c.rank,
                "configId": c.config_id,
                "medianE2EMs": c.median_e2e_ms,
                "p99E2EMs": c.p99_e2e_ms,
                "stddevMs": c.stddev_ms,
                "sampleCount": c.sample_count,
                "breakdown": {
                    "sttMs": c.breakdown.stt_ms,
                    "llmTTFBMs": c.breakdown.llm_ttfb_ms,
                    "llmCompletionMs": c.breakdown.llm_completion_ms,
                    "ttsTTFBMs": c.breakdown.tts_ttfb_ms,
                    "ttsCompletionMs": c.breakdown.tts_completion_ms,
                },
                "networkProjections": {
                    k: {
                        "e2eMs": v.e2e_ms,
                        "meets500ms": v.meets_500ms,
                        "meets1000ms": v.meets_1000ms,
                    }
                    for k, v in c.network_projections.items()
                },
                "estimatedCostPerHour": c.estimated_cost_per_hour,
            }
            for c in report.best_configurations
        ],
        "networkProjections": [
            {
                "network": p.network,
                "addedLatencyMs": p.added_latency_ms,
                "projectedMedianMs": p.projected_median_ms,
                "projectedP99Ms": p.projected_p99_ms,
                "meetsTarget": p.meets_target,
                "configsMeetingTarget": p.configs_meeting_target,
                "totalConfigs": p.total_configs,
            }
            for p in report.network_projections
        ],
        "regressions": [
            {
                "configId": r.config_id,
                "metric": r.metric,
                "baselineValue": r.baseline_value,
                "currentValue": r.current_value,
                "changePercent": r.change_percent,
                "severity": r.severity.value,
            }
            for r in report.regressions
        ],
        "recommendations": report.recommendations,
    })


async def handle_compare_runs(request: web.Request) -> web.Response:
    """POST /api/latency-tests/compare - Compare two test runs."""
    try:
        data = await request.json()
        run1_id = data.get("run1Id")
        run2_id = data.get("run2Id")

        if not run1_id or not run2_id:
            return web.json_response(
                {"error": "run1Id and run2Id are required"},
                status=400
            )

        orchestrator = get_orchestrator()
        run1 = orchestrator.get_run(run1_id)
        run2 = orchestrator.get_run(run2_id)

        if not run1:
            return web.json_response(
                {"error": f"Run not found: {run1_id}"},
                status=404
            )
        if not run2:
            return web.json_response(
                {"error": f"Run not found: {run2_id}"},
                status=404
            )

        analyzer = ResultsAnalyzer()
        comparison = analyzer.compare_runs(run1, run2)

        return web.json_response(comparison)

    except json.JSONDecodeError:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )


async def handle_export_results(request: web.Request) -> web.Response:
    """GET /api/latency-tests/runs/{run_id}/export - Export results as CSV/JSON."""
    run_id = request.match_info["run_id"]
    format_type = request.query.get("format", "json")

    orchestrator = get_orchestrator()
    run = orchestrator.get_run(run_id)

    if not run:
        return web.json_response(
            {"error": f"Run not found: {run_id}"},
            status=404
        )

    if format_type == "csv":
        # Generate CSV
        import io
        import csv

        output = io.StringIO()
        writer = csv.writer(output)

        # Header
        writer.writerow([
            "config_id", "scenario_name", "repetition", "timestamp",
            "stt_latency_ms", "llm_ttfb_ms", "llm_completion_ms",
            "tts_ttfb_ms", "tts_completion_ms", "e2e_latency_ms",
            "network_profile", "is_success", "errors"
        ])

        # Data rows
        for r in run.results:
            writer.writerow([
                r.config_id, r.scenario_name, r.repetition,
                r.timestamp.isoformat(),
                r.stt_latency_ms, r.llm_ttfb_ms, r.llm_completion_ms,
                r.tts_ttfb_ms, r.tts_completion_ms, r.e2e_latency_ms,
                r.network_profile.value, r.is_success, ";".join(r.errors)
            ])

        return web.Response(
            text=output.getvalue(),
            content_type="text/csv",
            headers={
                "Content-Disposition": f"attachment; filename=latency_results_{run_id}.csv"
            }
        )

    else:
        # JSON format
        return web.json_response({
            "runId": run.id,
            "suiteName": run.suite_name,
            "startedAt": run.started_at.isoformat(),
            "completedAt": run.completed_at.isoformat() if run.completed_at else None,
            "results": [r.to_dict() for r in run.results],
        })


# =============================================================================
# Client Management Endpoints
# =============================================================================

async def handle_list_test_clients(request: web.Request) -> web.Response:
    """GET /api/latency-tests/clients - List connected test clients."""
    orchestrator = get_orchestrator()

    # Get all clients
    clients = list(orchestrator.clients.values())

    return web.json_response({
        "clients": [
            {
                "clientId": c.client_id,
                "clientType": c.client_type.value,
                "isConnected": c.status.is_connected,
                "isRunningTest": c.status.is_running_test,
                "currentConfigId": c.status.current_config_id,
                "lastHeartbeat": c.last_heartbeat.isoformat(),
                "capabilities": {
                    "supportedSTTProviders": c.capabilities.supported_stt_providers,
                    "supportedLLMProviders": c.capabilities.supported_llm_providers,
                    "supportedTTSProviders": c.capabilities.supported_tts_providers,
                    "hasHighPrecisionTiming": c.capabilities.has_high_precision_timing,
                    "hasDeviceMetrics": c.capabilities.has_device_metrics,
                    "hasOnDeviceML": c.capabilities.has_on_device_ml,
                    "maxConcurrentTests": c.capabilities.max_concurrent_tests,
                },
            }
            for c in clients
        ]
    })


async def handle_client_heartbeat_latency(request: web.Request) -> web.Response:
    """POST /api/latency-tests/heartbeat - Receive client heartbeat."""
    try:
        data = await request.json()
        client_id = data.get("clientId")
        client_type_str = data.get("clientType")
        capabilities_data = data.get("capabilities", {})

        if not client_id or not client_type_str:
            return web.json_response(
                {"error": "clientId and clientType are required"},
                status=400
            )

        orchestrator = get_orchestrator()

        # Parse client type
        try:
            client_type = ClientType(client_type_str)
        except ValueError:
            return web.json_response(
                {"error": f"Invalid clientType: {client_type_str}"},
                status=400
            )

        # Check if client exists
        if client_id in orchestrator.clients:
            await orchestrator.update_client_heartbeat(client_id)
        else:
            # Register new client
            capabilities = ClientCapabilities(
                supported_stt_providers=capabilities_data.get("supportedSTTProviders", []),
                supported_llm_providers=capabilities_data.get("supportedLLMProviders", []),
                supported_tts_providers=capabilities_data.get("supportedTTSProviders", []),
                has_high_precision_timing=capabilities_data.get("hasHighPrecisionTiming", False),
                has_device_metrics=capabilities_data.get("hasDeviceMetrics", False),
                has_on_device_ml=capabilities_data.get("hasOnDeviceML", False),
                max_concurrent_tests=capabilities_data.get("maxConcurrentTests", 1),
            )
            await orchestrator.register_client(
                client_id=client_id,
                client_type=client_type,
                capabilities=capabilities,
            )

        return web.json_response({"status": "ok"})

    except json.JSONDecodeError:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )


async def handle_submit_result(request: web.Request) -> web.Response:
    """POST /api/latency-tests/results - Submit a test result from a client."""
    try:
        data = await request.json()
        client_id = data.get("clientId")
        result_data = data.get("result")

        if not client_id or not result_data:
            return web.json_response(
                {"error": "clientId and result are required"},
                status=400
            )

        # Parse the result
        # For now, just acknowledge - full implementation would store and process
        logger.info(f"Received result from {client_id}: {result_data.get('configId')}")

        return web.json_response({"status": "received"})

    except json.JSONDecodeError:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )


# =============================================================================
# Baseline Management Endpoints
# =============================================================================

async def handle_list_baselines(request: web.Request) -> web.Response:
    """GET /api/latency-tests/baselines - List performance baselines."""
    global _storage

    if not _storage:
        return web.json_response(
            {"error": "Storage not initialized"},
            status=500
        )

    try:
        baselines = await _storage.list_baselines()
        return web.json_response({
            "baselines": [
                {
                    "id": b.id,
                    "name": b.name,
                    "description": b.description,
                    "runId": b.run_id,
                    "createdAt": b.created_at.isoformat(),
                    "isActive": b.is_active,
                    "configCount": len(b.config_metrics),
                    "overallMedianE2EMs": b.overall_metrics.median_e2e_ms if b.overall_metrics else None,
                }
                for b in baselines
            ]
        })
    except Exception as e:
        logger.error(f"Failed to list baselines: {e}")
        return web.json_response(
            {"error": str(e)},
            status=500
        )


async def handle_create_baseline(request: web.Request) -> web.Response:
    """POST /api/latency-tests/baselines - Create baseline from run."""
    global _storage

    if not _storage:
        return web.json_response(
            {"error": "Storage not initialized"},
            status=500
        )

    try:
        data = await request.json()
        run_id = data.get("runId")
        name = data.get("name", f"Baseline from {run_id}")
        description = data.get("description", "")
        set_active = data.get("setActive", False)

        if not run_id:
            return web.json_response(
                {"error": "runId is required"},
                status=400
            )

        # Get the run
        orchestrator = get_orchestrator()
        run = orchestrator.get_run(run_id)

        if not run:
            return web.json_response(
                {"error": f"Run not found: {run_id}"},
                status=404
            )

        if run.status != RunStatus.COMPLETED:
            return web.json_response(
                {"error": f"Run is not completed (status: {run.status.value})"},
                status=400
            )

        # Filter to successful results
        successful_results = [r for r in run.results if r.is_success]

        if not successful_results:
            return web.json_response(
                {"error": "Run has no successful results"},
                status=400
            )

        # Compute per-config metrics
        config_metrics: Dict[str, BaselineMetrics] = {}
        by_config: Dict[str, List] = defaultdict(list)

        for r in successful_results:
            by_config[r.config_id].append(r)

        for config_id, results in by_config.items():
            e2e = [r.e2e_latency_ms for r in results]
            stt = [r.stt_latency_ms for r in results if r.stt_latency_ms]
            llm_ttfb = [r.llm_ttfb_ms for r in results]
            llm_completion = [r.llm_completion_ms for r in results]
            tts_ttfb = [r.tts_ttfb_ms for r in results]
            tts_completion = [r.tts_completion_ms for r in results]

            config_metrics[config_id] = BaselineMetrics(
                median_e2e_ms=statistics.median(e2e),
                p99_e2e_ms=sorted(e2e)[int(len(e2e) * 0.99)] if len(e2e) > 1 else e2e[0],
                min_e2e_ms=min(e2e),
                max_e2e_ms=max(e2e),
                median_stt_ms=statistics.median(stt) if stt else None,
                median_llm_ttfb_ms=statistics.median(llm_ttfb),
                median_llm_completion_ms=statistics.median(llm_completion),
                median_tts_ttfb_ms=statistics.median(tts_ttfb),
                median_tts_completion_ms=statistics.median(tts_completion),
                sample_count=len(results),
            )

        # Compute overall metrics
        all_e2e = [r.e2e_latency_ms for r in successful_results]
        all_stt = [r.stt_latency_ms for r in successful_results if r.stt_latency_ms]
        all_llm_ttfb = [r.llm_ttfb_ms for r in successful_results]
        all_llm_completion = [r.llm_completion_ms for r in successful_results]
        all_tts_ttfb = [r.tts_ttfb_ms for r in successful_results]
        all_tts_completion = [r.tts_completion_ms for r in successful_results]

        overall_metrics = BaselineMetrics(
            median_e2e_ms=statistics.median(all_e2e),
            p99_e2e_ms=sorted(all_e2e)[int(len(all_e2e) * 0.99)] if len(all_e2e) > 1 else all_e2e[0],
            min_e2e_ms=min(all_e2e),
            max_e2e_ms=max(all_e2e),
            median_stt_ms=statistics.median(all_stt) if all_stt else None,
            median_llm_ttfb_ms=statistics.median(all_llm_ttfb),
            median_llm_completion_ms=statistics.median(all_llm_completion),
            median_tts_ttfb_ms=statistics.median(all_tts_ttfb),
            median_tts_completion_ms=statistics.median(all_tts_completion),
            sample_count=len(successful_results),
        )

        # Create baseline
        baseline_id = str(uuid.uuid4())[:8]
        baseline = PerformanceBaseline(
            id=baseline_id,
            name=name,
            description=description,
            run_id=run_id,
            created_at=datetime.now(),
            is_active=set_active,
            config_metrics=config_metrics,
            overall_metrics=overall_metrics,
        )

        # Save baseline
        await _storage.save_baseline(baseline)

        logger.info(f"Created baseline {baseline_id} from run {run_id}")

        return web.json_response({
            "id": baseline.id,
            "name": baseline.name,
            "runId": baseline.run_id,
            "createdAt": baseline.created_at.isoformat(),
            "isActive": baseline.is_active,
            "configCount": len(baseline.config_metrics),
            "overallMetrics": baseline.overall_metrics.to_dict() if baseline.overall_metrics else None,
        })

    except json.JSONDecodeError:
        return web.json_response(
            {"error": "Invalid JSON"},
            status=400
        )
    except Exception as e:
        logger.error(f"Failed to create baseline: {e}")
        return web.json_response(
            {"error": str(e)},
            status=500
        )


async def handle_check_baseline(request: web.Request) -> web.Response:
    """GET /api/latency-tests/baselines/{baseline_id}/check - Check run against baseline."""
    global _storage

    if not _storage:
        return web.json_response(
            {"error": "Storage not initialized"},
            status=500
        )

    baseline_id = request.match_info["baseline_id"]
    run_id = request.query.get("runId")

    if not run_id:
        return web.json_response(
            {"error": "runId query parameter is required"},
            status=400
        )

    try:
        # Get the baseline
        baseline = await _storage.get_baseline(baseline_id)
        if not baseline:
            return web.json_response(
                {"error": f"Baseline not found: {baseline_id}"},
                status=404
            )

        # Get the run
        orchestrator = get_orchestrator()
        run = orchestrator.get_run(run_id)

        if not run:
            return web.json_response(
                {"error": f"Run not found: {run_id}"},
                status=404
            )

        # Convert baseline to format expected by analyzer
        baseline_dict: Dict[str, Dict[str, float]] = {}
        for config_id, metrics in baseline.config_metrics.items():
            baseline_dict[config_id] = {
                "e2e_median_ms": metrics.median_e2e_ms,
                "e2e_p99_ms": metrics.p99_e2e_ms,
                "stt_median_ms": metrics.median_stt_ms,
                "llm_ttfb_median_ms": metrics.median_llm_ttfb_ms,
                "llm_completion_median_ms": metrics.median_llm_completion_ms,
                "tts_ttfb_median_ms": metrics.median_tts_ttfb_ms,
                "tts_completion_median_ms": metrics.median_tts_completion_ms,
            }

        # Analyze with baseline for regression detection
        analyzer = ResultsAnalyzer(baselines=baseline_dict)
        report = analyzer.analyze(run)

        # Compute comparison summary
        comparison_results = []
        by_config: Dict[str, List] = defaultdict(list)

        successful_results = [r for r in run.results if r.is_success]
        for r in successful_results:
            by_config[r.config_id].append(r)

        for config_id, results in by_config.items():
            current_median = statistics.median([r.e2e_latency_ms for r in results])

            baseline_metrics = baseline.config_metrics.get(config_id)
            if baseline_metrics:
                baseline_median = baseline_metrics.median_e2e_ms
                change_percent = ((current_median - baseline_median) / baseline_median * 100)

                comparison_results.append({
                    "configId": config_id,
                    "baselineMedianMs": baseline_median,
                    "currentMedianMs": current_median,
                    "changePercent": round(change_percent, 2),
                    "improved": change_percent < -5,
                    "regressed": change_percent > 10,
                    "severity": (
                        "severe" if change_percent > 50 else
                        "moderate" if change_percent > 20 else
                        "minor" if change_percent > 10 else
                        "none"
                    ),
                })
            else:
                # New config not in baseline
                comparison_results.append({
                    "configId": config_id,
                    "baselineMedianMs": None,
                    "currentMedianMs": current_median,
                    "changePercent": None,
                    "improved": False,
                    "regressed": False,
                    "severity": "unknown",
                    "note": "Configuration not in baseline"
                })

        # Overall comparison
        overall_current_median = report.summary.overall_median_e2e_ms
        overall_baseline_median = baseline.overall_metrics.median_e2e_ms if baseline.overall_metrics else None
        overall_change = None
        if overall_baseline_median:
            overall_change = ((overall_current_median - overall_baseline_median) / overall_baseline_median * 100)

        return web.json_response({
            "baselineId": baseline_id,
            "baselineName": baseline.name,
            "runId": run_id,
            "checkedAt": datetime.now().isoformat(),
            "overall": {
                "baselineMedianMs": overall_baseline_median,
                "currentMedianMs": overall_current_median,
                "changePercent": round(overall_change, 2) if overall_change else None,
                "meetsTarget500ms": overall_current_median < 500,
                "meetsTarget1000ms": overall_current_median < 1000,
            },
            "regressions": [
                {
                    "configId": r.config_id,
                    "metric": r.metric,
                    "baselineValue": r.baseline_value,
                    "currentValue": r.current_value,
                    "changePercent": round(r.change_percent, 2),
                    "severity": r.severity.value,
                }
                for r in report.regressions
            ],
            "configComparisons": sorted(
                comparison_results,
                key=lambda x: x.get("changePercent") or 0,
                reverse=True
            ),
            "summary": {
                "totalConfigs": len(comparison_results),
                "improvedConfigs": sum(1 for c in comparison_results if c.get("improved")),
                "regressedConfigs": sum(1 for c in comparison_results if c.get("regressed")),
                "newConfigs": sum(1 for c in comparison_results if c.get("baselineMedianMs") is None),
            },
        })

    except Exception as e:
        logger.error(f"Failed to check baseline: {e}")
        return web.json_response(
            {"error": str(e)},
            status=500
        )


# =============================================================================
# WebSocket Endpoint
# =============================================================================

async def handle_latency_websocket(request: web.Request) -> web.WebSocketResponse:
    """WebSocket endpoint for real-time latency test updates.

    Clients connect to /api/latency-tests/ws to receive:
    - test_progress: Progress updates during test execution
    - test_result: Individual test result as they complete
    - run_complete: Notification when a run finishes
    - client_connected: New test client connected
    - client_disconnected: Test client disconnected
    """
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    # Add to connected clients
    _latency_websockets.add(ws)
    logger.info(f"WebSocket client connected for latency updates (total: {len(_latency_websockets)})")

    # Send initial state
    orchestrator = get_orchestrator()
    active_runs = orchestrator.list_runs(status=RunStatus.running)

    await ws.send_json({
        "type": "connection_established",
        "data": {
            "connectedClients": len(orchestrator.clients),
            "activeRuns": len(active_runs),
            "activeRunIds": [r.id for r in active_runs],
        },
        "timestamp": datetime.now().isoformat()
    })

    try:
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    msg_type = data.get("type")

                    # Handle subscribe/unsubscribe for specific runs
                    if msg_type == "subscribe_run":
                        run_id = data.get("runId")
                        # For now, all connections receive all updates
                        # Future: implement per-run subscription filtering
                        await ws.send_json({
                            "type": "subscribed",
                            "data": {"runId": run_id},
                            "timestamp": datetime.now().isoformat()
                        })

                    elif msg_type == "ping":
                        await ws.send_json({
                            "type": "pong",
                            "timestamp": datetime.now().isoformat()
                        })

                    elif msg_type == "get_status":
                        # Return current harness status
                        clients = list(orchestrator.clients.values())
                        await ws.send_json({
                            "type": "status",
                            "data": {
                                "connectedTestClients": len(clients),
                                "activeRuns": len(orchestrator.list_runs(status=RunStatus.running)),
                                "clients": [
                                    {
                                        "clientId": c.client_id,
                                        "clientType": c.client_type.value,
                                        "isConnected": c.status.is_connected,
                                        "isRunningTest": c.status.is_running_test,
                                    }
                                    for c in clients
                                ],
                            },
                            "timestamp": datetime.now().isoformat()
                        })

                except json.JSONDecodeError:
                    await ws.send_json({
                        "type": "error",
                        "data": {"message": "Invalid JSON"},
                        "timestamp": datetime.now().isoformat()
                    })

            elif msg.type == web.WSMsgType.ERROR:
                logger.warning(f"WebSocket error: {ws.exception()}")
                break

    except Exception as e:
        logger.error(f"WebSocket handler error: {e}")
    finally:
        _latency_websockets.discard(ws)
        logger.info(f"WebSocket client disconnected (remaining: {len(_latency_websockets)})")

    return ws


# =============================================================================
# Route Registration
# =============================================================================

def register_latency_harness_routes(app: web.Application):
    """Register all latency harness routes."""

    # Test Suites
    app.router.add_get("/api/latency-tests/suites", handle_list_suites)
    app.router.add_get("/api/latency-tests/suites/{suite_id}", handle_get_suite)
    app.router.add_post("/api/latency-tests/suites", handle_upload_suite)
    app.router.add_delete("/api/latency-tests/suites/{suite_id}", handle_delete_suite)

    # Test Runs
    app.router.add_post("/api/latency-tests/runs", handle_start_run)
    app.router.add_get("/api/latency-tests/runs", handle_list_runs)
    app.router.add_get("/api/latency-tests/runs/{run_id}", handle_get_run)
    app.router.add_get("/api/latency-tests/runs/{run_id}/results", handle_get_run_results)
    app.router.add_delete("/api/latency-tests/runs/{run_id}", handle_cancel_run)

    # Analysis
    app.router.add_get("/api/latency-tests/runs/{run_id}/analysis", handle_get_analysis)
    app.router.add_post("/api/latency-tests/compare", handle_compare_runs)
    app.router.add_get("/api/latency-tests/runs/{run_id}/export", handle_export_results)

    # Clients
    app.router.add_get("/api/latency-tests/clients", handle_list_test_clients)
    app.router.add_post("/api/latency-tests/heartbeat", handle_client_heartbeat_latency)
    app.router.add_post("/api/latency-tests/results", handle_submit_result)

    # Baselines
    app.router.add_get("/api/latency-tests/baselines", handle_list_baselines)
    app.router.add_post("/api/latency-tests/baselines", handle_create_baseline)
    app.router.add_get("/api/latency-tests/baselines/{baseline_id}/check", handle_check_baseline)

    # WebSocket for real-time updates
    app.router.add_get("/api/latency-tests/ws", handle_latency_websocket)

    logger.info("Latency harness API routes registered")
