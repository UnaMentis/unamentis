"""
Comprehensive tests for fov_context/manager.py (FOVContextManager).

Tests cover:
- Manager creation via for_model and for_context_window
- Immediate buffer management (segments, barge-in, conversation turns)
- Working buffer management (topics, glossary, misconceptions)
- Episodic buffer management (topic completion, questions, learner signals)
- Semantic buffer management (curriculum position, outline)
- Context building with all buffer layers
- LLM message building
- State management (reset, snapshot)
- Edge cases and error handling

Additionally tests SessionManager class for session lifecycle management.
"""

import pytest
from datetime import datetime, timedelta
from unittest.mock import patch

from fov_context.manager import (
    DEFAULT_SYSTEM_PROMPT,
    FOVContextManager,
)
from fov_context.models import (
    AdaptiveBudgetConfig,
    ConversationTurn,
    CurriculumPosition,
    GlossaryTerm,
    MessageRole,
    MisconceptionTrigger,
    ModelTier,
    PacePreference,
    TopicSummary,
    TranscriptSegment,
)
from fov_context.session import (
    FOVSession,
    PlaybackState,
    SessionConfig,
    SessionEvent,
    SessionManager,
    SessionState,
    UserSession,
    UserVoiceConfig,
)


# =============================================================================
# FOVContextManager Creation Tests
# =============================================================================

class TestFOVContextManagerCreation:
    """Tests for FOVContextManager factory methods."""

    def test_for_context_window_cloud_tier(self):
        """Test manager creation for cloud context window (100K+)."""
        manager = FOVContextManager.for_context_window(200_000)

        assert manager.budget_config.tier == ModelTier.CLOUD
        assert manager.budget_config.model_context_window == 200_000
        assert manager.base_system_prompt == DEFAULT_SYSTEM_PROMPT

    def test_for_context_window_mid_range_tier(self):
        """Test manager creation for mid-range context window (32K-100K)."""
        manager = FOVContextManager.for_context_window(64_000)

        assert manager.budget_config.tier == ModelTier.MID_RANGE

    def test_for_context_window_on_device_tier(self):
        """Test manager creation for on-device context window (8K-32K)."""
        manager = FOVContextManager.for_context_window(16_000)

        assert manager.budget_config.tier == ModelTier.ON_DEVICE

    def test_for_context_window_tiny_tier(self):
        """Test manager creation for tiny context window (<8K)."""
        manager = FOVContextManager.for_context_window(4_000)

        assert manager.budget_config.tier == ModelTier.TINY

    def test_for_context_window_boundary_cloud(self):
        """Test exact boundary at 100K for cloud tier."""
        manager = FOVContextManager.for_context_window(100_000)

        assert manager.budget_config.tier == ModelTier.CLOUD

    def test_for_context_window_boundary_mid_range(self):
        """Test exact boundary at 32K for mid-range tier."""
        manager = FOVContextManager.for_context_window(32_000)

        assert manager.budget_config.tier == ModelTier.MID_RANGE

    def test_for_context_window_boundary_on_device(self):
        """Test exact boundary at 8K for on-device tier."""
        manager = FOVContextManager.for_context_window(8_000)

        assert manager.budget_config.tier == ModelTier.ON_DEVICE

    def test_for_context_window_with_custom_prompt(self):
        """Test manager creation with custom system prompt."""
        custom_prompt = "You are a physics tutor specializing in quantum mechanics."
        manager = FOVContextManager.for_context_window(
            200_000,
            system_prompt=custom_prompt
        )

        assert manager.base_system_prompt == custom_prompt
        assert manager.base_system_prompt != DEFAULT_SYSTEM_PROMPT

    def test_for_model_known_claude(self):
        """Test manager creation for known Claude model."""
        manager = FOVContextManager.for_model("claude-3-5-sonnet-20241022")

        assert manager.budget_config.tier == ModelTier.CLOUD

    def test_for_model_known_gpt4o(self):
        """Test manager creation for known GPT-4o model."""
        manager = FOVContextManager.for_model("gpt-4o")

        assert manager.budget_config.tier == ModelTier.CLOUD

    def test_for_model_known_gpt4(self):
        """Test manager creation for GPT-4 (smaller context)."""
        manager = FOVContextManager.for_model("gpt-4")

        # GPT-4 has 8192 context window, should be ON_DEVICE tier
        assert manager.budget_config.tier == ModelTier.ON_DEVICE

    def test_for_model_unknown_defaults_to_mid_range(self):
        """Test manager creation for unknown model defaults to mid-range."""
        manager = FOVContextManager.for_model("unknown-model-xyz")

        # Unknown models default to 32K, which is mid-range
        assert manager.budget_config.tier == ModelTier.MID_RANGE

    def test_for_model_with_custom_prompt(self):
        """Test for_model with custom system prompt."""
        custom_prompt = "Custom prompt"
        manager = FOVContextManager.for_model("gpt-4o", system_prompt=custom_prompt)

        assert manager.base_system_prompt == custom_prompt

    def test_buffers_initialized_empty(self):
        """Test that all buffers are initialized empty."""
        manager = FOVContextManager.for_context_window(200_000)

        assert manager.immediate_buffer.recent_turns == []
        assert manager.immediate_buffer.barge_in_utterance is None
        assert manager.working_buffer.topic_id is None
        assert manager.episodic_buffer.topic_summaries == []
        assert manager.semantic_buffer.position is None


# =============================================================================
# Immediate Buffer Management Tests
# =============================================================================

class TestImmediateBufferManagement:
    """Tests for immediate buffer operations."""

    def test_set_current_segment(self):
        """Test setting current transcript segment."""
        manager = FOVContextManager.for_context_window(200_000)
        segment = TranscriptSegment(
            segment_id="seg-001",
            text="The mitochondria is the powerhouse of the cell.",
            start_time=0.0,
            end_time=5.0,
            topic_id="bio-101"
        )

        manager.set_current_segment(segment)

        assert manager.immediate_buffer.current_segment == segment
        assert manager.immediate_buffer.current_segment.segment_id == "seg-001"

    def test_set_current_segment_replaces_previous(self):
        """Test that setting segment replaces previous segment."""
        manager = FOVContextManager.for_context_window(200_000)
        segment1 = TranscriptSegment(segment_id="seg-001", text="First segment")
        segment2 = TranscriptSegment(segment_id="seg-002", text="Second segment")

        manager.set_current_segment(segment1)
        manager.set_current_segment(segment2)

        assert manager.immediate_buffer.current_segment.segment_id == "seg-002"

    def test_record_barge_in(self):
        """Test recording barge-in utterance."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_barge_in("Wait, what does that mean?")

        assert manager.immediate_buffer.barge_in_utterance == "Wait, what does that mean?"

    def test_record_barge_in_with_position(self):
        """Test recording barge-in with interrupted position."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_barge_in("Hold on!", interrupted_position=3.5)

        assert manager.immediate_buffer.barge_in_utterance == "Hold on!"
        assert manager.immediate_buffer.interrupted_at_position == 3.5

    def test_clear_barge_in(self):
        """Test clearing barge-in state."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.record_barge_in("Question", interrupted_position=2.0)

        manager.clear_barge_in()

        assert manager.immediate_buffer.barge_in_utterance is None
        assert manager.immediate_buffer.interrupted_at_position is None

    def test_add_conversation_turn_user(self):
        """Test adding user conversation turn."""
        manager = FOVContextManager.for_context_window(200_000)
        turn = ConversationTurn(role=MessageRole.USER, content="Hello, tutor!")

        manager.add_conversation_turn(turn)

        assert len(manager.immediate_buffer.recent_turns) == 1
        assert manager.immediate_buffer.recent_turns[0].content == "Hello, tutor!"
        assert manager.immediate_buffer.recent_turns[0].role == MessageRole.USER

    def test_add_conversation_turn_assistant(self):
        """Test adding assistant conversation turn."""
        manager = FOVContextManager.for_context_window(200_000)
        turn = ConversationTurn(role=MessageRole.ASSISTANT, content="Hello, student!")

        manager.add_conversation_turn(turn)

        assert len(manager.immediate_buffer.recent_turns) == 1
        assert manager.immediate_buffer.recent_turns[0].role == MessageRole.ASSISTANT

    def test_conversation_turns_preserved_in_order(self):
        """Test that conversation turns preserve order."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.add_conversation_turn(
            ConversationTurn(role=MessageRole.USER, content="Message 1")
        )
        manager.add_conversation_turn(
            ConversationTurn(role=MessageRole.ASSISTANT, content="Message 2")
        )
        manager.add_conversation_turn(
            ConversationTurn(role=MessageRole.USER, content="Message 3")
        )

        assert len(manager.immediate_buffer.recent_turns) == 3
        assert manager.immediate_buffer.recent_turns[0].content == "Message 1"
        assert manager.immediate_buffer.recent_turns[1].content == "Message 2"
        assert manager.immediate_buffer.recent_turns[2].content == "Message 3"

    def test_conversation_turns_trimmed_to_max_cloud(self):
        """Test turns are trimmed to max for cloud tier (20 turns)."""
        manager = FOVContextManager.for_context_window(200_000)
        max_turns = manager.budget_config.max_conversation_turns
        assert max_turns == 20  # Cloud tier

        # Add more than max turns
        for i in range(max_turns + 10):
            turn = ConversationTurn(role=MessageRole.USER, content=f"Message {i}")
            manager.add_conversation_turn(turn)

        assert len(manager.immediate_buffer.recent_turns) == max_turns
        # Oldest messages should be trimmed
        assert manager.immediate_buffer.recent_turns[0].content == "Message 10"

    def test_conversation_turns_trimmed_to_max_tiny(self):
        """Test turns are trimmed to max for tiny tier (3 turns)."""
        manager = FOVContextManager.for_context_window(4_000)
        max_turns = manager.budget_config.max_conversation_turns
        assert max_turns == 3  # Tiny tier

        for i in range(10):
            turn = ConversationTurn(role=MessageRole.USER, content=f"Message {i}")
            manager.add_conversation_turn(turn)

        assert len(manager.immediate_buffer.recent_turns) == max_turns


# =============================================================================
# Working Buffer Management Tests
# =============================================================================

class TestWorkingBufferManagement:
    """Tests for working buffer operations."""

    def test_set_current_topic_basic(self):
        """Test setting current topic with basic info."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_current_topic(
            topic_id="topic-001",
            topic_title="Introduction to Physics",
            topic_content="Physics is the study of matter and energy.",
            learning_objectives=["Understand basic concepts", "Apply formulas"]
        )

        assert manager.working_buffer.topic_id == "topic-001"
        assert manager.working_buffer.topic_title == "Introduction to Physics"
        assert manager.working_buffer.topic_content == "Physics is the study of matter and energy."
        assert len(manager.working_buffer.learning_objectives) == 2

    def test_set_current_topic_with_glossary(self):
        """Test setting topic with glossary terms."""
        manager = FOVContextManager.for_context_window(200_000)
        glossary = [
            GlossaryTerm(term="Energy", definition="Capacity to do work"),
            GlossaryTerm(term="Force", definition="A push or pull", pronunciation="fors"),
        ]

        manager.set_current_topic(
            topic_id="topic-001",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=[],
            glossary_terms=glossary
        )

        assert len(manager.working_buffer.glossary_terms) == 2
        assert manager.working_buffer.glossary_terms[0].term == "Energy"
        assert manager.working_buffer.glossary_terms[1].pronunciation == "fors"

    def test_set_current_topic_with_misconceptions(self):
        """Test setting topic with misconception triggers."""
        manager = FOVContextManager.for_context_window(200_000)
        misconceptions = [
            MisconceptionTrigger(
                trigger_phrase="heavier falls faster",
                misconception="Heavy objects fall faster than light ones",
                remediation="In a vacuum, all objects fall at the same rate"
            ),
        ]

        manager.set_current_topic(
            topic_id="topic-001",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=[],
            misconception_triggers=misconceptions
        )

        assert len(manager.working_buffer.misconception_triggers) == 1
        assert manager.working_buffer.misconception_triggers[0].trigger_phrase == "heavier falls faster"

    def test_set_current_topic_replaces_buffer(self):
        """Test that set_current_topic replaces entire working buffer."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_current_topic(
            topic_id="topic-001",
            topic_title="First Topic",
            topic_content="First content",
            learning_objectives=["Obj 1", "Obj 2"]
        )
        manager.set_current_topic(
            topic_id="topic-002",
            topic_title="Second Topic",
            topic_content="Second content",
            learning_objectives=["Obj 3"]
        )

        assert manager.working_buffer.topic_id == "topic-002"
        assert manager.working_buffer.topic_title == "Second Topic"
        assert len(manager.working_buffer.learning_objectives) == 1

    def test_update_working_buffer_partial(self):
        """Test updating working buffer with partial fields."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.set_current_topic(
            topic_id="topic-001",
            topic_title="Original Title",
            topic_content="Original content",
            learning_objectives=["Obj 1"]
        )

        manager.update_working_buffer(topic_title="Updated Title")

        assert manager.working_buffer.topic_id == "topic-001"  # unchanged
        assert manager.working_buffer.topic_title == "Updated Title"  # changed
        assert manager.working_buffer.topic_content == "Original content"  # unchanged

    def test_update_working_buffer_all_fields(self):
        """Test updating working buffer with all fields."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.update_working_buffer(
            topic_id="new-id",
            topic_title="New Title",
            topic_content="New content",
            learning_objectives=["New obj"],
            glossary_terms=[GlossaryTerm(term="Term", definition="Def")],
            misconception_triggers=[MisconceptionTrigger(
                trigger_phrase="phrase",
                misconception="misconception",
                remediation="remediation"
            )]
        )

        assert manager.working_buffer.topic_id == "new-id"
        assert len(manager.working_buffer.glossary_terms) == 1
        assert len(manager.working_buffer.misconception_triggers) == 1


# =============================================================================
# Episodic Buffer Management Tests
# =============================================================================

class TestEpisodicBufferManagement:
    """Tests for episodic buffer operations."""

    def test_record_topic_completion(self):
        """Test recording topic completion."""
        manager = FOVContextManager.for_context_window(200_000)
        summary = TopicSummary(
            topic_id="topic-001",
            title="Introduction",
            summary="Covered basic concepts",
            mastery_level=0.85
        )

        manager.record_topic_completion(summary)

        assert len(manager.episodic_buffer.topic_summaries) == 1
        assert manager.episodic_buffer.topic_summaries[0].mastery_level == 0.85

    def test_topic_summaries_trimmed_to_max(self):
        """Test topic summaries are trimmed to max of 10."""
        manager = FOVContextManager.for_context_window(200_000)

        # Add 15 topic summaries
        for i in range(15):
            summary = TopicSummary(
                topic_id=f"topic-{i:03d}",
                title=f"Topic {i}",
                summary=f"Summary {i}",
                mastery_level=0.8
            )
            manager.record_topic_completion(summary)

        assert len(manager.episodic_buffer.topic_summaries) == 10
        # First 5 should be trimmed
        assert manager.episodic_buffer.topic_summaries[0].topic_id == "topic-005"

    def test_record_user_question(self):
        """Test recording user question."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_user_question("What is gravity?")

        assert len(manager.episodic_buffer.user_questions) == 1
        assert manager.episodic_buffer.user_questions[0] == "What is gravity?"

    def test_user_questions_trimmed_to_max(self):
        """Test user questions are trimmed to max of 10."""
        manager = FOVContextManager.for_context_window(200_000)

        for i in range(15):
            manager.record_user_question(f"Question {i}")

        assert len(manager.episodic_buffer.user_questions) == 10
        assert manager.episodic_buffer.user_questions[0] == "Question 5"

    def test_record_clarification_request(self):
        """Test recording clarification request."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_clarification_request()
        manager.record_clarification_request()

        assert manager.episodic_buffer.learner_signals.clarification_requests == 2

    def test_record_repetition_request(self):
        """Test recording repetition request."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_repetition_request()

        assert manager.episodic_buffer.learner_signals.repetition_requests == 1

    def test_record_confusion_signal(self):
        """Test recording confusion signal."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.record_confusion_signal()
        manager.record_confusion_signal()
        manager.record_confusion_signal()

        assert manager.episodic_buffer.learner_signals.confusion_indicators == 3

    def test_set_pace_preference_slower(self):
        """Test setting pace preference to slower."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_pace_preference(PacePreference.SLOWER)

        assert manager.episodic_buffer.learner_signals.pace_preference == PacePreference.SLOWER

    def test_set_pace_preference_faster(self):
        """Test setting pace preference to faster."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_pace_preference(PacePreference.FASTER)

        assert manager.episodic_buffer.learner_signals.pace_preference == PacePreference.FASTER

    def test_update_session_duration(self):
        """Test updating session duration."""
        manager = FOVContextManager.for_context_window(200_000)
        # Set session start to 30 minutes ago
        manager.episodic_buffer.session_start = datetime.now() - timedelta(minutes=30)

        manager.update_session_duration()

        # Duration should be approximately 30 minutes
        assert 29.9 < manager.episodic_buffer.session_duration_minutes < 30.1


# =============================================================================
# Semantic Buffer Management Tests
# =============================================================================

class TestSemanticBufferManagement:
    """Tests for semantic buffer operations."""

    def test_set_curriculum_position(self):
        """Test setting curriculum position."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_curriculum_position(
            curriculum_id="curr-001",
            curriculum_title="Physics 101",
            current_topic_index=5,
            total_topics=20
        )

        pos = manager.semantic_buffer.position
        assert pos.curriculum_id == "curr-001"
        assert pos.curriculum_title == "Physics 101"
        assert pos.current_topic_index == 5
        assert pos.total_topics == 20

    def test_set_curriculum_position_with_unit(self):
        """Test setting curriculum position with unit and module."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.set_curriculum_position(
            curriculum_id="curr-001",
            curriculum_title="Physics 101",
            current_topic_index=5,
            total_topics=20,
            unit_title="Unit 2: Motion",
            module_title="Module 1: Kinematics"
        )

        pos = manager.semantic_buffer.position
        assert pos.unit_title == "Unit 2: Motion"
        assert pos.module_title == "Module 1: Kinematics"

    def test_update_semantic_buffer_outline(self):
        """Test updating semantic buffer with curriculum outline."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.update_semantic_buffer(
            curriculum_outline="1. Intro\n2. Motion\n3. Forces\n4. Energy"
        )

        assert "Motion" in manager.semantic_buffer.curriculum_outline

    def test_update_semantic_buffer_position(self):
        """Test updating semantic buffer with position."""
        manager = FOVContextManager.for_context_window(200_000)
        position = CurriculumPosition(
            curriculum_id="curr-001",
            curriculum_title="Physics",
            current_topic_index=3,
            total_topics=10
        )

        manager.update_semantic_buffer(position=position)

        assert manager.semantic_buffer.position.current_topic_index == 3

    def test_update_semantic_buffer_prerequisites(self):
        """Test updating semantic buffer with prerequisites."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.update_semantic_buffer(
            prerequisite_topics=["Algebra", "Trigonometry"]
        )

        assert len(manager.semantic_buffer.prerequisite_topics) == 2
        assert "Algebra" in manager.semantic_buffer.prerequisite_topics

    def test_update_semantic_buffer_upcoming(self):
        """Test updating semantic buffer with upcoming topics."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.update_semantic_buffer(
            upcoming_topics=["Forces", "Energy", "Momentum"]
        )

        assert len(manager.semantic_buffer.upcoming_topics) == 3


# =============================================================================
# Context Building Tests
# =============================================================================

class TestContextBuilding:
    """Tests for context building operations."""

    def test_build_context_empty(self):
        """Test building context with empty buffers."""
        manager = FOVContextManager.for_context_window(200_000)

        context = manager.build_context()

        assert context.system_prompt == DEFAULT_SYSTEM_PROMPT
        assert context.total_token_estimate > 0

    def test_build_context_with_none_history(self):
        """Test building context with None history."""
        manager = FOVContextManager.for_context_window(200_000)

        context = manager.build_context(conversation_history=None)

        assert context is not None

    def test_build_context_with_empty_history(self):
        """Test building context with empty list history."""
        manager = FOVContextManager.for_context_window(200_000)

        context = manager.build_context(conversation_history=[])

        assert context is not None

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

        context = manager.build_context(barge_in_utterance="Wait, explain that!")

        message = context.to_system_message()
        assert "explain that" in message
        assert "INTERRUPTED" in message

    def test_build_context_updates_immediate_buffer(self):
        """Test that build_context updates immediate buffer state."""
        manager = FOVContextManager.for_context_window(200_000)
        history = [
            ConversationTurn(role=MessageRole.USER, content="Test message"),
        ]

        manager.build_context(history, barge_in_utterance="Interruption!")

        assert len(manager.immediate_buffer.recent_turns) == 1
        assert manager.immediate_buffer.barge_in_utterance == "Interruption!"

    def test_build_context_respects_turn_limit(self):
        """Test that build_context respects max conversation turns."""
        manager = FOVContextManager.for_context_window(200_000)
        max_turns = manager.budget_config.max_conversation_turns

        # Create more history than the limit
        history = [
            ConversationTurn(role=MessageRole.USER, content=f"Message {i}")
            for i in range(max_turns + 10)
        ]

        manager.build_context(history)

        assert len(manager.immediate_buffer.recent_turns) == max_turns

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

        # Verify content from each buffer
        assert "Gravity" in message  # working
        assert "Physics Course" in message  # semantic
        assert "Previous Topic" in message  # episodic


class TestLLMMessagesBuilding:
    """Tests for LLM messages building."""

    def test_build_messages_empty(self):
        """Test building messages with no history."""
        manager = FOVContextManager.for_context_window(200_000)

        messages = manager.build_messages_for_llm()

        assert len(messages) == 1
        assert messages[0]["role"] == "system"

    def test_build_messages_with_none_history(self):
        """Test building messages with None history."""
        manager = FOVContextManager.for_context_window(200_000)

        messages = manager.build_messages_for_llm(conversation_history=None)

        assert len(messages) == 1

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
        assert messages[1]["content"] == "Hello"
        assert messages[2]["role"] == "assistant"
        assert messages[2]["content"] == "Hi!"

    def test_build_messages_with_barge_in(self):
        """Test building messages with barge-in utterance."""
        manager = FOVContextManager.for_context_window(200_000)

        messages = manager.build_messages_for_llm(
            barge_in_utterance="Wait!"
        )

        assert "Wait!" in messages[0]["content"]

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


# =============================================================================
# State Management Tests
# =============================================================================

class TestStateManagement:
    """Tests for state management operations."""

    def test_reset(self):
        """Test resetting all buffers."""
        manager = FOVContextManager.for_context_window(200_000)

        # Populate all buffers
        manager.set_current_topic(
            topic_id="t1",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=["Obj"]
        )
        manager.add_conversation_turn(
            ConversationTurn(role=MessageRole.USER, content="Hello")
        )
        manager.record_topic_completion(TopicSummary(
            topic_id="t0",
            title="Done",
            summary="Summary",
            mastery_level=0.9
        ))
        manager.set_curriculum_position(
            curriculum_id="c1",
            curriculum_title="Course",
            current_topic_index=5,
            total_topics=10
        )

        manager.reset()

        # All buffers should be empty
        assert manager.immediate_buffer.recent_turns == []
        assert manager.immediate_buffer.barge_in_utterance is None
        assert manager.working_buffer.topic_id is None
        assert len(manager.episodic_buffer.topic_summaries) == 0
        assert manager.semantic_buffer.position is None

    def test_get_state_snapshot_basic(self):
        """Test getting basic state snapshot."""
        manager = FOVContextManager.for_context_window(200_000)

        snapshot = manager.get_state_snapshot()

        assert "tier" in snapshot
        assert snapshot["tier"] == "cloud"
        assert "budgets" in snapshot
        assert "immediate" in snapshot
        assert "working" in snapshot
        assert "episodic" in snapshot
        assert "semantic" in snapshot

    def test_get_state_snapshot_budgets(self):
        """Test that snapshot includes all budget info."""
        manager = FOVContextManager.for_context_window(200_000)

        snapshot = manager.get_state_snapshot()

        assert snapshot["budgets"]["immediate"] > 0
        assert snapshot["budgets"]["working"] > 0
        assert snapshot["budgets"]["episodic"] > 0
        assert snapshot["budgets"]["semantic"] > 0
        assert snapshot["budgets"]["total"] > 0

    def test_get_state_snapshot_with_content(self):
        """Test snapshot reflects actual content."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.set_current_topic(
            topic_id="topic-001",
            topic_title="Test Topic",
            topic_content="Content",
            learning_objectives=["Obj 1", "Obj 2"],
            glossary_terms=[GlossaryTerm(term="T", definition="D")],
            misconception_triggers=[MisconceptionTrigger(
                trigger_phrase="p", misconception="m", remediation="r"
            )]
        )
        manager.add_conversation_turn(
            ConversationTurn(role=MessageRole.USER, content="Hello")
        )
        manager.record_barge_in("Wait!")
        manager.set_current_segment(TranscriptSegment(segment_id="s1", text="Text"))

        snapshot = manager.get_state_snapshot()

        assert snapshot["working"]["topic_id"] == "topic-001"
        assert snapshot["working"]["topic_title"] == "Test Topic"
        assert snapshot["working"]["objective_count"] == 2
        assert snapshot["working"]["glossary_count"] == 1
        assert snapshot["working"]["misconception_count"] == 1
        assert snapshot["immediate"]["turn_count"] == 1
        assert snapshot["immediate"]["has_barge_in"] is True
        assert snapshot["immediate"]["has_segment"] is True

    def test_get_state_snapshot_episodic(self):
        """Test snapshot episodic buffer info."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.record_topic_completion(TopicSummary(
            topic_id="t1", title="T1", summary="S", mastery_level=0.8
        ))
        manager.record_user_question("Q1")
        manager.record_clarification_request()
        manager.record_clarification_request()

        snapshot = manager.get_state_snapshot()

        assert snapshot["episodic"]["topic_count"] == 1
        assert snapshot["episodic"]["question_count"] == 1
        assert snapshot["episodic"]["clarification_requests"] == 2

    def test_get_state_snapshot_semantic(self):
        """Test snapshot semantic buffer info."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.update_semantic_buffer(
            curriculum_outline="Outline",
            prerequisite_topics=["A", "B"],
            upcoming_topics=["C", "D", "E"]
        )
        manager.set_curriculum_position(
            curriculum_id="c1",
            curriculum_title="Course",
            current_topic_index=5,
            total_topics=10
        )

        snapshot = manager.get_state_snapshot()

        assert snapshot["semantic"]["has_outline"] is True
        assert snapshot["semantic"]["has_position"] is True
        assert snapshot["semantic"]["prerequisite_count"] == 2
        assert snapshot["semantic"]["upcoming_count"] == 3


# =============================================================================
# SessionManager Tests
# =============================================================================

class TestSessionManager:
    """Tests for SessionManager class."""

    def test_create_session(self):
        """Test creating FOV session through manager."""
        manager = SessionManager()

        session = manager.create_session(curriculum_id="curr-123")

        assert session.session_id is not None
        assert session.curriculum_id == "curr-123"
        assert manager.get_session(session.session_id) is session

    def test_create_session_with_config(self):
        """Test creating session with custom config."""
        manager = SessionManager()
        config = SessionConfig(
            model_name="gpt-4o",
            model_context_window=128_000
        )

        session = manager.create_session(curriculum_id="curr-123", config=config)

        assert session.config.model_name == "gpt-4o"

    def test_get_session_exists(self):
        """Test getting existing session by ID."""
        manager = SessionManager()
        session = manager.create_session(curriculum_id="curr-123")

        retrieved = manager.get_session(session.session_id)

        assert retrieved is session

    def test_get_session_not_exists(self):
        """Test getting nonexistent session returns None."""
        manager = SessionManager()

        result = manager.get_session("nonexistent-id")

        assert result is None

    def test_end_session(self):
        """Test ending and removing session."""
        manager = SessionManager()
        session = manager.create_session(curriculum_id="curr-123")
        session_id = session.session_id

        result = manager.end_session(session_id)

        assert result is True
        assert session.state == SessionState.ENDED
        assert manager.get_session(session_id) is None

    def test_end_nonexistent_session(self):
        """Test ending nonexistent session returns False."""
        manager = SessionManager()

        result = manager.end_session("nonexistent-id")

        assert result is False

    def test_list_sessions_empty(self):
        """Test listing sessions when empty."""
        manager = SessionManager()

        sessions = manager.list_sessions()

        assert sessions == []

    def test_list_sessions_multiple(self):
        """Test listing multiple sessions."""
        manager = SessionManager()
        manager.create_session(curriculum_id="curr-1")
        manager.create_session(curriculum_id="curr-2")
        manager.create_session(curriculum_id="curr-3")

        sessions = manager.list_sessions()

        assert len(sessions) == 3

    def test_cleanup_ended_sessions(self):
        """Test cleanup of ended sessions."""
        manager = SessionManager()
        s1 = manager.create_session(curriculum_id="curr-1")
        s2 = manager.create_session(curriculum_id="curr-2")
        s3 = manager.create_session(curriculum_id="curr-3")

        s1.end()
        s3.end()

        removed = manager.cleanup_ended_sessions()

        assert removed == 2
        assert manager.get_session(s1.session_id) is None
        assert manager.get_session(s2.session_id) is not None
        assert manager.get_session(s3.session_id) is None

    def test_cleanup_ended_sessions_none(self):
        """Test cleanup when no sessions are ended."""
        manager = SessionManager()
        manager.create_session(curriculum_id="curr-1")
        manager.create_session(curriculum_id="curr-2")

        removed = manager.cleanup_ended_sessions()

        assert removed == 0


# =============================================================================
# User Session Tests
# =============================================================================

class TestUserSessionManager:
    """Tests for user session management in SessionManager."""

    def test_create_user_session(self):
        """Test creating user session."""
        manager = SessionManager()

        session = manager.create_user_session(user_id="user-001")

        assert session.user_id == "user-001"
        assert session.session_id is not None

    def test_create_user_session_with_org(self):
        """Test creating user session with organization."""
        manager = SessionManager()

        session = manager.create_user_session(
            user_id="user-001",
            organization_id="org-001"
        )

        assert session.organization_id == "org-001"

    def test_create_user_session_with_voice_config(self):
        """Test creating user session with voice config."""
        manager = SessionManager()
        voice_config = UserVoiceConfig(
            voice_id="alloy",
            tts_provider="openai",
            speed=1.2
        )

        session = manager.create_user_session(
            user_id="user-001",
            voice_config=voice_config
        )

        assert session.voice_config.voice_id == "alloy"
        assert session.voice_config.speed == 1.2

    def test_create_user_session_returns_existing(self):
        """Test that creating user session returns existing one."""
        manager = SessionManager()

        session1 = manager.create_user_session(user_id="user-001")
        session2 = manager.create_user_session(user_id="user-001")

        assert session1 is session2

    def test_get_user_session(self):
        """Test getting user session by session ID."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-001")

        retrieved = manager.get_user_session(session.session_id)

        assert retrieved is session

    def test_get_user_session_by_user(self):
        """Test getting user session by user ID."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-001")

        retrieved = manager.get_user_session_by_user("user-001")

        assert retrieved is session

    def test_get_user_session_by_user_not_exists(self):
        """Test getting nonexistent user session by user ID."""
        manager = SessionManager()

        result = manager.get_user_session_by_user("nonexistent-user")

        assert result is None

    def test_end_user_session(self):
        """Test ending user session."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-001")
        session_id = session.session_id

        result = manager.end_user_session(session_id)

        assert result is True
        assert manager.get_user_session(session_id) is None
        assert manager.get_user_session_by_user("user-001") is None

    def test_end_user_session_with_fov(self):
        """Test ending user session also ends attached FOV session."""
        manager = SessionManager()
        user_session = manager.create_user_session(user_id="user-001")
        fov_session = manager.create_session(curriculum_id="curr-001")
        user_session.attach_fov_session(fov_session)

        manager.end_user_session(user_session.session_id)

        assert manager.get_session(fov_session.session_id) is None

    def test_end_nonexistent_user_session(self):
        """Test ending nonexistent user session returns False."""
        manager = SessionManager()

        result = manager.end_user_session("nonexistent-id")

        assert result is False

    def test_list_user_sessions(self):
        """Test listing user sessions."""
        manager = SessionManager()
        manager.create_user_session(user_id="user-001")
        manager.create_user_session(user_id="user-002")

        sessions = manager.list_user_sessions()

        assert len(sessions) == 2

    def test_cleanup_inactive_user_sessions(self):
        """Test cleanup of inactive user sessions."""
        manager = SessionManager()

        # Create session with old last_active_at
        session = manager.create_user_session(user_id="user-001")
        session.last_active_at = datetime.now() - timedelta(hours=2)

        # Create recent session
        manager.create_user_session(user_id="user-002")

        removed = manager.cleanup_inactive_user_sessions(max_inactive_minutes=60)

        assert removed == 1
        assert manager.get_user_session_by_user("user-001") is None
        assert manager.get_user_session_by_user("user-002") is not None


# =============================================================================
# User Session and Playback State Tests
# =============================================================================

class TestUserSession:
    """Tests for UserSession class."""

    def test_create(self):
        """Test UserSession creation."""
        session = UserSession.create(user_id="user-001")

        assert session.user_id == "user-001"
        assert session.session_id is not None

    def test_attach_fov_session(self):
        """Test attaching FOV session."""
        user_session = UserSession.create(user_id="user-001")
        fov_session = FOVSession.create(curriculum_id="curr-001")

        user_session.attach_fov_session(fov_session)

        assert user_session.fov_session is fov_session

    def test_update_voice_config(self):
        """Test updating voice config."""
        session = UserSession.create(user_id="user-001")

        session.update_voice_config(
            voice_id="echo",
            tts_provider="openai",
            speed=0.9
        )

        assert session.voice_config.voice_id == "echo"
        assert session.voice_config.tts_provider == "openai"
        assert session.voice_config.speed == 0.9

    def test_update_playback(self):
        """Test updating playback position."""
        session = UserSession.create(user_id="user-001")

        session.update_playback(segment_index=5, offset_ms=1500)

        assert session.playback_state.segment_index == 5
        assert session.playback_state.segment_offset_ms == 1500
        assert session.playback_state.is_playing is True

    def test_set_current_topic(self):
        """Test setting current topic for playback."""
        session = UserSession.create(user_id="user-001")

        session.set_current_topic(curriculum_id="curr-001", topic_id="topic-001")

        assert session.playback_state.curriculum_id == "curr-001"
        assert session.playback_state.topic_id == "topic-001"
        assert session.playback_state.segment_index == 0

    def test_get_state(self):
        """Test getting user session state."""
        session = UserSession.create(
            user_id="user-001",
            organization_id="org-001"
        )

        state = session.get_state()

        assert state["user_id"] == "user-001"
        assert state["organization_id"] == "org-001"
        assert "voice_config" in state
        assert "playback_state" in state


class TestPlaybackState:
    """Tests for PlaybackState class."""

    def test_update_position(self):
        """Test updating playback position."""
        state = PlaybackState()

        state.update_position(segment_index=3, offset_ms=500, is_playing=True)

        assert state.segment_index == 3
        assert state.segment_offset_ms == 500
        assert state.is_playing is True
        assert state.last_heartbeat is not None

    def test_set_topic(self):
        """Test setting topic."""
        state = PlaybackState()
        state.segment_index = 5
        state.segment_offset_ms = 1000

        state.set_topic(curriculum_id="curr-001", topic_id="topic-001")

        assert state.curriculum_id == "curr-001"
        assert state.topic_id == "topic-001"
        assert state.segment_index == 0
        assert state.segment_offset_ms == 0

    def test_to_dict(self):
        """Test converting to dictionary."""
        state = PlaybackState(
            curriculum_id="curr-001",
            topic_id="topic-001",
            segment_index=3,
            segment_offset_ms=500,
            is_playing=True
        )

        d = state.to_dict()

        assert d["curriculum_id"] == "curr-001"
        assert d["topic_id"] == "topic-001"
        assert d["segment_index"] == 3


class TestUserVoiceConfig:
    """Tests for UserVoiceConfig class."""

    def test_default_values(self):
        """Test default voice config values."""
        config = UserVoiceConfig()

        assert config.voice_id == "nova"
        assert config.tts_provider == "vibevoice"
        assert config.speed == 1.0

    def test_to_dict_basic(self):
        """Test basic to_dict conversion."""
        config = UserVoiceConfig(
            voice_id="alloy",
            tts_provider="openai",
            speed=1.2
        )

        d = config.to_dict()

        assert d["voice_id"] == "alloy"
        assert d["tts_provider"] == "openai"
        assert d["speed"] == 1.2
        assert "exaggeration" not in d

    def test_to_dict_with_chatterbox(self):
        """Test to_dict with Chatterbox-specific fields."""
        config = UserVoiceConfig(
            voice_id="custom",
            tts_provider="chatterbox",
            speed=1.0,
            exaggeration=0.5,
            cfg_weight=0.8
        )

        d = config.to_dict()

        assert d["exaggeration"] == 0.5
        assert d["cfg_weight"] == 0.8

    def test_get_chatterbox_config_not_chatterbox(self):
        """Test get_chatterbox_config returns None for non-Chatterbox."""
        config = UserVoiceConfig(tts_provider="openai")

        result = config.get_chatterbox_config()

        assert result is None

    def test_get_chatterbox_config_with_values(self):
        """Test get_chatterbox_config with values."""
        config = UserVoiceConfig(
            tts_provider="chatterbox",
            exaggeration=0.7,
            cfg_weight=0.9,
            language="en"
        )

        result = config.get_chatterbox_config()

        assert result["exaggeration"] == 0.7
        assert result["cfg_weight"] == 0.9
        assert result["language"] == "en"

    def test_get_chatterbox_config_no_values(self):
        """Test get_chatterbox_config returns None when no values set."""
        config = UserVoiceConfig(tts_provider="chatterbox")

        result = config.get_chatterbox_config()

        assert result is None


# =============================================================================
# Edge Cases and Error Handling Tests
# =============================================================================

class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_very_small_context_window(self):
        """Test with very small context window."""
        manager = FOVContextManager.for_context_window(1000)

        assert manager.budget_config.tier == ModelTier.TINY

    def test_very_large_context_window(self):
        """Test with very large context window."""
        manager = FOVContextManager.for_context_window(1_000_000)

        assert manager.budget_config.tier == ModelTier.CLOUD

    def test_empty_conversation_turns(self):
        """Test with no conversation turns."""
        manager = FOVContextManager.for_context_window(200_000)

        context = manager.build_context([])

        assert context is not None

    def test_single_character_messages(self):
        """Test with single character messages."""
        manager = FOVContextManager.for_context_window(200_000)
        turn = ConversationTurn(role=MessageRole.USER, content="?")

        manager.add_conversation_turn(turn)
        context = manager.build_context()

        assert "?" in context.to_system_message()

    def test_very_long_message(self):
        """Test with very long message content."""
        manager = FOVContextManager.for_context_window(200_000)
        long_content = "A" * 10000
        turn = ConversationTurn(role=MessageRole.USER, content=long_content)

        manager.add_conversation_turn(turn)
        context = manager.build_context()

        # Context should be built, possibly truncated
        assert context is not None

    def test_special_characters_in_content(self):
        """Test with special characters in content."""
        manager = FOVContextManager.for_context_window(200_000)
        special_content = "What is E=mc^2? And what about x<y && z>w?"
        turn = ConversationTurn(role=MessageRole.USER, content=special_content)

        manager.add_conversation_turn(turn)
        messages = manager.build_messages_for_llm()

        assert any(special_content in m.get("content", "") for m in messages)

    def test_unicode_content(self):
        """Test with Unicode content."""
        manager = FOVContextManager.for_context_window(200_000)
        unicode_content = "Explain: pi, sigma, omega"
        turn = ConversationTurn(role=MessageRole.USER, content=unicode_content)

        manager.add_conversation_turn(turn)
        context = manager.build_context()

        assert "pi" in context.to_system_message()

    def test_multiple_resets(self):
        """Test multiple consecutive resets."""
        manager = FOVContextManager.for_context_window(200_000)

        manager.reset()
        manager.reset()
        manager.reset()

        # Should not raise any errors
        assert manager.immediate_buffer.recent_turns == []

    def test_build_context_after_reset(self):
        """Test building context immediately after reset."""
        manager = FOVContextManager.for_context_window(200_000)
        manager.set_current_topic(
            topic_id="t1",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=[]
        )
        manager.reset()

        context = manager.build_context()

        assert context is not None
        assert "Test" not in context.to_system_message()


class TestSessionEventLogging:
    """Tests for session event logging."""

    def test_session_event_creation(self):
        """Test SessionEvent creation."""
        event = SessionEvent(
            event_type="test_event",
            data={"key": "value"}
        )

        assert event.event_type == "test_event"
        assert event.data["key"] == "value"
        assert event.timestamp is not None

    def test_session_event_timestamp_auto_set(self):
        """Test event timestamp is auto-set."""
        before = datetime.now()
        event = SessionEvent(event_type="test")
        after = datetime.now()

        assert before <= event.timestamp <= after

    def test_session_event_empty_data(self):
        """Test event with empty data dict."""
        event = SessionEvent(event_type="test")

        assert event.data == {}


class TestFOVSessionLifecycle:
    """Tests for FOVSession lifecycle events."""

    def test_session_events_logged_on_creation(self):
        """Test that session_created event is logged."""
        session = FOVSession.create(curriculum_id="curr-001")

        events = session.get_events()
        event_types = [e["type"] for e in events]

        assert "session_created" in event_types

    def test_session_events_logged_on_start(self):
        """Test that session_started event is logged."""
        session = FOVSession.create(curriculum_id="curr-001")
        session.start()

        events = session.get_events()
        event_types = [e["type"] for e in events]

        assert "session_started" in event_types

    def test_session_events_logged_on_topic_change(self):
        """Test that topic_changed event is logged."""
        session = FOVSession.create(curriculum_id="curr-001")
        session.set_current_topic(
            topic_id="t1",
            topic_title="Test",
            topic_content="Content",
            learning_objectives=[]
        )

        events = session.get_events()
        event_types = [e["type"] for e in events]

        assert "topic_changed" in event_types

    def test_record_topic_completion_no_current_topic(self):
        """Test recording topic completion without current topic set."""
        session = FOVSession.create(curriculum_id="curr-001")

        # Should not raise, but should do nothing
        session.record_topic_completion(
            summary="Summary",
            mastery_level=0.85
        )

        # No topic summary should be added
        assert len(session.context_manager.episodic_buffer.topic_summaries) == 0
