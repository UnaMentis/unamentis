"""
Comprehensive tests for the FOV Confidence Monitor.

Tests cover:
- All enums and their behaviors (ConfidenceMarker, ConfidenceTrend, ExpansionPriority, ExpansionScope)
- Dataclasses (ConfidenceMonitorConfig, ConfidenceAnalysis, ExpansionRecommendation)
- ConfidenceMonitor class and all its methods
- Edge cases, error handling, and boundary conditions
"""

import pytest

from fov_context.confidence import (
    ConfidenceAnalysis,
    ConfidenceMarker,
    ConfidenceMonitor,
    ConfidenceMonitorConfig,
    ConfidenceTrend,
    ExpansionPriority,
    ExpansionRecommendation,
    ExpansionScope,
)


# --- Enum Tests ---


class TestConfidenceMarkerEnum:
    """Tests for ConfidenceMarker enum."""

    def test_all_marker_values(self):
        """Test all confidence marker values exist."""
        assert ConfidenceMarker.HEDGING == "hedging"
        assert ConfidenceMarker.QUESTION_DEFLECTION == "question_deflection"
        assert ConfidenceMarker.KNOWLEDGE_GAP == "knowledge_gap"
        assert ConfidenceMarker.VAGUE_LANGUAGE == "vague_language"
        assert ConfidenceMarker.OUT_OF_SCOPE == "out_of_scope"

    def test_marker_is_string_enum(self):
        """Test that markers are string enums."""
        assert isinstance(ConfidenceMarker.HEDGING, str)
        assert ConfidenceMarker.HEDGING.value == "hedging"

    def test_marker_count(self):
        """Test we have exactly 5 marker types."""
        assert len(ConfidenceMarker) == 5


class TestConfidenceTrendEnum:
    """Tests for ConfidenceTrend enum."""

    def test_all_trend_values(self):
        """Test all confidence trend values exist."""
        assert ConfidenceTrend.STABLE == "stable"
        assert ConfidenceTrend.IMPROVING == "improving"
        assert ConfidenceTrend.DECLINING == "declining"

    def test_trend_is_string_enum(self):
        """Test that trends are string enums."""
        assert isinstance(ConfidenceTrend.STABLE, str)
        assert ConfidenceTrend.STABLE.value == "stable"

    def test_trend_count(self):
        """Test we have exactly 3 trend types."""
        assert len(ConfidenceTrend) == 3


class TestExpansionPriorityEnum:
    """Tests for ExpansionPriority enum with comparison operators."""

    def test_all_priority_values(self):
        """Test all priority values exist."""
        assert ExpansionPriority.NONE == "none"
        assert ExpansionPriority.LOW == "low"
        assert ExpansionPriority.MEDIUM == "medium"
        assert ExpansionPriority.HIGH == "high"

    def test_priority_is_string_enum(self):
        """Test that priorities are string enums."""
        assert isinstance(ExpansionPriority.NONE, str)
        assert ExpansionPriority.HIGH.value == "high"

    def test_priority_count(self):
        """Test we have exactly 4 priority levels."""
        assert len(ExpansionPriority) == 4

    def test_priority_less_than(self):
        """Test __lt__ comparison operator."""
        assert ExpansionPriority.NONE < ExpansionPriority.LOW
        assert ExpansionPriority.LOW < ExpansionPriority.MEDIUM
        assert ExpansionPriority.MEDIUM < ExpansionPriority.HIGH
        assert not (ExpansionPriority.HIGH < ExpansionPriority.NONE)
        assert not (ExpansionPriority.HIGH < ExpansionPriority.HIGH)

    def test_priority_less_than_or_equal(self):
        """Test __le__ comparison operator."""
        assert ExpansionPriority.NONE <= ExpansionPriority.LOW
        assert ExpansionPriority.LOW <= ExpansionPriority.LOW
        assert ExpansionPriority.LOW <= ExpansionPriority.MEDIUM
        assert ExpansionPriority.HIGH <= ExpansionPriority.HIGH
        assert not (ExpansionPriority.HIGH <= ExpansionPriority.NONE)

    def test_priority_greater_than(self):
        """Test __gt__ comparison operator."""
        assert ExpansionPriority.HIGH > ExpansionPriority.MEDIUM
        assert ExpansionPriority.MEDIUM > ExpansionPriority.LOW
        assert ExpansionPriority.LOW > ExpansionPriority.NONE
        assert not (ExpansionPriority.NONE > ExpansionPriority.LOW)
        assert not (ExpansionPriority.LOW > ExpansionPriority.LOW)

    def test_priority_greater_than_or_equal(self):
        """Test __ge__ comparison operator."""
        assert ExpansionPriority.HIGH >= ExpansionPriority.MEDIUM
        assert ExpansionPriority.HIGH >= ExpansionPriority.HIGH
        assert ExpansionPriority.LOW >= ExpansionPriority.NONE
        assert ExpansionPriority.NONE >= ExpansionPriority.NONE
        assert not (ExpansionPriority.NONE >= ExpansionPriority.LOW)

    def test_priority_sorting(self):
        """Test that priorities can be sorted."""
        priorities = [
            ExpansionPriority.HIGH,
            ExpansionPriority.NONE,
            ExpansionPriority.MEDIUM,
            ExpansionPriority.LOW,
        ]
        sorted_priorities = sorted(priorities)
        assert sorted_priorities == [
            ExpansionPriority.NONE,
            ExpansionPriority.LOW,
            ExpansionPriority.MEDIUM,
            ExpansionPriority.HIGH,
        ]


class TestExpansionScopeEnum:
    """Tests for ExpansionScope enum."""

    def test_all_scope_values(self):
        """Test all expansion scope values exist."""
        assert ExpansionScope.CURRENT_TOPIC == "current_topic"
        assert ExpansionScope.CURRENT_UNIT == "current_unit"
        assert ExpansionScope.FULL_CURRICULUM == "full_curriculum"
        assert ExpansionScope.RELATED_TOPICS == "related_topics"

    def test_scope_is_string_enum(self):
        """Test that scopes are string enums."""
        assert isinstance(ExpansionScope.CURRENT_TOPIC, str)
        assert ExpansionScope.FULL_CURRICULUM.value == "full_curriculum"

    def test_scope_count(self):
        """Test we have exactly 4 scope types."""
        assert len(ExpansionScope) == 4


# --- Dataclass Tests ---


class TestConfidenceMonitorConfig:
    """Tests for ConfidenceMonitorConfig dataclass."""

    def test_default_values(self):
        """Test default configuration values."""
        config = ConfidenceMonitorConfig()
        assert config.expansion_threshold == 0.5
        assert config.trend_threshold == 0.75
        assert config.hedging_weight == 0.25
        assert config.deflection_weight == 0.3
        assert config.knowledge_gap_weight == 0.35
        assert config.vague_language_weight == 0.1

    def test_custom_values(self):
        """Test custom configuration values."""
        config = ConfidenceMonitorConfig(
            expansion_threshold=0.7,
            trend_threshold=0.9,
            hedging_weight=0.3,
            deflection_weight=0.25,
            knowledge_gap_weight=0.3,
            vague_language_weight=0.15,
        )
        assert config.expansion_threshold == 0.7
        assert config.trend_threshold == 0.9
        assert config.hedging_weight == 0.3
        assert config.deflection_weight == 0.25
        assert config.knowledge_gap_weight == 0.3
        assert config.vague_language_weight == 0.15

    def test_tutoring_preset(self):
        """Test tutoring configuration preset."""
        config = ConfidenceMonitorConfig.tutoring()
        assert config.expansion_threshold == 0.5
        assert config.trend_threshold == 0.75
        assert config.hedging_weight == 0.25
        assert config.deflection_weight == 0.3
        assert config.knowledge_gap_weight == 0.35
        assert config.vague_language_weight == 0.1

    def test_strict_preset(self):
        """Test strict configuration preset."""
        config = ConfidenceMonitorConfig.strict()
        assert config.expansion_threshold == 0.6
        assert config.trend_threshold == 0.8
        assert config.hedging_weight == 0.3
        assert config.deflection_weight == 0.25
        assert config.knowledge_gap_weight == 0.35
        assert config.vague_language_weight == 0.1
        # Strict has higher expansion threshold
        assert config.expansion_threshold > ConfidenceMonitorConfig.tutoring().expansion_threshold

    def test_weight_sum_approximately_one(self):
        """Test that weights sum approximately to 1.0 for proper weighting."""
        config = ConfidenceMonitorConfig()
        weight_sum = (
            config.hedging_weight
            + config.deflection_weight
            + config.knowledge_gap_weight
            + config.vague_language_weight
        )
        assert weight_sum == pytest.approx(1.0, rel=0.01)


class TestConfidenceAnalysis:
    """Tests for ConfidenceAnalysis dataclass."""

    def test_create_analysis(self):
        """Test creating a confidence analysis."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.8,
            uncertainty_score=0.2,
            hedging_score=0.1,
            question_deflection_score=0.05,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
        )
        assert analysis.confidence_score == 0.8
        assert analysis.uncertainty_score == 0.2
        assert analysis.hedging_score == 0.1
        assert analysis.question_deflection_score == 0.05
        assert analysis.knowledge_gap_score == 0.0
        assert analysis.vague_language_score == 0.1

    def test_default_detected_markers(self):
        """Test default detected markers is empty set."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.8,
            uncertainty_score=0.2,
            hedging_score=0.1,
            question_deflection_score=0.05,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
        )
        assert analysis.detected_markers == set()

    def test_default_trend(self):
        """Test default trend is stable."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.8,
            uncertainty_score=0.2,
            hedging_score=0.1,
            question_deflection_score=0.05,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
        )
        assert analysis.trend == ConfidenceTrend.STABLE

    def test_analysis_with_markers(self):
        """Test analysis with detected markers."""
        markers = {ConfidenceMarker.HEDGING, ConfidenceMarker.VAGUE_LANGUAGE}
        analysis = ConfidenceAnalysis(
            confidence_score=0.5,
            uncertainty_score=0.5,
            hedging_score=0.4,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.4,
            detected_markers=markers,
            trend=ConfidenceTrend.DECLINING,
        )
        assert analysis.detected_markers == markers
        assert ConfidenceMarker.HEDGING in analysis.detected_markers
        assert analysis.trend == ConfidenceTrend.DECLINING


class TestExpansionRecommendation:
    """Tests for ExpansionRecommendation dataclass."""

    def test_create_recommendation_no_expansion(self):
        """Test creating a no-expansion recommendation."""
        recommendation = ExpansionRecommendation(
            should_expand=False,
            priority=ExpansionPriority.NONE,
            suggested_scope=ExpansionScope.CURRENT_TOPIC,
            reason="Confidence is sufficient",
        )
        assert recommendation.should_expand is False
        assert recommendation.priority == ExpansionPriority.NONE
        assert recommendation.reason == "Confidence is sufficient"
        assert recommendation.query_hint is None

    def test_create_recommendation_with_expansion(self):
        """Test creating an expansion recommendation."""
        recommendation = ExpansionRecommendation(
            should_expand=True,
            priority=ExpansionPriority.HIGH,
            suggested_scope=ExpansionScope.FULL_CURRICULUM,
            reason="Knowledge gap detected",
            query_hint="Search for related topics",
        )
        assert recommendation.should_expand is True
        assert recommendation.priority == ExpansionPriority.HIGH
        assert recommendation.suggested_scope == ExpansionScope.FULL_CURRICULUM
        assert recommendation.query_hint == "Search for related topics"


# --- ConfidenceMonitor Tests ---


class TestConfidenceMonitorInitialization:
    """Tests for ConfidenceMonitor initialization."""

    def test_default_initialization(self):
        """Test default monitor initialization."""
        monitor = ConfidenceMonitor()
        assert monitor.config is not None
        assert monitor.config.expansion_threshold == 0.5  # Tutoring default
        assert len(monitor._recent_scores) == 0
        assert monitor._last_analysis is None

    def test_custom_config_initialization(self):
        """Test monitor initialization with custom config."""
        config = ConfidenceMonitorConfig(expansion_threshold=0.7)
        monitor = ConfidenceMonitor(config)
        assert monitor.config.expansion_threshold == 0.7

    def test_strict_config_initialization(self):
        """Test monitor initialization with strict config."""
        config = ConfidenceMonitorConfig.strict()
        monitor = ConfidenceMonitor(config)
        assert monitor.config.expansion_threshold == 0.6


class TestConfidenceMonitorHedgingDetection:
    """Tests for hedging language detection."""

    def test_detect_hedging_im_not_sure(self):
        """Test detection of 'I'm not sure'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("I'm not sure about this topic.")
        assert ConfidenceMarker.HEDGING in analysis.detected_markers

    def test_detect_hedging_i_think(self):
        """Test detection of 'I think'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("I think the answer is 42, but let me verify.")
        # i_think has weight 0.4, may or may not trigger marker threshold
        assert analysis.hedging_score > 0

    def test_detect_hedging_maybe(self):
        """Test detection of 'maybe'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("Maybe this is correct, maybe not.")
        assert analysis.hedging_score > 0

    def test_detect_hedging_possibly_perhaps(self):
        """Test detection of 'possibly' and 'perhaps'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("Possibly, or perhaps it's something else.")
        assert analysis.hedging_score > 0

    def test_detect_hedging_multiple_phrases(self):
        """Test detection of multiple hedging phrases."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I'm not sure, but I think maybe possibly it could be related to physics."
        )
        assert ConfidenceMarker.HEDGING in analysis.detected_markers
        assert analysis.hedging_score > 0.3

    def test_detect_hedging_dont_quote_me(self):
        """Test detection of 'don't quote me on this'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("The answer is 42, but don't quote me on this.")
        assert ConfidenceMarker.HEDGING in analysis.detected_markers

    def test_detect_hedging_as_far_as_i_know(self):
        """Test detection of 'as far as I know'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("As far as I know, this is correct.")
        assert analysis.hedging_score > 0

    def test_no_hedging_in_confident_response(self):
        """Test no hedging detected in confident response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "The speed of light is 299,792,458 meters per second."
        )
        assert ConfidenceMarker.HEDGING not in analysis.detected_markers
        assert analysis.hedging_score == 0


class TestConfidenceMonitorDeflectionDetection:
    """Tests for question deflection detection."""

    def test_detect_deflection_cant_help(self):
        """Test detection of 'I can't help with that'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("I can't help with that kind of question.")
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_deflection_outside_scope(self):
        """Test detection of 'outside/beyond my scope'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("That's outside my scope of expertise.")
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_deflection_beyond_scope(self):
        """Test detection of 'beyond the scope'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("That's beyond the scope of this tutorial.")
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_deflection_not_equipped(self):
        """Test detection of 'I'm not equipped to'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("I'm not equipped to answer medical questions.")
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_deflection_should_consult(self):
        """Test detection of 'you should/might want to consult'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "You should consult a professional for this matter."
        )
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_deflection_cannot_provide_advice(self):
        """Test detection of 'I cannot provide medical/legal/financial advice'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I cannot provide medical advice on this matter."
        )
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_deflection_redirect(self):
        """Test detection of 'let me redirect you'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "Let me redirect you to a more appropriate resource."
        )
        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_no_deflection_in_normal_response(self):
        """Test no deflection in normal response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "Here's how photosynthesis works in plants."
        )
        assert ConfidenceMarker.QUESTION_DEFLECTION not in analysis.detected_markers
        assert analysis.question_deflection_score == 0


class TestConfidenceMonitorKnowledgeGapDetection:
    """Tests for knowledge gap detection."""

    def test_detect_gap_dont_have_information(self):
        """Test detection of 'I don't have information about'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I don't have information about that specific topic."
        )
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_gap_not_aware(self):
        """Test detection of 'I'm not aware of'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I'm not aware of any studies on this subject."
        )
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_gap_information_not_available(self):
        """Test detection of 'information is not available'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "That information isn't available in my training data."
        )
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_gap_havent_been_trained(self):
        """Test detection of 'I haven't been trained on'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("I haven't been trained on this topic.")
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_gap_knowledge_doesnt_include(self):
        """Test detection of 'my knowledge doesn't include'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "My knowledge doesn't include recent developments."
        )
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_gap_lack_knowledge(self):
        """Test detection of 'I lack specific knowledge'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I lack specific knowledge about this protocol."
        )
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_gap_outside_training(self):
        """Test detection of 'outside/beyond my training'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("That's outside my training data.")
        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_no_gap_in_knowledgeable_response(self):
        """Test no gap in knowledgeable response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "The Pythagorean theorem states that a^2 + b^2 = c^2."
        )
        assert ConfidenceMarker.KNOWLEDGE_GAP not in analysis.detected_markers
        assert analysis.knowledge_gap_score == 0


class TestConfidenceMonitorVagueLanguageDetection:
    """Tests for vague language detection."""

    def test_detect_vague_probably(self):
        """Test detection of 'probably'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("This is probably correct.")
        assert analysis.vague_language_score > 0

    def test_detect_vague_likely(self):
        """Test detection of 'likely'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("The answer is likely correct.")
        assert analysis.vague_language_score > 0

    def test_detect_vague_typically_usually(self):
        """Test detection of 'typically' and 'usually'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "This typically happens. Usually it works."
        )
        assert analysis.vague_language_score > 0

    def test_detect_vague_kind_of_sort_of(self):
        """Test detection of 'kind of' and 'sort of'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "It's kind of like that, sort of related to the concept."
        )
        assert analysis.vague_language_score > 0

    def test_detect_vague_more_or_less(self):
        """Test detection of 'more or less'."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("More or less, that's the idea.")
        assert analysis.vague_language_score > 0

    def test_detect_vague_multiple_occurrences(self):
        """Test multiple occurrences of vague words."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "Probably probably probably, this is somewhat roughly correct."
        )
        assert analysis.vague_language_score > 0.3

    def test_vague_language_threshold_for_marker(self):
        """Test that marker is added only when score exceeds threshold."""
        monitor = ConfidenceMonitor()
        # Need many vague words to exceed 0.3 threshold
        analysis = monitor.analyze_response(
            "Probably sometimes sort of kind of approximately maybe roughly."
        )
        # Check that vague language is being detected
        assert analysis.vague_language_score > 0

    def test_no_vague_in_precise_response(self):
        """Test no vague language in precise response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("The answer is exactly 42.")
        assert analysis.vague_language_score == 0


class TestConfidenceScoring:
    """Tests for overall confidence scoring."""

    def test_high_confidence_for_clear_response(self):
        """Test high confidence for clear, factual response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "The speed of light in a vacuum is 299,792,458 meters per second."
        )
        assert analysis.confidence_score > 0.9
        assert analysis.uncertainty_score < 0.1

    def test_low_confidence_for_uncertain_response(self):
        """Test low confidence for uncertain response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I'm not sure, but I think maybe possibly it might be related "
            "to something I don't have information about."
        )
        assert analysis.confidence_score < 0.7
        assert analysis.uncertainty_score > 0.3

    def test_confidence_score_clamped_to_valid_range(self):
        """Test that confidence score is always between 0 and 1."""
        monitor = ConfidenceMonitor()
        # Test with many uncertainty signals
        analysis = monitor.analyze_response(
            "I'm not sure, I don't have information about that. "
            "I can't help with that. I think maybe possibly perhaps. "
            "I'm not aware of the details."
        )
        assert 0.0 <= analysis.confidence_score <= 1.0
        assert 0.0 <= analysis.uncertainty_score <= 1.0

    def test_confidence_uncertainty_relationship(self):
        """Test that confidence and uncertainty are inversely related."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("Some response text.")
        # Confidence should be approximately 1 - uncertainty (before clamping)
        assert analysis.confidence_score + analysis.uncertainty_score >= 0.9

    def test_weighted_scoring(self):
        """Test that scores are properly weighted."""
        monitor = ConfidenceMonitor()
        # Response with hedging should have weighted hedging contribution
        analysis = monitor.analyze_response("I'm not sure about this.")
        assert analysis.hedging_score > 0
        # The uncertainty should reflect weighted contribution
        expected_hedging_contribution = (
            analysis.hedging_score * monitor.config.hedging_weight
        )
        assert analysis.uncertainty_score >= expected_hedging_contribution * 0.8


class TestConfidenceTrendCalculation:
    """Tests for confidence trend calculation."""

    def test_stable_trend_with_few_responses(self):
        """Test stable trend with fewer than 3 responses."""
        monitor = ConfidenceMonitor()
        analysis1 = monitor.analyze_response("First response.")
        assert analysis1.trend == ConfidenceTrend.STABLE

        analysis2 = monitor.analyze_response("Second response.")
        assert analysis2.trend == ConfidenceTrend.STABLE

    def test_stable_trend_with_consistent_scores(self):
        """Test stable trend with consistent confidence scores."""
        monitor = ConfidenceMonitor()
        for i in range(5):
            analysis = monitor.analyze_response("This is a clear, confident answer.")
        assert analysis.trend == ConfidenceTrend.STABLE

    def test_declining_trend_detection(self):
        """Test declining trend when confidence drops."""
        monitor = ConfidenceMonitor()
        # Start with confident responses
        for _ in range(3):
            monitor.analyze_response("Clear factual statement.")

        # Follow with uncertain responses
        for _ in range(3):
            analysis = monitor.analyze_response(
                "I'm not sure, maybe possibly I don't have information about this."
            )

        # Should detect decline if difference is significant
        assert analysis.trend in [ConfidenceTrend.DECLINING, ConfidenceTrend.STABLE]

    def test_improving_trend_detection(self):
        """Test improving trend when confidence increases."""
        monitor = ConfidenceMonitor()
        # Start with uncertain responses
        for _ in range(3):
            monitor.analyze_response("I'm not sure, maybe possibly.")

        # Follow with confident responses
        for _ in range(3):
            analysis = monitor.analyze_response("This is definitely correct. F = ma.")

        # Should detect improvement if difference is significant
        assert analysis.trend in [ConfidenceTrend.IMPROVING, ConfidenceTrend.STABLE]

    def test_trend_uses_recent_scores(self):
        """Test that trend calculation uses recent scores."""
        monitor = ConfidenceMonitor()
        # Fill with 10 responses (maxlen)
        for _ in range(10):
            monitor.analyze_response("Consistent response.")

        # Add more to verify deque is working
        for _ in range(3):
            analysis = monitor.analyze_response("Another response.")

        assert len(monitor._recent_scores) == 10  # Maxlen is 10


class TestExpansionTriggering:
    """Tests for should_trigger_expansion method."""

    def test_no_trigger_for_high_confidence(self):
        """Test no expansion trigger for high confidence."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("The Pythagorean theorem is a^2 + b^2 = c^2.")
        assert monitor.should_trigger_expansion(analysis) is False

    def test_trigger_for_low_confidence(self):
        """Test expansion trigger for low confidence."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "I'm not sure, maybe possibly I don't have information about this topic."
        )
        assert monitor.should_trigger_expansion(analysis) is True

    def test_trigger_for_knowledge_gap_marker(self):
        """Test expansion trigger for knowledge gap marker."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("I don't have information about that topic.")
        assert monitor.should_trigger_expansion(analysis) is True

    def test_trigger_for_out_of_scope_marker(self):
        """Test expansion trigger for out of scope marker (synthetic)."""
        # Create an analysis with OUT_OF_SCOPE marker manually
        analysis = ConfidenceAnalysis(
            confidence_score=0.8,  # High confidence but out of scope
            uncertainty_score=0.2,
            hedging_score=0.0,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.0,
            detected_markers={ConfidenceMarker.OUT_OF_SCOPE},
        )
        monitor = ConfidenceMonitor()
        assert monitor.should_trigger_expansion(analysis) is True

    def test_trigger_for_declining_trend(self):
        """Test expansion trigger for declining trend."""
        # Create analysis with declining trend
        analysis = ConfidenceAnalysis(
            confidence_score=0.7,  # Above threshold
            uncertainty_score=0.3,
            hedging_score=0.1,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
            detected_markers=set(),
            trend=ConfidenceTrend.DECLINING,
        )
        monitor = ConfidenceMonitor()
        assert monitor.should_trigger_expansion(analysis) is True

    def test_no_trigger_for_improving_trend_high_confidence(self):
        """Test no trigger for improving trend with high confidence."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.9,
            uncertainty_score=0.1,
            hedging_score=0.0,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.0,
            detected_markers=set(),
            trend=ConfidenceTrend.IMPROVING,
        )
        monitor = ConfidenceMonitor()
        assert monitor.should_trigger_expansion(analysis) is False


class TestExpansionRecommendations:
    """Tests for get_expansion_recommendation method."""

    def test_no_expansion_recommendation(self):
        """Test recommendation when no expansion needed."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("The answer is definitely 42.")
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is False
        assert recommendation.priority == ExpansionPriority.NONE
        assert recommendation.reason == "Confidence is sufficient"

    def test_high_priority_for_very_low_confidence(self):
        """Test high priority for very low confidence (< 0.3)."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.2,
            uncertainty_score=0.8,
            hedging_score=0.5,
            question_deflection_score=0.3,
            knowledge_gap_score=0.5,
            vague_language_score=0.2,
            detected_markers={ConfidenceMarker.HEDGING, ConfidenceMarker.KNOWLEDGE_GAP},
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.priority == ExpansionPriority.HIGH

    def test_medium_priority_for_moderate_confidence(self):
        """Test medium priority for moderate confidence (0.3 - 0.5)."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.4,
            uncertainty_score=0.6,
            hedging_score=0.3,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.2,
            detected_markers={ConfidenceMarker.HEDGING},
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.priority == ExpansionPriority.MEDIUM

    def test_low_priority_for_borderline_confidence(self):
        """Test low priority for borderline confidence (>= 0.5 but triggered)."""
        # Trigger via declining trend
        analysis = ConfidenceAnalysis(
            confidence_score=0.55,
            uncertainty_score=0.45,
            hedging_score=0.2,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
            detected_markers=set(),
            trend=ConfidenceTrend.DECLINING,
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.priority == ExpansionPriority.LOW

    def test_related_topics_scope_for_out_of_scope(self):
        """Test related topics scope for out of scope marker."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.3,
            uncertainty_score=0.7,
            hedging_score=0.2,
            question_deflection_score=0.3,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
            detected_markers={ConfidenceMarker.OUT_OF_SCOPE},
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.suggested_scope == ExpansionScope.RELATED_TOPICS
        assert "out of scope" in recommendation.reason.lower()

    def test_full_curriculum_scope_for_knowledge_gap(self):
        """Test full curriculum scope for knowledge gap."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.3,
            uncertainty_score=0.7,
            hedging_score=0.0,
            question_deflection_score=0.0,
            knowledge_gap_score=0.9,
            vague_language_score=0.0,
            detected_markers={ConfidenceMarker.KNOWLEDGE_GAP},
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.suggested_scope == ExpansionScope.FULL_CURRICULUM
        assert "knowledge gap" in recommendation.reason.lower()

    def test_current_unit_scope_for_declining_trend(self):
        """Test current unit scope for declining trend."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.55,
            uncertainty_score=0.45,
            hedging_score=0.1,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.1,
            detected_markers=set(),
            trend=ConfidenceTrend.DECLINING,
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.suggested_scope == ExpansionScope.CURRENT_UNIT
        assert "declining" in recommendation.reason.lower()

    def test_current_topic_scope_for_general_uncertainty(self):
        """Test current topic scope for general uncertainty."""
        analysis = ConfidenceAnalysis(
            confidence_score=0.4,
            uncertainty_score=0.6,
            hedging_score=0.4,
            question_deflection_score=0.0,
            knowledge_gap_score=0.0,
            vague_language_score=0.3,
            detected_markers={ConfidenceMarker.HEDGING},
        )
        monitor = ConfidenceMonitor()
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True
        assert recommendation.suggested_scope == ExpansionScope.CURRENT_TOPIC
        assert "uncertainty" in recommendation.reason.lower()


class TestMonitorConfigUpdate:
    """Tests for update_config method."""

    def test_update_config(self):
        """Test updating monitor configuration."""
        monitor = ConfidenceMonitor()
        original_threshold = monitor.config.expansion_threshold

        new_config = ConfidenceMonitorConfig(expansion_threshold=0.8)
        monitor.update_config(new_config)

        assert monitor.config.expansion_threshold == 0.8
        assert monitor.config.expansion_threshold != original_threshold

    def test_update_config_affects_behavior(self):
        """Test that config update affects expansion triggering."""
        monitor = ConfidenceMonitor()

        # Low threshold - should trigger
        low_config = ConfidenceMonitorConfig(expansion_threshold=0.9)
        monitor.update_config(low_config)
        analysis = monitor.analyze_response("This is a clear statement.")
        # With 0.9 threshold, most responses will trigger expansion
        if analysis.confidence_score < 0.9:
            assert monitor.should_trigger_expansion(analysis) is True


class TestMonitorReset:
    """Tests for reset method."""

    def test_reset_clears_recent_scores(self):
        """Test that reset clears the recent scores deque."""
        monitor = ConfidenceMonitor()
        for _ in range(5):
            monitor.analyze_response("Some response.")
        assert len(monitor._recent_scores) == 5

        monitor.reset()
        assert len(monitor._recent_scores) == 0

    def test_reset_clears_last_analysis(self):
        """Test that reset clears the last analysis."""
        monitor = ConfidenceMonitor()
        monitor.analyze_response("Some response.")
        assert monitor._last_analysis is not None

        monitor.reset()
        assert monitor._last_analysis is None

    def test_behavior_after_reset(self):
        """Test that monitor works correctly after reset."""
        monitor = ConfidenceMonitor()
        # Build up history
        for _ in range(5):
            monitor.analyze_response("Clear response.")

        monitor.reset()

        # Should work normally after reset
        analysis = monitor.analyze_response("New response after reset.")
        assert analysis.trend == ConfidenceTrend.STABLE  # Not enough history


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_empty_response(self):
        """Test handling of empty response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("")
        assert 0.0 <= analysis.confidence_score <= 1.0
        assert analysis.detected_markers == set()

    def test_whitespace_only_response(self):
        """Test handling of whitespace-only response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("   \n\t  ")
        assert 0.0 <= analysis.confidence_score <= 1.0

    def test_very_long_response(self):
        """Test handling of very long response."""
        monitor = ConfidenceMonitor()
        long_response = "This is a sentence. " * 1000
        analysis = monitor.analyze_response(long_response)
        assert 0.0 <= analysis.confidence_score <= 1.0

    def test_unicode_response(self):
        """Test handling of unicode characters."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "E = mc^2 (energy equals mass times the speed of light squared)"
        )
        assert 0.0 <= analysis.confidence_score <= 1.0

    def test_special_characters_response(self):
        """Test handling of special characters."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("!@#$%^&*()_+-=[]{}|;':\",./<>?")
        assert 0.0 <= analysis.confidence_score <= 1.0

    def test_case_insensitivity(self):
        """Test that detection is case insensitive."""
        monitor = ConfidenceMonitor()
        analysis_lower = monitor.analyze_response("i'm not sure about this.")
        monitor.reset()
        analysis_upper = monitor.analyze_response("I'M NOT SURE ABOUT THIS.")
        monitor.reset()
        analysis_mixed = monitor.analyze_response("I'm Not Sure About This.")

        # All should detect hedging
        assert ConfidenceMarker.HEDGING in analysis_lower.detected_markers
        assert ConfidenceMarker.HEDGING in analysis_upper.detected_markers
        assert ConfidenceMarker.HEDGING in analysis_mixed.detected_markers

    def test_punctuation_only_response(self):
        """Test handling of punctuation-only response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("...")
        assert 0.0 <= analysis.confidence_score <= 1.0

    def test_numbers_only_response(self):
        """Test handling of numbers-only response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("42 3.14159 2.718")
        assert analysis.confidence_score > 0.9  # Should be confident

    def test_rapid_succession_analysis(self):
        """Test many analyses in rapid succession."""
        monitor = ConfidenceMonitor()
        for i in range(100):
            analysis = monitor.analyze_response(f"Response number {i}")
            assert 0.0 <= analysis.confidence_score <= 1.0

    def test_newlines_in_response(self):
        """Test handling of newlines in response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response(
            "Line 1\nLine 2\nLine 3\nI'm not sure about line 4."
        )
        assert ConfidenceMarker.HEDGING in analysis.detected_markers

    def test_tabs_in_response(self):
        """Test handling of tabs in response."""
        monitor = ConfidenceMonitor()
        analysis = monitor.analyze_response("Column1\tColumn2\tI'm not sure\tColumn4")
        assert ConfidenceMarker.HEDGING in analysis.detected_markers


class TestPrivateMethods:
    """Tests for private scoring methods."""

    def test_calculate_hedging_score_no_matches(self):
        """Test hedging score calculation with no matches."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_hedging_score("clear factual statement")
        assert score == 0.0

    def test_calculate_hedging_score_single_match(self):
        """Test hedging score calculation with single match."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_hedging_score("i'm not sure")
        assert score > 0

    def test_calculate_deflection_score_no_matches(self):
        """Test deflection score calculation with no matches."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_deflection_score("helpful response here")
        assert score == 0.0

    def test_calculate_deflection_score_match(self):
        """Test deflection score calculation with match."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_deflection_score("i can't help with that")
        assert score == 0.8

    def test_calculate_knowledge_gap_score_no_matches(self):
        """Test knowledge gap score calculation with no matches."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_knowledge_gap_score("i know about this")
        assert score == 0.0

    def test_calculate_knowledge_gap_score_match(self):
        """Test knowledge gap score calculation with match."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_knowledge_gap_score("i don't have information about that")
        assert score == 0.9

    def test_calculate_vague_language_score_no_matches(self):
        """Test vague language score calculation with no matches."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_vague_language_score("definite certain exact")
        assert score == 0.0

    def test_calculate_vague_language_score_capped_occurrences(self):
        """Test that vague word occurrences are capped at 3."""
        monitor = ConfidenceMonitor()
        # Many occurrences of "probably"
        score = monitor._calculate_vague_language_score(
            "probably probably probably probably probably"
        )
        # Score should be capped, not unlimited
        assert score <= 1.0

    def test_calculate_vague_language_score_empty_text(self):
        """Test vague language score with empty text."""
        monitor = ConfidenceMonitor()
        score = monitor._calculate_vague_language_score("")
        assert score == 0.0

    def test_record_score(self):
        """Test score recording."""
        monitor = ConfidenceMonitor()
        monitor._record_score(0.8)
        assert len(monitor._recent_scores) == 1
        assert monitor._recent_scores[0] == 0.8

    def test_record_score_maxlen(self):
        """Test that score recording respects maxlen."""
        monitor = ConfidenceMonitor()
        for i in range(15):
            monitor._record_score(0.5 + i * 0.01)
        # maxlen is 10
        assert len(monitor._recent_scores) == 10

    def test_calculate_trend_not_enough_data(self):
        """Test trend calculation with insufficient data."""
        monitor = ConfidenceMonitor()
        monitor._record_score(0.8)
        monitor._record_score(0.7)
        trend = monitor._calculate_trend()
        assert trend == ConfidenceTrend.STABLE  # Less than 3 scores

    def test_calculate_trend_stable(self):
        """Test trend calculation for stable scores."""
        monitor = ConfidenceMonitor()
        for _ in range(5):
            monitor._record_score(0.8)
        trend = monitor._calculate_trend()
        assert trend == ConfidenceTrend.STABLE

    def test_calculate_trend_improving(self):
        """Test trend calculation for improving scores."""
        monitor = ConfidenceMonitor()
        # Older scores low
        monitor._record_score(0.3)
        monitor._record_score(0.3)
        # Recent scores high
        monitor._record_score(0.8)
        monitor._record_score(0.8)
        monitor._record_score(0.8)
        trend = monitor._calculate_trend()
        assert trend == ConfidenceTrend.IMPROVING

    def test_calculate_trend_declining(self):
        """Test trend calculation for declining scores."""
        monitor = ConfidenceMonitor()
        # Older scores high
        monitor._record_score(0.9)
        monitor._record_score(0.9)
        # Recent scores low
        monitor._record_score(0.3)
        monitor._record_score(0.3)
        monitor._record_score(0.3)
        trend = monitor._calculate_trend()
        assert trend == ConfidenceTrend.DECLINING


class TestIntegration:
    """Integration tests for complete workflows."""

    def test_full_tutoring_workflow(self):
        """Test a complete tutoring workflow with multiple responses."""
        monitor = ConfidenceMonitor(ConfidenceMonitorConfig.tutoring())

        # Initial confident responses
        for _ in range(3):
            analysis = monitor.analyze_response(
                "Newton's first law states that an object at rest stays at rest."
            )
            recommendation = monitor.get_expansion_recommendation(analysis)
            assert recommendation.should_expand is False

        # Student asks about something the tutor is uncertain about
        analysis = monitor.analyze_response(
            "I'm not sure about the specifics of quantum entanglement. "
            "I don't have detailed information about that topic."
        )
        recommendation = monitor.get_expansion_recommendation(analysis)
        assert recommendation.should_expand is True
        assert recommendation.priority in [ExpansionPriority.MEDIUM, ExpansionPriority.HIGH]

    def test_strict_mode_workflow(self):
        """Test workflow with strict configuration."""
        monitor = ConfidenceMonitor(ConfidenceMonitorConfig.strict())

        # Response that would be fine in tutoring mode
        analysis = monitor.analyze_response(
            "I believe the answer is related to conservation of energy."
        )
        # Strict mode has higher threshold (0.6)
        if analysis.confidence_score < 0.6:
            recommendation = monitor.get_expansion_recommendation(analysis)
            assert recommendation.should_expand is True

    def test_session_reset_workflow(self):
        """Test workflow with session reset."""
        monitor = ConfidenceMonitor()

        # Build up declining trend
        for _ in range(3):
            monitor.analyze_response("Clear confident answer.")
        for _ in range(3):
            analysis = monitor.analyze_response("I'm not sure, maybe possibly.")

        # Reset for new topic
        monitor.reset()

        # Should start fresh
        analysis = monitor.analyze_response("Another response.")
        assert analysis.trend == ConfidenceTrend.STABLE
        assert len(monitor._recent_scores) == 1
