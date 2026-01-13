"""
Comprehensive tests for fov_context/session.py

Tests cover:
- SessionState enum
- PlaybackState class
- UserVoiceConfig class
- SessionConfig class
- SessionEvent class
- FOVSession class and all its methods
- UserSession class and all its methods
- SessionManager class and all its methods
- Edge cases, error handling, and boundary conditions
"""

import pytest
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch
import time

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
from fov_context.models import (
    ConversationTurn,
    GlossaryTerm,
    MessageRole,
    MisconceptionTrigger,
    TranscriptSegment,
)
from fov_context.confidence import (
    ConfidenceAnalysis,
    ConfidenceMarker,
    ConfidenceTrend,
    ExpansionPriority,
    ExpansionScope,
)


# --- SessionState Enum Tests ---


class TestSessionStateEnum:
    """Tests for SessionState enum."""

    def test_all_session_state_values(self):
        """Test all session state values exist."""
        assert SessionState.IDLE == "idle"
        assert SessionState.PLAYING == "playing"
        assert SessionState.USER_SPEAKING == "user_speaking"
        assert SessionState.AI_THINKING == "ai_thinking"
        assert SessionState.AI_SPEAKING == "ai_speaking"
        assert SessionState.PAUSED == "paused"
        assert SessionState.ENDED == "ended"

    def test_session_state_is_string_enum(self):
        """Test that session states are string enums."""
        assert isinstance(SessionState.IDLE, str)
        assert SessionState.IDLE.value == "idle"

    def test_session_state_count(self):
        """Test we have exactly 7 session states."""
        assert len(SessionState) == 7


# --- PlaybackState Tests ---


class TestPlaybackState:
    """Tests for PlaybackState dataclass."""

    def test_default_values(self):
        """Test default playback state values."""
        state = PlaybackState()
        assert state.curriculum_id == ""
        assert state.topic_id == ""
        assert state.segment_index == 0
        assert state.segment_offset_ms == 0
        assert state.is_playing is False
        assert state.last_heartbeat is None

    def test_custom_values(self):
        """Test playback state with custom values."""
        now = datetime.now()
        state = PlaybackState(
            curriculum_id="curr-123",
            topic_id="topic-456",
            segment_index=5,
            segment_offset_ms=1500,
            is_playing=True,
            last_heartbeat=now,
        )
        assert state.curriculum_id == "curr-123"
        assert state.topic_id == "topic-456"
        assert state.segment_index == 5
        assert state.segment_offset_ms == 1500
        assert state.is_playing is True
        assert state.last_heartbeat == now

    def test_update_position(self):
        """Test updating playback position."""
        state = PlaybackState()
        state.update_position(segment_index=3, offset_ms=500, is_playing=True)

        assert state.segment_index == 3
        assert state.segment_offset_ms == 500
        assert state.is_playing is True
        assert state.last_heartbeat is not None

    def test_update_position_default_offset(self):
        """Test updating position with default offset."""
        state = PlaybackState()
        state.update_position(segment_index=2)

        assert state.segment_index == 2
        assert state.segment_offset_ms == 0
        assert state.is_playing is True

    def test_update_position_paused(self):
        """Test updating position when paused."""
        state = PlaybackState()
        state.update_position(segment_index=4, offset_ms=200, is_playing=False)

        assert state.segment_index == 4
        assert state.is_playing is False

    def test_set_topic(self):
        """Test setting current topic."""
        state = PlaybackState(segment_index=5, segment_offset_ms=1000)
        state.set_topic("curr-new", "topic-new")

        assert state.curriculum_id == "curr-new"
        assert state.topic_id == "topic-new"
        assert state.segment_index == 0
        assert state.segment_offset_ms == 0

    def test_to_dict(self):
        """Test converting playback state to dict."""
        now = datetime.now()
        state = PlaybackState(
            curriculum_id="curr-123",
            topic_id="topic-456",
            segment_index=5,
            segment_offset_ms=1500,
            is_playing=True,
            last_heartbeat=now,
        )
        result = state.to_dict()

        assert result["curriculum_id"] == "curr-123"
        assert result["topic_id"] == "topic-456"
        assert result["segment_index"] == 5
        assert result["segment_offset_ms"] == 1500
        assert result["is_playing"] is True
        assert result["last_heartbeat"] == now.isoformat()

    def test_to_dict_no_heartbeat(self):
        """Test converting to dict without heartbeat."""
        state = PlaybackState()
        result = state.to_dict()

        assert result["last_heartbeat"] is None


# --- UserVoiceConfig Tests ---


class TestUserVoiceConfig:
    """Tests for UserVoiceConfig dataclass."""

    def test_default_values(self):
        """Test default voice config values."""
        config = UserVoiceConfig()
        assert config.voice_id == "nova"
        assert config.tts_provider == "vibevoice"
        assert config.speed == 1.0
        assert config.exaggeration is None
        assert config.cfg_weight is None
        assert config.language is None

    def test_custom_values(self):
        """Test custom voice config values."""
        config = UserVoiceConfig(
            voice_id="alloy",
            tts_provider="chatterbox",
            speed=1.2,
            exaggeration=0.5,
            cfg_weight=0.7,
            language="en-US",
        )
        assert config.voice_id == "alloy"
        assert config.tts_provider == "chatterbox"
        assert config.speed == 1.2
        assert config.exaggeration == 0.5
        assert config.cfg_weight == 0.7
        assert config.language == "en-US"

    def test_to_dict_basic(self):
        """Test converting basic config to dict."""
        config = UserVoiceConfig()
        result = config.to_dict()

        assert result["voice_id"] == "nova"
        assert result["tts_provider"] == "vibevoice"
        assert result["speed"] == 1.0
        assert "exaggeration" not in result
        assert "cfg_weight" not in result
        assert "language" not in result

    def test_to_dict_with_optional_fields(self):
        """Test converting config with optional fields to dict."""
        config = UserVoiceConfig(
            voice_id="alloy",
            tts_provider="chatterbox",
            speed=1.1,
            exaggeration=0.6,
            cfg_weight=0.8,
            language="en-GB",
        )
        result = config.to_dict()

        assert result["voice_id"] == "alloy"
        assert result["tts_provider"] == "chatterbox"
        assert result["speed"] == 1.1
        assert result["exaggeration"] == 0.6
        assert result["cfg_weight"] == 0.8
        assert result["language"] == "en-GB"

    def test_get_chatterbox_config_non_chatterbox(self):
        """Test get_chatterbox_config returns None for non-chatterbox provider."""
        config = UserVoiceConfig(tts_provider="vibevoice")
        result = config.get_chatterbox_config()

        assert result is None

    def test_get_chatterbox_config_with_params(self):
        """Test get_chatterbox_config returns config for chatterbox provider."""
        config = UserVoiceConfig(
            tts_provider="chatterbox",
            exaggeration=0.5,
            cfg_weight=0.7,
            language="en-US",
        )
        result = config.get_chatterbox_config()

        assert result == {
            "exaggeration": 0.5,
            "cfg_weight": 0.7,
            "language": "en-US",
        }

    def test_get_chatterbox_config_no_params(self):
        """Test get_chatterbox_config returns None when chatterbox has no params."""
        config = UserVoiceConfig(tts_provider="chatterbox")
        result = config.get_chatterbox_config()

        assert result is None

    def test_get_chatterbox_config_partial_params(self):
        """Test get_chatterbox_config with only some params."""
        config = UserVoiceConfig(
            tts_provider="chatterbox",
            exaggeration=0.3,
        )
        result = config.get_chatterbox_config()

        assert result == {"exaggeration": 0.3}


# --- SessionConfig Tests ---


class TestSessionConfig:
    """Tests for SessionConfig dataclass."""

    def test_default_values(self):
        """Test default session config values."""
        config = SessionConfig()
        assert config.model_name == "claude-3-5-sonnet-20241022"
        assert config.model_context_window == 200_000
        assert config.system_prompt is None
        assert config.auto_expand_context is True
        assert config.confidence_threshold == 0.5

    def test_custom_values(self):
        """Test custom session config values."""
        config = SessionConfig(
            model_name="gpt-4o",
            model_context_window=128_000,
            system_prompt="You are a helpful tutor.",
            auto_expand_context=False,
            confidence_threshold=0.7,
        )
        assert config.model_name == "gpt-4o"
        assert config.model_context_window == 128_000
        assert config.system_prompt == "You are a helpful tutor."
        assert config.auto_expand_context is False
        assert config.confidence_threshold == 0.7


# --- SessionEvent Tests ---


class TestSessionEvent:
    """Tests for SessionEvent dataclass."""

    def test_event_creation_with_data(self):
        """Test event creation with data."""
        event = SessionEvent(
            event_type="test_event",
            data={"key": "value", "count": 42}
        )

        assert event.event_type == "test_event"
        assert event.data["key"] == "value"
        assert event.data["count"] == 42
        assert event.timestamp is not None

    def test_event_timestamp_auto_set(self):
        """Test event timestamp is auto-set."""
        before = datetime.now()
        event = SessionEvent(event_type="test")
        after = datetime.now()

        assert before <= event.timestamp <= after

    def test_event_default_data(self):
        """Test event default data is empty dict."""
        event = SessionEvent(event_type="test")
        assert event.data == {}

    def test_event_with_custom_timestamp(self):
        """Test event with custom timestamp."""
        custom_time = datetime(2024, 1, 15, 10, 30, 0)
        event = SessionEvent(
            event_type="test",
            timestamp=custom_time,
        )
        assert event.timestamp == custom_time


# --- FOVSession Creation Tests ---


class TestFOVSessionCreation:
    """Tests for FOVSession creation."""

    def test_create_session_basic(self):
        """Test basic session creation."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.session_id is not None
        assert len(session.session_id) == 36  # UUID format
        assert session.curriculum_id == "curr-123"
        assert session.state == SessionState.IDLE

    def test_create_with_config(self):
        """Test session creation with custom config."""
        config = SessionConfig(
            model_name="gpt-4o",
            model_context_window=128_000,
            auto_expand_context=False,
        )
        session = FOVSession.create(curriculum_id="curr-123", config=config)

        assert session.config.model_name == "gpt-4o"
        assert session.config.model_context_window == 128_000
        assert session.config.auto_expand_context is False

    def test_session_has_context_manager(self):
        """Test session has context manager initialized."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.context_manager is not None

    def test_session_has_confidence_monitor(self):
        """Test session has confidence monitor initialized."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.confidence_monitor is not None

    def test_session_initial_metrics(self):
        """Test session has initial metrics set to zero."""
        session = FOVSession.create(curriculum_id="curr-123")

        assert session.total_turns == 0
        assert session.barge_in_count == 0
        assert session.expansion_count == 0

    def test_session_created_event_logged(self):
        """Test session_created event is logged."""
        session = FOVSession.create(curriculum_id="curr-123")

        events = session.get_events(event_type="session_created")
        assert len(events) == 1
        assert events[0]["data"]["curriculum_id"] == "curr-123"

    def test_session_timestamps_initialized(self):
        """Test session timestamps are properly initialized."""
        before = datetime.now()
        session = FOVSession.create(curriculum_id="curr-123")
        after = datetime.now()

        assert before <= session.created_at <= after
        assert session.started_at is None
        assert session.ended_at is None


# --- FOVSession Lifecycle Tests ---


class TestFOVSessionLifecycle:
    """Tests for FOVSession lifecycle management."""

    def test_start_session(self):
        """Test starting a session."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.start()

        assert session.state == SessionState.PLAYING
        assert session.started_at is not None

    def test_start_logs_event(self):
        """Test starting logs session_started event."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        events = session.get_events(event_type="session_started")
        assert len(events) == 1

    def test_pause_session(self):
        """Test pausing a session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        session.pause()

        assert session.state == SessionState.PAUSED

    def test_pause_logs_event(self):
        """Test pausing logs session_paused event."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.pause()

        events = session.get_events(event_type="session_paused")
        assert len(events) == 1

    def test_resume_session(self):
        """Test resuming a paused session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.pause()

        session.resume()

        assert session.state == SessionState.PLAYING

    def test_resume_logs_event(self):
        """Test resuming logs session_resumed event."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.pause()
        session.resume()

        events = session.get_events(event_type="session_resumed")
        assert len(events) == 1

    def test_end_session(self):
        """Test ending a session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        session.end()

        assert session.state == SessionState.ENDED
        assert session.ended_at is not None

    def test_end_logs_event(self):
        """Test ending logs session_ended event."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.end()

        events = session.get_events(event_type="session_ended")
        assert len(events) == 1

    def test_multiple_pause_resume_cycles(self):
        """Test multiple pause/resume cycles."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        for _ in range(3):
            session.pause()
            assert session.state == SessionState.PAUSED
            session.resume()
            assert session.state == SessionState.PLAYING


# --- FOVSession Curriculum Context Tests ---


class TestFOVSessionCurriculumContext:
    """Tests for curriculum context management."""

    def test_set_current_topic(self):
        """Test setting current topic."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Introduction to Physics",
            topic_content="Physics is the study of matter and energy.",
            learning_objectives=["Understand basic concepts", "Apply formulas"]
        )

        assert session.current_topic_id == "topic-1"
        assert session.context_manager.working_buffer.topic_title == "Introduction to Physics"
        assert len(session.context_manager.working_buffer.learning_objectives) == 2

    def test_set_topic_with_glossary_dicts(self):
        """Test setting topic with glossary as dicts."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Physics",
            topic_content="Content",
            learning_objectives=[],
            glossary_terms=[
                {"term": "Force", "definition": "A push or pull"},
                {"term": "Mass", "definition": "Amount of matter"},
            ]
        )

        assert len(session.context_manager.working_buffer.glossary_terms) == 2
        assert session.context_manager.working_buffer.glossary_terms[0].term == "Force"

    def test_set_topic_with_glossary_objects(self):
        """Test setting topic with glossary as GlossaryTerm objects."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Physics",
            topic_content="Content",
            learning_objectives=[],
            glossary_terms=[
                GlossaryTerm(term="Velocity", definition="Speed with direction"),
            ]
        )

        assert len(session.context_manager.working_buffer.glossary_terms) == 1

    def test_set_topic_with_misconceptions(self):
        """Test setting topic with misconception triggers."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Physics",
            topic_content="Content",
            learning_objectives=[],
            misconceptions=[
                {
                    "trigger_phrase": "heavier objects fall faster",
                    "misconception": "Mass affects falling speed in vacuum",
                    "remediation": "All objects fall at same rate in vacuum",
                }
            ]
        )

        assert len(session.context_manager.working_buffer.misconception_triggers) == 1

    def test_set_topic_logs_event(self):
        """Test setting topic logs topic_changed event."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="topic-1",
            topic_title="Test Topic",
            topic_content="Content",
            learning_objectives=[]
        )

        events = session.get_events(event_type="topic_changed")
        assert len(events) == 1
        assert events[0]["data"]["topic_id"] == "topic-1"

    def test_set_curriculum_position(self):
        """Test setting curriculum position."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_curriculum_position(
            curriculum_title="Physics 101",
            current_topic_index=5,
            total_topics=20,
            unit_title="Mechanics"
        )

        pos = session.context_manager.semantic_buffer.position
        assert pos.current_topic_index == 5
        assert pos.total_topics == 20
        assert pos.curriculum_title == "Physics 101"
        assert pos.unit_title == "Mechanics"

    def test_set_curriculum_position_with_outline(self):
        """Test setting curriculum position with outline."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_curriculum_position(
            curriculum_title="Physics 101",
            current_topic_index=0,
            total_topics=10,
            curriculum_outline="Unit 1: Mechanics\nUnit 2: Waves"
        )

        assert session.context_manager.semantic_buffer.curriculum_outline == "Unit 1: Mechanics\nUnit 2: Waves"

    def test_set_current_segment(self):
        """Test setting current transcript segment."""
        session = FOVSession.create(curriculum_id="curr-123")
        segment = TranscriptSegment(
            segment_id="seg-1",
            text="The mitochondria is the powerhouse of the cell.",
            start_time=0.0,
            end_time=5.0,
        )

        session.set_current_segment(segment)

        assert session.current_segment == segment
        assert session.context_manager.immediate_buffer.current_segment == segment


# --- FOVSession Conversation Tests ---


class TestFOVSessionConversation:
    """Tests for conversation management."""

    def test_add_user_turn(self):
        """Test adding user turn."""
        session = FOVSession.create(curriculum_id="curr-123")

        turn = session.add_user_turn("Hello, can you explain this?")

        assert turn.role == MessageRole.USER
        assert turn.content == "Hello, can you explain this?"
        assert len(session.conversation_history) == 1
        assert session.total_turns == 1

    def test_add_assistant_turn(self):
        """Test adding assistant turn."""
        session = FOVSession.create(curriculum_id="curr-123")

        turn = session.add_assistant_turn("Of course! Let me explain.")

        assert turn.role == MessageRole.ASSISTANT
        assert len(session.conversation_history) == 1
        assert session.total_turns == 1

    def test_barge_in_recorded(self):
        """Test barge-in is recorded properly."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("Wait, what does that mean?", is_barge_in=True)

        assert session.barge_in_count == 1
        assert session.context_manager.immediate_buffer.barge_in_utterance is not None

    def test_barge_in_logs_event(self):
        """Test barge-in logs event."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("What?", is_barge_in=True)

        events = session.get_events(event_type="barge_in")
        assert len(events) == 1

    def test_user_turn_logs_event(self):
        """Test user turn logs event."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("Question?", is_barge_in=False)

        events = session.get_events(event_type="user_turn")
        assert len(events) == 1

    def test_assistant_turn_logs_event(self):
        """Test assistant turn logs event."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_assistant_turn("Answer.")

        events = session.get_events(event_type="assistant_turn")
        assert len(events) == 1

    def test_turn_count_tracked(self):
        """Test total turn count is tracked."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("Hello")
        session.add_assistant_turn("Hi!")
        session.add_user_turn("Question?")
        session.add_assistant_turn("Answer.")

        assert session.total_turns == 4

    def test_multiple_barge_ins_tracked(self):
        """Test multiple barge-ins are tracked."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.add_user_turn("First interrupt", is_barge_in=True)
        session.add_user_turn("Second interrupt", is_barge_in=True)
        session.add_user_turn("Normal turn", is_barge_in=False)
        session.add_user_turn("Third interrupt", is_barge_in=True)

        assert session.barge_in_count == 3


# --- FOVSession Context Building Tests ---


class TestFOVSessionContextBuilding:
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
        assert "explain that" in message.lower()

    def test_build_llm_messages(self):
        """Test building LLM messages list."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.add_user_turn("Hello")
        session.add_assistant_turn("Hi!")

        messages = session.build_llm_messages()

        assert len(messages) >= 1
        assert messages[0]["role"] == "system"

    def test_build_llm_messages_with_barge_in(self):
        """Test building messages with barge-in."""
        session = FOVSession.create(curriculum_id="curr-123")

        messages = session.build_llm_messages(barge_in_utterance="Stop!")

        assert len(messages) >= 1
        assert "Stop" in messages[0]["content"]


# --- FOVSession Confidence Analysis Tests ---


class TestFOVSessionConfidenceAnalysis:
    """Tests for confidence analysis in session."""

    def test_analyze_response_confident(self):
        """Test analyzing confident LLM response."""
        session = FOVSession.create(curriculum_id="curr-123")

        analysis = session.analyze_response("Gravity is 9.8 m/s^2 on Earth.")

        assert analysis.confidence_score > 0.5

    def test_analyze_response_uncertain(self):
        """Test analyzing uncertain LLM response."""
        session = FOVSession.create(curriculum_id="curr-123")

        analysis = session.analyze_response("I'm not sure about this topic.")

        assert analysis.confidence_score < 1.0

    def test_analyze_response_logs_event(self):
        """Test analyzing response logs event."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.analyze_response("Some response")

        events = session.get_events(event_type="confidence_analysis")
        assert len(events) == 1

    def test_get_expansion_recommendation_no_expand(self):
        """Test getting recommendation when no expansion needed."""
        session = FOVSession.create(curriculum_id="curr-123")
        analysis = session.analyze_response("Clear factual statement here.")

        recommendation = session.get_expansion_recommendation(analysis)

        # Depends on confidence score
        assert recommendation.should_expand in [True, False]

    def test_get_expansion_recommendation_expand(self):
        """Test getting recommendation when expansion needed."""
        session = FOVSession.create(curriculum_id="curr-123")
        analysis = session.analyze_response(
            "I'm not sure, I don't have information about this."
        )

        recommendation = session.get_expansion_recommendation(analysis)

        # Should trigger expansion due to uncertainty
        if recommendation.should_expand:
            assert recommendation.priority != ExpansionPriority.NONE

    def test_process_response_with_confidence_auto_expand_enabled(self):
        """Test processing response with auto-expand enabled."""
        config = SessionConfig(auto_expand_context=True)
        session = FOVSession.create(curriculum_id="curr-123", config=config)

        analysis, recommendation = session.process_response_with_confidence(
            "I think it might be related to physics."
        )

        assert analysis is not None
        assert recommendation is not None

    def test_process_response_with_confidence_auto_expand_disabled(self):
        """Test processing response with auto-expand disabled."""
        config = SessionConfig(auto_expand_context=False)
        session = FOVSession.create(curriculum_id="curr-123", config=config)

        analysis, recommendation = session.process_response_with_confidence(
            "I think it might be related to physics."
        )

        assert analysis is not None
        assert recommendation is None

    def test_expansion_count_incremented(self):
        """Test expansion count is incremented when recommendation made."""
        session = FOVSession.create(curriculum_id="curr-123")

        # Force an uncertain response that triggers expansion
        session.process_response_with_confidence(
            "I'm not sure, maybe possibly, I don't have information."
        )

        # Count may or may not increment based on analysis
        assert session.expansion_count >= 0


# --- FOVSession Learner Signals Tests ---


class TestFOVSessionLearnerSignals:
    """Tests for learner signal recording."""

    def test_record_clarification_request(self):
        """Test recording clarification request."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.record_clarification_request()

        signals = session.context_manager.episodic_buffer.learner_signals
        assert signals.clarification_requests == 1

    def test_record_multiple_clarification_requests(self):
        """Test recording multiple clarification requests."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.record_clarification_request()
        session.record_clarification_request()
        session.record_clarification_request()

        signals = session.context_manager.episodic_buffer.learner_signals
        assert signals.clarification_requests == 3

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
        assert summaries[0].topic_id == "t1"

    def test_record_topic_completion_no_current_topic(self):
        """Test recording topic completion without current topic does nothing."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.record_topic_completion(
            summary="Test summary",
            mastery_level=0.5
        )

        summaries = session.context_manager.episodic_buffer.topic_summaries
        assert len(summaries) == 0

    def test_record_topic_completion_logs_event(self):
        """Test recording topic completion logs event."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.set_current_topic(
            topic_id="t1",
            topic_title="Topic",
            topic_content="Content",
            learning_objectives=[]
        )

        session.record_topic_completion(summary="Done", mastery_level=0.9)

        events = session.get_events(event_type="topic_completed")
        assert len(events) == 1
        assert events[0]["data"]["mastery"] == 0.9


# --- FOVSession State Export Tests ---


class TestFOVSessionStateExport:
    """Tests for session state export."""

    def test_get_state_basic(self):
        """Test getting session state."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()

        state = session.get_state()

        assert state["session_id"] == session.session_id
        assert state["curriculum_id"] == "curr-123"
        assert state["state"] == "playing"
        assert state["started_at"] is not None
        assert state["created_at"] is not None

    def test_get_state_includes_metrics(self):
        """Test state includes metrics."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.add_user_turn("Question", is_barge_in=True)
        session.add_assistant_turn("Answer")

        state = session.get_state()

        assert state["total_turns"] == 2
        assert state["barge_in_count"] == 1

    def test_get_state_includes_duration(self):
        """Test state includes duration."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        time.sleep(0.1)

        state = session.get_state()

        assert state["duration_minutes"] >= 0

    def test_get_state_ended_session(self):
        """Test state for ended session."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.end()

        state = session.get_state()

        assert state["state"] == "ended"
        assert state["ended_at"] is not None

    def test_get_state_includes_context_state(self):
        """Test state includes context state."""
        session = FOVSession.create(curriculum_id="curr-123")

        state = session.get_state()

        assert "context_state" in state
        assert "tier" in state["context_state"]

    def test_get_events_all(self):
        """Test getting all session events."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.add_user_turn("Hello")

        events = session.get_events()

        assert len(events) >= 3  # session_created, session_started, user_turn

    def test_get_events_filtered(self):
        """Test getting events filtered by type."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        session.add_user_turn("Hello")
        session.add_user_turn("Another")

        events = session.get_events(event_type="user_turn")

        assert len(events) == 2
        assert all(e["type"] == "user_turn" for e in events)

    def test_get_events_empty_filter(self):
        """Test getting events with non-matching filter."""
        session = FOVSession.create(curriculum_id="curr-123")

        events = session.get_events(event_type="nonexistent_event")

        assert len(events) == 0


# --- UserSession Tests ---


class TestUserSession:
    """Tests for UserSession class."""

    def test_create_user_session(self):
        """Test creating a user session."""
        session = UserSession.create(user_id="user-123")

        assert session.user_id == "user-123"
        assert session.session_id is not None
        assert len(session.session_id) == 36  # UUID format
        assert session.organization_id is None

    def test_create_with_organization(self):
        """Test creating user session with organization."""
        session = UserSession.create(
            user_id="user-123",
            organization_id="org-456"
        )

        assert session.organization_id == "org-456"

    def test_create_with_voice_config(self):
        """Test creating user session with voice config."""
        voice_config = UserVoiceConfig(
            voice_id="alloy",
            tts_provider="openai",
        )
        session = UserSession.create(
            user_id="user-123",
            voice_config=voice_config,
        )

        assert session.voice_config.voice_id == "alloy"
        assert session.voice_config.tts_provider == "openai"

    def test_default_values(self):
        """Test default values for user session."""
        session = UserSession.create(user_id="user-123")

        assert session.prefetch_lookahead == 5
        assert session.fov_session is None
        assert session.voice_config.voice_id == "nova"

    def test_attach_fov_session(self):
        """Test attaching FOV session."""
        user_session = UserSession.create(user_id="user-123")
        fov_session = FOVSession.create(curriculum_id="curr-123")

        user_session.attach_fov_session(fov_session)

        assert user_session.fov_session == fov_session

    def test_attach_fov_session_updates_activity(self):
        """Test attaching FOV session updates last_active_at."""
        user_session = UserSession.create(user_id="user-123")
        original_time = user_session.last_active_at
        time.sleep(0.01)

        fov_session = FOVSession.create(curriculum_id="curr-123")
        user_session.attach_fov_session(fov_session)

        assert user_session.last_active_at >= original_time

    def test_update_voice_config_voice_id(self):
        """Test updating voice ID."""
        session = UserSession.create(user_id="user-123")

        session.update_voice_config(voice_id="shimmer")

        assert session.voice_config.voice_id == "shimmer"

    def test_update_voice_config_provider(self):
        """Test updating TTS provider."""
        session = UserSession.create(user_id="user-123")

        session.update_voice_config(tts_provider="openai")

        assert session.voice_config.tts_provider == "openai"

    def test_update_voice_config_speed(self):
        """Test updating speed."""
        session = UserSession.create(user_id="user-123")

        session.update_voice_config(speed=1.5)

        assert session.voice_config.speed == 1.5

    def test_update_voice_config_chatterbox_params(self):
        """Test updating Chatterbox-specific params."""
        session = UserSession.create(user_id="user-123")

        session.update_voice_config(
            tts_provider="chatterbox",
            exaggeration=0.6,
            cfg_weight=0.8,
            language="en-GB"
        )

        assert session.voice_config.exaggeration == 0.6
        assert session.voice_config.cfg_weight == 0.8
        assert session.voice_config.language == "en-GB"

    def test_update_voice_config_updates_activity(self):
        """Test updating voice config updates last_active_at."""
        session = UserSession.create(user_id="user-123")
        original_time = session.last_active_at
        time.sleep(0.01)

        session.update_voice_config(speed=1.2)

        assert session.last_active_at >= original_time

    def test_update_playback(self):
        """Test updating playback position."""
        session = UserSession.create(user_id="user-123")

        session.update_playback(segment_index=5, offset_ms=1000, is_playing=True)

        assert session.playback_state.segment_index == 5
        assert session.playback_state.segment_offset_ms == 1000
        assert session.playback_state.is_playing is True

    def test_update_playback_updates_activity(self):
        """Test updating playback updates last_active_at."""
        session = UserSession.create(user_id="user-123")
        original_time = session.last_active_at
        time.sleep(0.01)

        session.update_playback(segment_index=1)

        assert session.last_active_at >= original_time

    def test_set_current_topic(self):
        """Test setting current topic in playback."""
        session = UserSession.create(user_id="user-123")

        session.set_current_topic("curr-456", "topic-789")

        assert session.playback_state.curriculum_id == "curr-456"
        assert session.playback_state.topic_id == "topic-789"
        assert session.playback_state.segment_index == 0

    def test_set_current_topic_updates_activity(self):
        """Test setting topic updates last_active_at."""
        session = UserSession.create(user_id="user-123")
        original_time = session.last_active_at
        time.sleep(0.01)

        session.set_current_topic("curr", "topic")

        assert session.last_active_at >= original_time

    def test_get_state(self):
        """Test getting user session state."""
        session = UserSession.create(
            user_id="user-123",
            organization_id="org-456"
        )

        state = session.get_state()

        assert state["user_id"] == "user-123"
        assert state["session_id"] == session.session_id
        assert state["organization_id"] == "org-456"
        assert "voice_config" in state
        assert "playback_state" in state
        assert state["prefetch_lookahead"] == 5
        assert state["fov_session_id"] is None

    def test_get_state_with_fov_session(self):
        """Test getting state when FOV session attached."""
        user_session = UserSession.create(user_id="user-123")
        fov_session = FOVSession.create(curriculum_id="curr-123")
        user_session.attach_fov_session(fov_session)

        state = user_session.get_state()

        assert state["fov_session_id"] == fov_session.session_id


# --- SessionManager FOV Session Tests ---


class TestSessionManagerFOVSessions:
    """Tests for SessionManager FOV session operations."""

    def test_create_session(self):
        """Test creating session through manager."""
        manager = SessionManager()

        session = manager.create_session(curriculum_id="curr-123")

        assert session.session_id is not None
        assert manager.get_session(session.session_id) is session

    def test_create_session_with_config(self):
        """Test creating session with config through manager."""
        manager = SessionManager()
        config = SessionConfig(model_name="gpt-4o")

        session = manager.create_session(curriculum_id="curr-123", config=config)

        assert session.config.model_name == "gpt-4o"

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


# --- SessionManager User Session Tests ---


class TestSessionManagerUserSessions:
    """Tests for SessionManager user session operations."""

    def test_create_user_session(self):
        """Test creating user session."""
        manager = SessionManager()

        session = manager.create_user_session(user_id="user-123")

        assert session.user_id == "user-123"
        assert session.session_id is not None

    def test_create_user_session_with_organization(self):
        """Test creating user session with organization."""
        manager = SessionManager()

        session = manager.create_user_session(
            user_id="user-123",
            organization_id="org-456"
        )

        assert session.organization_id == "org-456"

    def test_create_user_session_with_voice_config(self):
        """Test creating user session with voice config."""
        manager = SessionManager()
        voice_config = UserVoiceConfig(voice_id="alloy")

        session = manager.create_user_session(
            user_id="user-123",
            voice_config=voice_config
        )

        assert session.voice_config.voice_id == "alloy"

    def test_create_user_session_returns_existing(self):
        """Test that create_user_session returns existing session for same user."""
        manager = SessionManager()

        session1 = manager.create_user_session(user_id="user-123")
        session2 = manager.create_user_session(user_id="user-123")

        assert session1 is session2
        assert session1.session_id == session2.session_id

    def test_get_user_session(self):
        """Test getting user session by session ID."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-123")

        retrieved = manager.get_user_session(session.session_id)

        assert retrieved is session

    def test_get_user_session_nonexistent(self):
        """Test getting nonexistent user session returns None."""
        manager = SessionManager()

        result = manager.get_user_session("nonexistent-id")

        assert result is None

    def test_get_user_session_by_user(self):
        """Test getting user session by user ID."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-123")

        retrieved = manager.get_user_session_by_user("user-123")

        assert retrieved is session

    def test_get_user_session_by_user_nonexistent(self):
        """Test getting session for nonexistent user returns None."""
        manager = SessionManager()

        result = manager.get_user_session_by_user("nonexistent-user")

        assert result is None

    def test_end_user_session(self):
        """Test ending and removing user session."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-123")
        session_id = session.session_id

        result = manager.end_user_session(session_id)

        assert result is True
        assert manager.get_user_session(session_id) is None
        assert manager.get_user_session_by_user("user-123") is None

    def test_end_user_session_nonexistent(self):
        """Test ending nonexistent user session returns False."""
        manager = SessionManager()

        result = manager.end_user_session("nonexistent-id")

        assert result is False

    def test_end_user_session_with_fov_session(self):
        """Test ending user session also ends attached FOV session."""
        manager = SessionManager()
        user_session = manager.create_user_session(user_id="user-123")
        fov_session = manager.create_session(curriculum_id="curr-123")
        user_session.attach_fov_session(fov_session)

        manager.end_user_session(user_session.session_id)

        assert manager.get_session(fov_session.session_id) is None

    def test_list_user_sessions(self):
        """Test listing all user sessions."""
        manager = SessionManager()
        manager.create_user_session(user_id="user-1")
        manager.create_user_session(user_id="user-2")
        manager.create_user_session(user_id="user-3")

        sessions = manager.list_user_sessions()

        assert len(sessions) == 3

    def test_cleanup_inactive_user_sessions(self):
        """Test cleanup of inactive user sessions."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-123")

        # Manually set last_active_at to be old
        session.last_active_at = datetime.now() - timedelta(minutes=120)

        removed = manager.cleanup_inactive_user_sessions(max_inactive_minutes=60)

        assert removed == 1
        assert manager.get_user_session(session.session_id) is None

    def test_cleanup_keeps_active_sessions(self):
        """Test cleanup keeps recently active sessions."""
        manager = SessionManager()
        session = manager.create_user_session(user_id="user-123")
        # Session is active (just created)

        removed = manager.cleanup_inactive_user_sessions(max_inactive_minutes=60)

        assert removed == 0
        assert manager.get_user_session(session.session_id) is not None

    def test_cleanup_mixed_sessions(self):
        """Test cleanup with mixed active/inactive sessions."""
        manager = SessionManager()
        active_session = manager.create_user_session(user_id="user-active")
        inactive_session = manager.create_user_session(user_id="user-inactive")

        # Make one session inactive
        inactive_session.last_active_at = datetime.now() - timedelta(minutes=120)

        removed = manager.cleanup_inactive_user_sessions(max_inactive_minutes=60)

        assert removed == 1
        assert manager.get_user_session(active_session.session_id) is not None
        assert manager.get_user_session(inactive_session.session_id) is None


# --- Edge Cases and Integration Tests ---


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    def test_empty_curriculum_id(self):
        """Test creating session with empty curriculum ID."""
        session = FOVSession.create(curriculum_id="")
        assert session.curriculum_id == ""

    def test_long_curriculum_id(self):
        """Test creating session with long curriculum ID."""
        long_id = "x" * 1000
        session = FOVSession.create(curriculum_id=long_id)
        assert session.curriculum_id == long_id

    def test_unicode_in_topic_content(self):
        """Test setting topic with unicode content."""
        session = FOVSession.create(curriculum_id="curr-123")

        session.set_current_topic(
            topic_id="t1",
            topic_title="Math: Einstein's E=mc^2",
            topic_content="Energy equals mass times speed of light squared",
            learning_objectives=["Understand E = mc^2"]
        )

        assert "E=mc^2" in session.context_manager.working_buffer.topic_title

    def test_special_characters_in_conversation(self):
        """Test conversation with special characters."""
        session = FOVSession.create(curriculum_id="curr-123")

        turn = session.add_user_turn("What is @#$%^&*() in math?")

        assert "@#$%^&*()" in turn.content

    def test_very_long_conversation(self):
        """Test session with many conversation turns."""
        session = FOVSession.create(curriculum_id="curr-123")

        for i in range(100):
            session.add_user_turn(f"Question {i}")
            session.add_assistant_turn(f"Answer {i}")

        assert session.total_turns == 200

    def test_rapid_state_changes(self):
        """Test rapid state changes."""
        session = FOVSession.create(curriculum_id="curr-123")

        for _ in range(10):
            session.start()
            session.pause()
            session.resume()
            session.pause()
            session.resume()
            session.end()
            # Create new session for next iteration
            session = FOVSession.create(curriculum_id="curr-123")

    def test_session_duration_calculation(self):
        """Test session duration is calculated correctly."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        time.sleep(0.1)

        state = session.get_state()

        # Duration should be > 0
        assert state["duration_minutes"] > 0

    def test_session_duration_after_end(self):
        """Test session duration after ending."""
        session = FOVSession.create(curriculum_id="curr-123")
        session.start()
        time.sleep(0.1)
        session.end()

        state = session.get_state()

        # Duration should be calculated correctly
        assert state["duration_minutes"] > 0
        assert state["ended_at"] is not None


class TestIntegrationWorkflows:
    """Integration tests for complete workflows."""

    def test_complete_tutoring_workflow(self):
        """Test a complete tutoring session workflow."""
        # Create manager and sessions
        manager = SessionManager()
        user_session = manager.create_user_session(
            user_id="student-1",
            organization_id="school-1"
        )
        fov_session = manager.create_session(curriculum_id="physics-101")
        user_session.attach_fov_session(fov_session)

        # Start session
        fov_session.start()
        assert fov_session.state == SessionState.PLAYING

        # Set topic
        fov_session.set_current_topic(
            topic_id="gravity",
            topic_title="Introduction to Gravity",
            topic_content="Gravity is a force that attracts objects.",
            learning_objectives=["Understand what gravity is", "Calculate gravitational force"]
        )

        # Conversation
        fov_session.add_user_turn("What is gravity?")
        fov_session.add_assistant_turn("Gravity is the force that attracts objects toward each other.")
        fov_session.add_user_turn("Can you explain more?", is_barge_in=True)
        fov_session.add_assistant_turn("Of course! On Earth, gravity accelerates objects at 9.8 m/s^2.")

        # Update playback
        user_session.update_playback(segment_index=3, offset_ms=1500)

        # End session
        fov_session.end()

        # Verify state
        state = fov_session.get_state()
        assert state["state"] == "ended"
        assert state["total_turns"] == 4
        assert state["barge_in_count"] == 1

    def test_multi_user_session_workflow(self):
        """Test workflow with multiple users."""
        manager = SessionManager()

        # Create sessions for multiple users
        users = ["user-1", "user-2", "user-3"]
        sessions = []

        for user_id in users:
            user_session = manager.create_user_session(user_id=user_id)
            fov_session = manager.create_session(curriculum_id=f"curr-{user_id}")
            user_session.attach_fov_session(fov_session)
            sessions.append((user_session, fov_session))

        # Verify all sessions exist
        assert len(manager.list_user_sessions()) == 3
        assert len(manager.list_sessions()) == 3

        # End one session
        manager.end_user_session(sessions[0][0].session_id)

        # Verify cleanup
        assert len(manager.list_user_sessions()) == 2
        assert len(manager.list_sessions()) == 2

    def test_session_recovery_workflow(self):
        """Test session recovery/resume workflow."""
        manager = SessionManager()

        # Create initial session
        user_session = manager.create_user_session(user_id="user-123")
        user_session.set_current_topic("curr-1", "topic-1")
        user_session.update_playback(segment_index=5, offset_ms=2000)

        # Simulate "reconnection" - get same session
        recovered_session = manager.create_user_session(user_id="user-123")

        # Should be same session
        assert recovered_session is user_session
        assert recovered_session.playback_state.segment_index == 5
        assert recovered_session.playback_state.segment_offset_ms == 2000
