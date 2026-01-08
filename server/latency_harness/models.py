"""
UnaMentis Latency Test Harness - Data Models

Shared data structures for test configuration, results, and analysis.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional, Dict, List, Any
import uuid


# ============================================================================
# Enums
# ============================================================================

class ClientType(str, Enum):
    IOS_SIMULATOR = "ios_simulator"
    IOS_DEVICE = "ios_device"
    WEB = "web"


class RunStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class NetworkProfile(str, Enum):
    LOCALHOST = "localhost"
    WIFI = "wifi"
    CELLULAR_US = "cellular_us"
    CELLULAR_EU = "cellular_eu"
    INTERCONTINENTAL = "intercontinental"

    @property
    def added_latency_ms(self) -> float:
        """Expected network overhead in milliseconds."""
        return {
            NetworkProfile.LOCALHOST: 0,
            NetworkProfile.WIFI: 10,
            NetworkProfile.CELLULAR_US: 50,
            NetworkProfile.CELLULAR_EU: 70,
            NetworkProfile.INTERCONTINENTAL: 120,
        }[self]


class ScenarioType(str, Enum):
    AUDIO_INPUT = "audio_input"
    TEXT_INPUT = "text_input"
    TTS_ONLY = "tts_only"
    CONVERSATION = "conversation"


class ResponseType(str, Enum):
    SHORT = "short"
    MEDIUM = "medium"
    LONG = "long"


class RegressionSeverity(str, Enum):
    MINOR = "minor"       # 10-20% regression
    MODERATE = "moderate" # 20-50% regression
    SEVERE = "severe"     # >50% regression


# ============================================================================
# Provider Configurations
# ============================================================================

@dataclass
class STTTestConfig:
    provider: str
    model: Optional[str] = None
    chunk_size_ms: Optional[int] = None
    language: str = "en-US"

    @property
    def requires_network(self) -> bool:
        return self.provider not in ["apple", "glm-asr-ondevice", "web-speech"]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "chunkSizeMs": self.chunk_size_ms,
            "language": self.language,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "STTTestConfig":
        return cls(
            provider=data["provider"],
            model=data.get("model"),
            chunk_size_ms=data.get("chunkSizeMs"),
            language=data.get("language", "en-US"),
        )


@dataclass
class LLMTestConfig:
    provider: str
    model: str
    max_tokens: int = 512
    temperature: float = 0.7
    top_p: Optional[float] = None
    stream: bool = True

    @property
    def requires_network(self) -> bool:
        return self.provider not in ["mlx"]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "maxTokens": self.max_tokens,
            "temperature": self.temperature,
            "topP": self.top_p,
            "stream": self.stream,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LLMTestConfig":
        return cls(
            provider=data["provider"],
            model=data["model"],
            max_tokens=data.get("maxTokens", 512),
            temperature=data.get("temperature", 0.7),
            top_p=data.get("topP"),
            stream=data.get("stream", True),
        )


@dataclass
class ChatterboxConfig:
    exaggeration: float = 0.5
    cfg_weight: float = 0.5
    speed: float = 1.0
    enable_paralinguistic_tags: bool = False
    use_multilingual: bool = False
    language: str = "en"
    use_streaming: bool = True
    seed: Optional[int] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "exaggeration": self.exaggeration,
            "cfgWeight": self.cfg_weight,
            "speed": self.speed,
            "enableParalinguisticTags": self.enable_paralinguistic_tags,
            "useMultilingual": self.use_multilingual,
            "language": self.language,
            "useStreaming": self.use_streaming,
            "seed": self.seed,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ChatterboxConfig":
        return cls(
            exaggeration=data.get("exaggeration", 0.5),
            cfg_weight=data.get("cfgWeight", 0.5),
            speed=data.get("speed", 1.0),
            enable_paralinguistic_tags=data.get("enableParalinguisticTags", False),
            use_multilingual=data.get("useMultilingual", False),
            language=data.get("language", "en"),
            use_streaming=data.get("useStreaming", True),
            seed=data.get("seed"),
        )


@dataclass
class TTSTestConfig:
    provider: str
    voice_id: Optional[str] = None
    speed: float = 1.0
    use_streaming: bool = True
    chatterbox_config: Optional[ChatterboxConfig] = None

    @property
    def requires_network(self) -> bool:
        return self.provider not in ["apple", "web-speech"]

    def to_dict(self) -> Dict[str, Any]:
        result = {
            "provider": self.provider,
            "voiceId": self.voice_id,
            "speed": self.speed,
            "useStreaming": self.use_streaming,
        }
        if self.chatterbox_config:
            result["chatterboxConfig"] = self.chatterbox_config.to_dict()
        return result

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TTSTestConfig":
        chatterbox_config = None
        if data.get("chatterboxConfig"):
            chatterbox_config = ChatterboxConfig.from_dict(data["chatterboxConfig"])
        return cls(
            provider=data["provider"],
            voice_id=data.get("voiceId"),
            speed=data.get("speed", 1.0),
            use_streaming=data.get("useStreaming", True),
            chatterbox_config=chatterbox_config,
        )


@dataclass
class AudioEngineTestConfig:
    sample_rate: float = 24000
    buffer_size: int = 1024
    vad_threshold: float = 0.5
    vad_smoothing_window: int = 5

    def to_dict(self) -> Dict[str, Any]:
        return {
            "sampleRate": self.sample_rate,
            "bufferSize": self.buffer_size,
            "vadThreshold": self.vad_threshold,
            "vadSmoothingWindow": self.vad_smoothing_window,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "AudioEngineTestConfig":
        return cls(
            sample_rate=data.get("sampleRate", 24000),
            buffer_size=data.get("bufferSize", 1024),
            vad_threshold=data.get("vadThreshold", 0.5),
            vad_smoothing_window=data.get("vadSmoothingWindow", 5),
        )


# ============================================================================
# Test Configuration
# ============================================================================

@dataclass
class TestConfiguration:
    """Complete configuration for a single test execution."""
    id: str
    scenario_name: str
    repetition: int
    stt: STTTestConfig
    llm: LLMTestConfig
    tts: TTSTestConfig
    audio_engine: AudioEngineTestConfig
    network_profile: NetworkProfile = NetworkProfile.LOCALHOST

    @property
    def config_id(self) -> str:
        """Generate a unique configuration identifier."""
        return f"{self.stt.provider}_{self.llm.provider}_{self.llm.model}_{self.tts.provider}"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "scenarioName": self.scenario_name,
            "repetition": self.repetition,
            "stt": self.stt.to_dict(),
            "llm": self.llm.to_dict(),
            "tts": self.tts.to_dict(),
            "audioEngine": self.audio_engine.to_dict(),
            "networkProfile": self.network_profile.value,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TestConfiguration":
        return cls(
            id=data["id"],
            scenario_name=data["scenarioName"],
            repetition=data["repetition"],
            stt=STTTestConfig.from_dict(data["stt"]),
            llm=LLMTestConfig.from_dict(data["llm"]),
            tts=TTSTestConfig.from_dict(data["tts"]),
            audio_engine=AudioEngineTestConfig.from_dict(data["audioEngine"]),
            network_profile=NetworkProfile(data.get("networkProfile", "localhost")),
        )


# ============================================================================
# Test Scenario
# ============================================================================

@dataclass
class TestScenario:
    """Definition of a test scenario."""
    id: str
    name: str
    description: str
    scenario_type: ScenarioType
    repetitions: int = 10
    user_utterance_audio_path: Optional[str] = None
    user_utterance_text: Optional[str] = None
    expected_response_type: ResponseType = ResponseType.MEDIUM

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "scenarioType": self.scenario_type.value,
            "repetitions": self.repetitions,
            "userUtteranceAudioPath": self.user_utterance_audio_path,
            "userUtteranceText": self.user_utterance_text,
            "expectedResponseType": self.expected_response_type.value,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TestScenario":
        """Deserialize from dictionary."""
        return cls(
            id=data["id"],
            name=data["name"],
            description=data["description"],
            scenario_type=ScenarioType(data["scenarioType"]),
            repetitions=data.get("repetitions", 10),
            user_utterance_audio_path=data.get("userUtteranceAudioPath"),
            user_utterance_text=data.get("userUtteranceText"),
            expected_response_type=ResponseType(data.get("expectedResponseType", "medium")),
        )


# ============================================================================
# Test Result
# ============================================================================

@dataclass
class TestResult:
    """Complete result from a single test execution."""
    id: str
    config_id: str
    scenario_name: str
    repetition: int
    timestamp: datetime
    client_type: ClientType

    # Per-stage latencies (milliseconds)
    stt_latency_ms: Optional[float]
    llm_ttfb_ms: float
    llm_completion_ms: float
    tts_ttfb_ms: float
    tts_completion_ms: float
    e2e_latency_ms: float

    # Network profile
    network_profile: NetworkProfile
    network_projections: Dict[str, float] = field(default_factory=dict)

    # Quality metrics
    stt_confidence: Optional[float] = None
    tts_audio_duration_ms: Optional[float] = None
    llm_output_tokens: Optional[int] = None
    llm_input_tokens: Optional[int] = None

    # Resource utilization
    peak_cpu_percent: Optional[float] = None
    peak_memory_mb: Optional[float] = None
    thermal_state: Optional[str] = None

    # Configuration snapshot
    stt_config: Optional[Dict[str, Any]] = None
    llm_config: Optional[Dict[str, Any]] = None
    tts_config: Optional[Dict[str, Any]] = None
    audio_config: Optional[Dict[str, Any]] = None

    # Errors
    errors: List[str] = field(default_factory=list)

    @property
    def is_success(self) -> bool:
        return len(self.errors) == 0

    def calculate_network_projections(
        self,
        stt_requires_network: bool,
        llm_requires_network: bool,
        tts_requires_network: bool,
    ) -> Dict[str, float]:
        """Calculate projected E2E latency for different network conditions."""
        projections = {}
        for profile in NetworkProfile:
            projected = self.e2e_latency_ms
            if stt_requires_network:
                projected += profile.added_latency_ms
            if llm_requires_network:
                projected += profile.added_latency_ms
            if tts_requires_network:
                projected += profile.added_latency_ms
            projections[profile.value] = projected
        return projections

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "configId": self.config_id,
            "scenarioName": self.scenario_name,
            "repetition": self.repetition,
            "timestamp": self.timestamp.isoformat(),
            "clientType": self.client_type.value,
            "sttLatencyMs": self.stt_latency_ms,
            "llmTTFBMs": self.llm_ttfb_ms,
            "llmCompletionMs": self.llm_completion_ms,
            "ttsTTFBMs": self.tts_ttfb_ms,
            "ttsCompletionMs": self.tts_completion_ms,
            "e2eLatencyMs": self.e2e_latency_ms,
            "networkProfile": self.network_profile.value,
            "networkProjections": self.network_projections,
            "sttConfidence": self.stt_confidence,
            "ttsAudioDurationMs": self.tts_audio_duration_ms,
            "llmOutputTokens": self.llm_output_tokens,
            "llmInputTokens": self.llm_input_tokens,
            "peakCPUPercent": self.peak_cpu_percent,
            "peakMemoryMB": self.peak_memory_mb,
            "thermalState": self.thermal_state,
            "sttConfig": self.stt_config,
            "llmConfig": self.llm_config,
            "ttsConfig": self.tts_config,
            "audioConfig": self.audio_config,
            "errors": self.errors,
            "isSuccess": self.is_success,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TestResult":
        """Deserialize from dictionary."""
        return cls(
            id=data["id"],
            config_id=data["configId"],
            scenario_name=data["scenarioName"],
            repetition=data["repetition"],
            timestamp=datetime.fromisoformat(data["timestamp"]),
            client_type=ClientType(data["clientType"]),
            stt_latency_ms=data.get("sttLatencyMs"),
            llm_ttfb_ms=data["llmTTFBMs"],
            llm_completion_ms=data["llmCompletionMs"],
            tts_ttfb_ms=data["ttsTTFBMs"],
            tts_completion_ms=data["ttsCompletionMs"],
            e2e_latency_ms=data["e2eLatencyMs"],
            network_profile=NetworkProfile(data["networkProfile"]),
            network_projections=data.get("networkProjections", {}),
            stt_confidence=data.get("sttConfidence"),
            tts_audio_duration_ms=data.get("ttsAudioDurationMs"),
            llm_output_tokens=data.get("llmOutputTokens"),
            llm_input_tokens=data.get("llmInputTokens"),
            peak_cpu_percent=data.get("peakCPUPercent"),
            peak_memory_mb=data.get("peakMemoryMB"),
            thermal_state=data.get("thermalState"),
            stt_config=data.get("sttConfig"),
            llm_config=data.get("llmConfig"),
            tts_config=data.get("ttsConfig"),
            audio_config=data.get("audioConfig"),
            errors=data.get("errors", []),
        )


# ============================================================================
# Client Status
# ============================================================================

@dataclass
class ClientCapabilities:
    """Capabilities of a test client."""
    supported_stt_providers: List[str]
    supported_llm_providers: List[str]
    supported_tts_providers: List[str]
    has_high_precision_timing: bool
    has_device_metrics: bool
    has_on_device_ml: bool
    max_concurrent_tests: int


@dataclass
class ClientStatus:
    """Current status of a test client."""
    client_id: str
    client_type: ClientType
    is_connected: bool
    is_running_test: bool
    current_config_id: Optional[str]
    last_heartbeat: datetime
    capabilities: Optional[ClientCapabilities] = None


# ============================================================================
# Test Run
# ============================================================================

@dataclass
class TestRun:
    """A complete test run (execution of a test suite)."""
    id: str
    suite_name: str
    suite_id: str
    started_at: datetime
    client_id: str
    client_type: ClientType
    total_configurations: int
    status: RunStatus = RunStatus.PENDING
    completed_at: Optional[datetime] = None
    completed_configurations: int = 0
    results: List[TestResult] = field(default_factory=list)

    @property
    def progress_percent(self) -> float:
        if self.total_configurations == 0:
            return 0.0
        return self.completed_configurations / self.total_configurations * 100

    @property
    def elapsed_time(self) -> float:
        """Elapsed time in seconds."""
        end_time = self.completed_at or datetime.now()
        return (end_time - self.started_at).total_seconds()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "suiteName": self.suite_name,
            "suiteId": self.suite_id,
            "startedAt": self.started_at.isoformat(),
            "completedAt": self.completed_at.isoformat() if self.completed_at else None,
            "clientId": self.client_id,
            "clientType": self.client_type.value,
            "status": self.status.value,
            "totalConfigurations": self.total_configurations,
            "completedConfigurations": self.completed_configurations,
            "progressPercent": self.progress_percent,
            "elapsedTimeSeconds": self.elapsed_time,
            "results": [r.to_dict() for r in self.results],
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TestRun":
        """Deserialize from dictionary."""
        completed_at = None
        if data.get("completedAt"):
            completed_at = datetime.fromisoformat(data["completedAt"])

        # Deserialize results if present
        results = []
        if "results" in data:
            results = [TestResult.from_dict(r) for r in data["results"]]

        return cls(
            id=data["id"],
            suite_name=data["suiteName"],
            suite_id=data["suiteId"],
            started_at=datetime.fromisoformat(data["startedAt"]),
            client_id=data["clientId"],
            client_type=ClientType(data["clientType"]),
            total_configurations=data["totalConfigurations"],
            status=RunStatus(data["status"]),
            completed_at=completed_at,
            completed_configurations=data.get("completedConfigurations", 0),
            results=results,
        )


# ============================================================================
# Analysis Report
# ============================================================================

@dataclass
class LatencyBreakdown:
    stt_ms: Optional[float]
    llm_ttfb_ms: float
    llm_completion_ms: float
    tts_ttfb_ms: float
    tts_completion_ms: float


@dataclass
class NetworkMeetsTarget:
    e2e_ms: float
    meets_500ms: bool
    meets_1000ms: bool


@dataclass
class RankedConfiguration:
    rank: int
    config_id: str
    median_e2e_ms: float
    p99_e2e_ms: float
    stddev_ms: float
    sample_count: int
    breakdown: LatencyBreakdown
    network_projections: Dict[str, NetworkMeetsTarget]
    estimated_cost_per_hour: float


@dataclass
class SummaryStatistics:
    total_configurations: int
    total_tests: int
    successful_tests: int
    failed_tests: int
    overall_median_e2e_ms: float
    overall_p99_e2e_ms: float
    overall_min_e2e_ms: float
    overall_max_e2e_ms: float
    median_stt_ms: Optional[float]
    median_llm_ttfb_ms: float
    median_llm_completion_ms: float
    median_tts_ttfb_ms: float
    median_tts_completion_ms: float
    test_duration_minutes: float


@dataclass
class NetworkProjection:
    network: str
    added_latency_ms: float
    projected_median_ms: float
    projected_p99_ms: float
    meets_target: bool
    configs_meeting_target: int
    total_configs: int


@dataclass
class Regression:
    config_id: str
    metric: str
    baseline_value: float
    current_value: float
    change_percent: float
    severity: RegressionSeverity


@dataclass
class AnalysisReport:
    run_id: str
    generated_at: datetime
    summary: SummaryStatistics
    best_configurations: List[RankedConfiguration]
    network_projections: List[NetworkProjection]
    regressions: List[Regression]
    recommendations: List[str]


# ============================================================================
# Test Suite Definition
# ============================================================================

@dataclass
class ParameterSpace:
    stt_configs: List[STTTestConfig]
    llm_configs: List[LLMTestConfig]
    tts_configs: List[TTSTestConfig]
    audio_configs: List[AudioEngineTestConfig] = field(
        default_factory=lambda: [AudioEngineTestConfig()]
    )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "sttConfigs": [c.to_dict() for c in self.stt_configs],
            "llmConfigs": [c.to_dict() for c in self.llm_configs],
            "ttsConfigs": [c.to_dict() for c in self.tts_configs],
            "audioConfigs": [c.to_dict() for c in self.audio_configs],
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "ParameterSpace":
        return cls(
            stt_configs=[STTTestConfig.from_dict(c) for c in data["sttConfigs"]],
            llm_configs=[LLMTestConfig.from_dict(c) for c in data["llmConfigs"]],
            tts_configs=[TTSTestConfig.from_dict(c) for c in data["ttsConfigs"]],
            audio_configs=[AudioEngineTestConfig.from_dict(c) for c in data.get("audioConfigs", [{"sampleRate": 24000}])],
        )


@dataclass
class TestSuiteDefinition:
    """Complete test suite definition."""
    id: str
    name: str
    description: str
    scenarios: List[TestScenario]
    network_profiles: List[NetworkProfile]
    parameter_space: ParameterSpace

    def generate_configurations(self) -> List[TestConfiguration]:
        """Generate all test configurations from parameter space."""
        configs = []
        config_index = 0

        for scenario in self.scenarios:
            for stt_config in self.parameter_space.stt_configs:
                for llm_config in self.parameter_space.llm_configs:
                    for tts_config in self.parameter_space.tts_configs:
                        for audio_config in self.parameter_space.audio_configs:
                            for network_profile in self.network_profiles:
                                for repetition in range(1, scenario.repetitions + 1):
                                    config_index += 1
                                    config = TestConfiguration(
                                        id=f"config_{config_index}",
                                        scenario_name=scenario.name,
                                        repetition=repetition,
                                        stt=stt_config,
                                        llm=llm_config,
                                        tts=tts_config,
                                        audio_engine=audio_config,
                                        network_profile=network_profile,
                                    )
                                    configs.append(config)

        return configs

    @property
    def total_test_count(self) -> int:
        """Estimated total number of tests."""
        scenario_reps = sum(s.repetitions for s in self.scenarios)
        return (
            scenario_reps
            * len(self.parameter_space.stt_configs)
            * len(self.parameter_space.llm_configs)
            * len(self.parameter_space.tts_configs)
            * len(self.parameter_space.audio_configs)
            * len(self.network_profiles)
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "scenarios": [s.to_dict() for s in self.scenarios],
            "networkProfiles": [p.value for p in self.network_profiles],
            "parameterSpace": self.parameter_space.to_dict(),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "TestSuiteDefinition":
        return cls(
            id=data["id"],
            name=data["name"],
            description=data["description"],
            scenarios=[TestScenario.from_dict(s) for s in data["scenarios"]],
            network_profiles=[NetworkProfile(p) for p in data["networkProfiles"]],
            parameter_space=ParameterSpace.from_dict(data["parameterSpace"]),
        )


# ============================================================================
# Predefined Test Suites
# ============================================================================

def create_quick_validation_suite() -> TestSuiteDefinition:
    """Quick validation suite for CI/CD."""
    return TestSuiteDefinition(
        id="quick_validation",
        name="Quick Validation",
        description="Fast sanity check for CI/CD pipelines",
        scenarios=[
            TestScenario(
                id="short_response",
                name="Short Response",
                description="Brief Q&A exchange",
                scenario_type=ScenarioType.TEXT_INPUT,
                repetitions=3,
                user_utterance_text="What is the capital of France?",
                expected_response_type=ResponseType.SHORT,
            )
        ],
        network_profiles=[NetworkProfile.LOCALHOST],
        parameter_space=ParameterSpace(
            stt_configs=[STTTestConfig(provider="deepgram")],
            llm_configs=[LLMTestConfig(provider="anthropic", model="claude-3-5-haiku-20241022")],
            tts_configs=[TTSTestConfig(provider="chatterbox")],
        ),
    )


def create_provider_comparison_suite() -> TestSuiteDefinition:
    """Provider comparison suite."""
    return TestSuiteDefinition(
        id="provider_comparison",
        name="Provider Comparison",
        description="Compare all available providers",
        scenarios=[
            TestScenario(
                id="short_response",
                name="Short Response",
                description="Brief Q&A exchange",
                scenario_type=ScenarioType.TEXT_INPUT,
                repetitions=10,
                user_utterance_text="What is photosynthesis?",
                expected_response_type=ResponseType.SHORT,
            ),
            TestScenario(
                id="medium_response",
                name="Medium Response",
                description="Moderate explanation",
                scenario_type=ScenarioType.TEXT_INPUT,
                repetitions=5,
                user_utterance_text="Explain how the human heart works.",
                expected_response_type=ResponseType.MEDIUM,
            ),
        ],
        network_profiles=[
            NetworkProfile.LOCALHOST,
            NetworkProfile.WIFI,
            NetworkProfile.CELLULAR_US,
        ],
        parameter_space=ParameterSpace(
            stt_configs=[
                STTTestConfig(provider="deepgram"),
                STTTestConfig(provider="assemblyai"),
                STTTestConfig(provider="apple"),
            ],
            llm_configs=[
                LLMTestConfig(provider="anthropic", model="claude-3-5-haiku-20241022"),
                LLMTestConfig(provider="openai", model="gpt-4o-mini"),
                LLMTestConfig(provider="selfhosted", model="qwen2.5:7b"),
            ],
            tts_configs=[
                TTSTestConfig(provider="chatterbox"),
                TTSTestConfig(provider="vibevoice"),
                TTSTestConfig(provider="apple"),
            ],
        ),
    )


# ============================================================================
# Performance Baseline
# ============================================================================

@dataclass
class BaselineMetrics:
    """Metrics captured for a baseline."""
    median_e2e_ms: float
    p99_e2e_ms: float
    min_e2e_ms: float
    max_e2e_ms: float
    median_stt_ms: Optional[float]
    median_llm_ttfb_ms: float
    median_llm_completion_ms: float
    median_tts_ttfb_ms: float
    median_tts_completion_ms: float
    sample_count: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            "medianE2EMs": self.median_e2e_ms,
            "p99E2EMs": self.p99_e2e_ms,
            "minE2EMs": self.min_e2e_ms,
            "maxE2EMs": self.max_e2e_ms,
            "medianSTTMs": self.median_stt_ms,
            "medianLLMTTFBMs": self.median_llm_ttfb_ms,
            "medianLLMCompletionMs": self.median_llm_completion_ms,
            "medianTTSTTFBMs": self.median_tts_ttfb_ms,
            "medianTTSCompletionMs": self.median_tts_completion_ms,
            "sampleCount": self.sample_count,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BaselineMetrics":
        return cls(
            median_e2e_ms=data["medianE2EMs"],
            p99_e2e_ms=data["p99E2EMs"],
            min_e2e_ms=data["minE2EMs"],
            max_e2e_ms=data["maxE2EMs"],
            median_stt_ms=data.get("medianSTTMs"),
            median_llm_ttfb_ms=data["medianLLMTTFBMs"],
            median_llm_completion_ms=data["medianLLMCompletionMs"],
            median_tts_ttfb_ms=data["medianTTSTTFBMs"],
            median_tts_completion_ms=data["medianTTSCompletionMs"],
            sample_count=data["sampleCount"],
        )


@dataclass
class PerformanceBaseline:
    """Performance baseline for regression detection."""
    id: str
    name: str
    description: str
    run_id: str
    created_at: datetime
    is_active: bool = False
    config_metrics: Dict[str, BaselineMetrics] = field(default_factory=dict)
    overall_metrics: Optional[BaselineMetrics] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "runId": self.run_id,
            "createdAt": self.created_at.isoformat(),
            "isActive": self.is_active,
            "configMetrics": {
                k: v.to_dict() for k, v in self.config_metrics.items()
            },
            "overallMetrics": self.overall_metrics.to_dict() if self.overall_metrics else None,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "PerformanceBaseline":
        return cls(
            id=data["id"],
            name=data["name"],
            description=data["description"],
            run_id=data["runId"],
            created_at=datetime.fromisoformat(data["createdAt"]),
            is_active=data.get("isActive", False),
            config_metrics={
                k: BaselineMetrics.from_dict(v)
                for k, v in data.get("configMetrics", {}).items()
            },
            overall_metrics=BaselineMetrics.from_dict(data["overallMetrics"])
            if data.get("overallMetrics") else None,
        )
