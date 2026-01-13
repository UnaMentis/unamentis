"""
Tests for the FOV Context API endpoints.

Tests cover:
- Session lifecycle (create, list, get, start, pause, resume, end, delete)
- Context updates (topic, position, segment)
- Conversation handling (turns, barge-in)
- Context building
- Confidence analysis
- Learner signals
- Events
- Debug/health endpoints
"""

import json
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from enum import Enum

import pytest
from aiohttp import web

# Import the module under test
import fov_context_api


# --- Mock Classes ---

class MockSessionState(Enum):
    """Mock session state enum."""
    CREATED = "created"
    ACTIVE = "active"
    PAUSED = "paused"
    ENDED = "ended"


class MockMessageRole(Enum):
    """Mock message role enum."""
    USER = "user"
    ASSISTANT = "assistant"


class MockConfidenceMarker(Enum):
    """Mock confidence marker enum."""
    HEDGING = "hedging"
    UNCERTAINTY = "uncertainty"


class MockTrend(Enum):
    """Mock trend enum."""
    STABLE = "stable"
    DECLINING = "declining"


class MockPriority(Enum):
    """Mock priority enum."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class MockScope(Enum):
    """Mock expansion scope enum."""
    NARROW = "narrow"
    MEDIUM = "medium"
    WIDE = "wide"


class MockTurn:
    """Mock conversation turn."""
    def __init__(self, turn_id="turn-123", role=None, content="", timestamp=None):
        self.id = turn_id
        self.role = role or MockMessageRole.USER
        self.content = content
        self.timestamp = timestamp or datetime.now()


class MockContext:
    """Mock LLM context."""
    def __init__(self):
        self.system_prompt = "You are a helpful tutor."
        self.immediate_context = "Current segment content"
        self.working_context = "Topic content"
        self.episodic_context = "Session history"
        self.semantic_context = "Curriculum structure"
        self.total_token_estimate = 1500

    def to_system_message(self):
        return self.system_prompt


class MockConfidenceAnalysis:
    """Mock confidence analysis result."""
    def __init__(self):
        self.confidence_score = 0.75
        self.uncertainty_score = 0.2
        self.hedging_score = 0.15
        self.question_deflection_score = 0.1
        self.knowledge_gap_score = 0.05
        self.vague_language_score = 0.08
        self.detected_markers = [MockConfidenceMarker.HEDGING]
        self.trend = MockTrend.STABLE


class MockExpansionRecommendation:
    """Mock expansion recommendation."""
    def __init__(self):
        self.should_expand = True
        self.priority = MockPriority.MEDIUM
        self.suggested_scope = MockScope.NARROW
        self.reason = "Low confidence detected"


class MockLearnerSignals:
    """Mock learner signals."""
    def __init__(self):
        self.clarification_requests = 2
        self.repetition_requests = 1
        self.confusion_indicators = 0


class MockBudgetConfig:
    """Mock budget configuration."""
    class MockTier(Enum):
        CLOUD = "cloud"
        ON_DEVICE = "on_device"

    def __init__(self):
        self.tier = self.MockTier.CLOUD
        self.immediate_token_budget = 2000
        self.working_token_budget = 4000
        self.episodic_token_budget = 2000
        self.semantic_token_budget = 2000
        self.total_context_budget = 10000
        self.max_conversation_turns = 20


class MockImmediateBuffer:
    """Mock immediate buffer."""
    def __init__(self):
        self.recent_turns = [MockTurn(), MockTurn()]


class MockWorkingBuffer:
    """Mock working buffer."""
    def __init__(self):
        self.topic_content = "Topic content here"
        self.glossary_terms = [{"term": "physics", "definition": "science"}]
        self.misconception_triggers = []


class MockEpisodicBuffer:
    """Mock episodic buffer."""
    def __init__(self):
        self.topic_summaries = ["Summary 1", "Summary 2"]
        self.user_questions = ["What is gravity?"]
        self.learner_signals = MockLearnerSignals()

    def record_user_question(self, question):
        self.user_questions.append(question)


class MockPosition:
    """Mock curriculum position."""
    def __init__(self):
        self.curriculum_id = "curriculum-123"
        self.current_topic_index = 3
        self.total_topics = 20


class MockSemanticBuffer:
    """Mock semantic buffer."""
    def __init__(self):
        self.curriculum_outline = "1. Intro\n2. Chapter 1"
        self.position = MockPosition()


class MockContextManager:
    """Mock context manager."""
    def __init__(self):
        self.budget_config = MockBudgetConfig()
        self.immediate_buffer = MockImmediateBuffer()
        self.working_buffer = MockWorkingBuffer()
        self.episodic_buffer = MockEpisodicBuffer()
        self.semantic_buffer = MockSemanticBuffer()

    def get_state_snapshot(self):
        return {
            "tier": "cloud",
            "budgets": {
                "immediate": 2000,
                "working": 4000,
                "episodic": 2000,
                "semantic": 2000,
            },
            "immediate": {"current_segment": "segment text", "barge_in": None},
            "working": {"topic_id": "topic-123", "topic_title": "Physics"},
        }

    def record_user_question(self, question):
        self.episodic_buffer.record_user_question(question)


class MockSession:
    """Mock FOV session."""
    def __init__(self, session_id="session-123", curriculum_id="curriculum-123"):
        self.session_id = session_id
        self.curriculum_id = curriculum_id
        self.state = MockSessionState.CREATED
        self.created_at = datetime.now()
        self.turn_count = 5
        self.barge_in_count = 1
        self.context_manager = MockContextManager()

    def get_state(self):
        return {
            "session_id": self.session_id,
            "curriculum_id": self.curriculum_id,
            "state": self.state.value,
            "created_at": self.created_at.isoformat(),
            "turn_count": self.turn_count,
            "barge_in_count": self.barge_in_count,
        }

    def start(self):
        self.state = MockSessionState.ACTIVE

    def pause(self):
        self.state = MockSessionState.PAUSED

    def resume(self):
        self.state = MockSessionState.ACTIVE

    def end(self):
        self.state = MockSessionState.ENDED

    def set_current_topic(self, topic_id, topic_title, topic_content, learning_objectives, glossary_terms, misconceptions):
        pass

    def set_curriculum_position(self, curriculum_title, current_topic_index, total_topics, unit_title, curriculum_outline):
        pass

    def set_current_segment(self, segment):
        pass

    def add_user_turn(self, content, is_barge_in=False):
        self.turn_count += 1
        if is_barge_in:
            self.barge_in_count += 1
        return MockTurn(role=MockMessageRole.USER, content=content)

    def add_assistant_turn(self, content):
        self.turn_count += 1
        return MockTurn(role=MockMessageRole.ASSISTANT, content=content)

    def build_llm_context(self, barge_in_utterance=None):
        return MockContext()

    def build_llm_messages(self, barge_in_utterance=None):
        return [
            {"role": "system", "content": "System prompt"},
            {"role": "user", "content": "Hello"},
        ]

    def process_response_with_confidence(self, response):
        return MockConfidenceAnalysis(), MockExpansionRecommendation()

    def record_clarification_request(self):
        pass

    def record_repetition_request(self):
        pass

    def record_confusion_signal(self):
        pass

    def get_events(self, event_type=None):
        events = [
            {"type": "confidence_analysis", "timestamp": "2024-01-01T00:00:00", "confidence_score": 0.8},
            {"type": "barge_in", "timestamp": "2024-01-01T00:01:00", "utterance": "Wait!"},
        ]
        if event_type:
            return [e for e in events if e.get("type") == event_type]
        return events


class MockSessionManager:
    """Mock session manager."""
    def __init__(self):
        self.sessions = {}

    def create_session(self, curriculum_id, config):
        session = MockSession(curriculum_id=curriculum_id)
        self.sessions[session.session_id] = session
        return session

    def get_session(self, session_id):
        return self.sessions.get(session_id)

    def list_sessions(self):
        return [s.get_state() for s in self.sessions.values()]

    def end_session(self, session_id):
        if session_id in self.sessions:
            del self.sessions[session_id]
            return True
        return False


# --- Fixtures ---

@pytest.fixture
def mock_session_manager():
    """Create a mock session manager with a test session."""
    manager = MockSessionManager()
    # Pre-create a session
    session = MockSession()
    manager.sessions[session.session_id] = session
    return manager


@pytest.fixture
def mock_request_factory():
    """Factory for creating mock requests."""
    def factory(method="GET", match_info=None, json_data=None, query_params=None):
        request = MagicMock(spec=web.Request)
        request.method = method
        request.match_info = match_info or {}
        request.query = query_params or {}

        if json_data is not None:
            async def mock_json():
                return json_data
            request.json = mock_json
        else:
            async def mock_json():
                raise ValueError("Invalid JSON")
            request.json = mock_json

        return request
    return factory


# --- Session Lifecycle Tests ---

class TestSessionLifecycle:
    """Tests for session lifecycle endpoints."""

    @pytest.mark.asyncio
    async def test_create_session_success(self, mock_request_factory, mock_session_manager):
        """Test successful session creation."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                json_data={
                    "curriculum_id": "curriculum-456",
                    "model_name": "claude-3-5-sonnet",
                    "model_context_window": 100000,
                }
            )

            response = await fov_context_api.handle_create_session(request)

            assert response.status == 201
            data = json.loads(response.body)
            assert "session_id" in data
            assert data["curriculum_id"] == "curriculum-456"
            assert data["state"] == "created"

    @pytest.mark.asyncio
    async def test_create_session_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test session creation with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(method="POST")  # No json_data

            response = await fov_context_api.handle_create_session(request)

            assert response.status == 400
            data = json.loads(response.body)
            assert "Invalid JSON" in data["error"]

    @pytest.mark.asyncio
    async def test_create_session_missing_curriculum_id(self, mock_request_factory, mock_session_manager):
        """Test session creation without curriculum_id."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                json_data={"model_name": "claude-3-5-sonnet"}
            )

            response = await fov_context_api.handle_create_session(request)

            assert response.status == 400
            data = json.loads(response.body)
            assert "curriculum_id is required" in data["error"]

    @pytest.mark.asyncio
    async def test_list_sessions(self, mock_request_factory, mock_session_manager):
        """Test listing sessions."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory()

            response = await fov_context_api.handle_list_sessions(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "sessions" in data
            assert len(data["sessions"]) == 1

    @pytest.mark.asyncio
    async def test_get_session_success(self, mock_request_factory, mock_session_manager):
        """Test getting a specific session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_get_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["session_id"] == "session-123"

    @pytest.mark.asyncio
    async def test_get_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test getting a non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "nonexistent"}
            )

            response = await fov_context_api.handle_get_session(request)

            assert response.status == 404
            data = json.loads(response.body)
            assert "Session not found" in data["error"]

    @pytest.mark.asyncio
    async def test_start_session(self, mock_request_factory, mock_session_manager):
        """Test starting a session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_start_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["state"] == "active"

    @pytest.mark.asyncio
    async def test_start_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test starting a non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "nonexistent"}
            )

            response = await fov_context_api.handle_start_session(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_pause_session(self, mock_request_factory, mock_session_manager):
        """Test pausing a session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            # First start the session
            mock_session_manager.sessions["session-123"].start()

            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_pause_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["state"] == "paused"

    @pytest.mark.asyncio
    async def test_resume_session(self, mock_request_factory, mock_session_manager):
        """Test resuming a session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            # First pause the session
            mock_session_manager.sessions["session-123"].pause()

            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_resume_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["state"] == "active"

    @pytest.mark.asyncio
    async def test_end_session(self, mock_request_factory, mock_session_manager):
        """Test ending a session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_end_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "session_id" in data

    @pytest.mark.asyncio
    async def test_delete_session_success(self, mock_request_factory, mock_session_manager):
        """Test deleting a session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="DELETE",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_delete_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["deleted"] is True

    @pytest.mark.asyncio
    async def test_delete_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test deleting a non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="DELETE",
                match_info={"session_id": "nonexistent"}
            )

            response = await fov_context_api.handle_delete_session(request)

            assert response.status == 404


# --- Context Update Tests ---

class TestContextUpdates:
    """Tests for context update endpoints."""

    @pytest.mark.asyncio
    async def test_set_topic_success(self, mock_request_factory, mock_session_manager):
        """Test setting the current topic."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"},
                json_data={
                    "topic_id": "topic-456",
                    "topic_title": "Newton's Laws",
                    "topic_content": "Physics content...",
                    "learning_objectives": ["Understand F=ma"],
                    "glossary_terms": [{"term": "force", "definition": "push or pull"}],
                    "misconceptions": [],
                }
            )

            response = await fov_context_api.handle_set_topic(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["topic_id"] == "topic-456"
            assert data["topic_title"] == "Newton's Laws"

    @pytest.mark.asyncio
    async def test_set_topic_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test setting topic with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_set_topic(request)

            assert response.status == 400

    @pytest.mark.asyncio
    async def test_set_topic_missing_required_fields(self, mock_request_factory, mock_session_manager):
        """Test setting topic without required fields."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"},
                json_data={"topic_content": "Content only"}
            )

            response = await fov_context_api.handle_set_topic(request)

            assert response.status == 400
            data = json.loads(response.body)
            assert "topic_id and topic_title are required" in data["error"]

    @pytest.mark.asyncio
    async def test_set_topic_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test setting topic for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "nonexistent"},
                json_data={
                    "topic_id": "topic-456",
                    "topic_title": "Newton's Laws",
                }
            )

            response = await fov_context_api.handle_set_topic(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_set_position_success(self, mock_request_factory, mock_session_manager):
        """Test setting curriculum position."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"},
                json_data={
                    "curriculum_title": "Physics 101",
                    "current_topic_index": 5,
                    "total_topics": 20,
                    "unit_title": "Mechanics",
                    "curriculum_outline": "1. Introduction\n2. Motion",
                }
            )

            response = await fov_context_api.handle_set_position(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["updated"] is True

    @pytest.mark.asyncio
    async def test_set_position_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test setting position with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_set_position(request)

            assert response.status == 400

    @pytest.mark.asyncio
    async def test_set_segment_success(self, mock_request_factory, mock_session_manager):
        """Test setting current transcript segment."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"},
                json_data={
                    "segment_id": "segment-789",
                    "text": "This is the transcript text...",
                    "start_time": 0.0,
                    "end_time": 10.5,
                    "topic_id": "topic-456",
                }
            )

            response = await fov_context_api.handle_set_segment(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["updated"] is True

    @pytest.mark.asyncio
    async def test_set_segment_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test setting segment with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="PUT",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_set_segment(request)

            assert response.status == 400


# --- Conversation Tests ---

class TestConversation:
    """Tests for conversation handling endpoints."""

    @pytest.mark.asyncio
    async def test_add_user_turn(self, mock_request_factory, mock_session_manager):
        """Test adding a user conversation turn."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={
                    "role": "user",
                    "content": "What is gravity?",
                }
            )

            response = await fov_context_api.handle_add_turn(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "turn_id" in data
            assert data["role"] == "user"

    @pytest.mark.asyncio
    async def test_add_assistant_turn(self, mock_request_factory, mock_session_manager):
        """Test adding an assistant conversation turn."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={
                    "role": "assistant",
                    "content": "Gravity is the force that attracts objects toward each other.",
                }
            )

            response = await fov_context_api.handle_add_turn(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["role"] == "assistant"

    @pytest.mark.asyncio
    async def test_add_turn_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test adding turn with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_add_turn(request)

            assert response.status == 400

    @pytest.mark.asyncio
    async def test_add_turn_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test adding turn to non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "nonexistent"},
                json_data={"role": "user", "content": "Hello"}
            )

            response = await fov_context_api.handle_add_turn(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_barge_in_success(self, mock_request_factory, mock_session_manager):
        """Test handling a barge-in event."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={
                    "utterance": "Wait, can you explain that again?",
                    "interrupted_position": 15.5,
                }
            )

            response = await fov_context_api.handle_barge_in(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["session_id"] == "session-123"
            assert "barge_in_count" in data
            assert "context" in data
            assert "messages" in data

    @pytest.mark.asyncio
    async def test_barge_in_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test barge-in with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_barge_in(request)

            assert response.status == 400


# --- Context Building Tests ---

class TestContextBuilding:
    """Tests for context building endpoints."""

    @pytest.mark.asyncio
    async def test_get_context_success(self, mock_request_factory, mock_session_manager):
        """Test getting current context state."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_get_context(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "tier" in data
            assert "budgets" in data

    @pytest.mark.asyncio
    async def test_get_context_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test getting context for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "nonexistent"}
            )

            response = await fov_context_api.handle_get_context(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_build_context_success(self, mock_request_factory, mock_session_manager):
        """Test building LLM context."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={}
            )

            response = await fov_context_api.handle_build_context(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "system_message" in data
            assert "immediate" in data
            assert "working" in data
            assert "total_tokens" in data

    @pytest.mark.asyncio
    async def test_build_context_with_barge_in(self, mock_request_factory, mock_session_manager):
        """Test building context with barge-in utterance."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={"barge_in_utterance": "Wait, what?"}
            )

            response = await fov_context_api.handle_build_context(request)

            assert response.status == 200

    @pytest.mark.asyncio
    async def test_build_context_invalid_json_fallback(self, mock_request_factory, mock_session_manager):
        """Test build context handles invalid JSON gracefully."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            # Should still work with empty data fallback
            response = await fov_context_api.handle_build_context(request)

            assert response.status == 200

    @pytest.mark.asyncio
    async def test_get_messages_success(self, mock_request_factory, mock_session_manager):
        """Test getting LLM message list."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_get_messages(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "messages" in data
            assert len(data["messages"]) > 0

    @pytest.mark.asyncio
    async def test_get_messages_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test getting messages for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "nonexistent"}
            )

            response = await fov_context_api.handle_get_messages(request)

            assert response.status == 404


# --- Confidence Analysis Tests ---

class TestConfidenceAnalysis:
    """Tests for confidence analysis endpoints."""

    @pytest.mark.asyncio
    async def test_analyze_response_success(self, mock_request_factory, mock_session_manager):
        """Test analyzing an LLM response for confidence."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={
                    "response": "I'm not entirely sure, but I think the answer is..."
                }
            )

            response = await fov_context_api.handle_analyze_response(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "confidence_score" in data
            assert "uncertainty_score" in data
            assert "detected_markers" in data
            assert "expansion" in data
            assert data["expansion"]["should_expand"] is True

    @pytest.mark.asyncio
    async def test_analyze_response_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test analyzing with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_analyze_response(request)

            assert response.status == 400

    @pytest.mark.asyncio
    async def test_analyze_response_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test analyzing for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "nonexistent"},
                json_data={"response": "Test response"}
            )

            response = await fov_context_api.handle_analyze_response(request)

            assert response.status == 404


# --- Learner Signal Tests ---

class TestLearnerSignals:
    """Tests for learner signal endpoints."""

    @pytest.mark.asyncio
    async def test_record_clarification_signal(self, mock_request_factory, mock_session_manager):
        """Test recording a clarification request signal."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={"signal_type": "clarification"}
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["recorded"] is True

    @pytest.mark.asyncio
    async def test_record_repetition_signal(self, mock_request_factory, mock_session_manager):
        """Test recording a repetition request signal."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={"signal_type": "repetition"}
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 200

    @pytest.mark.asyncio
    async def test_record_confusion_signal(self, mock_request_factory, mock_session_manager):
        """Test recording a confusion indicator signal."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={"signal_type": "confusion"}
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 200

    @pytest.mark.asyncio
    async def test_record_question_signal(self, mock_request_factory, mock_session_manager):
        """Test recording a question signal with content."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={
                    "signal_type": "question",
                    "content": "What is the relationship between force and acceleration?"
                }
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 200

    @pytest.mark.asyncio
    async def test_record_unknown_signal_type(self, mock_request_factory, mock_session_manager):
        """Test recording an unknown signal type."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"},
                json_data={"signal_type": "unknown_signal"}
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 400
            data = json.loads(response.body)
            assert "Unknown signal type" in data["error"]

    @pytest.mark.asyncio
    async def test_record_signal_invalid_json(self, mock_request_factory, mock_session_manager):
        """Test recording signal with invalid JSON."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 400

    @pytest.mark.asyncio
    async def test_record_signal_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test recording signal for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                method="POST",
                match_info={"session_id": "nonexistent"},
                json_data={"signal_type": "clarification"}
            )

            response = await fov_context_api.handle_record_signal(request)

            assert response.status == 404


# --- Event Tests ---

class TestEvents:
    """Tests for event retrieval endpoints."""

    @pytest.mark.asyncio
    async def test_get_all_events(self, mock_request_factory, mock_session_manager):
        """Test getting all events."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "session-123"},
                query_params={}
            )

            response = await fov_context_api.handle_get_events(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "events" in data
            assert len(data["events"]) > 0

    @pytest.mark.asyncio
    async def test_get_filtered_events(self, mock_request_factory, mock_session_manager):
        """Test getting events filtered by type."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "session-123"},
                query_params={"type": "barge_in"}
            )

            response = await fov_context_api.handle_get_events(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "events" in data
            # All returned events should be of type "barge_in"
            for event in data["events"]:
                assert event["type"] == "barge_in"

    @pytest.mark.asyncio
    async def test_get_events_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test getting events for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "nonexistent"},
                query_params={}
            )

            response = await fov_context_api.handle_get_events(request)

            assert response.status == 404


# --- Debug and Health Tests ---

class TestDebugAndHealth:
    """Tests for debug and health endpoints."""

    @pytest.mark.asyncio
    async def test_debug_session_success(self, mock_request_factory, mock_session_manager):
        """Test getting debug information for a session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "session-123"}
            )

            response = await fov_context_api.handle_debug_session(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["session_id"] == "session-123"
            assert "state" in data
            assert "buffers" in data
            assert "token_usage" in data
            assert "budget_config" in data

    @pytest.mark.asyncio
    async def test_debug_session_not_found(self, mock_request_factory, mock_session_manager):
        """Test debug for non-existent session."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory(
                match_info={"session_id": "nonexistent"}
            )

            response = await fov_context_api.handle_debug_session(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_fov_health_success(self, mock_request_factory, mock_session_manager):
        """Test FOV health endpoint."""
        with patch.object(fov_context_api, '_session_manager', mock_session_manager):
            request = mock_request_factory()

            response = await fov_context_api.handle_fov_health(request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "healthy"
            assert "sessions" in data
            assert "features" in data
            assert data["features"]["confidence_monitoring"] is True


# --- Route Registration Tests ---

class TestRouteRegistration:
    """Tests for route registration."""

    def test_setup_fov_context_routes(self):
        """Test that all routes are registered."""
        app = web.Application()

        fov_context_api.setup_fov_context_routes(app)

        # Check that routes are registered
        routes = [r.resource.canonical for r in app.router.routes()]

        expected_routes = [
            "/api/sessions",
            "/api/sessions/{session_id}",
            "/api/sessions/{session_id}/start",
            "/api/sessions/{session_id}/pause",
            "/api/sessions/{session_id}/resume",
            "/api/sessions/{session_id}/end",
            "/api/sessions/{session_id}/topic",
            "/api/sessions/{session_id}/position",
            "/api/sessions/{session_id}/segment",
            "/api/sessions/{session_id}/turns",
            "/api/sessions/{session_id}/barge-in",
            "/api/sessions/{session_id}/context",
            "/api/sessions/{session_id}/context/build",
            "/api/sessions/{session_id}/messages",
            "/api/sessions/{session_id}/analyze-response",
            "/api/sessions/{session_id}/signals",
            "/api/sessions/{session_id}/events",
            "/api/sessions/{session_id}/debug",
            "/api/fov/health",
        ]

        for expected in expected_routes:
            assert any(expected in route for route in routes), f"Route {expected} not found"

    def test_get_session_manager(self):
        """Test get_session_manager helper function."""
        manager = fov_context_api.get_session_manager()
        assert manager is not None
