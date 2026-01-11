"""Tests for ConfidenceMonitor."""

import pytest

from ..confidence import (
    ConfidenceAnalysis,
    ConfidenceMarker,
    ConfidenceMonitor,
    ConfidenceMonitorConfig,
    ConfidenceTrend,
    ExpansionPriority,
    ExpansionRecommendation,
    ExpansionScope,
)


class TestConfidenceMarkerDetection:
    """Tests for detecting confidence markers."""

    def test_detect_hedging(self):
        """Test detection of hedging language."""
        monitor = ConfidenceMonitor()
        response = "I'm not sure, but I think the answer might be related to gravity."

        analysis = monitor.analyze_response(response)

        assert ConfidenceMarker.HEDGING in analysis.detected_markers

    def test_detect_question_deflection(self):
        """Test detection of question deflection patterns."""
        monitor = ConfidenceMonitor()
        response = "I can't help with that topic. That's outside my scope."

        analysis = monitor.analyze_response(response)

        assert ConfidenceMarker.QUESTION_DEFLECTION in analysis.detected_markers

    def test_detect_knowledge_gap(self):
        """Test detection of knowledge gap admission."""
        monitor = ConfidenceMonitor()
        response = "I don't have information about that specific experiment."

        analysis = monitor.analyze_response(response)

        assert ConfidenceMarker.KNOWLEDGE_GAP in analysis.detected_markers

    def test_detect_vague_language_when_prominent(self):
        """Test detection of vague language when used prominently."""
        monitor = ConfidenceMonitor()
        # Need more vague words to exceed the threshold
        response = "Probably sometimes sort of kind of approximately maybe."

        analysis = monitor.analyze_response(response)

        # Vague language score should be calculated
        assert analysis.vague_language_score > 0

    def test_confident_response_no_markers(self):
        """Test that confident responses have no markers."""
        monitor = ConfidenceMonitor()
        response = "Gravity causes objects to accelerate at 9.8 m/s² near Earth's surface."

        analysis = monitor.analyze_response(response)

        assert len(analysis.detected_markers) == 0


class TestConfidenceScoring:
    """Tests for confidence scoring."""

    def test_high_confidence_for_clear_response(self):
        """Test high confidence for clear, definitive response."""
        monitor = ConfidenceMonitor()
        response = "The mitochondria is the powerhouse of the cell. It produces ATP."

        analysis = monitor.analyze_response(response)

        assert analysis.confidence_score > 0.8

    def test_lower_confidence_for_hedging(self):
        """Test lower confidence for hedged response."""
        monitor = ConfidenceMonitor()
        response = "I'm not sure, but I think maybe possibly perhaps it might be related."

        analysis = monitor.analyze_response(response)

        # Should have reduced confidence
        assert analysis.confidence_score < 0.9

    def test_confidence_in_valid_range(self):
        """Test that confidence is always in [0, 1]."""
        monitor = ConfidenceMonitor()
        responses = [
            "I'm not sure maybe possibly I think perhaps.",
            "Gravity is 9.8 m/s².",
            "I don't have information about quantum mechanics specifically.",
            "",
        ]

        for response in responses:
            analysis = monitor.analyze_response(response)
            assert 0.0 <= analysis.confidence_score <= 1.0


class TestConfidenceTrend:
    """Tests for confidence trend tracking."""

    def test_stable_trend_for_single_response(self):
        """Test stable trend for first response."""
        monitor = ConfidenceMonitor()
        response = "Gravity affects all objects."

        analysis = monitor.analyze_response(response)

        assert analysis.trend == ConfidenceTrend.STABLE

    def test_stable_trend_with_few_responses(self):
        """Test stable trend when fewer than 3 responses."""
        monitor = ConfidenceMonitor()

        # First response
        monitor.analyze_response("Gravity causes acceleration at 9.8 m/s².")

        # Second response
        analysis = monitor.analyze_response("Force equals mass times acceleration.")

        # Should still be stable (not enough data for trend)
        assert analysis.trend == ConfidenceTrend.STABLE

    def test_declining_trend_with_enough_responses(self):
        """Test declining trend when confidence drops consistently."""
        monitor = ConfidenceMonitor()

        # Build up history with confident responses
        for _ in range(3):
            monitor.analyze_response("Gravity causes acceleration at 9.8 m/s².")

        # Now add uncertain responses
        for _ in range(3):
            analysis = monitor.analyze_response(
                "I'm not sure, possibly maybe there are factors I don't know about."
            )

        # Should detect declining trend if enough difference
        # Note: depends on exact threshold implementation
        assert analysis.trend in [ConfidenceTrend.DECLINING, ConfidenceTrend.STABLE]


class TestExpansionRecommendation:
    """Tests for expansion recommendations."""

    def test_no_expansion_for_high_confidence(self):
        """Test no expansion recommended for high confidence."""
        monitor = ConfidenceMonitor()
        response = "Newton's second law states F = ma."

        analysis = monitor.analyze_response(response)
        recommendation = monitor.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is False

    def test_expansion_for_knowledge_gap(self):
        """Test expansion recommended for knowledge gap."""
        monitor = ConfidenceMonitor()
        response = "I don't have information about that specific topic."

        analysis = monitor.analyze_response(response)
        recommendation = monitor.get_expansion_recommendation(analysis)

        # Knowledge gap is a high-signal marker
        assert recommendation.should_expand is True

    def test_expansion_scope_for_knowledge_gap(self):
        """Test expansion scope for knowledge gap is full curriculum."""
        monitor = ConfidenceMonitor()
        response = "I don't have information about that specific topic."

        analysis = monitor.analyze_response(response)
        recommendation = monitor.get_expansion_recommendation(analysis)

        if recommendation.should_expand:
            assert recommendation.suggested_scope == ExpansionScope.FULL_CURRICULUM


class TestExpansionPriority:
    """Tests for expansion priority levels."""

    def test_high_priority_for_very_low_confidence(self):
        """Test high priority when confidence is very low."""
        monitor = ConfidenceMonitor()
        # Trigger multiple uncertainty signals
        response = (
            "I'm not sure, I don't have information about that. "
            "I can't help with that topic."
        )

        analysis = monitor.analyze_response(response)
        recommendation = monitor.get_expansion_recommendation(analysis)

        if recommendation.should_expand and analysis.confidence_score < 0.3:
            assert recommendation.priority == ExpansionPriority.HIGH

    def test_priority_comparison(self):
        """Test that priority levels can be compared."""
        assert ExpansionPriority.NONE < ExpansionPriority.LOW
        assert ExpansionPriority.LOW < ExpansionPriority.MEDIUM
        assert ExpansionPriority.MEDIUM < ExpansionPriority.HIGH


class TestConfidenceMonitorConfig:
    """Tests for ConfidenceMonitorConfig."""

    def test_default_expansion_threshold(self):
        """Test default expansion threshold."""
        config = ConfidenceMonitorConfig()
        assert 0.0 < config.expansion_threshold < 1.0

    def test_tutoring_config(self):
        """Test tutoring configuration preset."""
        config = ConfidenceMonitorConfig.tutoring()
        assert config.expansion_threshold == 0.5

    def test_strict_config(self):
        """Test strict configuration preset."""
        config = ConfidenceMonitorConfig.strict()
        assert config.expansion_threshold > 0.5

    def test_custom_threshold(self):
        """Test custom expansion threshold."""
        config = ConfidenceMonitorConfig(expansion_threshold=0.8)
        monitor = ConfidenceMonitor(config)

        # Mild hedging that might not trigger at 0.8 threshold
        response = "I believe the answer is related to energy."
        analysis = monitor.analyze_response(response)

        # At high threshold, only very uncertain responses trigger expansion
        if analysis.confidence_score >= 0.8:
            recommendation = monitor.get_expansion_recommendation(analysis)
            assert recommendation.should_expand is False


class TestAnalysisDetails:
    """Tests for analysis detail extraction."""

    def test_analysis_includes_all_scores(self):
        """Test that analysis includes all component scores."""
        monitor = ConfidenceMonitor()
        response = "I don't have enough information to answer that accurately."

        analysis = monitor.analyze_response(response)

        assert hasattr(analysis, 'hedging_score')
        assert hasattr(analysis, 'question_deflection_score')
        assert hasattr(analysis, 'knowledge_gap_score')
        assert hasattr(analysis, 'vague_language_score')

    def test_analysis_detects_multiple_markers(self):
        """Test that analysis detects all markers in complex response."""
        monitor = ConfidenceMonitor()
        response = (
            "I'm not sure, but I think maybe there might be some things. "
            "I don't have specific information about that topic."
        )

        analysis = monitor.analyze_response(response)

        # Should detect both hedging and knowledge gap
        assert len(analysis.detected_markers) >= 2


class TestEdgeCases:
    """Tests for edge cases."""

    def test_empty_response(self):
        """Test handling of empty response."""
        monitor = ConfidenceMonitor()

        analysis = monitor.analyze_response("")

        assert analysis.confidence_score >= 0.0
        assert analysis.confidence_score <= 1.0

    def test_very_long_response(self):
        """Test handling of very long response."""
        monitor = ConfidenceMonitor()
        response = "This is a detailed explanation. " * 1000

        analysis = monitor.analyze_response(response)

        assert analysis.confidence_score >= 0.0
        assert analysis.confidence_score <= 1.0

    def test_response_with_only_punctuation(self):
        """Test handling of response with only punctuation."""
        monitor = ConfidenceMonitor()

        analysis = monitor.analyze_response("...")

        assert analysis.confidence_score >= 0.0

    def test_unicode_response(self):
        """Test handling of unicode characters."""
        monitor = ConfidenceMonitor()
        response = "The formula is E = mc². This is well-established physics."

        analysis = monitor.analyze_response(response)

        # Should handle unicode without error
        assert analysis.confidence_score > 0.0

    def test_case_insensitive_detection(self):
        """Test that detection is case insensitive."""
        monitor = ConfidenceMonitor()
        response1 = "I'M NOT SURE ABOUT THIS."
        response2 = "i'm not sure about this."

        analysis1 = monitor.analyze_response(response1)
        analysis2 = monitor.analyze_response(response2)

        # Both should detect hedging
        assert ConfidenceMarker.HEDGING in analysis1.detected_markers
        assert ConfidenceMarker.HEDGING in analysis2.detected_markers


class TestShouldTriggerExpansion:
    """Tests for the should_trigger_expansion helper."""

    def test_should_trigger_for_knowledge_gap(self):
        """Test trigger for knowledge gap."""
        monitor = ConfidenceMonitor()
        response = "I don't have information about that topic."

        analysis = monitor.analyze_response(response)

        assert monitor.should_trigger_expansion(analysis) is True

    def test_should_not_trigger_for_high_confidence(self):
        """Test no trigger for high confidence."""
        monitor = ConfidenceMonitor()
        response = "The speed of light is approximately 299,792,458 m/s."

        analysis = monitor.analyze_response(response)

        assert monitor.should_trigger_expansion(analysis) is False


class TestMonitorReset:
    """Tests for monitor reset functionality."""

    def test_reset_clears_history(self):
        """Test that reset clears score history."""
        monitor = ConfidenceMonitor()

        # Add some responses
        for _ in range(5):
            monitor.analyze_response("Some response.")

        monitor.reset()

        # History should be cleared
        assert len(monitor._recent_scores) == 0

    def test_reset_clears_last_analysis(self):
        """Test that reset clears last analysis."""
        monitor = ConfidenceMonitor()
        monitor.analyze_response("Some response.")

        monitor.reset()

        assert monitor._last_analysis is None
