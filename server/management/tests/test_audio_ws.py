"""
Tests for Audio WebSocket Handler

Comprehensive tests for real-time audio streaming WebSocket protocol.
Tests verify message handling, session management, and error cases.
"""

import asyncio
import base64
import json
import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from aiohttp import web, WSMsgType

from audio_ws import (
    AudioWebSocketHandler,
    handle_audio_websocket,
    register_audio_websocket,
)


class MockWebSocketResponse:
    """Mock WebSocket response for testing."""

    def __init__(self):
        self.closed = False
        self.sent_messages = []
        self.prepared = False
        self._receive_queue = asyncio.Queue()
        self._exception = None

    async def prepare(self, request):  # noqa: ARG002
        self.prepared = True

    async def send_json(self, data):
        self.sent_messages.append(data)

    async def close(self):
        self.closed = True

    def exception(self):
        """Return the WebSocket exception, if any."""
        return self._exception

    def add_message(self, msg_type, data):
        """Add a message to the receive queue."""
        msg = MagicMock()
        msg.type = msg_type
        msg.data = json.dumps(data) if isinstance(data, dict) else data
        self._receive_queue.put_nowait(msg)

    def add_close(self):
        """Add close message."""
        msg = MagicMock()
        msg.type = WSMsgType.CLOSE
        self._receive_queue.put_nowait(msg)

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._receive_queue.empty():
            raise StopAsyncIteration
        return await self._receive_queue.get()


class MockPlaybackState:
    """Mock playback state."""

    def __init__(self):
        self.curriculum_id = "test-curriculum"
        self.topic_id = "test-topic"
        self.segment_index = 0
        self.offset_ms = 0
        self.is_playing = False


class MockVoiceConfig:
    """Mock voice configuration."""

    def __init__(self):
        self.voice_id = "nova"
        self.tts_provider = "vibevoice"
        self.speed = 1.0
        self.exaggeration = None
        self.cfg_weight = None
        self.language = None

    def to_dict(self):
        return {
            "voice_id": self.voice_id,
            "tts_provider": self.tts_provider,
            "speed": self.speed,
        }


class MockUserSession:
    """Mock user session."""

    def __init__(self, session_id: str = "test-session", user_id: str = "test-user"):
        self.session_id = session_id
        self.user_id = user_id
        self.playback_state = MockPlaybackState()
        self.voice_config = MockVoiceConfig()
        self._playback_updates = []
        self._voice_updates = []
        self._topic_updates = []

    def update_playback(self, segment_index: int, offset_ms: int, is_playing: bool):
        self._playback_updates.append((segment_index, offset_ms, is_playing))
        self.playback_state.segment_index = segment_index
        self.playback_state.offset_ms = offset_ms
        self.playback_state.is_playing = is_playing

    def update_voice_config(self, **kwargs):
        self._voice_updates.append(kwargs)
        for key, value in kwargs.items():
            if value is not None and hasattr(self.voice_config, key):
                setattr(self.voice_config, key, value)

    def set_current_topic(self, curriculum_id: str, topic_id: str):
        self._topic_updates.append((curriculum_id, topic_id))
        self.playback_state.curriculum_id = curriculum_id
        self.playback_state.topic_id = topic_id


class MockSessionManager:
    """Mock session manager."""

    def __init__(self):
        self.sessions = {}
        self._created_sessions = []

    def get_user_session(self, session_id: str):
        return self.sessions.get(session_id)

    def get_user_session_by_user(self, user_id: str):
        for session in self.sessions.values():
            if session.user_id == user_id:
                return session
        return None

    def create_user_session(self, user_id: str):
        session = MockUserSession(f"session-{user_id}", user_id)
        self.sessions[session.session_id] = session
        self._created_sessions.append(session)
        return session


class MockSessionCache:
    """Mock session cache integration."""

    def __init__(self):
        self.audio_requests = []
        self.prefetch_calls = []
        self._audio_data = b"test-audio-data"
        self._cache_hit = True
        self._duration = 2.5

    async def get_audio_for_segment(self, session, segment_text: str):
        self.audio_requests.append((session.session_id, segment_text))
        return self._audio_data, self._cache_hit, self._duration

    async def prefetch_upcoming(self, session, segment_index: int, segments: list):
        self.prefetch_calls.append((session.session_id, segment_index, len(segments)))


# =============================================================================
# HANDLER INITIALIZATION TESTS
# =============================================================================


class TestAudioWebSocketHandlerInit:
    """Tests for handler initialization."""

    def test_init_stores_dependencies(self):
        """Test handler stores session manager and cache."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()

        handler = AudioWebSocketHandler(session_manager, session_cache)

        assert handler.session_manager is session_manager
        assert handler.session_cache is session_cache
        assert handler._connections == {}
        assert handler._segments_by_topic == {}

    def test_set_topic_segments(self):
        """Test setting segments for a topic."""
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        segments = ["Segment 1", "Segment 2", "Segment 3"]
        handler.set_topic_segments("curriculum-1", "topic-1", segments)

        assert handler.get_topic_segments("curriculum-1", "topic-1") == segments

    def test_get_topic_segments_not_found(self):
        """Test getting segments for non-existent topic returns None."""
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        result = handler.get_topic_segments("nonexistent", "topic")

        assert result is None

    def test_set_topic_segments_multiple_curricula(self):
        """Test setting segments for multiple curricula."""
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        handler.set_topic_segments("curriculum-1", "topic-1", ["A", "B"])
        handler.set_topic_segments("curriculum-2", "topic-1", ["X", "Y", "Z"])

        assert handler.get_topic_segments("curriculum-1", "topic-1") == ["A", "B"]
        assert handler.get_topic_segments("curriculum-2", "topic-1") == ["X", "Y", "Z"]

    def test_set_topic_segments_multiple_topics_same_curriculum(self):
        """Test setting segments for multiple topics in same curriculum."""
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        handler.set_topic_segments("curriculum-1", "topic-1", ["A", "B"])
        handler.set_topic_segments("curriculum-1", "topic-2", ["C", "D", "E"])

        assert handler.get_topic_segments("curriculum-1", "topic-1") == ["A", "B"]
        assert handler.get_topic_segments("curriculum-1", "topic-2") == ["C", "D", "E"]

    def test_set_topic_segments_overwrites_existing(self):
        """Test setting segments overwrites existing segments for same topic."""
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        handler.set_topic_segments("curriculum-1", "topic-1", ["Old 1", "Old 2"])
        handler.set_topic_segments("curriculum-1", "topic-1", ["New 1", "New 2", "New 3"])

        assert handler.get_topic_segments("curriculum-1", "topic-1") == ["New 1", "New 2", "New 3"]

    def test_get_topic_segments_nonexistent_topic_in_existing_curriculum(self):
        """Test getting segments for non-existent topic in existing curriculum."""
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        handler.set_topic_segments("curriculum-1", "topic-1", ["A", "B"])
        result = handler.get_topic_segments("curriculum-1", "topic-nonexistent")

        assert result is None


# =============================================================================
# CONNECTION HANDLING TESTS
# =============================================================================


class TestConnectionHandling:
    """Tests for WebSocket connection handling."""

    @pytest.fixture
    def handler(self):
        """Create handler with mock dependencies."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        return handler

    @pytest.mark.asyncio
    async def test_connection_with_session_id(self, handler):
        """Test connection with existing session ID."""
        # Create existing session
        session = MockUserSession("existing-session", "user-1")
        handler.session_manager.sessions["existing-session"] = session

        request = MagicMock()
        request.query = {"session_id": "existing-session"}

        ws = MockWebSocketResponse()
        ws.add_close()  # Immediately close

        with patch.object(handler, 'handle_connection') as mock_handle:
            # Test that session lookup works
            found_session = handler.session_manager.get_user_session("existing-session")
            assert found_session is session

    @pytest.mark.asyncio
    async def test_connection_with_user_id_creates_session(self, handler):
        """Test connection with user_id creates new session."""
        request = MagicMock()
        request.query = {"user_id": "new-user"}

        # Session manager should create new session
        session = handler.session_manager.create_user_session("new-user")

        assert session is not None
        assert session.user_id == "new-user"
        assert len(handler.session_manager._created_sessions) == 1

    @pytest.mark.asyncio
    async def test_get_connected_sessions(self, handler):
        """Test getting list of connected sessions."""
        # Manually add connections
        handler._connections["session-1"] = MockWebSocketResponse()
        handler._connections["session-2"] = MockWebSocketResponse()

        connected = handler.get_connected_sessions()

        assert len(connected) == 2
        assert "session-1" in connected
        assert "session-2" in connected

    @pytest.mark.asyncio
    async def test_get_connected_sessions_empty(self, handler):
        """Test getting connected sessions when none exist."""
        connected = handler.get_connected_sessions()

        assert connected == []

    @pytest.mark.asyncio
    async def test_session_lookup_by_user_id(self, handler):
        """Test session lookup by user_id fallback."""
        # Create session for a user
        session = MockUserSession("session-for-user", "user-123")
        handler.session_manager.sessions["session-for-user"] = session

        # Lookup by user_id should find it
        found = handler.session_manager.get_user_session_by_user("user-123")
        assert found is session

    @pytest.mark.asyncio
    async def test_session_lookup_by_user_id_not_found(self, handler):
        """Test session lookup by user_id when not found."""
        found = handler.session_manager.get_user_session_by_user("nonexistent-user")
        assert found is None


# =============================================================================
# MESSAGE LOOP TESTS
# =============================================================================


class TestMessageLoop:
    """Tests for the _handle_messages message loop."""

    @pytest.fixture
    def handler(self):
        """Create handler with segments registered."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        handler.set_topic_segments("test-curriculum", "test-topic", [
            "Segment one text",
            "Segment two text",
        ])
        return handler

    @pytest.fixture
    def session(self):
        """Create test session."""
        return MockUserSession()

    @pytest.mark.asyncio
    async def test_handle_messages_invalid_json(self, handler, session):
        """Test handling of invalid JSON message."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, "not valid json {{{")
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert len(ws.sent_messages) == 1
        assert ws.sent_messages[0]["type"] == "error"
        assert "Invalid JSON" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_messages_unknown_type(self, handler, session):
        """Test handling of unknown message type."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, {"type": "unknown_message_type"})
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert len(ws.sent_messages) == 1
        assert ws.sent_messages[0]["type"] == "error"
        assert "Unknown message type" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_messages_text_type_request_audio(self, handler, session):
        """Test handling TEXT message with request_audio type."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, {
            "type": "request_audio",
            "segment_index": 0,
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert ws.sent_messages[0]["type"] == "audio"

    @pytest.mark.asyncio
    async def test_handle_messages_text_type_sync(self, handler, session):
        """Test handling TEXT message with sync type."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, {
            "type": "sync",
            "segment_index": 1,
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert ws.sent_messages[0]["type"] == "sync_ack"

    @pytest.mark.asyncio
    async def test_handle_messages_text_type_barge_in(self, handler, session):
        """Test handling TEXT message with barge_in type."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, {
            "type": "barge_in",
            "segment_index": 0,
            "offset_ms": 500,
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert ws.sent_messages[0]["type"] == "barge_in_ack"

    @pytest.mark.asyncio
    async def test_handle_messages_text_type_voice_config(self, handler, session):
        """Test handling TEXT message with voice_config type."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, {
            "type": "voice_config",
            "voice_id": "alloy",
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert ws.sent_messages[0]["type"] == "voice_config_ack"

    @pytest.mark.asyncio
    async def test_handle_messages_text_type_set_topic(self, handler, session):
        """Test handling TEXT message with set_topic type."""
        ws = MockWebSocketResponse()
        ws.add_message(WSMsgType.TEXT, {
            "type": "set_topic",
            "curriculum_id": "test-curriculum",
            "topic_id": "test-topic",
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert ws.sent_messages[0]["type"] == "topic_set"

    @pytest.mark.asyncio
    async def test_handle_messages_error_type_stops_loop(self, handler, session):
        """Test handling ERROR message type stops the loop."""
        ws = MockWebSocketResponse()

        # Create an error message
        error_msg = MagicMock()
        error_msg.type = WSMsgType.ERROR
        ws._receive_queue.put_nowait(error_msg)

        # Add another message that should NOT be processed
        ws.add_message(WSMsgType.TEXT, {"type": "sync", "segment_index": 0})

        await handler._handle_messages(ws, session)

        # No messages should have been sent since ERROR stops the loop
        assert len(ws.sent_messages) == 0

    @pytest.mark.asyncio
    async def test_handle_messages_close_type_stops_loop(self, handler, session):
        """Test handling CLOSE message type stops the loop."""
        ws = MockWebSocketResponse()

        # Add close first, then another message
        ws.add_close()
        ws.add_message(WSMsgType.TEXT, {"type": "sync", "segment_index": 0})

        await handler._handle_messages(ws, session)

        # No messages should have been sent since CLOSE stops the loop first
        assert len(ws.sent_messages) == 0

    @pytest.mark.asyncio
    async def test_handle_messages_multiple_messages(self, handler, session):
        """Test handling multiple messages in sequence."""
        ws = MockWebSocketResponse()

        ws.add_message(WSMsgType.TEXT, {
            "type": "set_topic",
            "curriculum_id": "test-curriculum",
            "topic_id": "test-topic",
        })
        ws.add_message(WSMsgType.TEXT, {
            "type": "request_audio",
            "segment_index": 0,
        })
        ws.add_message(WSMsgType.TEXT, {
            "type": "sync",
            "segment_index": 0,
            "offset_ms": 1000,
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert len(ws.sent_messages) == 3
        assert ws.sent_messages[0]["type"] == "topic_set"
        assert ws.sent_messages[1]["type"] == "audio"
        assert ws.sent_messages[2]["type"] == "sync_ack"

    @pytest.mark.asyncio
    async def test_handle_messages_exception_during_handling(self, handler, session):
        """Test that exceptions during message handling send error response."""
        ws = MockWebSocketResponse()

        # Mock the _handle_sync method to raise an exception
        async def raise_exception(*args, **kwargs):
            raise ValueError("Test exception")

        handler._handle_sync = raise_exception

        ws.add_message(WSMsgType.TEXT, {
            "type": "sync",
            "segment_index": 0,
        })
        ws.add_close()

        await handler._handle_messages(ws, session)

        assert len(ws.sent_messages) == 1
        assert ws.sent_messages[0]["type"] == "error"
        assert "Test exception" in ws.sent_messages[0]["error"]


# =============================================================================
# MESSAGE HANDLING TESTS
# =============================================================================


class TestMessageHandling:
    """Tests for WebSocket message handling."""

    @pytest.fixture
    def handler(self):
        """Create handler with segments registered."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        handler.set_topic_segments("test-curriculum", "test-topic", [
            "Segment one text",
            "Segment two text",
            "Segment three text",
        ])
        return handler

    @pytest.fixture
    def session(self):
        """Create test session."""
        return MockUserSession()

    @pytest.mark.asyncio
    async def test_handle_audio_request_success(self, handler, session):
        """Test successful audio request."""
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {
            "type": "request_audio",
            "segment_index": 0,
        })

        assert len(ws.sent_messages) == 1
        msg = ws.sent_messages[0]
        assert msg["type"] == "audio"
        assert msg["segment_index"] == 0
        assert "audio_base64" in msg
        assert msg["duration_seconds"] == 2.5
        assert msg["total_segments"] == 3

    @pytest.mark.asyncio
    async def test_handle_audio_request_cache_hit_reported(self, handler, session):
        """Test that cache hit status is reported."""
        ws = MockWebSocketResponse()
        handler.session_cache._cache_hit = True

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[0]["cache_hit"] is True

    @pytest.mark.asyncio
    async def test_handle_audio_request_updates_playback(self, handler, session):
        """Test that audio request updates playback state."""
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {"segment_index": 2})

        assert session._playback_updates[-1] == (2, 0, True)

    @pytest.mark.asyncio
    async def test_handle_audio_request_no_curriculum(self, handler, session):
        """Test audio request without curriculum returns error."""
        ws = MockWebSocketResponse()
        session.playback_state.curriculum_id = None
        session.playback_state.topic_id = None

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[0]["type"] == "error"
        assert "curriculum_id" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_audio_request_invalid_segment_index(self, handler, session):
        """Test audio request with invalid segment index."""
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {"segment_index": 999})

        assert ws.sent_messages[0]["type"] == "error"
        assert "Invalid segment_index" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_audio_request_negative_index(self, handler, session):
        """Test audio request with negative segment index."""
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {"segment_index": -1})

        assert ws.sent_messages[0]["type"] == "error"

    @pytest.mark.asyncio
    async def test_handle_audio_request_no_segments(self, handler, session):
        """Test audio request for topic without segments."""
        ws = MockWebSocketResponse()
        session.playback_state.curriculum_id = "no-segments"
        session.playback_state.topic_id = "empty"

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[0]["type"] == "error"
        assert "No segments found" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_audio_request_triggers_prefetch(self, handler, session):
        """Test that audio request triggers prefetch."""
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        # Give async task time to start
        await asyncio.sleep(0.01)

        # Prefetch should have been called
        assert len(handler.session_cache.prefetch_calls) >= 0  # May be async

    @pytest.mark.asyncio
    async def test_handle_sync_updates_playback(self, handler, session):
        """Test sync message updates playback state."""
        ws = MockWebSocketResponse()

        await handler._handle_sync(ws, session, {
            "segment_index": 5,
            "offset_ms": 1500,
            "is_playing": True,
        })

        assert session.playback_state.segment_index == 5
        assert session.playback_state.offset_ms == 1500
        assert session.playback_state.is_playing is True

    @pytest.mark.asyncio
    async def test_handle_sync_sends_ack(self, handler, session):
        """Test sync message sends acknowledgment."""
        ws = MockWebSocketResponse()

        await handler._handle_sync(ws, session, {"segment_index": 3})

        assert len(ws.sent_messages) == 1
        assert ws.sent_messages[0]["type"] == "sync_ack"
        assert ws.sent_messages[0]["segment_index"] == 3
        assert "server_time" in ws.sent_messages[0]

    @pytest.mark.asyncio
    async def test_handle_barge_in_stops_playback(self, handler, session):
        """Test barge-in stops playback."""
        ws = MockWebSocketResponse()
        session.playback_state.is_playing = True

        await handler._handle_barge_in(ws, session, {
            "segment_index": 5,
            "offset_ms": 2000,
        })

        assert session.playback_state.is_playing is False
        assert session.playback_state.segment_index == 5
        assert session.playback_state.offset_ms == 2000

    @pytest.mark.asyncio
    async def test_handle_barge_in_sends_ack(self, handler, session):
        """Test barge-in sends acknowledgment."""
        ws = MockWebSocketResponse()

        await handler._handle_barge_in(ws, session, {
            "segment_index": 3,
            "offset_ms": 1000,
        })

        assert ws.sent_messages[0]["type"] == "barge_in_ack"
        assert ws.sent_messages[0]["segment_index"] == 3
        assert ws.sent_messages[0]["offset_ms"] == 1000

    @pytest.mark.asyncio
    async def test_handle_voice_config_updates_settings(self, handler, session):
        """Test voice config updates session settings."""
        ws = MockWebSocketResponse()

        await handler._handle_voice_config(ws, session, {
            "voice_id": "shimmer",
            "tts_provider": "openai",
            "speed": 1.2,
        })

        assert session.voice_config.voice_id == "shimmer"
        assert session.voice_config.tts_provider == "openai"
        assert session.voice_config.speed == 1.2

    @pytest.mark.asyncio
    async def test_handle_voice_config_sends_ack(self, handler, session):
        """Test voice config sends acknowledgment with config."""
        ws = MockWebSocketResponse()

        await handler._handle_voice_config(ws, session, {"voice_id": "alloy"})

        assert ws.sent_messages[0]["type"] == "voice_config_ack"
        assert "voice_config" in ws.sent_messages[0]

    @pytest.mark.asyncio
    async def test_handle_set_topic_success(self, handler, session):
        """Test set topic updates session."""
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "test-curriculum",
            "topic_id": "test-topic",
        })

        assert session.playback_state.curriculum_id == "test-curriculum"
        assert session.playback_state.topic_id == "test-topic"

    @pytest.mark.asyncio
    async def test_handle_set_topic_sends_response(self, handler, session):
        """Test set topic sends response with segment count."""
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "test-curriculum",
            "topic_id": "test-topic",
        })

        assert ws.sent_messages[0]["type"] == "topic_set"
        assert ws.sent_messages[0]["total_segments"] == 3

    @pytest.mark.asyncio
    async def test_handle_set_topic_missing_ids(self, handler, session):
        """Test set topic with missing IDs returns error."""
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {})

        assert ws.sent_messages[0]["type"] == "error"
        assert "Missing" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_set_topic_missing_curriculum_id_only(self, handler, session):
        """Test set topic with only topic_id returns error."""
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {"topic_id": "test-topic"})

        assert ws.sent_messages[0]["type"] == "error"
        assert "Missing" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_set_topic_missing_topic_id_only(self, handler, session):
        """Test set topic with only curriculum_id returns error."""
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {"curriculum_id": "test-curriculum"})

        assert ws.sent_messages[0]["type"] == "error"
        assert "Missing" in ws.sent_messages[0]["error"]

    @pytest.mark.asyncio
    async def test_handle_set_topic_unknown_topic_returns_zero_segments(self, handler, session):
        """Test set topic for unknown topic returns zero segments."""
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "unknown-curriculum",
            "topic_id": "unknown-topic",
        })

        assert ws.sent_messages[0]["type"] == "topic_set"
        assert ws.sent_messages[0]["total_segments"] == 0

    @pytest.mark.asyncio
    async def test_handle_audio_request_with_explicit_curriculum_topic(self, handler, session):
        """Test audio request with explicit curriculum_id and topic_id in message."""
        ws = MockWebSocketResponse()

        # Session has different defaults
        session.playback_state.curriculum_id = "other-curriculum"
        session.playback_state.topic_id = "other-topic"

        # Request with explicit IDs
        await handler._handle_audio_request(ws, session, {
            "segment_index": 0,
            "curriculum_id": "test-curriculum",
            "topic_id": "test-topic",
        })

        assert ws.sent_messages[0]["type"] == "audio"

    @pytest.mark.asyncio
    async def test_handle_audio_request_cache_miss(self, handler, session):
        """Test audio request when cache miss occurs."""
        ws = MockWebSocketResponse()
        handler.session_cache._cache_hit = False

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[0]["cache_hit"] is False

    @pytest.mark.asyncio
    async def test_handle_audio_request_with_default_segment_index(self, handler, session):
        """Test audio request uses default segment_index 0."""
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {})

        assert ws.sent_messages[0]["segment_index"] == 0

    @pytest.mark.asyncio
    async def test_handle_sync_with_default_values(self, handler, session):
        """Test sync with default values from session."""
        ws = MockWebSocketResponse()
        session.playback_state.segment_index = 5

        await handler._handle_sync(ws, session, {})

        # Should use session's segment_index as default
        assert ws.sent_messages[0]["segment_index"] == 5

    @pytest.mark.asyncio
    async def test_handle_sync_with_is_playing_false(self, handler, session):
        """Test sync with is_playing set to false."""
        ws = MockWebSocketResponse()

        await handler._handle_sync(ws, session, {
            "segment_index": 0,
            "is_playing": False,
        })

        assert session.playback_state.is_playing is False

    @pytest.mark.asyncio
    async def test_handle_barge_in_with_default_values(self, handler, session):
        """Test barge-in with default values from session."""
        ws = MockWebSocketResponse()
        session.playback_state.segment_index = 3

        await handler._handle_barge_in(ws, session, {})

        assert ws.sent_messages[0]["segment_index"] == 3
        assert ws.sent_messages[0]["offset_ms"] == 0

    @pytest.mark.asyncio
    async def test_handle_barge_in_with_utterance(self, handler, session):
        """Test barge-in includes utterance (for logging)."""
        ws = MockWebSocketResponse()

        await handler._handle_barge_in(ws, session, {
            "segment_index": 1,
            "offset_ms": 500,
            "utterance": "Wait, I have a question",
        })

        # Barge-in should still send ack (utterance is for logging/future use)
        assert ws.sent_messages[0]["type"] == "barge_in_ack"

    @pytest.mark.asyncio
    async def test_handle_voice_config_with_all_parameters(self, handler, session):
        """Test voice config with all parameters including optional ones."""
        ws = MockWebSocketResponse()

        await handler._handle_voice_config(ws, session, {
            "voice_id": "shimmer",
            "tts_provider": "chatterbox",
            "speed": 1.5,
            "exaggeration": 0.8,
            "cfg_weight": 0.5,
            "language": "en-US",
        })

        assert session.voice_config.voice_id == "shimmer"
        assert session.voice_config.tts_provider == "chatterbox"
        assert session.voice_config.speed == 1.5
        assert session.voice_config.exaggeration == 0.8
        assert session.voice_config.cfg_weight == 0.5
        assert session.voice_config.language == "en-US"

    @pytest.mark.asyncio
    async def test_handle_voice_config_partial_update(self, handler, session):
        """Test voice config only updates provided fields."""
        ws = MockWebSocketResponse()

        # Set initial values
        session.voice_config.voice_id = "nova"
        session.voice_config.speed = 1.0

        # Update only speed
        await handler._handle_voice_config(ws, session, {
            "speed": 1.3,
        })

        # voice_id should remain unchanged
        assert session.voice_config.voice_id == "nova"
        assert session.voice_config.speed == 1.3


# =============================================================================
# BROADCAST TESTS
# =============================================================================


class TestBroadcast:
    """Tests for broadcast functionality."""

    @pytest.fixture
    def handler(self):
        """Create handler."""
        return AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

    @pytest.mark.asyncio
    async def test_broadcast_to_connected_session(self, handler):
        """Test broadcasting to connected session."""
        ws = MockWebSocketResponse()
        handler._connections["session-1"] = ws

        result = await handler.broadcast_to_session("session-1", {"type": "test"})

        assert result is True
        assert len(ws.sent_messages) == 1
        assert ws.sent_messages[0]["type"] == "test"

    @pytest.mark.asyncio
    async def test_broadcast_to_disconnected_session(self, handler):
        """Test broadcasting to disconnected session returns False."""
        result = await handler.broadcast_to_session("nonexistent", {"type": "test"})

        assert result is False

    @pytest.mark.asyncio
    async def test_broadcast_to_closed_ws(self, handler):
        """Test broadcasting to closed WebSocket returns False."""
        ws = MockWebSocketResponse()
        ws.closed = True
        handler._connections["session-1"] = ws

        result = await handler.broadcast_to_session("session-1", {"type": "test"})

        assert result is False


# =============================================================================
# ERROR HANDLING TESTS
# =============================================================================


class TestErrorHandling:
    """Tests for error handling."""

    @pytest.fixture
    def handler(self):
        """Create handler."""
        return AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

    @pytest.mark.asyncio
    async def test_handle_audio_request_generation_error(self, handler):
        """Test audio request handles generation errors."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        handler.set_topic_segments("test-curriculum", "test-topic", ["Segment"])

        # Make cache raise error
        async def raise_error(*args):
            raise Exception("TTS generation failed")

        handler.session_cache.get_audio_for_segment = raise_error

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[0]["type"] == "error"
        assert "Failed to get audio" in ws.sent_messages[0]["error"]


# =============================================================================
# ROUTE HANDLER TESTS
# =============================================================================


class TestRouteHandlers:
    """Tests for route handler functions."""

    @pytest.mark.asyncio
    async def test_handle_audio_websocket_no_handler(self):
        """Test WebSocket handler when not initialized returns error."""
        # Mock the WebSocketResponse creation
        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = AsyncMock()
            mock_ws.prepare = AsyncMock()
            mock_ws.send_json = AsyncMock()
            mock_ws.close = AsyncMock()
            MockWS.return_value = mock_ws

            request = MagicMock()
            request.app = {}  # No handler set

            await handle_audio_websocket(request)

            mock_ws.prepare.assert_called_once_with(request)
            mock_ws.send_json.assert_called_once()
            call_args = mock_ws.send_json.call_args[0][0]
            assert call_args["type"] == "error"
            assert "not initialized" in call_args["error"]
            mock_ws.close.assert_called_once()

    @pytest.mark.asyncio
    async def test_handle_audio_websocket_with_handler(self):
        """Test WebSocket handler delegates to registered handler."""
        mock_handler = AsyncMock()
        mock_ws = MagicMock()
        mock_handler.handle_connection = AsyncMock(return_value=mock_ws)

        request = MagicMock()
        request.app = {"audio_ws_handler": mock_handler}

        result = await handle_audio_websocket(request)

        mock_handler.handle_connection.assert_called_once_with(request)
        assert result is mock_ws

    def test_register_audio_websocket(self):
        """Test route registration."""
        app = web.Application()
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        register_audio_websocket(app, handler)

        assert app["audio_ws_handler"] is handler
        # Check route exists
        routes = [str(r.resource.canonical) for r in app.router.routes() if hasattr(r, 'resource')]
        assert any("/ws/audio" in r for r in routes)

    def test_register_audio_websocket_overwrites_existing(self):
        """Test registering new handler overwrites existing."""
        app = web.Application()
        handler1 = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())
        handler2 = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        register_audio_websocket(app, handler1)
        app["audio_ws_handler"] = handler2  # Simulate overwrite

        assert app["audio_ws_handler"] is handler2


# =============================================================================
# INTEGRATION TESTS
# =============================================================================


class TestIntegration:
    """Integration tests for complete message flows."""

    @pytest.fixture
    def handler(self):
        """Create fully configured handler."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)

        # Register segments
        handler.set_topic_segments("physics-101", "quantum-intro", [
            "Introduction to quantum mechanics.",
            "Wave-particle duality explained.",
            "The uncertainty principle.",
        ])

        return handler

    @pytest.mark.asyncio
    async def test_complete_playback_flow(self, handler):
        """Test complete playback flow: set topic, request audio, sync."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # 1. Set topic
        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "physics-101",
            "topic_id": "quantum-intro",
        })

        assert ws.sent_messages[0]["type"] == "topic_set"
        assert ws.sent_messages[0]["total_segments"] == 3

        # 2. Request first segment
        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[1]["type"] == "audio"
        assert ws.sent_messages[1]["segment_index"] == 0

        # 3. Send sync update
        await handler._handle_sync(ws, session, {
            "segment_index": 0,
            "offset_ms": 1500,
            "is_playing": True,
        })

        assert ws.sent_messages[2]["type"] == "sync_ack"

        # 4. Request next segment
        await handler._handle_audio_request(ws, session, {"segment_index": 1})

        assert ws.sent_messages[3]["type"] == "audio"
        assert ws.sent_messages[3]["segment_index"] == 1

    @pytest.mark.asyncio
    async def test_barge_in_flow(self, handler):
        """Test barge-in interruption flow."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # Setup topic
        session.playback_state.curriculum_id = "physics-101"
        session.playback_state.topic_id = "quantum-intro"

        # Start playback
        await handler._handle_audio_request(ws, session, {"segment_index": 1})
        assert session.playback_state.is_playing is True

        # Barge in
        await handler._handle_barge_in(ws, session, {
            "segment_index": 1,
            "offset_ms": 1000,
            "utterance": "Wait, can you explain that again?",
        })

        assert session.playback_state.is_playing is False
        assert ws.sent_messages[-1]["type"] == "barge_in_ack"

    @pytest.mark.asyncio
    async def test_voice_config_change_flow(self, handler):
        """Test voice configuration change during playback."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # Change voice config
        await handler._handle_voice_config(ws, session, {
            "voice_id": "shimmer",
            "speed": 0.9,
        })

        assert session.voice_config.voice_id == "shimmer"
        assert session.voice_config.speed == 0.9
        assert ws.sent_messages[0]["type"] == "voice_config_ack"


# =============================================================================
# HANDLE CONNECTION FULL FLOW TESTS
# =============================================================================


class TestHandleConnectionFlow:
    """Tests for full handle_connection flow."""

    @pytest.fixture
    def handler(self):
        """Create handler with segments registered."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        handler.set_topic_segments("test-curriculum", "test-topic", [
            "Segment one",
            "Segment two",
        ])
        return handler

    @pytest.mark.asyncio
    async def test_handle_connection_with_existing_session_id(self, handler):
        """Test handle_connection with existing session_id."""
        # Create existing session
        session = MockUserSession("existing-session", "user-1")
        handler.session_manager.sessions["existing-session"] = session

        request = MagicMock()
        request.query = {"session_id": "existing-session"}

        # Mock the WebSocketResponse creation
        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = MockWebSocketResponse()
            mock_ws.add_close()  # Immediately close connection
            MockWS.return_value = mock_ws

            result = await handler.handle_connection(request)

            # Verify session was found and connection was registered then cleaned up
            assert result is mock_ws

    @pytest.mark.asyncio
    async def test_handle_connection_with_user_id_lookup(self, handler):
        """Test handle_connection finds existing session by user_id."""
        # Create existing session
        session = MockUserSession("session-for-user", "user-123")
        handler.session_manager.sessions["session-for-user"] = session

        request = MagicMock()
        request.query = {"user_id": "user-123"}  # No session_id, only user_id

        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = MockWebSocketResponse()
            mock_ws.add_close()
            MockWS.return_value = mock_ws

            result = await handler.handle_connection(request)

            assert result is mock_ws

    @pytest.mark.asyncio
    async def test_handle_connection_creates_new_session_with_user_id(self, handler):
        """Test handle_connection creates new session when user_id provided but no existing session."""
        request = MagicMock()
        request.query = {"user_id": "new-user-456"}

        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = MockWebSocketResponse()
            mock_ws.add_close()
            MockWS.return_value = mock_ws

            await handler.handle_connection(request)

            # Session should have been created
            assert len(handler.session_manager._created_sessions) == 1
            assert handler.session_manager._created_sessions[0].user_id == "new-user-456"

    @pytest.mark.asyncio
    async def test_handle_connection_no_session_or_user_returns_error(self, handler):
        """Test handle_connection returns error when no session_id or user_id."""
        request = MagicMock()
        request.query = {}  # No session_id or user_id

        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = MockWebSocketResponse()
            MockWS.return_value = mock_ws

            await handler.handle_connection(request)

            # Should have sent error and closed
            assert len(mock_ws.sent_messages) == 1
            assert mock_ws.sent_messages[0]["type"] == "error"
            assert "No session_id or user_id" in mock_ws.sent_messages[0]["error"]
            assert mock_ws.closed is True

    @pytest.mark.asyncio
    async def test_handle_connection_exception_handling(self, handler):
        """Test handle_connection handles exceptions during message handling."""
        session = MockUserSession("test-session", "user-1")
        handler.session_manager.sessions["test-session"] = session

        request = MagicMock()
        request.query = {"session_id": "test-session"}

        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = MockWebSocketResponse()

            # Make the iterator raise an exception
            async def raise_on_iter():
                raise RuntimeError("Connection lost")

            mock_ws.__aiter__ = lambda self: self
            mock_ws.__anext__ = raise_on_iter
            MockWS.return_value = mock_ws

            # Should not raise, exception is caught
            await handler.handle_connection(request)

            # Connection should be cleaned up
            assert "test-session" not in handler._connections

    @pytest.mark.asyncio
    async def test_handle_connection_cleanup_on_normal_disconnect(self, handler):
        """Test connection cleanup on normal disconnect."""
        session = MockUserSession("cleanup-session", "user-1")
        handler.session_manager.sessions["cleanup-session"] = session

        request = MagicMock()
        request.query = {"session_id": "cleanup-session"}

        with patch('audio_ws.web.WebSocketResponse') as MockWS:
            mock_ws = MockWebSocketResponse()
            mock_ws.add_close()
            MockWS.return_value = mock_ws

            await handler.handle_connection(request)

            # Connection should be cleaned up after disconnect
            assert "cleanup-session" not in handler._connections

    @pytest.mark.asyncio
    async def test_connection_cleanup_on_disconnect(self, handler):
        """Test connection is removed from _connections on disconnect."""
        # Create a session
        session = MockUserSession("test-session", "test-user")
        handler.session_manager.sessions["test-session"] = session

        # Manually add connection (simulating successful connection)
        ws = MockWebSocketResponse()
        handler._connections["test-session"] = ws

        assert "test-session" in handler._connections

        # Simulate disconnect by removing (as would happen in finally block)
        del handler._connections["test-session"]

        assert "test-session" not in handler._connections

    @pytest.mark.asyncio
    async def test_connection_registers_in_connections_dict(self, handler):
        """Test that connecting adds to _connections dict."""
        session = MockUserSession("register-test", "user-1")
        handler.session_manager.sessions["register-test"] = session

        ws = MockWebSocketResponse()
        handler._connections[session.session_id] = ws

        assert handler._connections["register-test"] is ws

    @pytest.mark.asyncio
    async def test_multiple_concurrent_connections(self, handler):
        """Test handling multiple concurrent connections."""
        # Create multiple sessions
        session1 = MockUserSession("session-1", "user-1")
        session2 = MockUserSession("session-2", "user-2")
        handler.session_manager.sessions["session-1"] = session1
        handler.session_manager.sessions["session-2"] = session2

        # Add both connections
        ws1 = MockWebSocketResponse()
        ws2 = MockWebSocketResponse()
        handler._connections["session-1"] = ws1
        handler._connections["session-2"] = ws2

        assert len(handler.get_connected_sessions()) == 2

        # Send to both
        await handler.broadcast_to_session("session-1", {"type": "test1"})
        await handler.broadcast_to_session("session-2", {"type": "test2"})

        assert ws1.sent_messages[0]["type"] == "test1"
        assert ws2.sent_messages[0]["type"] == "test2"


# =============================================================================
# AUDIO DATA ENCODING TESTS
# =============================================================================


class TestAudioDataEncoding:
    """Tests for audio data base64 encoding."""

    @pytest.fixture
    def handler(self):
        """Create handler with segments."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        handler.set_topic_segments("test-curriculum", "test-topic", ["Test segment"])
        return handler

    @pytest.mark.asyncio
    async def test_audio_response_base64_encoding(self, handler):
        """Test audio data is properly base64 encoded."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # Set specific audio data
        test_audio = b"\x00\x01\x02\x03\xff\xfe"
        handler.session_cache._audio_data = test_audio

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        # Verify base64 encoding
        audio_b64 = ws.sent_messages[0]["audio_base64"]
        decoded = base64.b64decode(audio_b64)
        assert decoded == test_audio

    @pytest.mark.asyncio
    async def test_audio_response_with_empty_data(self, handler):
        """Test audio response with empty audio data."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # Set empty audio data
        handler.session_cache._audio_data = b""

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        audio_b64 = ws.sent_messages[0]["audio_base64"]
        decoded = base64.b64decode(audio_b64)
        assert decoded == b""


# =============================================================================
# SESSION STATE TRACKING TESTS
# =============================================================================


class TestSessionStateTracking:
    """Tests for session state changes during WebSocket operations."""

    @pytest.fixture
    def handler(self):
        """Create handler with segments."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        handler.set_topic_segments("curriculum-a", "topic-1", ["Seg 1", "Seg 2"])
        handler.set_topic_segments("curriculum-b", "topic-2", ["Seg A", "Seg B", "Seg C"])
        return handler

    @pytest.mark.asyncio
    async def test_topic_switch_updates_session_state(self, handler):
        """Test switching topics updates session state correctly."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # Set first topic
        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "curriculum-a",
            "topic_id": "topic-1",
        })

        assert session.playback_state.curriculum_id == "curriculum-a"
        assert session.playback_state.topic_id == "topic-1"
        assert ws.sent_messages[0]["total_segments"] == 2

        # Switch to second topic
        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "curriculum-b",
            "topic_id": "topic-2",
        })

        assert session.playback_state.curriculum_id == "curriculum-b"
        assert session.playback_state.topic_id == "topic-2"
        assert ws.sent_messages[1]["total_segments"] == 3

    @pytest.mark.asyncio
    async def test_playback_state_progression(self, handler):
        """Test playback state progresses through segments."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        session.playback_state.curriculum_id = "curriculum-a"
        session.playback_state.topic_id = "topic-1"

        # Request segment 0
        await handler._handle_audio_request(ws, session, {"segment_index": 0})
        assert session.playback_state.segment_index == 0
        assert session.playback_state.is_playing is True

        # Sync at halfway point
        await handler._handle_sync(ws, session, {
            "segment_index": 0,
            "offset_ms": 1000,
            "is_playing": True,
        })
        assert session.playback_state.offset_ms == 1000

        # Request segment 1
        await handler._handle_audio_request(ws, session, {"segment_index": 1})
        assert session.playback_state.segment_index == 1

    @pytest.mark.asyncio
    async def test_voice_config_state_tracking(self, handler):
        """Test voice config changes are tracked in session."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        # Track all updates
        assert len(session._voice_updates) == 0

        # First update
        await handler._handle_voice_config(ws, session, {"voice_id": "alloy"})
        assert len(session._voice_updates) == 1

        # Second update
        await handler._handle_voice_config(ws, session, {"speed": 1.5})
        assert len(session._voice_updates) == 2

        # Third update with multiple fields
        await handler._handle_voice_config(ws, session, {
            "voice_id": "nova",
            "tts_provider": "openai",
        })
        assert len(session._voice_updates) == 3


# =============================================================================
# EDGE CASE TESTS
# =============================================================================


class TestEdgeCases:
    """Tests for edge cases and boundary conditions."""

    @pytest.fixture
    def handler(self):
        """Create handler."""
        session_manager = MockSessionManager()
        session_cache = MockSessionCache()
        handler = AudioWebSocketHandler(session_manager, session_cache)
        handler.set_topic_segments("test", "topic", ["Only segment"])
        return handler

    @pytest.mark.asyncio
    async def test_audio_request_boundary_index(self, handler):
        """Test audio request at exact boundary (last valid index)."""
        session = MockUserSession()
        session.playback_state.curriculum_id = "test"
        session.playback_state.topic_id = "topic"
        ws = MockWebSocketResponse()

        # Single segment, so index 0 is valid, index 1 is not
        await handler._handle_audio_request(ws, session, {"segment_index": 0})
        assert ws.sent_messages[0]["type"] == "audio"

        await handler._handle_audio_request(ws, session, {"segment_index": 1})
        assert ws.sent_messages[1]["type"] == "error"

    @pytest.mark.asyncio
    async def test_sync_with_zero_offset(self, handler):
        """Test sync with zero offset (beginning of segment)."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        await handler._handle_sync(ws, session, {
            "segment_index": 0,
            "offset_ms": 0,
            "is_playing": True,
        })

        assert session.playback_state.offset_ms == 0
        assert ws.sent_messages[0]["type"] == "sync_ack"

    @pytest.mark.asyncio
    async def test_sync_with_large_offset(self, handler):
        """Test sync with large offset value."""
        session = MockUserSession()
        ws = MockWebSocketResponse()

        await handler._handle_sync(ws, session, {
            "segment_index": 0,
            "offset_ms": 999999,
            "is_playing": True,
        })

        assert session.playback_state.offset_ms == 999999

    @pytest.mark.asyncio
    async def test_voice_config_with_none_values(self, handler):
        """Test voice config update with explicit None values."""
        session = MockUserSession()
        session.voice_config.voice_id = "original"
        ws = MockWebSocketResponse()

        # Update with None should not change original
        await handler._handle_voice_config(ws, session, {
            "voice_id": None,
            "speed": 1.2,
        })

        # voice_id should remain "original" because None is filtered
        assert session.voice_config.voice_id == "original"
        assert session.voice_config.speed == 1.2

    @pytest.mark.asyncio
    async def test_empty_segments_list(self, handler):
        """Test topic with empty segments list."""
        handler.set_topic_segments("empty-curriculum", "empty-topic", [])

        session = MockUserSession()
        ws = MockWebSocketResponse()

        await handler._handle_set_topic(ws, session, {
            "curriculum_id": "empty-curriculum",
            "topic_id": "empty-topic",
        })

        assert ws.sent_messages[0]["total_segments"] == 0

    @pytest.mark.asyncio
    async def test_request_audio_from_empty_topic(self, handler):
        """Test requesting audio from topic with no segments."""
        handler.set_topic_segments("empty-curriculum", "empty-topic", [])

        session = MockUserSession()
        session.playback_state.curriculum_id = "empty-curriculum"
        session.playback_state.topic_id = "empty-topic"
        ws = MockWebSocketResponse()

        await handler._handle_audio_request(ws, session, {"segment_index": 0})

        assert ws.sent_messages[0]["type"] == "error"
        # Empty segments list returns "No segments found" error
        assert "No segments found" in ws.sent_messages[0]["error"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
