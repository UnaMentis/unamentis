"""Tests for FOV context models."""

import pytest
from datetime import datetime

from ..models import (
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


class TestModelTier:
    """Tests for ModelTier classification."""

    def test_cloud_classification(self):
        """Test that large context windows are classified as cloud."""
        assert ModelTier.from_context_window(128_000) == ModelTier.CLOUD
        assert ModelTier.from_context_window(200_000) == ModelTier.CLOUD
        assert ModelTier.from_context_window(100_000) == ModelTier.CLOUD

    def test_mid_range_classification(self):
        """Test mid-range context window classification."""
        assert ModelTier.from_context_window(32_000) == ModelTier.MID_RANGE
        assert ModelTier.from_context_window(64_000) == ModelTier.MID_RANGE
        assert ModelTier.from_context_window(99_999) == ModelTier.MID_RANGE

    def test_on_device_classification(self):
        """Test on-device context window classification."""
        assert ModelTier.from_context_window(8_000) == ModelTier.ON_DEVICE
        assert ModelTier.from_context_window(16_000) == ModelTier.ON_DEVICE
        assert ModelTier.from_context_window(31_999) == ModelTier.ON_DEVICE

    def test_tiny_classification(self):
        """Test tiny context window classification."""
        assert ModelTier.from_context_window(4_000) == ModelTier.TINY
        assert ModelTier.from_context_window(2_000) == ModelTier.TINY
        assert ModelTier.from_context_window(7_999) == ModelTier.TINY


class TestTokenBudgets:
    """Tests for TokenBudgets."""

    def test_cloud_budgets(self):
        """Test cloud tier token budgets."""
        budgets = TokenBudgets.for_tier(ModelTier.CLOUD)
        assert budgets.total == 12000
        assert budgets.immediate == 4000
        assert budgets.working == 4000

    def test_budgets_sum_to_total(self):
        """Test that budget components sum to total."""
        for tier in ModelTier:
            budgets = TokenBudgets.for_tier(tier)
            component_sum = (
                budgets.immediate +
                budgets.working +
                budgets.episodic +
                budgets.semantic
            )
            assert component_sum == budgets.total

    def test_tier_budgets_decrease(self):
        """Test that smaller tiers have smaller budgets."""
        cloud = TokenBudgets.for_tier(ModelTier.CLOUD)
        mid = TokenBudgets.for_tier(ModelTier.MID_RANGE)
        device = TokenBudgets.for_tier(ModelTier.ON_DEVICE)
        tiny = TokenBudgets.for_tier(ModelTier.TINY)

        assert cloud.total > mid.total > device.total > tiny.total


class TestAdaptiveBudgetConfig:
    """Tests for AdaptiveBudgetConfig."""

    def test_from_context_window(self):
        """Test config creation from context window."""
        config = AdaptiveBudgetConfig.from_context_window(200_000)
        assert config.tier == ModelTier.CLOUD
        assert config.model_context_window == 200_000

    def test_for_model(self):
        """Test config creation for specific model."""
        config = AdaptiveBudgetConfig.for_model("gpt-4o")
        assert config.tier == ModelTier.CLOUD
        assert config.model_context_window == 128_000

    def test_unknown_model_uses_default(self):
        """Test that unknown models use default context window."""
        config = AdaptiveBudgetConfig.for_model("unknown-model")
        assert config.model_context_window == 32_000
        assert config.tier == ModelTier.MID_RANGE

    def test_max_turns_decrease_with_tier(self):
        """Test that max turns decrease with smaller tiers."""
        cloud = AdaptiveBudgetConfig.from_context_window(200_000)
        tiny = AdaptiveBudgetConfig.from_context_window(4_000)

        assert cloud.max_conversation_turns > tiny.max_conversation_turns


class TestImmediateBuffer:
    """Tests for ImmediateBuffer."""

    def test_empty_buffer_renders_empty(self):
        """Test that empty buffer renders to empty string."""
        buffer = ImmediateBuffer()
        assert buffer.render(1000) == ""

    def test_barge_in_included_in_render(self):
        """Test that barge-in utterance is included."""
        buffer = ImmediateBuffer(barge_in_utterance="Wait, what?")
        rendered = buffer.render(1000)
        assert "Wait, what?" in rendered
        assert "INTERRUPTED" in rendered

    def test_current_segment_included(self):
        """Test that current segment is included."""
        segment = TranscriptSegment(
            segment_id="123",
            text="The process of photosynthesis..."
        )
        buffer = ImmediateBuffer(current_segment=segment)
        rendered = buffer.render(1000)
        assert "photosynthesis" in rendered

    def test_recent_turns_included(self):
        """Test that conversation turns are included."""
        turns = [
            ConversationTurn(role=MessageRole.USER, content="Hello"),
            ConversationTurn(role=MessageRole.ASSISTANT, content="Hi there!"),
        ]
        buffer = ImmediateBuffer(recent_turns=turns)
        rendered = buffer.render(1000)
        assert "Hello" in rendered
        assert "Hi there!" in rendered

    def test_truncation_respects_budget(self):
        """Test that rendering respects token budget."""
        long_text = "x" * 10000
        buffer = ImmediateBuffer(barge_in_utterance=long_text)
        rendered = buffer.render(100)  # 100 tokens ~ 400 chars
        assert len(rendered) < 500


class TestWorkingBuffer:
    """Tests for WorkingBuffer."""

    def test_topic_info_included(self):
        """Test that topic information is rendered."""
        buffer = WorkingBuffer(
            topic_title="Introduction to Physics",
            topic_content="Physics is the study of matter and energy.",
            learning_objectives=["Understand basic concepts"]
        )
        rendered = buffer.render(1000)
        assert "Introduction to Physics" in rendered
        assert "matter and energy" in rendered

    def test_glossary_terms_included(self):
        """Test that glossary terms are included."""
        buffer = WorkingBuffer(
            topic_title="Test",
            glossary_terms=[
                GlossaryTerm(term="Energy", definition="The capacity to do work")
            ]
        )
        rendered = buffer.render(1000)
        assert "Energy" in rendered
        assert "capacity to do work" in rendered

    def test_misconceptions_included(self):
        """Test that misconception triggers are included."""
        buffer = WorkingBuffer(
            topic_title="Test",
            misconception_triggers=[
                MisconceptionTrigger(
                    trigger_phrase="heavier falls faster",
                    misconception="Objects fall at same rate",
                    remediation="In vacuum, all objects..."
                )
            ]
        )
        rendered = buffer.render(1000)
        assert "heavier falls faster" in rendered


class TestEpisodicBuffer:
    """Tests for EpisodicBuffer."""

    def test_topic_summaries_included(self):
        """Test that completed topics are included."""
        buffer = EpisodicBuffer(
            topic_summaries=[
                TopicSummary(
                    topic_id="123",
                    title="Intro",
                    summary="Covered basics",
                    mastery_level=0.8
                )
            ]
        )
        rendered = buffer.render(1000)
        assert "Intro" in rendered
        assert "80%" in rendered

    def test_learner_signals_included(self):
        """Test that learner signals are included."""
        buffer = EpisodicBuffer(
            learner_signals=LearnerSignals(
                clarification_requests=3,
                pace_preference=PacePreference.SLOWER
            )
        )
        rendered = buffer.render(1000)
        assert "3 clarifications" in rendered
        assert "slower" in rendered


class TestSemanticBuffer:
    """Tests for SemanticBuffer."""

    def test_curriculum_position_included(self):
        """Test that position is rendered."""
        buffer = SemanticBuffer(
            position=CurriculumPosition(
                curriculum_id="123",
                curriculum_title="Physics 101",
                current_topic_index=3,
                total_topics=20
            )
        )
        rendered = buffer.render(1000)
        assert "Physics 101" in rendered
        assert "4/20" in rendered

    def test_outline_included(self):
        """Test that curriculum outline is included."""
        buffer = SemanticBuffer(
            curriculum_outline="1. Intro\n2. Motion\n3. Forces"
        )
        rendered = buffer.render(1000)
        assert "Intro" in rendered
        assert "Motion" in rendered


class TestFOVContext:
    """Tests for FOVContext."""

    def test_to_system_message_combines_all(self):
        """Test that system message combines all contexts."""
        context = FOVContext(
            system_prompt="You are a tutor.",
            immediate_context="User just asked...",
            working_context="Current topic: Physics",
            episodic_context="Session: 30 min",
            semantic_context="Course: Physics 101"
        )

        message = context.to_system_message()
        assert "You are a tutor" in message
        assert "User just asked" in message
        assert "Current topic: Physics" in message
        assert "Session: 30 min" in message
        assert "Course: Physics 101" in message

    def test_token_estimate_calculated(self):
        """Test that token estimate is calculated."""
        context = FOVContext(
            system_prompt="Test " * 100,  # ~100 tokens
            immediate_context="More " * 50,  # ~50 tokens
            working_context="",
            episodic_context="",
            semantic_context=""
        )

        assert context.total_token_estimate > 0

    def test_to_messages_format(self):
        """Test that messages format is correct."""
        context = FOVContext(
            system_prompt="You are a tutor.",
            immediate_context="",
            working_context="",
            episodic_context="",
            semantic_context=""
        )

        messages = context.to_messages()
        assert len(messages) == 1
        assert messages[0]["role"] == "system"
        assert "tutor" in messages[0]["content"]


class TestConversationTurn:
    """Tests for ConversationTurn."""

    def test_token_estimate_auto_calculated(self):
        """Test that token estimate is auto-calculated."""
        turn = ConversationTurn(
            role=MessageRole.USER,
            content="This is a test message with some words."
        )
        assert turn.token_estimate > 0

    def test_id_auto_generated(self):
        """Test that ID is auto-generated."""
        turn = ConversationTurn(role=MessageRole.USER, content="Test")
        assert turn.id is not None
        assert len(turn.id) > 0

    def test_timestamp_auto_set(self):
        """Test that timestamp is auto-set."""
        turn = ConversationTurn(role=MessageRole.USER, content="Test")
        assert turn.timestamp is not None
        assert isinstance(turn.timestamp, datetime)
