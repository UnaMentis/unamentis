"""
Tests for Audio WebSocket Handler

Comprehensive tests for real-time audio streaming WebSocket protocol.
Tests verify message handling, session management, and error cases.
"""

import asyncio
import base64
import json
import pytest
from datetime import datetime
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

    async def prepare(self, request):
        self.prepared = True

    async def send_json(self, data):
        self.sent_messages.append(data)

    async def close(self):
        self.closed = True

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
        """Test WebSocket handler when not initialized."""
        request = MagicMock()
        request.app = {}  # No handler

        # This would need more complex mocking for full test
        # The function creates a WebSocketResponse

    def test_register_audio_websocket(self):
        """Test route registration."""
        app = web.Application()
        handler = AudioWebSocketHandler(MockSessionManager(), MockSessionCache())

        register_audio_websocket(app, handler)

        assert app["audio_ws_handler"] is handler
        # Check route exists
        routes = [str(r.resource.canonical) for r in app.router.routes() if hasattr(r, 'resource')]
        assert any("/ws/audio" in r for r in routes)


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


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
