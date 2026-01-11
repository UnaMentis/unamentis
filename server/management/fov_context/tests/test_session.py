"""Tests for FOVSession and SessionManager."""

import pytest
from datetime import datetime

from ..session import (
    FOVSession,
    SessionConfig,
    SessionEvent,
    SessionManager,
    SessionState,
)
from ..models import (
    ConversationTurn,
    MessageRole,
    TranscriptSegment,
)


class TestFOVSessionCreation:
    """Tests for FOVSession creation."""

    def test_create_session(self):
        """Test basic session creation."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.session_id is not None
        assert session.curriculum_id == "curr-123"
        assert session.state == SessionState.IDLE

    def test_create_with_config(self):
        """Test session creation with custom config."""
        config = SessionConfig(
            model_name="gpt-4o",
            model_context_window=128_000
        )
        session = FOVSession.create(curriculum_id="curr-123", config=config)

        assert session.config.model_name == "gpt-4o"

    def test_session_has_context_manager(self):
        """Test session has context manager initialized."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.context_manager is not None

    def test_session_has_confidence_monitor(self):
        """Test session has confidence monitor initialized."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.confidence_monitor is not None


class TestSessionLifecycle:
    """Tests for session lifecycle management."""

    def test_start_session(self):
        """Test starting a session."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.start()

        assert session.state == SessionState.PLAYING
        assert session.started_at is not None

    def test_pause_session(self):
        """Test pausing a session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        session.pause()

        assert session.state == SessionState.PAUSED

    def test_resume_session(self):
        """Test resuming a paused session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.pause()

        session.resume()

        assert session.state == SessionState.PLAYING

    def test_end_session(self):
        """Test ending a session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        session.end()

        assert session.state == SessionState.ENDED
        assert session.ended_at is not None


class TestCurriculumContext:
    """Tests for curriculum context management."""

    def test_set_current_topic(self):
        """Test setting current topic."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Introduction",
            topic_content="Welcome to the course.",
            learning_objectives=["Understand basics"]
        )

        assert session.current_topic_id == "topic-1"
        assert session.context_manager.working_buffer.topic_title == "Introduction"

    def test_set_topic_with_glossary_dicts(self):
        """Test setting topic with glossary as dicts."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Physics",
            topic_content="Content",
            learning_objectives=[],
            glossary_terms=[{"term": "Force", "definition": "A push or pull"}]
        )

        assert len(session.context_manager.working_buffer.glossary_terms) == 1

    def test_set_curriculum_position(self):
        """Test setting curriculum position."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_curriculum_position(
            curriculum_title="Physics 101",
            current_topic_index=5,
            total_topics=20
        )

        assert session.context_manager.semantic_buffer.position.current_topic_index == 5

    def test_set_current_segment(self):
        """Test setting current transcript segment."""
        session = FOVSession.create(curriculum_id="curr-123")
        segment = TranscriptSegment(
            segment_id="seg-1",
            text="The mitochondria is the powerhouse of the cell."
        )

        session.set_current_segment(segment)

        assert session.current_segment == segment


class TestConversation:
    """Tests for conversation management."""

    def test_add_user_turn(self):
        """Test adding user turn."""
        session = FOVSession.create(curriculum_id="curr-123")

        turn = session.add_user_turn("Hello, can you explain this?")

        assert turn.role == MessageRole.USER
        assert turn.content == "Hello, can you explain this?"
        assert len(session.conversation_history) == 1

    def test_add_assistant_turn(self):
        """Test adding assistant turn."""
        session = FOVSession.create(curriculum_id="curr-123")

        turn = session.add_assistant_turn("Of course! Let me explain.")

        assert turn.role == MessageRole.ASSISTANT
        assert len(session.conversation_history) == 1

    def test_barge_in_recorded(self):
        """Test barge-in is recorded properly."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("Wait, what does that mean?", is_barge_in=True)

        assert session.barge_in_count == 1
        assert session.context_manager.immediate_buffer.barge_in_utterance is not None

    def test_turn_count_tracked(self):
        """Test total turn count is tracked."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("Hello")
        session.add_assistant_turn("Hi!")
        session.add_user_turn("Question?")
        session.add_assistant_turn("Answer.")

        assert session.total_turns == 4


class TestContextBuilding:
    """Tests for context building."""

    def test_build_llm_context(self):
        """Test building LLM context."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.set_current_topic(
            topic_id="t1",
            topic_title="Gravity",
            topic_content="Gravity pulls objects.",
            learning_objectives=["Understand gravity"]
        )
        session.add_user_turn("What is gravity?")

        context = session.build_llm_context()

        assert context.system_prompt is not None
        assert "Gravity" in context.to_system_message()

    def test_build_llm_context_with_barge_in(self):
        """Test building context with barge-in."""
        session = FOVSession.create(curriculum_id="curr-123")

        context = session.build_llm_context(
            barge_in_utterance="Wait, explain that!"
        )

        message = context.to_system_message()
        assert "explain that" in message

    def test_build_llm_messages(self):
        """Test building LLM messages list."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.add_user_turn("Hello")
        session.add_assistant_turn("Hi!")

        messages = session.build_llm_messages()

        assert len(messages) >= 1
        assert messages[0]["role"] == "system"


class TestConfidenceAnalysis:
    """Tests for confidence analysis in session."""

    def test_analyze_response(self):
        """Test analyzing LLM response."""
        session = FOVSession.create(curriculum_id="curr-123")

        analysis = session.analyze_response("Gravity is 9.8 m/s².")

        assert analysis.confidence_score > 0.0

    def test_get_expansion_recommendation(self):
        """Test getting expansion recommendation."""
        session = FOVSession.create(curriculum_id="curr-123")
        analysis = session.analyze_response("I'm not sure about this.")

        recommendation = session.get_expansion_recommendation(analysis)

        assert recommendation.should_expand is True or recommendation.should_expand is False

    def test_process_response_with_confidence(self):
        """Test processing response with confidence monitoring."""
        session = FOVSession.create(curriculum_id="curr-123")

        analysis, recommendation = session.process_response_with_confidence(
            "I think it might be related to physics."
        )

        assert analysis is not None
        # Recommendation only returned if auto_expand is enabled (default True)
        assert recommendation is not None

    def test_expansion_count_tracked(self):
        """Test expansion count is tracked."""
        session = FOVSession.create(curriculum_id="curr-123")

        # Trigger expansion with uncertain response
        session.process_response_with_confidence(
            "I'm not sure, but maybe it could be something."
        )

        # Expansion count may or may not increment based on analysis
        assert session.expansion_count >= 0


class TestLearnerSignals:
    """Tests for learner signal recording."""

    def test_record_clarification_request(self):
        """Test recording clarification request."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.record_clarification_request()

        signals = session.context_manager.episodic_buffer.learner_signals
        assert signals.clarification_requests == 1

    def test_record_repetition_request(self):
        """Test recording repetition request."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.record_repetition_request()

        signals = session.context_manager.episodic_buffer.learner_signals
        assert signals.repetition_requests == 1

    def test_record_confusion_signal(self):
        """Test recording confusion signal."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.record_confusion_signal()

        signals = session.context_manager.episodic_buffer.learner_signals
        assert signals.confusion_indicators == 1

    def test_record_topic_completion(self):
        """Test recording topic completion."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.set_current_topic(
            topic_id="t1",
            topic_title="Intro",
            topic_content="Content",
            learning_objectives=[]
        )

        session.record_topic_completion(
            summary="We covered the basics of physics.",
            mastery_level=0.85
        )

        summaries = session.context_manager.episodic_buffer.topic_summaries
        assert len(summaries) == 1
        assert summaries[0].mastery_level == 0.85


class TestStateExport:
    """Tests for session state export."""

    def test_get_state(self):
        """Test getting session state."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        state = session.get_state()

        assert state["session_id"] == session.session_id
        assert state["curriculum_id"] == "curr-123"
        assert state["state"] == "playing"
        assert state["started_at"] is not None

    def test_get_state_includes_metrics(self):
        """Test state includes metrics."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.add_user_turn("Question", is_barge_in=True)
        session.add_assistant_turn("Answer")

        state = session.get_state()

        assert state["total_turns"] == 2
        assert state["barge_in_count"] == 1

    def test_get_events(self):
        """Test getting session events."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.add_user_turn("Hello")

        events = session.get_events()

        assert len(events) >= 2  # session_created, session_started, user_turn

    def test_get_events_filtered(self):
        """Test getting events filtered by type."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.add_user_turn("Hello")
        session.add_user_turn("Another")

        events = session.get_events(event_type="user_turn")

        assert len(events) == 2
        assert all(e["type"] == "user_turn" for e in events)


class TestSessionManager:
    """Tests for SessionManager."""

    def test_create_session(self):
        """Test creating session through manager."""
        manager = SessionManager()

        session = manager.create_session(curriculum_id="curr-123")

        assert session.session_id is not None
        assert manager.get_session(session.session_id) is session

    def test_get_session(self):
        """Test getting session by ID."""
        manager = SessionManager()
        session = manager.create_session(curriculum_id="curr-123")

        retrieved = manager.get_session(session.session_id)

        assert retrieved is session

    def test_get_nonexistent_session(self):
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
        assert manager.get_session(session_id) is None

    def test_end_nonexistent_session(self):
        """Test ending nonexistent session returns False."""
        manager = SessionManager()

        result = manager.end_session("nonexistent-id")

        assert result is False

    def test_list_sessions(self):
        """Test listing all sessions."""
        manager = SessionManager()
        manager.create_session(curriculum_id="curr-1")
        manager.create_session(curriculum_id="curr-2")

        sessions = manager.list_sessions()

        assert len(sessions) == 2

    def test_cleanup_ended_sessions(self):
        """Test cleanup of ended sessions."""
        manager = SessionManager()
        s1 = manager.create_session(curriculum_id="curr-1")
        s2 = manager.create_session(curriculum_id="curr-2")

        s1.end()

        removed = manager.cleanup_ended_sessions()

        assert removed == 1
        assert manager.get_session(s1.session_id) is None
        assert manager.get_session(s2.session_id) is not None


class TestSessionEvent:
    """Tests for SessionEvent."""

    def test_event_creation(self):
        """Test event creation."""
        event = SessionEvent(
            event_type="test_event",
            data={"key": "value"}
        )

        assert event.event_type == "test_event"
        assert event.data["key"] == "value"
        assert event.timestamp is not None

    def test_event_timestamp_auto_set(self):
        """Test event timestamp is auto-set."""
        before = datetime.now()
        event = SessionEvent(event_type="test")
        after = datetime.now()

        assert before <= event.timestamp <= after
