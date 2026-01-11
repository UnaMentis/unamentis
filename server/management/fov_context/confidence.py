"""
Confidence Monitor - Server-side implementation

Analyzes LLM responses for uncertainty signals and determines when
to trigger context expansion.
"""

import logging
import re
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

logger = logging.getLogger(__name__)


class ConfidenceMarker(str, Enum):
    """Types of confidence/uncertainty markers detected in responses."""
    HEDGING = "hedging"
    QUESTION_DEFLECTION = "question_deflection"
    KNOWLEDGE_GAP = "knowledge_gap"
    VAGUE_LANGUAGE = "vague_language"
    OUT_OF_SCOPE = "out_of_scope"


class ConfidenceTrend(str, Enum):
    """Trend direction for confidence over recent responses."""
    STABLE = "stable"
    IMPROVING = "improving"
    DECLINING = "declining"


class ExpansionPriority(str, Enum):
    """Priority level for context expansion."""
    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"

    def __lt__(self, other: "ExpansionPriority") -> bool:
        order = [self.NONE, self.LOW, self.MEDIUM, self.HIGH]
        return order.index(self) < order.index(other)

    def __le__(self, other: "ExpansionPriority") -> bool:
        return self == other or self < other

    def __gt__(self, other: "ExpansionPriority") -> bool:
        return not self <= other

    def __ge__(self, other: "ExpansionPriority") -> bool:
        return not self < other


class ExpansionScope(str, Enum):
    """Scope for context expansion."""
    CURRENT_TOPIC = "current_topic"
    CURRENT_UNIT = "current_unit"
    FULL_CURRICULUM = "full_curriculum"
    RELATED_TOPICS = "related_topics"


@dataclass
class ConfidenceMonitorConfig:
    """Configuration for confidence detection thresholds."""
    expansion_threshold: float = 0.5  # Confidence below this triggers expansion
    trend_threshold: float = 0.75     # For detecting declining trends
    hedging_weight: float = 0.25
    deflection_weight: float = 0.3
    knowledge_gap_weight: float = 0.35
    vague_language_weight: float = 0.1

    @classmethod
    def tutoring(cls) -> "ConfidenceMonitorConfig":
        """Configuration tuned for tutoring interactions."""
        return cls(
            expansion_threshold=0.5,
            trend_threshold=0.75,
            hedging_weight=0.25,
            deflection_weight=0.3,
            knowledge_gap_weight=0.35,
            vague_language_weight=0.1
        )

    @classmethod
    def strict(cls) -> "ConfidenceMonitorConfig":
        """Stricter configuration for higher quality responses."""
        return cls(
            expansion_threshold=0.6,
            trend_threshold=0.8,
            hedging_weight=0.3,
            deflection_weight=0.25,
            knowledge_gap_weight=0.35,
            vague_language_weight=0.1
        )


@dataclass
class ConfidenceAnalysis:
    """Result of analyzing response confidence."""
    confidence_score: float  # 0.0 = uncertain, 1.0 = confident
    uncertainty_score: float  # Inverse of confidence
    hedging_score: float
    question_deflection_score: float
    knowledge_gap_score: float
    vague_language_score: float
    detected_markers: set[ConfidenceMarker] = field(default_factory=set)
    trend: ConfidenceTrend = ConfidenceTrend.STABLE


@dataclass
class ExpansionRecommendation:
    """Recommendation for context expansion."""
    should_expand: bool
    priority: ExpansionPriority
    suggested_scope: ExpansionScope
    reason: str
    query_hint: Optional[str] = None


class ConfidenceMonitor:
    """
    Monitors LLM response confidence and determines when context expansion
    is needed.

    Detects uncertainty signals:
    - Hedging language ("I think", "I'm not sure", etc.)
    - Question deflection ("I can't help with that")
    - Knowledge gaps ("I don't have information about")
    - Vague language ("probably", "might", "could be")
    """

    def __init__(self, config: Optional[ConfidenceMonitorConfig] = None):
        self.config = config or ConfidenceMonitorConfig.tutoring()
        self._recent_scores: deque[float] = deque(maxlen=10)
        self._last_analysis: Optional[ConfidenceAnalysis] = None

    # --- Hedging Phrases ---
    HEDGING_PHRASES = {
        "i'm not sure": 0.8,
        "i think": 0.4,
        "i believe": 0.4,
        "i'm uncertain": 0.9,
        "i'm not certain": 0.9,
        "possibly": 0.5,
        "perhaps": 0.5,
        "maybe": 0.6,
        "might be": 0.5,
        "could be": 0.5,
        "it seems": 0.4,
        "it appears": 0.4,
        "as far as i know": 0.6,
        "to the best of my knowledge": 0.5,
        "i would guess": 0.7,
        "if i recall correctly": 0.6,
        "don't quote me on this": 0.8,
    }

    # --- Deflection Patterns ---
    DEFLECTION_PATTERNS = [
        r"i can't help with that",
        r"that's (outside|beyond) (my|the) scope",
        r"i'm not (able|equipped) to",
        r"you (should|might want to) (ask|consult)",
        r"i (don't|cannot) provide (medical|legal|financial) advice",
        r"let me redirect you",
        r"that's not something i can",
        r"i'm not the (right|best) (source|person)",
    ]

    # --- Knowledge Gap Patterns ---
    KNOWLEDGE_GAP_PATTERNS = [
        r"i don't have (information|data|details) (about|on)",
        r"i'm not (aware|informed) (of|about)",
        r"i (don't|can't) know",
        r"that information (isn't|is not) available",
        r"i (haven't|have not) (learned|been trained on)",
        r"my knowledge (doesn't|does not) (include|cover)",
        r"i (lack|don't have) (specific|detailed) (knowledge|information)",
        r"(outside|beyond) my (training|knowledge)",
    ]

    # --- Vague Language ---
    VAGUE_LANGUAGE = {
        "probably": 0.3,
        "likely": 0.2,
        "typically": 0.1,
        "usually": 0.1,
        "generally": 0.1,
        "often": 0.1,
        "sometimes": 0.2,
        "somewhat": 0.3,
        "kind of": 0.3,
        "sort of": 0.3,
        "more or less": 0.4,
        "roughly": 0.3,
        "approximately": 0.2,
        "around": 0.1,
    }

    def analyze_response(self, response: str) -> ConfidenceAnalysis:
        """
        Analyze an LLM response for confidence signals.

        Args:
            response: The LLM's response text

        Returns:
            ConfidenceAnalysis with scores and detected markers
        """
        text = response.lower()
        detected_markers: set[ConfidenceMarker] = set()

        # Calculate component scores
        hedging_score = self._calculate_hedging_score(text)
        if hedging_score > 0.3:
            detected_markers.add(ConfidenceMarker.HEDGING)

        deflection_score = self._calculate_deflection_score(text)
        if deflection_score > 0.3:
            detected_markers.add(ConfidenceMarker.QUESTION_DEFLECTION)

        knowledge_gap_score = self._calculate_knowledge_gap_score(text)
        if knowledge_gap_score > 0.3:
            detected_markers.add(ConfidenceMarker.KNOWLEDGE_GAP)

        vague_score = self._calculate_vague_language_score(text)
        if vague_score > 0.3:
            detected_markers.add(ConfidenceMarker.VAGUE_LANGUAGE)

        # Calculate weighted uncertainty score
        uncertainty_score = (
            hedging_score * self.config.hedging_weight +
            deflection_score * self.config.deflection_weight +
            knowledge_gap_score * self.config.knowledge_gap_weight +
            vague_score * self.config.vague_language_weight
        )

        # Confidence is inverse of uncertainty (clamped to 0-1)
        confidence_score = max(0.0, min(1.0, 1.0 - uncertainty_score))

        # Record score for trend analysis
        self._record_score(confidence_score)

        # Determine trend
        trend = self._calculate_trend()

        analysis = ConfidenceAnalysis(
            confidence_score=confidence_score,
            uncertainty_score=uncertainty_score,
            hedging_score=hedging_score,
            question_deflection_score=deflection_score,
            knowledge_gap_score=knowledge_gap_score,
            vague_language_score=vague_score,
            detected_markers=detected_markers,
            trend=trend
        )

        self._last_analysis = analysis

        logger.debug(
            "Analyzed response confidence",
            extra={
                "confidence": confidence_score,
                "markers": [m.value for m in detected_markers],
                "trend": trend.value
            }
        )

        return analysis

    def should_trigger_expansion(self, analysis: ConfidenceAnalysis) -> bool:
        """Determine if context expansion should be triggered."""
        # Low confidence triggers expansion
        if analysis.confidence_score < self.config.expansion_threshold:
            return True

        # High-signal markers trigger expansion
        high_signal_markers = {
            ConfidenceMarker.KNOWLEDGE_GAP,
            ConfidenceMarker.OUT_OF_SCOPE
        }
        if analysis.detected_markers & high_signal_markers:
            return True

        # Declining trend triggers expansion
        if analysis.trend == ConfidenceTrend.DECLINING:
            return True

        return False

    def get_expansion_recommendation(
        self,
        analysis: ConfidenceAnalysis
    ) -> ExpansionRecommendation:
        """
        Get a recommendation for how to expand context.

        Args:
            analysis: The confidence analysis result

        Returns:
            ExpansionRecommendation with scope and priority
        """
        if not self.should_trigger_expansion(analysis):
            return ExpansionRecommendation(
                should_expand=False,
                priority=ExpansionPriority.NONE,
                suggested_scope=ExpansionScope.CURRENT_TOPIC,
                reason="Confidence is sufficient"
            )

        # Determine priority based on severity
        if analysis.confidence_score < 0.3:
            priority = ExpansionPriority.HIGH
        elif analysis.confidence_score < 0.5:
            priority = ExpansionPriority.MEDIUM
        else:
            priority = ExpansionPriority.LOW

        # Determine scope based on markers
        if ConfidenceMarker.OUT_OF_SCOPE in analysis.detected_markers:
            scope = ExpansionScope.RELATED_TOPICS
            reason = "Response indicates topic is out of scope"
        elif ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers:
            scope = ExpansionScope.FULL_CURRICULUM
            reason = "Knowledge gap detected, searching broader curriculum"
        elif analysis.trend == ConfidenceTrend.DECLINING:
            scope = ExpansionScope.CURRENT_UNIT
            reason = "Confidence declining, expanding to related topics"
        else:
            scope = ExpansionScope.CURRENT_TOPIC
            reason = "Uncertainty detected in current topic area"

        return ExpansionRecommendation(
            should_expand=True,
            priority=priority,
            suggested_scope=scope,
            reason=reason
        )

    def update_config(self, config: ConfidenceMonitorConfig) -> None:
        """Update the monitor configuration."""
        self.config = config

    def reset(self) -> None:
        """Reset the monitor state."""
        self._recent_scores.clear()
        self._last_analysis = None

    # --- Private Methods ---

    def _calculate_hedging_score(self, text: str) -> float:
        """Calculate hedging language score."""
        total_score = 0.0
        match_count = 0

        for phrase, weight in self.HEDGING_PHRASES.items():
            if phrase in text:
                total_score += weight
                match_count += 1

        if match_count == 0:
            return 0.0

        return min(1.0, total_score / max(1, match_count))

    def _calculate_deflection_score(self, text: str) -> float:
        """Calculate question deflection score."""
        max_score = 0.0

        for pattern in self.DEFLECTION_PATTERNS:
            if re.search(pattern, text):
                max_score = max(max_score, 0.8)

        return max_score

    def _calculate_knowledge_gap_score(self, text: str) -> float:
        """Calculate knowledge gap score."""
        max_score = 0.0

        for pattern in self.KNOWLEDGE_GAP_PATTERNS:
            if re.search(pattern, text):
                max_score = max(max_score, 0.9)

        return max_score

    def _calculate_vague_language_score(self, text: str) -> float:
        """Calculate vague language score."""
        total_score = 0.0
        word_count = len(text.split())

        for word, weight in self.VAGUE_LANGUAGE.items():
            count = text.count(word)
            if count > 0:
                # Cap at 3 occurrences
                total_score += weight * min(count, 3)

        # Normalize by text length
        if word_count == 0:
            return 0.0

        length_factor = min(500, len(text)) / 500.0
        normalized = total_score / (1 + length_factor)

        return min(1.0, normalized)

    def _record_score(self, score: float) -> None:
        """Record a score for trend analysis."""
        self._recent_scores.append(score)

    def _calculate_trend(self) -> ConfidenceTrend:
        """Calculate confidence trend from recent scores."""
        if len(self._recent_scores) < 3:
            return ConfidenceTrend.STABLE

        scores = list(self._recent_scores)
        recent = scores[-3:]
        older = scores[:-3] if len(scores) > 3 else scores[:1]

        recent_avg = sum(recent) / len(recent)
        older_avg = sum(older) / len(older)

        diff = recent_avg - older_avg

        if diff > 0.1:
            return ConfidenceTrend.IMPROVING
        elif diff < -0.1:
            return ConfidenceTrend.DECLINING
        else:
            return ConfidenceTrend.STABLE
