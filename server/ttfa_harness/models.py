"""
UnaMentis TTFA Harness - Data Models

Dataclass models for test scenarios, events, results, and baselines.
Follows the latency_harness pattern: dataclass + to_dict/from_dict.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional, Dict, List, Any
import uuid


# ============================================================================
# Enums
# ============================================================================


class AudioPath(str, Enum):
    """How audio reaches the speaker for a given feature."""

    CACHED = "cached"  # Pre-generated audio from Core Data or server cache
    STREAMING = "streaming"  # Direct TTS streaming (~200ms TTFB)
    PRE_BUFFERED = "pre_buffered"  # Generated ahead while playing current


class TTFAEventType(str, Enum):
    """Event types emitted by in-app TTFAInstrumentation."""

    ACTIVATE = "ACTIVATE"
    TTS_FIRST = "TTS_FIRST"
    AUDIO_SCHEDULED = "AUDIO_SCHEDULED"
    AUDIO_PLAYING = "AUDIO_PLAYING"
    CACHED_HIT = "CACHED_HIT"
    ERROR = "ERROR"


class RegressionSeverity(str, Enum):
    """Severity levels for detected regressions."""

    MINOR = "minor"  # 10-20% regression
    MODERATE = "moderate"  # 20-50% regression
    SEVERE = "severe"  # >50% regression


class SimActionType(str, Enum):
    """Types of simulator actions for test orchestration."""

    DEEP_LINK = "deep_link"
    TAP = "tap"
    WAIT = "wait"
    SWIPE = "swipe"


# ============================================================================
# Simulator Actions
# ============================================================================


@dataclass
class SimAction:
    """A single simulator action (tap, deep link, wait, etc.)."""

    action_type: SimActionType
    # deep_link
    url: Optional[str] = None
    # tap
    x: Optional[int] = None
    y: Optional[int] = None
    # wait
    seconds: Optional[float] = None
    # swipe
    x_end: Optional[int] = None
    y_end: Optional[int] = None

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {"action_type": self.action_type.value}
        if self.url is not None:
            d["url"] = self.url
        if self.x is not None:
            d["x"] = self.x
        if self.y is not None:
            d["y"] = self.y
        if self.seconds is not None:
            d["seconds"] = self.seconds
        if self.x_end is not None:
            d["x_end"] = self.x_end
        if self.y_end is not None:
            d["y_end"] = self.y_end
        return d

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "SimAction":
        return cls(
            action_type=SimActionType(data["action_type"]),
            url=data.get("url"),
            x=data.get("x"),
            y=data.get("y"),
            seconds=data.get("seconds"),
            x_end=data.get("x_end"),
            y_end=data.get("y_end"),
        )

    @staticmethod
    def deep_link(url: str) -> "SimAction":
        return SimAction(action_type=SimActionType.DEEP_LINK, url=url)

    @staticmethod
    def tap_at(x: int, y: int) -> "SimAction":
        return SimAction(action_type=SimActionType.TAP, x=x, y=y)

    @staticmethod
    def wait_for(seconds: float) -> "SimAction":
        return SimAction(action_type=SimActionType.WAIT, seconds=seconds)


# ============================================================================
# Test Scenarios
# ============================================================================


@dataclass
class TTFAScenario:
    """Definition of a single TTFA test scenario."""

    id: str
    name: str
    feature_id: str  # Matches TTFAFeature.rawValue in Swift
    audio_path: AudioPath
    setup_steps: List[SimAction] = field(default_factory=list)
    trigger_action: Optional[SimAction] = None
    target_ms: float = 1000.0  # < 1 second, no exceptions
    repetitions: int = 3
    requires_server: bool = False
    description: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "feature_id": self.feature_id,
            "audio_path": self.audio_path.value,
            "setup_steps": [s.to_dict() for s in self.setup_steps],
            "trigger_action": self.trigger_action.to_dict()
            if self.trigger_action
            else None,
            "target_ms": self.target_ms,
            "repetitions": self.repetitions,
            "requires_server": self.requires_server,
            "description": self.description,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTFAScenario":
        return cls(
            id=data["id"],
            name=data["name"],
            feature_id=data["feature_id"],
            audio_path=AudioPath(data["audio_path"]),
            setup_steps=[SimAction.from_dict(s) for s in data.get("setup_steps", [])],
            trigger_action=SimAction.from_dict(data["trigger_action"])
            if data.get("trigger_action")
            else None,
            target_ms=data.get("target_ms", 1000.0),
            repetitions=data.get("repetitions", 3),
            requires_server=data.get("requires_server", False),
            description=data.get("description", ""),
        )


# ============================================================================
# Events (parsed from os_log)
# ============================================================================


@dataclass
class TTFAEvent:
    """A single TTFA event parsed from the os_log stream."""

    event_type: TTFAEventType
    feature_id: str
    elapsed_ms: float
    metadata: str = ""
    wall_timestamp: Optional[datetime] = None

    def to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {
            "event_type": self.event_type.value,
            "feature_id": self.feature_id,
            "elapsed_ms": self.elapsed_ms,
        }
        if self.metadata:
            d["metadata"] = self.metadata
        if self.wall_timestamp:
            d["wall_timestamp"] = self.wall_timestamp.isoformat()
        return d


# ============================================================================
# Results
# ============================================================================


@dataclass
class TTFAResult:
    """Result of a single TTFA measurement (one scenario, one repetition)."""

    scenario_id: str
    scenario_name: str
    audio_path: AudioPath
    repetition: int
    timestamp: datetime = field(default_factory=datetime.now)

    # Timing breakdown (milliseconds)
    activate_to_tts_first_ms: Optional[float] = None
    activate_to_audio_scheduled_ms: Optional[float] = None
    activate_to_audio_playing_ms: Optional[float] = None

    # Derived
    was_cached: bool = False
    errors: List[str] = field(default_factory=list)

    @property
    def ttfa_ms(self) -> Optional[float]:
        """The TTFA value: activation to audio playing."""
        return self.activate_to_audio_playing_ms

    @property
    def passes_target(self) -> bool:
        """Whether this result is under the 1000ms target."""
        return self.ttfa_ms is not None and self.ttfa_ms < 1000.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "scenario_id": self.scenario_id,
            "scenario_name": self.scenario_name,
            "audio_path": self.audio_path.value,
            "repetition": self.repetition,
            "timestamp": self.timestamp.isoformat(),
            "activate_to_tts_first_ms": self.activate_to_tts_first_ms,
            "activate_to_audio_scheduled_ms": self.activate_to_audio_scheduled_ms,
            "activate_to_audio_playing_ms": self.activate_to_audio_playing_ms,
            "ttfa_ms": self.ttfa_ms,
            "was_cached": self.was_cached,
            "passes_target": self.passes_target,
            "errors": self.errors,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTFAResult":
        return cls(
            scenario_id=data["scenario_id"],
            scenario_name=data["scenario_name"],
            audio_path=AudioPath(data["audio_path"]),
            repetition=data["repetition"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            activate_to_tts_first_ms=data.get("activate_to_tts_first_ms"),
            activate_to_audio_scheduled_ms=data.get("activate_to_audio_scheduled_ms"),
            activate_to_audio_playing_ms=data.get("activate_to_audio_playing_ms"),
            was_cached=data.get("was_cached", False),
            errors=data.get("errors", []),
        )


@dataclass
class TTFASummary:
    """Summary statistics for a complete TTFA run."""

    total_scenarios: int = 0
    passed_scenarios: int = 0
    failed_scenarios: int = 0
    error_scenarios: int = 0
    median_ttfa_ms: float = 0.0
    p99_ttfa_ms: float = 0.0
    worst_scenario: str = ""
    worst_ttfa_ms: float = 0.0
    all_pass_target: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_scenarios": self.total_scenarios,
            "passed_scenarios": self.passed_scenarios,
            "failed_scenarios": self.failed_scenarios,
            "error_scenarios": self.error_scenarios,
            "median_ttfa_ms": self.median_ttfa_ms,
            "p99_ttfa_ms": self.p99_ttfa_ms,
            "worst_scenario": self.worst_scenario,
            "worst_ttfa_ms": self.worst_ttfa_ms,
            "all_pass_target": self.all_pass_target,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTFASummary":
        return cls(**{k: data[k] for k in data if k in cls.__dataclass_fields__})


@dataclass
class TTFARun:
    """A complete TTFA test run with all results."""

    id: str = field(default_factory=lambda: f"ttfa_{uuid.uuid4().hex[:8]}")
    timestamp: datetime = field(default_factory=datetime.now)
    device: str = "iPhone 16 Pro"
    app_build: str = ""
    results: List[TTFAResult] = field(default_factory=list)
    summary: TTFASummary = field(default_factory=TTFASummary)

    def compute_summary(self) -> None:
        """Compute summary statistics from results."""
        valid_results = [r for r in self.results if r.ttfa_ms is not None]
        error_results = [r for r in self.results if r.ttfa_ms is None]

        if not valid_results:
            self.summary = TTFASummary(
                total_scenarios=len(self.results),
                error_scenarios=len(error_results),
            )
            return

        ttfa_values = sorted(
            [r.ttfa_ms for r in valid_results if r.ttfa_ms is not None]
        )
        passed = [r for r in valid_results if r.passes_target]
        failed = [r for r in valid_results if not r.passes_target]

        # Find worst scenario (by median across repetitions)
        scenario_medians: Dict[str, List[float]] = {}
        for r in valid_results:
            if r.ttfa_ms is not None:
                scenario_medians.setdefault(r.scenario_id, []).append(r.ttfa_ms)

        worst_id = ""
        worst_median = 0.0
        for sid, values in scenario_medians.items():
            median = sorted(values)[len(values) // 2]
            if median > worst_median:
                worst_median = median
                worst_id = sid

        n = len(ttfa_values)
        self.summary = TTFASummary(
            total_scenarios=len(self.results),
            passed_scenarios=len(passed),
            failed_scenarios=len(failed),
            error_scenarios=len(error_results),
            median_ttfa_ms=ttfa_values[n // 2] if n > 0 else 0.0,
            p99_ttfa_ms=ttfa_values[int(n * 0.99)] if n > 0 else 0.0,
            worst_scenario=worst_id,
            worst_ttfa_ms=worst_median,
            all_pass_target=len(failed) == 0 and len(error_results) == 0,
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "timestamp": self.timestamp.isoformat(),
            "device": self.device,
            "app_build": self.app_build,
            "results": [r.to_dict() for r in self.results],
            "summary": self.summary.to_dict(),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTFARun":
        run = cls(
            id=data["id"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            device=data.get("device", ""),
            app_build=data.get("app_build", ""),
            results=[TTFAResult.from_dict(r) for r in data.get("results", [])],
        )
        if "summary" in data:
            run.summary = TTFASummary.from_dict(data["summary"])
        return run


# ============================================================================
# Baselines & Regressions
# ============================================================================


@dataclass
class ScenarioBaseline:
    """Baseline metrics for a single scenario."""

    median_ttfa_ms: float
    p99_ttfa_ms: float
    audio_path: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "median_ttfa_ms": self.median_ttfa_ms,
            "p99_ttfa_ms": self.p99_ttfa_ms,
            "audio_path": self.audio_path,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ScenarioBaseline":
        return cls(
            median_ttfa_ms=data["median_ttfa_ms"],
            p99_ttfa_ms=data["p99_ttfa_ms"],
            audio_path=data["audio_path"],
        )


@dataclass
class TTFABaseline:
    """A saved baseline for regression comparison."""

    id: str
    name: str
    created_at: datetime = field(default_factory=datetime.now)
    run_id: str = ""
    scenario_metrics: Dict[str, ScenarioBaseline] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "created_at": self.created_at.isoformat(),
            "run_id": self.run_id,
            "scenario_metrics": {
                k: v.to_dict() for k, v in self.scenario_metrics.items()
            },
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTFABaseline":
        return cls(
            id=data["id"],
            name=data["name"],
            created_at=datetime.fromisoformat(data["created_at"]),
            run_id=data.get("run_id", ""),
            scenario_metrics={
                k: ScenarioBaseline.from_dict(v)
                for k, v in data.get("scenario_metrics", {}).items()
            },
        )


@dataclass
class TTFARegression:
    """A detected performance regression."""

    scenario_id: str
    metric: str  # "median" or "p99"
    baseline_value: float
    current_value: float
    change_percent: float
    severity: RegressionSeverity

    def to_dict(self) -> Dict[str, Any]:
        return {
            "scenario_id": self.scenario_id,
            "metric": self.metric,
            "baseline_value": self.baseline_value,
            "current_value": self.current_value,
            "change_percent": self.change_percent,
            "severity": self.severity.value,
        }


# ============================================================================
# Predefined Scenarios
# ============================================================================


def get_predefined_scenarios() -> Dict[str, TTFAScenario]:
    """Return all predefined TTFA test scenarios."""
    return {
        s.id: s
        for s in [
            TTFAScenario(
                id="session-cold-start",
                name="Session Cold Start",
                feature_id="session.chat",
                audio_path=AudioPath.STREAMING,
                setup_steps=[
                    SimAction.deep_link("unamentis://chat?prompt=Hello"),
                    SimAction.wait_for(3.0),
                ],
                description="Measure TTFA from opening a freeform chat session to first AI audio response.",
            ),
            TTFAScenario(
                id="session-curriculum",
                name="Session Curriculum",
                feature_id="session.curriculum",
                audio_path=AudioPath.STREAMING,
                setup_steps=[
                    SimAction.deep_link("unamentis://lesson?id=test"),
                    SimAction.wait_for(3.0),
                ],
                requires_server=True,
                description="Measure TTFA from opening a curriculum topic to first audio segment.",
            ),
            TTFAScenario(
                id="kb-oral-cached",
                name="KB Oral Practice (cached)",
                feature_id="kb.oral",
                audio_path=AudioPath.CACHED,
                setup_steps=[
                    SimAction.deep_link("unamentis://learning"),
                    SimAction.wait_for(2.0),
                ],
                requires_server=True,
                description="Measure TTFA for KB question read with server audio cache warm.",
            ),
            TTFAScenario(
                id="kb-oral-uncached",
                name="KB Oral Practice (uncached)",
                feature_id="kb.oral",
                audio_path=AudioPath.STREAMING,
                setup_steps=[
                    SimAction.deep_link("unamentis://learning"),
                    SimAction.wait_for(2.0),
                ],
                description="Measure TTFA for KB question read with local TTS (no cache).",
            ),
            TTFAScenario(
                id="kb-drill",
                name="KB Domain Drill",
                feature_id="kb.drill",
                audio_path=AudioPath.STREAMING,
                setup_steps=[
                    SimAction.deep_link("unamentis://learning"),
                    SimAction.wait_for(2.0),
                ],
                description="Measure TTFA for KB domain drill question read.",
            ),
            TTFAScenario(
                id="kb-rebound",
                name="KB Rebound Training",
                feature_id="kb.rebound",
                audio_path=AudioPath.STREAMING,
                setup_steps=[
                    SimAction.deep_link("unamentis://learning"),
                    SimAction.wait_for(2.0),
                ],
                description="Measure TTFA for KB rebound speed training question read.",
            ),
            TTFAScenario(
                id="reading-cached",
                name="Reading List Play (cached)",
                feature_id="reading.play",
                audio_path=AudioPath.CACHED,
                setup_steps=[
                    SimAction.deep_link("unamentis://assistant"),
                    SimAction.wait_for(2.0),
                ],
                description="Measure TTFA for reading list playback with pre-generated audio.",
            ),
            TTFAScenario(
                id="reading-uncached",
                name="Reading List Play (uncached)",
                feature_id="reading.play",
                audio_path=AudioPath.STREAMING,
                setup_steps=[
                    SimAction.deep_link("unamentis://assistant"),
                    SimAction.wait_for(2.0),
                ],
                description="Measure TTFA for reading list playback via TTS streaming.",
            ),
            TTFAScenario(
                id="reading-resume",
                name="Reading List Resume",
                feature_id="reading.resume",
                audio_path=AudioPath.CACHED,
                setup_steps=[
                    SimAction.deep_link("unamentis://assistant"),
                    SimAction.wait_for(2.0),
                ],
                description="Measure TTFA for resuming a paused reading list item.",
            ),
        ]
    }


# Predefined test suites
SUITES: Dict[str, List[str]] = {
    "quick": [
        "session-cold-start",
        "kb-oral-uncached",
        "reading-cached",
        "reading-uncached",
    ],
    "full": list(get_predefined_scenarios().keys()),
}
