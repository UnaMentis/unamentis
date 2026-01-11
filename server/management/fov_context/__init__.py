"""
FOV Context Management - Server-side implementation

Foveated context management for voice tutoring sessions.
Manages hierarchical cognitive buffers and builds context for LLM calls.
"""

from .confidence import (
    ConfidenceAnalysis,
    ConfidenceMarker,
    ConfidenceMonitor,
    ConfidenceMonitorConfig,
    ConfidenceTrend,
    ExpansionPriority,
    ExpansionRecommendation,
    ExpansionScope,
)
from .manager import (
    DEFAULT_SYSTEM_PROMPT,
    FOVContextManager,
)
from .models import (
    AdaptiveBudgetConfig,
    ConversationTurn,
    CurriculumPosition,
    EpisodicBuffer,
    FOVContext,
    GlossaryTerm,
    ImmediateBuffer,
    LearnerSignals,
    MessageRole,
    MisconceptionTrigger,
    MODEL_CONTEXT_WINDOWS,
    ModelTier,
    PacePreference,
    SemanticBuffer,
    TokenBudgets,
    TopicSummary,
    TranscriptSegment,
    WorkingBuffer,
)
from .session import (
    FOVSession,
    PlaybackState,
    SessionConfig,
    SessionEvent,
    SessionManager,
    SessionState,
    UserSession,
    UserVoiceConfig,
)

__all__ = [
    # Models
    "AdaptiveBudgetConfig",
    "ConversationTurn",
    "CurriculumPosition",
    "EpisodicBuffer",
    "FOVContext",
    "GlossaryTerm",
    "ImmediateBuffer",
    "LearnerSignals",
    "MessageRole",
    "MisconceptionTrigger",
    "MODEL_CONTEXT_WINDOWS",
    "ModelTier",
    "PacePreference",
    "SemanticBuffer",
    "TokenBudgets",
    "TopicSummary",
    "TranscriptSegment",
    "WorkingBuffer",
    # Manager
    "DEFAULT_SYSTEM_PROMPT",
    "FOVContextManager",
    # Confidence
    "ConfidenceAnalysis",
    "ConfidenceMarker",
    "ConfidenceMonitor",
    "ConfidenceMonitorConfig",
    "ConfidenceTrend",
    "ExpansionPriority",
    "ExpansionRecommendation",
    "ExpansionScope",
    # Session
    "FOVSession",
    "PlaybackState",
    "SessionConfig",
    "SessionEvent",
    "SessionManager",
    "SessionState",
    "UserSession",
    "UserVoiceConfig",
]
