"""
FOV Context Models - Server-side implementation

Foveated context management for voice tutoring sessions.
Based on "Foveated Rendering" from VR: center of attention gets full detail,
periphery is compressed.

Hierarchical Cognitive Buffers:
- Immediate: Current turn, barge-in utterance (highest priority)
- Working: Current topic materials, glossary, misconceptions
- Episodic: Session memory, completed topics, learner signals
- Semantic: Curriculum overview, topic positioning
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional
import uuid


class ModelTier(str, Enum):
    """Model capability tiers based on context window size."""
    CLOUD = "cloud"        # 100K+ tokens (Claude, GPT-4)
    MID_RANGE = "mid_range"  # 32K-100K tokens
    ON_DEVICE = "on_device"  # 8K-32K tokens
    TINY = "tiny"          # <8K tokens

    @classmethod
    def from_context_window(cls, context_window: int) -> "ModelTier":
        """Determine tier from context window size."""
        if context_window >= 100_000:
            return cls.CLOUD
        elif context_window >= 32_000:
            return cls.MID_RANGE
        elif context_window >= 8_000:
            return cls.ON_DEVICE
        else:
            return cls.TINY


@dataclass
class TokenBudgets:
    """Token budgets for each buffer layer."""
    immediate: int
    working: int
    episodic: int
    semantic: int
    total: int

    @classmethod
    def for_tier(cls, tier: ModelTier) -> "TokenBudgets":
        """Get token budgets for a model tier."""
        budgets = {
            ModelTier.CLOUD: cls(
                immediate=4000,
                working=4000,
                episodic=2500,
                semantic=1500,
                total=12000
            ),
            ModelTier.MID_RANGE: cls(
                immediate=3000,
                working=2500,
                episodic=1500,
                semantic=1000,
                total=8000
            ),
            ModelTier.ON_DEVICE: cls(
                immediate=1500,
                working=1500,
                episodic=700,
                semantic=300,
                total=4000
            ),
            ModelTier.TINY: cls(
                immediate=1000,
                working=600,
                episodic=300,
                semantic=100,
                total=2000
            ),
        }
        return budgets[tier]


@dataclass
class AdaptiveBudgetConfig:
    """Configuration for adaptive token budgets."""
    tier: ModelTier
    budgets: TokenBudgets
    max_conversation_turns: int
    model_context_window: int

    @classmethod
    def from_context_window(cls, context_window: int) -> "AdaptiveBudgetConfig":
        """Create config from model context window size."""
        tier = ModelTier.from_context_window(context_window)
        budgets = TokenBudgets.for_tier(tier)

        # More turns for larger context windows
        max_turns = {
            ModelTier.CLOUD: 20,
            ModelTier.MID_RANGE: 12,
            ModelTier.ON_DEVICE: 6,
            ModelTier.TINY: 3,
        }

        return cls(
            tier=tier,
            budgets=budgets,
            max_conversation_turns=max_turns[tier],
            model_context_window=context_window
        )

    @classmethod
    def for_model(cls, model_name: str) -> "AdaptiveBudgetConfig":
        """Create config for a specific model."""
        context_window = MODEL_CONTEXT_WINDOWS.get(model_name, 32_000)
        return cls.from_context_window(context_window)


# Known model context windows
MODEL_CONTEXT_WINDOWS = {
    # Anthropic
    "claude-3-5-sonnet-20241022": 200_000,
    "claude-3-5-haiku-20241022": 200_000,
    "claude-3-opus-20240229": 200_000,
    "claude-3-sonnet-20240229": 200_000,
    "claude-3-haiku-20240307": 200_000,
    # OpenAI
    "gpt-4o": 128_000,
    "gpt-4o-mini": 128_000,
    "gpt-4-turbo": 128_000,
    "gpt-4": 8_192,
    "gpt-3.5-turbo": 16_385,
    # Self-hosted
    "qwen2.5:32b": 32_000,
    "qwen2.5:14b": 32_000,
    "qwen2.5:7b": 32_000,
    "llama3.1:70b": 128_000,
    "llama3.1:8b": 128_000,
    "mistral:7b": 32_000,
    # Mistral December 2025
    "ministral-3:14b": 256_000,
    "ministral-3:8b": 256_000,
    "ministral-3:3b": 256_000,
    # On-device
    "mlx-community/Qwen2.5-7B-Instruct-4bit": 32_000,
    "mlx-community/Llama-3.2-3B-Instruct-4bit": 8_000,
}


# --- Conversation Models ---

class MessageRole(str, Enum):
    """Role of a message in conversation."""
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"


@dataclass
class ConversationTurn:
    """A single turn in the conversation."""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    role: MessageRole = MessageRole.USER
    content: str = ""
    timestamp: datetime = field(default_factory=datetime.now)
    token_estimate: int = 0
    is_barge_in: bool = False

    def __post_init__(self):
        if not self.token_estimate:
            # Rough estimate: ~4 chars per token
            self.token_estimate = len(self.content) // 4


@dataclass
class TranscriptSegment:
    """A segment of the curriculum transcript."""
    segment_id: str
    text: str
    start_time: float = 0.0
    end_time: float = 0.0
    topic_id: Optional[str] = None


# --- Buffer Models ---

@dataclass
class ImmediateBuffer:
    """
    Immediate Buffer: Highest priority, current interaction.
    Contains the most recent conversation turns and any barge-in context.
    """
    recent_turns: list[ConversationTurn] = field(default_factory=list)
    barge_in_utterance: Optional[str] = None
    current_segment: Optional[TranscriptSegment] = None
    interrupted_at_position: Optional[float] = None

    def render(self, token_budget: int) -> str:
        """Render buffer content within token budget."""
        parts = []

        # Barge-in gets highest priority
        if self.barge_in_utterance:
            parts.append(f"[USER INTERRUPTED]: {self.barge_in_utterance}")

        # Current segment context
        if self.current_segment:
            parts.append(f"[INTERRUPTED CONTENT]: {self.current_segment.text}")

        # Recent conversation turns (newest first for priority)
        for turn in reversed(self.recent_turns):
            role_label = "User" if turn.role == MessageRole.USER else "Tutor"
            parts.append(f"{role_label}: {turn.content}")

        result = "\n\n".join(parts)
        return self._truncate_to_budget(result, token_budget)

    def _truncate_to_budget(self, text: str, budget: int) -> str:
        """Truncate text to fit within token budget."""
        estimated_tokens = len(text) // 4
        if estimated_tokens <= budget:
            return text
        target_chars = budget * 4
        return text[:target_chars - 3] + "..."


@dataclass
class GlossaryTerm:
    """A term from the curriculum glossary."""
    term: str
    definition: str
    pronunciation: Optional[str] = None


@dataclass
class MisconceptionTrigger:
    """A common misconception and how to address it."""
    trigger_phrase: str
    misconception: str
    remediation: str


@dataclass
class WorkingBuffer:
    """
    Working Buffer: Current topic context.
    Contains topic materials, glossary, and misconception triggers.
    """
    topic_id: Optional[str] = None
    topic_title: str = ""
    topic_content: str = ""
    learning_objectives: list[str] = field(default_factory=list)
    glossary_terms: list[GlossaryTerm] = field(default_factory=list)
    misconception_triggers: list[MisconceptionTrigger] = field(default_factory=list)

    def render(self, token_budget: int) -> str:
        """Render buffer content within token budget."""
        parts = []

        if self.topic_title:
            parts.append(f"CURRENT TOPIC: {self.topic_title}")

        if self.learning_objectives:
            objectives = "\n".join(f"- {obj}" for obj in self.learning_objectives)
            parts.append(f"LEARNING OBJECTIVES:\n{objectives}")

        if self.topic_content:
            parts.append(f"TOPIC OUTLINE:\n{self.topic_content}")

        if self.glossary_terms:
            terms = "\n".join(
                f"- {t.term}: {t.definition}" for t in self.glossary_terms[:5]
            )
            parts.append(f"KEY TERMS:\n{terms}")

        if self.misconception_triggers:
            triggers = "\n".join(
                f"- Watch for: '{t.trigger_phrase}' -> Clarify: {t.remediation}"
                for t in self.misconception_triggers[:3]
            )
            parts.append(f"COMMON MISCONCEPTIONS:\n{triggers}")

        result = "\n\n".join(parts)
        return self._truncate_to_budget(result, token_budget)

    def _truncate_to_budget(self, text: str, budget: int) -> str:
        estimated_tokens = len(text) // 4
        if estimated_tokens <= budget:
            return text
        target_chars = budget * 4
        return text[:target_chars - 3] + "..."


class PacePreference(str, Enum):
    """Learner's pace preference detected from signals."""
    SLOWER = "slower"
    NORMAL = "normal"
    FASTER = "faster"


@dataclass
class LearnerSignals:
    """Signals about the learner's state detected during the session."""
    clarification_requests: int = 0
    repetition_requests: int = 0
    confusion_indicators: int = 0
    pace_preference: Optional[PacePreference] = None
    topics_mastered: list[str] = field(default_factory=list)
    struggling_concepts: list[str] = field(default_factory=list)


@dataclass
class TopicSummary:
    """Summary of a completed topic."""
    topic_id: str
    title: str
    summary: str
    mastery_level: float  # 0.0 to 1.0
    completed_at: datetime = field(default_factory=datetime.now)


@dataclass
class EpisodicBuffer:
    """
    Episodic Buffer: Session memory.
    Contains completed topics, learner signals, and session context.
    """
    topic_summaries: list[TopicSummary] = field(default_factory=list)
    user_questions: list[str] = field(default_factory=list)
    learner_signals: LearnerSignals = field(default_factory=LearnerSignals)
    session_start: datetime = field(default_factory=datetime.now)
    session_duration_minutes: float = 0.0

    def render(self, token_budget: int) -> str:
        """Render buffer content within token budget."""
        parts = []

        # Session context
        parts.append(
            f"SESSION: Started {self.session_start.strftime('%H:%M')}, "
            f"Duration: {self.session_duration_minutes:.0f} min"
        )

        # Learner signals
        signals = self.learner_signals
        if signals.clarification_requests > 0 or signals.confusion_indicators > 0:
            signal_parts = []
            if signals.clarification_requests > 0:
                signal_parts.append(f"{signals.clarification_requests} clarifications")
            if signals.confusion_indicators > 0:
                signal_parts.append(f"{signals.confusion_indicators} confusion signals")
            if signals.pace_preference:
                signal_parts.append(f"prefers {signals.pace_preference.value} pace")
            parts.append(f"LEARNER SIGNALS: {', '.join(signal_parts)}")

        # Topic summaries
        if self.topic_summaries:
            summaries = "\n".join(
                f"- {s.title} (mastery: {s.mastery_level:.0%})"
                for s in self.topic_summaries[-5:]  # Last 5 topics
            )
            parts.append(f"COMPLETED TOPICS:\n{summaries}")

        # Recent questions
        if self.user_questions:
            questions = "\n".join(f"- {q}" for q in self.user_questions[-3:])
            parts.append(f"RECENT QUESTIONS:\n{questions}")

        result = "\n\n".join(parts)
        return self._truncate_to_budget(result, token_budget)

    def _truncate_to_budget(self, text: str, budget: int) -> str:
        estimated_tokens = len(text) // 4
        if estimated_tokens <= budget:
            return text
        target_chars = budget * 4
        return text[:target_chars - 3] + "..."


@dataclass
class CurriculumPosition:
    """Position within the curriculum hierarchy."""
    curriculum_id: str
    curriculum_title: str
    current_topic_index: int
    total_topics: int
    unit_title: Optional[str] = None
    module_title: Optional[str] = None


@dataclass
class SemanticBuffer:
    """
    Semantic Buffer: Curriculum overview.
    Contains curriculum structure and positioning.
    """
    curriculum_outline: str = ""
    position: Optional[CurriculumPosition] = None
    prerequisite_topics: list[str] = field(default_factory=list)
    upcoming_topics: list[str] = field(default_factory=list)

    def render(self, token_budget: int) -> str:
        """Render buffer content within token budget."""
        parts = []

        if self.position:
            pos = self.position
            progress = f"{pos.current_topic_index + 1}/{pos.total_topics}"
            parts.append(
                f"CURRICULUM: {pos.curriculum_title}\n"
                f"Progress: Topic {progress}"
            )

        if self.curriculum_outline:
            parts.append(f"OUTLINE:\n{self.curriculum_outline}")

        if self.prerequisite_topics:
            prereqs = ", ".join(self.prerequisite_topics[:3])
            parts.append(f"Prerequisites: {prereqs}")

        if self.upcoming_topics:
            upcoming = ", ".join(self.upcoming_topics[:3])
            parts.append(f"Coming up: {upcoming}")

        result = "\n\n".join(parts)
        return self._truncate_to_budget(result, token_budget)

    def _truncate_to_budget(self, text: str, budget: int) -> str:
        estimated_tokens = len(text) // 4
        if estimated_tokens <= budget:
            return text
        target_chars = budget * 4
        return text[:target_chars - 3] + "..."


# --- Complete FOV Context ---

@dataclass
class FOVContext:
    """
    Complete foveated context for an LLM call.
    Combines all buffer layers into a coherent context.
    """
    system_prompt: str
    immediate_context: str
    working_context: str
    episodic_context: str
    semantic_context: str
    total_token_estimate: int = 0

    def __post_init__(self):
        if not self.total_token_estimate:
            total = (
                len(self.system_prompt) +
                len(self.immediate_context) +
                len(self.working_context) +
                len(self.episodic_context) +
                len(self.semantic_context)
            ) // 4
            self.total_token_estimate = total

    def to_system_message(self) -> str:
        """Combine all context into a single system message."""
        parts = [self.system_prompt]

        if self.semantic_context:
            parts.append(f"=== CURRICULUM CONTEXT ===\n{self.semantic_context}")

        if self.working_context:
            parts.append(f"=== CURRENT TOPIC ===\n{self.working_context}")

        if self.episodic_context:
            parts.append(f"=== SESSION CONTEXT ===\n{self.episodic_context}")

        if self.immediate_context:
            parts.append(f"=== IMMEDIATE CONTEXT ===\n{self.immediate_context}")

        return "\n\n".join(parts)

    def to_messages(self) -> list[dict]:
        """Convert to LLM message format."""
        return [
            {"role": "system", "content": self.to_system_message()}
        ]
