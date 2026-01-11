"""Tests for FOVContextManager."""

import pytest
from datetime import datetime

from ..manager import (
    DEFAULT_SYSTEM_PROMPT,
    FOVContextManager,
)
from ..models import (
    AdaptiveBudgetConfig,
    ConversationTurn,
    CurriculumPosition,
    GlossaryTerm,
    MessageRole,
    MisconceptionTrigger,
    ModelTier,
    TopicSummary,
    TranscriptSegment,
)


class TestFOVContextManagerCreation:
    """Tests for FOVContextManager creation."""

    def test_for_context_window_cloud(self):
        """Test manager creation for cloud context window."""
        manager = FOVContextManager.for_context_window(200_000)
        assert manager.budget_config.tier == ModelTier.CLOUD
        assert manager.base_system_prompt == DEFAULT_SYSTEM_PROMPT

    def test_for_context_window_with_custom_prompt(self):
        """Test manager creation with custom system prompt."""
        custom_prompt = "You are a physics tutor."
        manager = FOVContextManager.for_context_window(
            200_000,
            system_prompt=custom_prompt
        )
        assert manager.base_system_prompt == custom_prompt

    def test_for_model_known(self):
        """Test manager creation for known model."""
        manager = FOVContextManager.for_model("gpt-4o")
        assert manager.budget_config.tier == ModelTier.CLOUD

    def test_for_model_unknown(self):
        """Test manager creation for unknown model."""
        manager = FOVContextManager.for_model("unknown-model")
        assert manager.budget_config.tier == ModelTier.MID_RANGE


class TestImmediateBufferUpdates:
    """Tests for immediate buffer updates."""

    def test_set_current_segment(self):
        """Test setting current segment."""
        manager = FOVContextManager.for_context_window(200_000)
        segment = TranscriptSegment(
            segment_id="seg1",
            text="The mitochondria is the powerhouse of the cell."
        )

        manager.set_current_segment(segment)

        assert manager.immediate_buffer.current_segment == segment

    def test_record_barge_in(self):
        """Test recording barge-in utterance."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_barge_in("Wait, what does that mean?")

        assert manager.immediate_buffer.barge_in_utterance == "Wait, what does that mean?"

    def test_clear_barge_in(self):
        """Test clearing barge-in after processing."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.record_barge_in("Question")

        manager.clear_barge_in()

        assert manager.immediate_buffer.barge_in_utterance is None

    def test_add_conversation_turn(self):
        """Test adding conversation turns."""
        manager = FOVContextManager.for_context_window(200_000)

        turn1 = ConversationTurn(role=MessageRole.USER, content="Hello")
        turn2 = ConversationTurn(role=MessageRole.ASSISTANT, content="Hi there!")

        manager.add_conversation_turn(turn1)
        manager.add_conversation_turn(turn2)

        assert len(manager.immediate_buffer.recent_turns) == 2
        assert manager.immediate_buffer.recent_turns[0].content == "Hello"

    def test_conversation_turns_trimmed_to_max(self):
        """Test that conversation turns are trimmed to max."""
        manager = FOVContextManager.for_context_window(200_000)
        max_turns = manager.budget_config.max_conversation_turns

        # Add more than max turns
        for i in range(max_turns + 5):
            turn = ConversationTurn(
                role=MessageRole.USER,
                content=f"Message {i}"
            )
            manager.add_conversation_turn(turn)

        assert len(manager.immediate_buffer.recent_turns) == max_turns


class TestWorkingBufferUpdates:
    """Tests for working buffer updates."""

    def test_set_current_topic(self):
        """Test setting current topic."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_current_topic(
            topic_id="topic1",
            topic_title="Introduction to Physics",
            topic_content="Physics is the study of matter and energy.",
            learning_objectives=["Understand basic concepts"]
        )

        assert manager.working_buffer.topic_id == "topic1"
        assert manager.working_buffer.topic_title == "Introduction to Physics"

    def test_set_topic_with_glossary(self):
        """Test setting topic with glossary terms."""
        manager = FOVContextManager.for_context_window(200_000)
        glossary = [
            GlossaryTerm(term="Energy", definition="Capacity to do work")
        ]

        manager.set_current_topic(
            topic_id="topic1",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=[],
            glossary_terms=glossary
        )

        assert len(manager.working_buffer.glossary_terms) == 1
        assert manager.working_buffer.glossary_terms[0].term == "Energy"

    def test_set_topic_with_misconceptions(self):
        """Test setting topic with misconception triggers."""
        manager = FOVContextManager.for_context_window(200_000)
        misconceptions = [
            MisconceptionTrigger(
                trigger_phrase="heavier falls faster",
                misconception="Objects fall at same rate",
                remediation="In a vacuum, all objects..."
            )
        ]

        manager.set_current_topic(
            topic_id="topic1",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=[],
            misconception_triggers=misconceptions
        )

        assert len(manager.working_buffer.misconception_triggers) == 1


class TestEpisodicBufferUpdates:
    """Tests for episodic buffer updates."""

    def test_record_clarification_request(self):
        """Test recording clarification requests."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_clarification_request()
        manager.record_clarification_request()

        assert manager.episodic_buffer.learner_signals.clarification_requests == 2

    def test_record_repetition_request(self):
        """Test recording repetition requests."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_repetition_request()

        assert manager.episodic_buffer.learner_signals.repetition_requests == 1

    def test_record_confusion_signal(self):
        """Test recording confusion signals."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_confusion_signal()
        manager.record_confusion_signal()
        manager.record_confusion_signal()

        assert manager.episodic_buffer.learner_signals.confusion_indicators == 3

    def test_record_topic_completion(self):
        """Test recording topic completion."""
        manager = FOVContextManager.for_context_window(200_000)
        summary = TopicSummary(
            topic_id="topic1",
            title="Intro",
            summary="Covered basics",
            mastery_level=0.85
        )

        manager.record_topic_completion(summary)

        assert len(manager.episodic_buffer.topic_summaries) == 1
        assert manager.episodic_buffer.topic_summaries[0].mastery_level == 0.85


class TestSemanticBufferUpdates:
    """Tests for semantic buffer updates."""

    def test_set_curriculum_position(self):
        """Test setting curriculum position."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_curriculum_position(
            curriculum_id="curr1",
            curriculum_title="Physics 101",
            current_topic_index=5,
            total_topics=20
        )

        assert manager.semantic_buffer.position.curriculum_id == "curr1"
        assert manager.semantic_buffer.position.current_topic_index == 5

    def test_update_semantic_buffer(self):
        """Test updating semantic buffer directly."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.update_semantic_buffer(
            curriculum_outline="1. Intro\n2. Motion\n3. Forces"
        )

        assert "Motion" in manager.semantic_buffer.curriculum_outline


class TestContextBuilding:
    """Tests for context building."""

    def test_build_context_empty(self):
        """Test building context with empty buffers."""
        manager = FOVContextManager.for_context_window(200_000)

        context = manager.build_context([])

        assert manager.base_system_prompt in context.system_prompt
        assert context.total_token_estimate > 0

    def test_build_context_with_history(self):
        """Test building context with conversation history."""
        manager = FOVContextManager.for_context_window(200_000)
        history = [
            ConversationTurn(role=MessageRole.USER, content="Hello"),
            ConversationTurn(role=MessageRole.ASSISTANT, content="Hi there!"),
        ]

        context = manager.build_context(history)
        message = context.to_system_message()

        assert "Hello" in message
        assert "Hi there!" in message

    def test_build_context_with_barge_in(self):
        """Test building context with barge-in utterance."""
        manager = FOVContextManager.for_context_window(200_000)

        context = manager.build_context(
            [],
            barge_in_utterance="Wait, explain that again!"
        )
        message = context.to_system_message()

        assert "explain that again" in message
        assert "INTERRUPTED" in message

    def test_build_context_includes_all_buffers(self):
        """Test that context includes content from all buffers."""
        manager = FOVContextManager.for_context_window(200_000)

        # Set up all buffers
        manager.set_current_topic(
            topic_id="t1",
            topic_title="Gravity",
            topic_content="Gravity pulls objects together.",
            learning_objectives=["Understand gravity"]
        )
        manager.set_curriculum_position(
            curriculum_id="c1",
            curriculum_title="Physics Course",
            current_topic_index=3,
            total_topics=10
        )
        manager.record_topic_completion(TopicSummary(
            topic_id="t0",
            title="Previous Topic",
            summary="We learned basics",
            mastery_level=0.9
        ))

        context = manager.build_context([])
        message = context.to_system_message()

        # Verify all buffer content is present
        assert "Gravity" in message
        assert "Physics Course" in message
        assert "Previous Topic" in message


class TestMessagesBuilding:
    """Tests for LLM messages building."""

    def test_build_messages_empty(self):
        """Test building messages with no history."""
        manager = FOVContextManager.for_context_window(200_000)

        messages = manager.build_messages_for_llm([])

        # Should have system message only
        assert len(messages) == 1
        assert messages[0]["role"] == "system"

    def test_build_messages_with_history(self):
        """Test building messages with conversation history."""
        manager = FOVContextManager.for_context_window(200_000)
        history = [
            ConversationTurn(role=MessageRole.USER, content="Hello"),
            ConversationTurn(role=MessageRole.ASSISTANT, content="Hi!"),
        ]

        messages = manager.build_messages_for_llm(history)

        # System + 2 conversation messages
        assert len(messages) == 3
        assert messages[0]["role"] == "system"
        assert messages[1]["role"] == "user"
        assert messages[2]["role"] == "assistant"

    def test_build_messages_respects_turn_limit(self):
        """Test that messages respect turn limit."""
        manager = FOVContextManager.for_context_window(200_000)
        max_turns = manager.budget_config.max_conversation_turns

        # Create more history than the limit
        history = [
            ConversationTurn(
                role=MessageRole.USER if i % 2 == 0 else MessageRole.ASSISTANT,
                content=f"Message {i}"
            )
            for i in range(max_turns + 10)
        ]

        messages = manager.build_messages_for_llm(history)

        # Should have system + max_turns messages
        assert len(messages) == max_turns + 1


class TestStateSnapshot:
    """Tests for state snapshot."""

    def test_get_state_snapshot(self):
        """Test getting state snapshot."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.set_current_topic(
            topic_id="topic1",
            topic_title="Test Topic",
            topic_content="Content",
            learning_objectives=["Learn"]
        )

        snapshot = manager.get_state_snapshot()

        assert "tier" in snapshot
        assert "working" in snapshot
        assert snapshot["working"]["topic_id"] == "topic1"

    def test_snapshot_includes_budgets(self):
        """Test that snapshot includes token budgets."""
        manager = FOVContextManager.for_context_window(200_000)

        snapshot = manager.get_state_snapshot()

        assert "budgets" in snapshot
        assert "immediate" in snapshot["budgets"]
        assert "working" in snapshot["budgets"]
        assert "episodic" in snapshot["budgets"]
        assert "semantic" in snapshot["budgets"]

    def test_snapshot_includes_buffer_info(self):
        """Test that snapshot includes buffer information."""
        manager = FOVContextManager.for_context_window(200_000)

        snapshot = manager.get_state_snapshot()

        assert "immediate" in snapshot
        assert "working" in snapshot
        assert "episodic" in snapshot
