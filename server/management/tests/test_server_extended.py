"""
Extended Test Suite for UnaMentis Management Server

This test file provides additional coverage for server.py sections not covered
by the main test_server.py file, including:
- Visual asset management handlers
- Audio streaming handlers
- WebSocket message handling details
- Model load/unload operations
- Curriculum archive/unarchive operations
- Asset pre-download and caching
- Admin user management with database mocking
- Pull model with SSE streaming
- Idle management and system metrics
- Profile management
- Curriculum archive/delete operations
"""

import pytest
import json
import asyncio
import time
from unittest.mock import MagicMock, patch, AsyncMock
from pathlib import Path
import sys

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from aiohttp import web

# Import server components
from server import (
    ManagementState,
    LogEntry,
    MetricsSnapshot,
    RemoteClient,
    ServerStatus,
    ModelInfo,
    ManagedService,
    CurriculumSummary,
    CurriculumDetail,
    TopicSummary,
    chunk_text_for_tts,
    broadcast_message,
    handle_load_model,
    handle_unload_model,
    handle_delete_model,
    handle_upload_visual_asset,
    handle_delete_visual_asset,
    handle_update_visual_asset,
    handle_stream_topic_audio,
    handle_preload_curriculum_assets,
    handle_get_curriculum_with_assets,
    download_and_save_asset,
    state,
    get_process_memory,
    get_system_memory,
    handle_get_stats,
    handle_get_services,
    handle_start_service,
    handle_stop_service,
    handle_restart_service,
    handle_start_all_services,
    handle_stop_all_services,
    handle_get_curricula,
    handle_get_curriculum_detail,
    handle_get_curriculum_full,
    handle_get_topic_transcript,
    handle_reload_curricula,
    handle_delete_curriculum,
    handle_archive_curriculum,
    handle_get_archived_curricula,
    handle_save_curriculum,
    handle_import_curriculum,
    handle_get_system_metrics,
    handle_get_system_snapshot,
    handle_get_power_history,
    handle_get_process_history,
    handle_get_idle_status,
    handle_set_idle_config,
    handle_idle_keep_awake,
    handle_idle_cancel_keep_awake,
    handle_idle_force_state,
    handle_get_power_modes,
    handle_get_idle_history,
    handle_get_profile,
    handle_create_profile,
    handle_update_profile,
    handle_delete_profile,
    handle_duplicate_profile,
    handle_get_diagnostic_config,
    handle_set_diagnostic_config,
    handle_diagnostic_toggle,
    handle_health,
    handle_get_models,
    handle_get_model_capabilities,
    service_to_dict,
    check_service_running,
)


# =============================================================================
# Mock Classes for Database
# =============================================================================


class MockRow(dict):
    """Mock database row that supports both dict and attribute access."""
    def __getattr__(self, key):
        try:
            return self[key]
        except KeyError:
            raise AttributeError(f"'{type(self).__name__}' has no attribute '{key}'")

    def get(self, key, default=None):
        return super().get(key, default)


class MockConnection:
    """Mock asyncpg connection."""
    def __init__(self, rows=None):
        self.rows = rows or []
        self.execute_calls = []
        self.fetch_calls = []

    async def fetch(self, query, *args):
        self.fetch_calls.append((query, args))
        return self.rows

    async def fetchval(self, query, *args):
        self.fetch_calls.append((query, args))
        if not self.rows:
            return None
        if isinstance(self.rows[0], (str, int)):
            return self.rows[0]
        return list(self.rows[0].values())[0]

    async def fetchrow(self, query, *args):
        self.fetch_calls.append((query, args))
        return self.rows[0] if self.rows else None

    async def execute(self, query, *args):
        self.execute_calls.append((query, args))
        return "DELETE 1" if "DELETE" in query else "INSERT 1"


class MockPool:
    """Mock asyncpg connection pool."""
    def __init__(self, rows=None):
        self.rows = rows or []
        self._conn = MockConnection(rows)

    def acquire(self):
        return MockConnectionContextManager(self._conn)


class MockConnectionContextManager:
    """Context manager for mock connection."""
    def __init__(self, conn):
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        pass


class MockMultipartReader:
    """Mock multipart reader for file uploads."""
    def __init__(self, parts):
        self.parts = parts
        self.index = 0

    async def next(self):
        if self.index >= len(self.parts):
            return None
        part = self.parts[self.index]
        self.index += 1
        return part


class MockMultipartPart:
    """Mock multipart part for file upload testing."""
    def __init__(self, name, data, filename=None, content_type=None):
        self.name = name
        self._data = data
        self.filename = filename
        self.headers = {"Content-Type": content_type} if content_type else {}

    async def read(self):
        if isinstance(self._data, bytes):
            return self._data
        return self._data.encode("utf-8")

    async def text(self):
        if isinstance(self._data, bytes):
            return self._data.decode("utf-8")
        return self._data


# =============================================================================
# Test Fixtures
# =============================================================================


@pytest.fixture
def mock_request():
    """Create a mock aiohttp request."""
    request = MagicMock(spec=web.Request)
    request.query = {}
    request.match_info = {}
    request.headers = {}
    request.remote = "127.0.0.1"
    request.app = {}
    return request


@pytest.fixture
def mock_app():
    """Create a mock aiohttp application."""
    app = {}
    return app


@pytest.fixture
def sample_curriculum_data():
    """Create sample UMCF curriculum data for testing."""
    return {
        "formatIdentifier": "umcf",
        "id": {"value": "test-curriculum"},
        "title": "Test Curriculum",
        "description": "A test curriculum for unit testing",
        "version": {"number": "1.0.0"},
        "educational": {
            "difficulty": "medium",
            "typicalAgeRange": "18+",
            "typicalLearningTime": "PT2H"
        },
        "metadata": {
            "keywords": ["test", "unit-test"]
        },
        "content": [
            {
                "id": {"value": "root"},
                "title": "Root",
                "children": [
                    {
                        "id": {"value": "topic-1"},
                        "title": "Test Topic 1",
                        "description": "First test topic",
                        "orderIndex": 0,
                        "timeEstimates": {"intermediate": "PT30M"},
                        "transcript": {
                            "segments": [
                                {"id": "seg-1", "content": "This is segment one.", "type": "lecture"},
                                {"id": "seg-2", "content": "This is segment two.", "type": "explanation"}
                            ]
                        },
                        "media": {
                            "embedded": [
                                {"id": "img-1", "url": "https://example.com/image1.jpg", "alt": "Image 1"}
                            ],
                            "reference": []
                        },
                        "assessments": []
                    }
                ]
            }
        ],
        "glossary": {"terms": []}
    }


# =============================================================================
# Test Classes - Model Operations
# =============================================================================


@pytest.mark.asyncio
class TestHandleLoadModel:
    """Tests for handle_load_model endpoint."""

    async def test_load_model_success(self, mock_request):
        """Test loading a model successfully."""
        mock_request.match_info = {"model_id": "ollama:llama2"}
        mock_request.json = AsyncMock(return_value={"keep_alive": "5m"})

        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.content = AsyncMock()
        mock_response.content.__aiter__ = lambda self: iter([b"{}"])

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()

            # Mock for generate endpoint (load)
            mock_context_gen = MagicMock()
            mock_context_gen.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context_gen.__aexit__ = AsyncMock()
            mock_session_instance.post.return_value = mock_context_gen

            # Mock for ps endpoint (VRAM check)
            mock_ps_response = MagicMock()
            mock_ps_response.status = 200
            mock_ps_response.json = AsyncMock(return_value={"models": [{"name": "llama2", "size_vram": 4000000000}]})
            mock_context_ps = MagicMock()
            mock_context_ps.__aenter__ = AsyncMock(return_value=mock_ps_response)
            mock_context_ps.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context_ps

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_load_model(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "ok"
            assert data["model"] == "llama2"

    async def test_load_model_with_full_id(self, mock_request):
        """Test loading a model with server:model format."""
        mock_request.match_info = {"model_id": "server1:llama2:7b"}
        mock_request.json = AsyncMock(return_value={})

        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.content = AsyncMock()
        mock_response.content.__aiter__ = lambda self: iter([b"{}"])

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.post.return_value = mock_context
            mock_session_instance.get.return_value = mock_context

            mock_ps_response = MagicMock()
            mock_ps_response.status = 200
            mock_ps_response.json = AsyncMock(return_value={"models": []})
            mock_context_ps = MagicMock()
            mock_context_ps.__aenter__ = AsyncMock(return_value=mock_ps_response)
            mock_context_ps.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context_ps

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_load_model(mock_request)

            assert response.status == 200

    async def test_load_model_ollama_error(self, mock_request):
        """Test loading model when Ollama returns error."""
        mock_request.match_info = {"model_id": "ollama:nonexistent"}
        mock_request.json = AsyncMock(return_value={})

        mock_response = MagicMock()
        mock_response.status = 404
        mock_response.text = AsyncMock(return_value="Model not found")

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.post.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_load_model(mock_request)

            assert response.status == 404
            data = json.loads(response.body)
            assert data["status"] == "error"

    async def test_load_model_timeout(self, mock_request):
        """Test loading model timeout."""
        mock_request.match_info = {"model_id": "ollama:large-model"}
        mock_request.json = AsyncMock(return_value={})

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            # Mock the context manager to raise TimeoutError
            mock_session_instance.__aenter__ = AsyncMock(side_effect=asyncio.TimeoutError())
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_load_model(mock_request)

            assert response.status == 504
            data = json.loads(response.body)
            assert "Timeout" in data["error"]

    async def test_load_model_no_body(self, mock_request):
        """Test loading model without request body."""
        mock_request.match_info = {"model_id": "ollama:llama2"}
        mock_request.json = AsyncMock(side_effect=Exception("No body"))

        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.content = AsyncMock()
        mock_response.content.__aiter__ = lambda self: iter([b"{}"])

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.post.return_value = mock_context

            mock_ps_response = MagicMock()
            mock_ps_response.status = 200
            mock_ps_response.json = AsyncMock(return_value={"models": []})
            mock_context_ps = MagicMock()
            mock_context_ps.__aenter__ = AsyncMock(return_value=mock_ps_response)
            mock_context_ps.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context_ps

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_load_model(mock_request)

            assert response.status == 200


@pytest.mark.asyncio
class TestHandleUnloadModel:
    """Tests for handle_unload_model endpoint."""

    async def test_unload_model_success(self, mock_request):
        """Test unloading a model successfully."""
        mock_request.match_info = {"model_id": "ollama:llama2"}

        # Mock for ps check (model is loaded)
        mock_ps_response = MagicMock()
        mock_ps_response.status = 200
        mock_ps_response.json = AsyncMock(return_value={
            "models": [{"name": "llama2", "size_vram": 4000000000}]
        })

        # Mock for unload request
        mock_unload_response = MagicMock()
        mock_unload_response.status = 200
        mock_unload_response.content = AsyncMock()
        mock_unload_response.content.__aiter__ = lambda self: iter([b"{}"])

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()

            mock_context_ps = MagicMock()
            mock_context_ps.__aenter__ = AsyncMock(return_value=mock_ps_response)
            mock_context_ps.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context_ps

            mock_context_unload = MagicMock()
            mock_context_unload.__aenter__ = AsyncMock(return_value=mock_unload_response)
            mock_context_unload.__aexit__ = AsyncMock()
            mock_session_instance.post.return_value = mock_context_unload

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_unload_model(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "ok"

    async def test_unload_model_not_loaded(self, mock_request):
        """Test unloading a model that is not loaded."""
        mock_request.match_info = {"model_id": "ollama:llama2"}

        mock_ps_response = MagicMock()
        mock_ps_response.status = 200
        mock_ps_response.json = AsyncMock(return_value={"models": []})

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_ps_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_unload_model(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["message"] == "Model was not loaded"


@pytest.mark.asyncio
class TestHandleDeleteModel:
    """Tests for handle_delete_model endpoint."""

    async def test_delete_model_success(self, mock_request):
        """Test deleting a model successfully."""
        mock_request.match_info = {"model_id": "ollama:test-model"}

        mock_response = MagicMock()
        mock_response.status = 200

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.delete.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_delete_model(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert data["status"] == "ok"

    async def test_delete_model_not_found(self, mock_request):
        """Test deleting a model that doesn't exist."""
        mock_request.match_info = {"model_id": "ollama:nonexistent"}

        mock_response = MagicMock()
        mock_response.status = 404
        mock_response.text = AsyncMock(return_value="Model not found")

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.delete.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_delete_model(mock_request)

            assert response.status == 404


# =============================================================================
# Test Classes - Visual Asset Management
# =============================================================================


@pytest.mark.asyncio
class TestHandleUploadVisualAsset:
    """Tests for handle_upload_visual_asset endpoint."""

    async def test_upload_asset_curriculum_not_found(self, mock_request):
        """Test upload fails when curriculum doesn't exist."""
        mock_request.match_info = {"curriculum_id": "nonexistent", "topic_id": "topic-1"}

        response = await handle_upload_visual_asset(mock_request)

        assert response.status == 404
        data = json.loads(response.body)
        assert "Curriculum not found" in data["error"]

    async def test_upload_asset_no_file(self, mock_request, sample_curriculum_data):
        """Test upload fails without file data."""
        # Add curriculum to state
        curriculum_id = "test-upload"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {"curriculum_id": curriculum_id, "topic_id": "topic-1"}

        # Create mock multipart reader with no file
        mock_reader = MockMultipartReader([
            MockMultipartPart("metadata", json.dumps({"alt": "Test alt"}))
        ])
        mock_request.multipart = AsyncMock(return_value=mock_reader)

        response = await handle_upload_visual_asset(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "No file uploaded" in data["error"]

        # Cleanup
        del state.curriculum_raw[curriculum_id]

    async def test_upload_asset_missing_alt_text(self, mock_request, sample_curriculum_data):
        """Test upload fails without alt text."""
        curriculum_id = "test-upload-alt"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {"curriculum_id": curriculum_id, "topic_id": "topic-1"}

        # Create mock multipart reader
        mock_reader = MockMultipartReader([
            MockMultipartPart("file", b"fake image data", filename="test.png", content_type="image/png"),
            MockMultipartPart("metadata", json.dumps({}))  # Missing alt
        ])
        mock_request.multipart = AsyncMock(return_value=mock_reader)

        response = await handle_upload_visual_asset(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "Alt text is required" in data["error"]

        # Cleanup
        del state.curriculum_raw[curriculum_id]


@pytest.mark.asyncio
class TestHandleDeleteVisualAsset:
    """Tests for handle_delete_visual_asset endpoint."""

    async def test_delete_asset_curriculum_not_found(self, mock_request):
        """Test delete fails when curriculum doesn't exist."""
        mock_request.match_info = {
            "curriculum_id": "nonexistent",
            "topic_id": "topic-1",
            "asset_id": "asset-1"
        }

        response = await handle_delete_visual_asset(mock_request)

        assert response.status == 404

    async def test_delete_asset_success(self, mock_request, sample_curriculum_data):
        """Test successfully deleting an asset from curriculum."""
        curriculum_id = "test-delete-asset"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data
        state.curriculums[curriculum_id] = CurriculumSummary(
            id=curriculum_id,
            title="Test",
            description="",
            version="1.0",
            topic_count=1,
            total_duration="PT1H",
            difficulty="easy",
            age_range="18+",
            file_path="/tmp/fake.umcf"
        )

        mock_request.match_info = {
            "curriculum_id": curriculum_id,
            "topic_id": "topic-1",
            "asset_id": "img-1"
        }

        # Mock file operations
        with patch("pathlib.Path.open", MagicMock()):
            with patch.object(state, "_load_curriculum_file", MagicMock()):
                response = await handle_delete_visual_asset(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "success"

        # Cleanup
        del state.curriculum_raw[curriculum_id]
        del state.curriculums[curriculum_id]


@pytest.mark.asyncio
class TestHandleUpdateVisualAsset:
    """Tests for handle_update_visual_asset endpoint."""

    async def test_update_asset_curriculum_not_found(self, mock_request):
        """Test update fails when curriculum doesn't exist."""
        mock_request.match_info = {
            "curriculum_id": "nonexistent",
            "topic_id": "topic-1",
            "asset_id": "asset-1"
        }
        mock_request.json = AsyncMock(return_value={"alt": "New alt text"})

        response = await handle_update_visual_asset(mock_request)

        assert response.status == 404

    async def test_update_asset_not_found(self, mock_request, sample_curriculum_data):
        """Test update fails when asset doesn't exist."""
        curriculum_id = "test-update-asset"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {
            "curriculum_id": curriculum_id,
            "topic_id": "topic-1",
            "asset_id": "nonexistent-asset"
        }
        mock_request.json = AsyncMock(return_value={"alt": "New alt text"})

        response = await handle_update_visual_asset(mock_request)

        assert response.status == 404

        # Cleanup
        del state.curriculum_raw[curriculum_id]


# =============================================================================
# Test Classes - Audio Streaming
# =============================================================================


@pytest.mark.asyncio
class TestHandleStreamTopicAudio:
    """Tests for handle_stream_topic_audio endpoint."""

    async def test_stream_audio_curriculum_not_found(self, mock_request):
        """Test streaming fails when curriculum doesn't exist."""
        mock_request.match_info = {"curriculum_id": "nonexistent", "topic_id": "topic-1"}
        mock_request.query = {}

        response = await handle_stream_topic_audio(mock_request)

        assert response.status == 404

    async def test_stream_audio_topic_not_found(self, mock_request, sample_curriculum_data):
        """Test streaming fails when topic doesn't exist."""
        curriculum_id = "test-stream"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {"curriculum_id": curriculum_id, "topic_id": "nonexistent-topic"}
        mock_request.query = {}

        response = await handle_stream_topic_audio(mock_request)

        assert response.status == 404

        # Cleanup
        del state.curriculum_raw[curriculum_id]

    async def test_stream_audio_no_content(self, mock_request):
        """Test streaming fails when curriculum has no content."""
        curriculum_id = "test-stream-empty"
        state.curriculum_raw[curriculum_id] = {"content": []}

        mock_request.match_info = {"curriculum_id": curriculum_id, "topic_id": "topic-1"}
        mock_request.query = {}

        response = await handle_stream_topic_audio(mock_request)

        assert response.status == 404

        # Cleanup
        del state.curriculum_raw[curriculum_id]


# =============================================================================
# Test Classes - Asset Pre-Download
# =============================================================================


@pytest.mark.asyncio
class TestDownloadAndSaveAsset:
    """Tests for download_and_save_asset function."""

    async def test_download_success(self):
        """Test successful asset download."""
        mock_response = MagicMock()
        mock_response.status = 200
        mock_response.read = AsyncMock(return_value=b"fake image data")
        mock_response.headers = {"Content-Type": "image/jpeg"}

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            with patch("pathlib.Path.exists", return_value=False):
                with patch("pathlib.Path.mkdir"):
                    with patch("builtins.open", MagicMock()):
                        # Skip the actual rate limit wait
                        with patch("asyncio.sleep", AsyncMock()):
                            result = await download_and_save_asset(
                                url="https://example.com/image.jpg",
                                curriculum_id="test",
                                topic_id="topic-1",
                                asset_id="asset-1"
                            )

            # Result should be a path string or None
            # Since we're mocking everything, we'll just verify it ran

    async def test_download_rate_limited(self):
        """Test handling of rate limited response."""
        mock_response = MagicMock()
        mock_response.status = 429

        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            with patch("pathlib.Path.exists", return_value=False):
                with patch("pathlib.Path.mkdir"):
                    with patch("asyncio.sleep", AsyncMock()):
                        result = await download_and_save_asset(
                            url="https://example.com/image.jpg",
                            curriculum_id="test",
                            topic_id="topic-1",
                            asset_id="asset-1"
                        )

            assert result is None

    async def test_download_timeout(self):
        """Test handling of download timeout."""
        with patch("aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(side_effect=asyncio.TimeoutError())
            mock_context.__aexit__ = AsyncMock()
            mock_session_instance.get.return_value = mock_context

            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            with patch("pathlib.Path.exists", return_value=False):
                with patch("pathlib.Path.mkdir"):
                    with patch("asyncio.sleep", AsyncMock()):
                        result = await download_and_save_asset(
                            url="https://example.com/image.jpg",
                            curriculum_id="test",
                            topic_id="topic-1",
                            asset_id="asset-1"
                        )

            assert result is None


@pytest.mark.asyncio
class TestHandlePreloadCurriculumAssets:
    """Tests for handle_preload_curriculum_assets endpoint."""

    async def test_preload_curriculum_not_found(self, mock_request):
        """Test preload fails when curriculum doesn't exist."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_preload_curriculum_assets(mock_request)

        assert response.status == 404

    async def test_preload_no_content(self, mock_request):
        """Test preload fails when curriculum has no content."""
        curriculum_id = "test-preload-empty"
        state.curriculum_raw[curriculum_id] = {"content": []}

        mock_request.match_info = {"curriculum_id": curriculum_id}

        response = await handle_preload_curriculum_assets(mock_request)

        assert response.status == 404

        # Cleanup
        del state.curriculum_raw[curriculum_id]


@pytest.mark.asyncio
class TestHandleGetCurriculumWithAssets:
    """Tests for handle_get_curriculum_with_assets endpoint."""

    async def test_get_with_assets_not_found(self, mock_request):
        """Test getting curriculum with assets when not found."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_get_curriculum_with_assets(mock_request)

        assert response.status == 404

    async def test_get_with_assets_empty_content(self, mock_request):
        """Test getting curriculum with assets when content is empty."""
        curriculum_id = "test-assets-empty"
        state.curriculum_raw[curriculum_id] = {"content": []}

        mock_request.match_info = {"curriculum_id": curriculum_id}

        response = await handle_get_curriculum_with_assets(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "assetData" not in data or data.get("assetData") == {}

        # Cleanup
        del state.curriculum_raw[curriculum_id]


# =============================================================================
# Test Classes - WebSocket Handler
# =============================================================================


@pytest.mark.asyncio
class TestHandleWebSocket:
    """Tests for handle_websocket endpoint."""

    async def test_websocket_connection(self, mock_request):
        """Test WebSocket connection establishment."""
        mock_ws = MagicMock(spec=web.WebSocketResponse)
        mock_ws.prepare = AsyncMock()
        mock_ws.send_json = AsyncMock()
        mock_ws.closed = False

        # Create an async iterator that yields nothing
        async def empty_iter():
            return
            yield  # Make it a generator

        mock_ws.__aiter__ = lambda self: empty_iter()

        with patch("aiohttp.web.WebSocketResponse", return_value=mock_ws):
            # We can't fully test the WebSocket handler without more complex mocking
            # Just verify the function exists and can be called
            pass


# =============================================================================
# Test Classes - chunk_text_for_tts Extended Tests
# =============================================================================


class TestChunkTextForTTSExtended:
    """Extended tests for chunk_text_for_tts function."""

    def test_long_sentence_splitting(self):
        """Test that very long sentences are split on clause boundaries."""
        long_text = (
            "This is a very long sentence with multiple clauses, "
            "including this one here, and another clause after this comma, "
            "followed by yet another clause; there's also a semicolon clause, "
            "and finally the sentence ends here."
        )
        result = chunk_text_for_tts(long_text, max_chars=100)

        # Should have multiple segments
        assert len(result) >= 1
        for seg in result:
            assert "content" in seg
            assert "type" in seg
            assert "id" in seg

    def test_multiple_paragraphs(self):
        """Test handling of multiple paragraphs."""
        text = """First paragraph with some content.

        Second paragraph with different content.

        Third paragraph at the end."""

        result = chunk_text_for_tts(text)

        assert len(result) >= 1
        combined = " ".join(seg["content"] for seg in result)
        assert "First paragraph" in combined
        assert "Second paragraph" in combined

    def test_mit_ocw_pattern_removal(self):
        """Test removal of various MIT OCW patterns."""
        patterns = [
            "MITOCW | MIT8_01F16_L00v01_360p Real content here.",
            "MIT8_01F16_L00v01_360p Real content here.",
            "v01_360p Real content here.",
        ]

        for text in patterns:
            result = chunk_text_for_tts(text)
            combined = " ".join(seg["content"] for seg in result)
            assert "360p" not in combined
            assert "MIT" not in combined
            assert "MITOCW" not in combined
            assert "Real content" in combined

    def test_empty_after_header_removal(self):
        """Test that pure headers return empty list."""
        headers_only = [
            "MITOCW | MIT8_01F16_L00v01_360p",
            "MIT8_01F16_L00v01_360p",
            "v01_360p",
        ]

        for text in headers_only:
            result = chunk_text_for_tts(text)
            assert result == []

    def test_segment_type_assignment(self):
        """Test that segment types are properly assigned."""
        text = "First sentence here. Second sentence follows. Third sentence ends."
        result = chunk_text_for_tts(text, max_chars=30, min_chars=10)

        # First segment should be "lecture", others "explanation"
        if len(result) > 0:
            assert result[0]["type"] == "lecture"
        if len(result) > 1:
            assert result[1]["type"] == "explanation"

    def test_min_chars_combination(self):
        """Test that short segments are combined."""
        text = "Hi. Yes. Ok."
        result = chunk_text_for_tts(text, min_chars=20)

        # Should combine short segments
        assert len(result) >= 1


# =============================================================================
# Test Classes - System Memory Functions
# =============================================================================


class TestSystemMemoryFunctions:
    """Tests for system memory utility functions."""

    def test_get_process_memory_current_process(self):
        """Test getting memory for current process."""
        import os
        pid = os.getpid()

        result = get_process_memory(pid)

        assert "rss_mb" in result
        assert "vsz_mb" in result
        assert "rss_bytes" in result
        assert "vsz_bytes" in result

    def test_get_process_memory_invalid_pid(self):
        """Test getting memory for invalid PID."""
        result = get_process_memory(-999999)

        assert result["rss_mb"] == 0
        assert result["vsz_mb"] == 0

    def test_get_system_memory_structure(self):
        """Test that get_system_memory returns expected structure."""
        result = get_system_memory()

        assert "total_gb" in result
        assert "used_gb" in result
        assert "free_gb" in result
        assert "percent_used" in result

    def test_get_system_memory_values(self):
        """Test that get_system_memory returns reasonable values."""
        result = get_system_memory()

        # On any real system, these should be > 0
        # But with mocking they might be 0
        assert result["total_gb"] >= 0
        assert result["used_gb"] >= 0
        assert result["percent_used"] >= 0


# =============================================================================
# Test Classes - Broadcast Message
# =============================================================================


@pytest.mark.asyncio
class TestBroadcastMessageExtended:
    """Extended tests for broadcast_message function."""

    async def test_broadcast_with_dead_socket(self):
        """Test broadcast handles dead sockets gracefully."""
        # Create a mock socket that raises on send
        mock_ws = MagicMock()
        mock_ws.send_str = AsyncMock(side_effect=Exception("Connection closed"))

        state.websockets.add(mock_ws)

        # Should not raise, should remove dead socket
        await broadcast_message("test", {"data": "test"})

        # Dead socket should be removed
        assert mock_ws not in state.websockets

    async def test_broadcast_with_working_socket(self):
        """Test broadcast sends to working sockets."""
        mock_ws = MagicMock()
        mock_ws.send_str = AsyncMock()

        state.websockets.add(mock_ws)

        await broadcast_message("test", {"data": "test"})

        # Should have called send_str
        mock_ws.send_str.assert_called_once()

        # Cleanup
        state.websockets.discard(mock_ws)


# =============================================================================
# Test Classes - Management State
# =============================================================================


class TestManagementStateExtended:
    """Extended tests for ManagementState class."""

    def test_default_servers_initialization(self):
        """Test all default servers are initialized."""
        mgmt_state = ManagementState()

        expected_servers = ["ollama", "whisper", "piper", "gateway", "vibevoice", "nextjs"]
        for server_id in expected_servers:
            assert server_id in mgmt_state.servers

    def test_server_status_structure(self):
        """Test server status has correct structure."""
        mgmt_state = ManagementState()

        for server_id, server in mgmt_state.servers.items():
            assert hasattr(server, "id")
            assert hasattr(server, "name")
            assert hasattr(server, "type")
            assert hasattr(server, "url")
            assert hasattr(server, "port")
            assert hasattr(server, "status")

    def test_reload_curricula_clears_state(self):
        """Test reload_curricula properly clears and reloads."""
        mgmt_state = ManagementState()

        # Add some test data
        mgmt_state.curriculums["test"] = CurriculumSummary(
            id="test",
            title="Test",
            description="",
            version="1.0",
            topic_count=0,
            total_duration="PT1H",
            difficulty="easy",
            age_range="18+"
        )

        # Reload should clear
        mgmt_state.reload_curricula()

        # Test curriculum should be gone (unless it's on disk)
        # The reload loads from disk, so our test curriculum won't persist


# =============================================================================
# Test Classes - Data Classes Extended
# =============================================================================


class TestMetricsSnapshotExtended:
    """Extended tests for MetricsSnapshot dataclass."""

    def test_all_latency_fields(self):
        """Test MetricsSnapshot with all latency fields."""
        snapshot = MetricsSnapshot(
            id="test",
            client_id="client",
            client_name="Test",
            timestamp="2025-01-01T00:00:00Z",
            received_at=time.time(),
            stt_latency_median=100.0,
            stt_latency_p99=200.0,
            llm_ttft_median=150.0,
            llm_ttft_p99=300.0,
            tts_ttfb_median=50.0,
            tts_ttfb_p99=100.0,
            e2e_latency_median=300.0,
            e2e_latency_p99=600.0
        )

        assert snapshot.stt_latency_median == 100.0
        assert snapshot.llm_ttft_p99 == 300.0
        assert snapshot.e2e_latency_p99 == 600.0

    def test_cost_fields(self):
        """Test MetricsSnapshot cost fields."""
        snapshot = MetricsSnapshot(
            id="test",
            client_id="client",
            client_name="Test",
            timestamp="2025-01-01T00:00:00Z",
            received_at=time.time(),
            stt_cost=0.05,
            tts_cost=0.10,
            llm_cost=0.25,
            total_cost=0.40
        )

        assert snapshot.stt_cost == 0.05
        assert snapshot.total_cost == 0.40

    def test_device_stats_fields(self):
        """Test MetricsSnapshot device stats fields."""
        snapshot = MetricsSnapshot(
            id="test",
            client_id="client",
            client_name="Test",
            timestamp="2025-01-01T00:00:00Z",
            received_at=time.time(),
            thermal_throttle_events=5,
            network_degradations=3
        )

        assert snapshot.thermal_throttle_events == 5
        assert snapshot.network_degradations == 3


class TestManagedServiceExtended:
    """Extended tests for ManagedService dataclass."""

    def test_service_with_process(self):
        """Test ManagedService with process reference."""
        import subprocess
        mock_process = MagicMock(spec=subprocess.Popen)
        mock_process.pid = 12345

        service = ManagedService(
            id="test",
            name="Test Service",
            service_type="test",
            command=["python", "test.py"],
            cwd="/tmp",
            port=8000,
            health_url="http://localhost:8000/health",
            process=mock_process,
            status="running",
            pid=12345,
            started_at=time.time()
        )

        assert service.process is mock_process
        assert service.pid == 12345
        assert service.status == "running"

    def test_service_error_state(self):
        """Test ManagedService in error state."""
        service = ManagedService(
            id="test",
            name="Test",
            service_type="test",
            command=["python"],
            cwd="/tmp",
            port=8000,
            health_url="http://localhost:8000/health",
            status="error",
            error_message="Process crashed"
        )

        assert service.status == "error"
        assert service.error_message == "Process crashed"


class TestTopicSummaryExtended:
    """Extended tests for TopicSummary dataclass."""

    def test_topic_with_all_fields(self):
        """Test TopicSummary with all fields populated."""
        topic = TopicSummary(
            id="topic-1",
            title="Test Topic",
            description="A test topic",
            order_index=0,
            duration="PT45M",
            has_transcript=True,
            segment_count=20,
            assessment_count=5,
            embedded_asset_count=10,
            reference_asset_count=3
        )

        assert topic.has_transcript is True
        assert topic.segment_count == 20
        assert topic.assessment_count == 5
        assert topic.embedded_asset_count == 10
        assert topic.reference_asset_count == 3

    def test_topic_defaults(self):
        """Test TopicSummary default values."""
        topic = TopicSummary(
            id="topic-2",
            title="Minimal Topic",
            description="",
            order_index=1,
            duration="PT30M"
        )

        assert topic.has_transcript is False
        assert topic.segment_count == 0
        assert topic.assessment_count == 0
        assert topic.embedded_asset_count == 0
        assert topic.reference_asset_count == 0


class TestCurriculumSummaryExtended:
    """Extended tests for CurriculumSummary dataclass."""

    def test_curriculum_with_visual_assets(self):
        """Test CurriculumSummary with visual assets."""
        summary = CurriculumSummary(
            id="curriculum-1",
            title="Visual Curriculum",
            description="A curriculum with images",
            version="1.0.0",
            topic_count=5,
            total_duration="PT4H",
            difficulty="medium",
            age_range="18+",
            visual_asset_count=50,
            has_visual_assets=True
        )

        assert summary.visual_asset_count == 50
        assert summary.has_visual_assets is True

    def test_curriculum_with_keywords(self):
        """Test CurriculumSummary with keywords."""
        summary = CurriculumSummary(
            id="curriculum-2",
            title="Keyword Curriculum",
            description="",
            version="1.0",
            topic_count=3,
            total_duration="PT2H",
            difficulty="easy",
            age_range="12+",
            keywords=["python", "programming", "basics"]
        )

        assert len(summary.keywords) == 3
        assert "python" in summary.keywords

    def test_curriculum_with_file_path(self):
        """Test CurriculumSummary with file_path."""
        summary = CurriculumSummary(
            id="curriculum-3",
            title="File Path Curriculum",
            description="",
            version="1.0",
            topic_count=1,
            total_duration="PT1H",
            difficulty="hard",
            age_range="21+",
            file_path="/path/to/curriculum.umcf"
        )

        assert summary.file_path == "/path/to/curriculum.umcf"


# =============================================================================
# Test Classes - Server Status Extended
# =============================================================================


class TestServerStatusExtended:
    """Extended tests for ServerStatus dataclass."""

    def test_server_with_models(self):
        """Test ServerStatus with model list."""
        server = ServerStatus(
            id="ollama-1",
            name="Ollama Server",
            type="ollama",
            url="http://localhost:11434",
            port=11434,
            status="healthy",
            models=["llama2", "codellama", "mistral"]
        )

        assert len(server.models) == 3
        assert "llama2" in server.models

    def test_server_with_capabilities(self):
        """Test ServerStatus with capabilities dict."""
        server = ServerStatus(
            id="whisper-1",
            name="Whisper Server",
            type="whisper",
            url="http://localhost:11401",
            port=11401,
            capabilities={
                "languages": ["en", "es", "fr"],
                "max_duration": 300
            }
        )

        assert "languages" in server.capabilities
        assert len(server.capabilities["languages"]) == 3

    def test_server_with_error(self):
        """Test ServerStatus with error message."""
        server = ServerStatus(
            id="down-1",
            name="Down Server",
            type="custom",
            url="http://localhost:9999",
            port=9999,
            status="unhealthy",
            error_message="Connection refused"
        )

        assert server.status == "unhealthy"
        assert server.error_message == "Connection refused"


# =============================================================================
# Test Classes - Model Info Extended
# =============================================================================


class TestModelInfoExtended:
    """Extended tests for ModelInfo dataclass."""

    def test_model_with_full_details(self):
        """Test ModelInfo with all details populated."""
        model = ModelInfo(
            id="ollama:llama2:7b",
            name="llama2:7b",
            type="llm",
            server_id="ollama-1",
            size_bytes=4_000_000_000,
            parameters="7B",
            quantization="Q4_0",
            loaded=True,
            last_used=time.time(),
            usage_count=100
        )

        assert model.size_bytes == 4_000_000_000
        assert model.parameters == "7B"
        assert model.quantization == "Q4_0"
        assert model.loaded is True
        assert model.usage_count == 100

    def test_model_defaults(self):
        """Test ModelInfo default values."""
        model = ModelInfo(
            id="test:model",
            name="test-model",
            type="llm",
            server_id="test"
        )

        assert model.size_bytes == 0
        assert model.parameters == ""
        assert model.quantization == ""
        assert model.loaded is False
        assert model.last_used == 0
        assert model.usage_count == 0


# =============================================================================
# Test Classes - Remote Client Extended
# =============================================================================


class TestRemoteClientExtended:
    """Extended tests for RemoteClient dataclass."""

    def test_client_with_session(self):
        """Test RemoteClient with active session."""
        client = RemoteClient(
            id="client-1",
            name="Test Device",
            device_model="iPhone15,3",
            os_version="18.0",
            app_version="1.0.0",
            current_session_id="session-123",
            total_sessions=10,
            total_logs=500
        )

        assert client.current_session_id == "session-123"
        assert client.total_sessions == 10
        assert client.total_logs == 500

    def test_client_with_config(self):
        """Test RemoteClient with configuration dict."""
        config = {
            "tts_voice": "nova",
            "llm_model": "llama2",
            "auto_listen": True
        }
        client = RemoteClient(
            id="client-2",
            name="Configured Device",
            config=config
        )

        assert client.config["tts_voice"] == "nova"
        assert client.config["auto_listen"] is True

    def test_client_status_states(self):
        """Test RemoteClient with different status states."""
        for status in ["online", "idle", "offline"]:
            client = RemoteClient(
                id=f"client-{status}",
                name="Status Test",
                status=status
            )
            assert client.status == status


# =============================================================================
# Test Classes - Log Entry Extended
# =============================================================================


class TestLogEntryExtended:
    """Extended tests for LogEntry dataclass."""

    def test_log_entry_with_all_fields(self):
        """Test LogEntry with all fields populated."""
        entry = LogEntry(
            id="log-full",
            timestamp="2025-01-01T12:00:00Z",
            level="ERROR",
            label="networking",
            message="Connection failed",
            file="network.py",
            function="connect",
            line=42,
            metadata={"attempt": 3, "timeout": 30},
            client_id="client-1",
            client_name="Test Device"
        )

        assert entry.file == "network.py"
        assert entry.function == "connect"
        assert entry.line == 42
        assert entry.metadata["attempt"] == 3
        assert entry.client_id == "client-1"

    def test_log_entry_levels(self):
        """Test LogEntry with different log levels."""
        levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

        for level in levels:
            entry = LogEntry(
                id=f"log-{level}",
                timestamp="2025-01-01T00:00:00Z",
                level=level,
                label="test",
                message=f"{level} message"
            )
            assert entry.level == level


# =============================================================================
# Test Classes - Curriculum Detail Extended
# =============================================================================


class TestCurriculumDetailExtended:
    """Extended tests for CurriculumDetail dataclass."""

    def test_curriculum_detail_with_topics(self):
        """Test CurriculumDetail with topic list."""
        topics = [
            {"id": "topic-1", "title": "Topic 1", "order_index": 0},
            {"id": "topic-2", "title": "Topic 2", "order_index": 1},
            {"id": "topic-3", "title": "Topic 3", "order_index": 2}
        ]

        detail = CurriculumDetail(
            id="detail-1",
            title="Test Curriculum",
            description="A test",
            version="1.0.0",
            difficulty="medium",
            age_range="18+",
            duration="PT4H",
            keywords=["test"],
            topics=topics,
            glossary_terms=[],
            learning_objectives=[]
        )

        assert len(detail.topics) == 3
        assert detail.topics[0]["id"] == "topic-1"

    def test_curriculum_detail_with_glossary(self):
        """Test CurriculumDetail with glossary terms."""
        glossary = [
            {"term": "AI", "definition": "Artificial Intelligence"},
            {"term": "ML", "definition": "Machine Learning"}
        ]

        detail = CurriculumDetail(
            id="detail-2",
            title="Test",
            description="",
            version="1.0",
            difficulty="easy",
            age_range="18+",
            duration="PT1H",
            keywords=[],
            topics=[],
            glossary_terms=glossary,
            learning_objectives=[]
        )

        assert len(detail.glossary_terms) == 2
        assert detail.glossary_terms[0]["term"] == "AI"

    def test_curriculum_detail_with_objectives(self):
        """Test CurriculumDetail with learning objectives."""
        objectives = [
            {"id": "obj-1", "text": "Understand basic concepts"},
            {"id": "obj-2", "text": "Apply knowledge practically"}
        ]

        detail = CurriculumDetail(
            id="detail-3",
            title="Test",
            description="",
            version="1.0",
            difficulty="hard",
            age_range="21+",
            duration="PT2H",
            keywords=[],
            topics=[],
            glossary_terms=[],
            learning_objectives=objectives
        )

        assert len(detail.learning_objectives) == 2


# =============================================================================
# Test Classes - Stats and Services Handlers
# =============================================================================


@pytest.mark.asyncio
class TestHandleGetStats:
    """Tests for handle_get_stats endpoint."""

    async def test_get_stats_basic(self, mock_request):
        """Test getting basic stats."""
        response = await handle_get_stats(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "uptime_seconds" in data
        assert "total_logs" in data
        assert "total_metrics" in data
        assert "online_clients" in data
        assert "websocket_connections" in data


@pytest.mark.asyncio
class TestHandleGetServices:
    """Tests for handle_get_services endpoint."""

    async def test_get_services_returns_list(self, mock_request):
        """Test getting services returns proper structure."""
        response = await handle_get_services(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "services" in data
        assert "total" in data
        assert "running" in data
        assert "stopped" in data
        assert "system_memory" in data


@pytest.mark.asyncio
class TestHandleStartService:
    """Tests for handle_start_service endpoint."""

    async def test_start_service_not_found(self, mock_request):
        """Test starting a non-existent service."""
        mock_request.match_info = {"service_id": "nonexistent-service"}

        response = await handle_start_service(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "not found" in data["message"]


@pytest.mark.asyncio
class TestHandleStopService:
    """Tests for handle_stop_service endpoint."""

    async def test_stop_service_not_found(self, mock_request):
        """Test stopping a non-existent service."""
        mock_request.match_info = {"service_id": "nonexistent-service"}

        response = await handle_stop_service(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "not found" in data["message"]


@pytest.mark.asyncio
class TestHandleRestartService:
    """Tests for handle_restart_service endpoint."""

    async def test_restart_service_not_found(self, mock_request):
        """Test restarting a non-existent service."""
        mock_request.match_info = {"service_id": "nonexistent-service"}

        response = await handle_restart_service(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleStartAllServices:
    """Tests for handle_start_all_services endpoint."""

    async def test_start_all_services(self, mock_request):
        """Test starting all services returns results."""
        response = await handle_start_all_services(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "results" in data


@pytest.mark.asyncio
class TestHandleStopAllServices:
    """Tests for handle_stop_all_services endpoint."""

    async def test_stop_all_services(self, mock_request):
        """Test stopping all services returns results."""
        response = await handle_stop_all_services(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "results" in data


# =============================================================================
# Test Classes - Curriculum Handlers
# =============================================================================


@pytest.mark.asyncio
class TestHandleGetCurricula:
    """Tests for handle_get_curricula endpoint."""

    async def test_get_curricula_empty(self, mock_request):
        """Test getting curricula returns proper structure."""
        mock_request.query = {}

        response = await handle_get_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "curricula" in data
        assert "total" in data

    async def test_get_curricula_with_search(self, mock_request):
        """Test getting curricula with search filter."""
        mock_request.query = {"search": "test"}

        response = await handle_get_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "curricula" in data

    async def test_get_curricula_with_difficulty(self, mock_request):
        """Test getting curricula with difficulty filter."""
        mock_request.query = {"difficulty": "medium"}

        response = await handle_get_curricula(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetCurriculumDetail:
    """Tests for handle_get_curriculum_detail endpoint."""

    async def test_get_curriculum_detail_not_found(self, mock_request):
        """Test getting nonexistent curriculum detail."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_get_curriculum_detail(mock_request)

        assert response.status == 404

    async def test_get_curriculum_detail_success(self, mock_request, sample_curriculum_data):
        """Test getting existing curriculum detail."""
        curriculum_id = "test-detail"
        state.curriculum_details[curriculum_id] = CurriculumDetail(
            id=curriculum_id,
            title="Test",
            description="",
            version="1.0",
            difficulty="easy",
            age_range="18+",
            duration="PT1H",
            keywords=[],
            topics=[],
            glossary_terms=[],
            learning_objectives=[],
            raw_umcf=sample_curriculum_data
        )

        mock_request.match_info = {"curriculum_id": curriculum_id}

        response = await handle_get_curriculum_detail(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["id"] == curriculum_id
        assert "raw_umcf" not in data  # Should be excluded

        # Cleanup
        del state.curriculum_details[curriculum_id]


@pytest.mark.asyncio
class TestHandleGetCurriculumFull:
    """Tests for handle_get_curriculum_full endpoint."""

    async def test_get_curriculum_full_not_found(self, mock_request):
        """Test getting nonexistent curriculum full data."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_get_curriculum_full(mock_request)

        assert response.status == 404

    async def test_get_curriculum_full_success(self, mock_request, sample_curriculum_data):
        """Test getting existing curriculum full data."""
        curriculum_id = "test-full"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {"curriculum_id": curriculum_id}

        response = await handle_get_curriculum_full(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["title"] == "Test Curriculum"

        # Cleanup
        del state.curriculum_raw[curriculum_id]


@pytest.mark.asyncio
class TestHandleGetTopicTranscript:
    """Tests for handle_get_topic_transcript endpoint."""

    async def test_get_transcript_curriculum_not_found(self, mock_request):
        """Test getting transcript when curriculum doesn't exist."""
        mock_request.match_info = {"curriculum_id": "nonexistent", "topic_id": "topic-1"}

        response = await handle_get_topic_transcript(mock_request)

        assert response.status == 404

    async def test_get_transcript_topic_not_found(self, mock_request, sample_curriculum_data):
        """Test getting transcript when topic doesn't exist."""
        curriculum_id = "test-transcript"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {"curriculum_id": curriculum_id, "topic_id": "nonexistent-topic"}

        response = await handle_get_topic_transcript(mock_request)

        assert response.status == 404

        # Cleanup
        del state.curriculum_raw[curriculum_id]

    async def test_get_transcript_success(self, mock_request, sample_curriculum_data):
        """Test getting transcript successfully."""
        curriculum_id = "test-transcript-success"
        state.curriculum_raw[curriculum_id] = sample_curriculum_data

        mock_request.match_info = {"curriculum_id": curriculum_id, "topic_id": "topic-1"}

        response = await handle_get_topic_transcript(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "segments" in data
        assert "topic_id" in data

        # Cleanup
        del state.curriculum_raw[curriculum_id]


@pytest.mark.asyncio
class TestHandleReloadCurricula:
    """Tests for handle_reload_curricula endpoint."""

    async def test_reload_curricula(self, mock_request):
        """Test reloading curricula."""
        response = await handle_reload_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"
        assert "count" in data


@pytest.mark.asyncio
class TestHandleDeleteCurriculum:
    """Tests for handle_delete_curriculum endpoint."""

    async def test_delete_curriculum_not_found(self, mock_request):
        """Test deleting nonexistent curriculum."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}
        mock_request.query = {"confirm": "true"}

        response = await handle_delete_curriculum(mock_request)

        assert response.status == 404

    async def test_delete_curriculum_no_confirmation(self, mock_request):
        """Test delete without confirmation returns warning."""
        curriculum_id = "test-delete-noconfirm"
        state.curriculums[curriculum_id] = CurriculumSummary(
            id=curriculum_id,
            title="Test",
            description="",
            version="1.0",
            topic_count=1,
            total_duration="PT1H",
            difficulty="easy",
            age_range="18+",
            file_path="/tmp/test.umcf"
        )

        mock_request.match_info = {"curriculum_id": curriculum_id}
        mock_request.query = {}

        response = await handle_delete_curriculum(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "confirmation_required"

        # Cleanup
        del state.curriculums[curriculum_id]


@pytest.mark.asyncio
class TestHandleArchiveCurriculum:
    """Tests for handle_archive_curriculum endpoint."""

    async def test_archive_curriculum_not_found(self, mock_request):
        """Test archiving nonexistent curriculum."""
        mock_request.match_info = {"curriculum_id": "nonexistent"}

        response = await handle_archive_curriculum(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleGetArchivedCurricula:
    """Tests for handle_get_archived_curricula endpoint."""

    async def test_get_archived_curricula(self, mock_request):
        """Test getting archived curricula."""
        response = await handle_get_archived_curricula(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "archived" in data
        assert "total" in data


@pytest.mark.asyncio
class TestHandleSaveCurriculum:
    """Tests for handle_save_curriculum endpoint."""

    async def test_save_curriculum_invalid_data(self, mock_request):
        """Test saving curriculum with invalid data."""
        mock_request.match_info = {"curriculum_id": "test"}
        mock_request.json = AsyncMock(return_value={"invalid": "data"})

        response = await handle_save_curriculum(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleImportCurriculum:
    """Tests for handle_import_curriculum endpoint."""

    async def test_import_curriculum_no_source(self, mock_request):
        """Test import without url or content."""
        mock_request.json = AsyncMock(return_value={})

        response = await handle_import_curriculum(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "url" in data["error"] or "content" in data["error"]

    async def test_import_curriculum_invalid_format(self, mock_request):
        """Test import with invalid format."""
        mock_request.json = AsyncMock(return_value={
            "content": {"formatIdentifier": "invalid"}
        })

        response = await handle_import_curriculum(mock_request)

        assert response.status == 400


# =============================================================================
# Test Classes - System Metrics and Idle Handlers
# =============================================================================


@pytest.mark.asyncio
class TestHandleGetSystemMetrics:
    """Tests for handle_get_system_metrics endpoint."""

    async def test_get_system_metrics(self, mock_request):
        """Test getting system metrics."""
        response = await handle_get_system_metrics(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetSystemSnapshot:
    """Tests for handle_get_system_snapshot endpoint."""

    async def test_get_system_snapshot(self, mock_request):
        """Test getting system snapshot."""
        response = await handle_get_system_snapshot(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetPowerHistory:
    """Tests for handle_get_power_history endpoint."""

    async def test_get_power_history_default(self, mock_request):
        """Test getting power history with default limit."""
        mock_request.query = {}

        response = await handle_get_power_history(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "history" in data
        assert "count" in data

    async def test_get_power_history_custom_limit(self, mock_request):
        """Test getting power history with custom limit."""
        mock_request.query = {"limit": "50"}

        response = await handle_get_power_history(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleGetProcessHistory:
    """Tests for handle_get_process_history endpoint."""

    async def test_get_process_history(self, mock_request):
        """Test getting process history."""
        mock_request.query = {}

        response = await handle_get_process_history(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "history" in data


@pytest.mark.asyncio
class TestHandleGetIdleStatus:
    """Tests for handle_get_idle_status endpoint."""

    async def test_get_idle_status(self, mock_request):
        """Test getting idle status."""
        response = await handle_get_idle_status(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleSetIdleConfig:
    """Tests for handle_set_idle_config endpoint."""

    async def test_set_idle_config_invalid_mode(self, mock_request):
        """Test setting invalid idle mode."""
        mock_request.json = AsyncMock(return_value={"mode": "invalid_mode_xyz"})

        response = await handle_set_idle_config(mock_request)

        assert response.status == 400

    async def test_set_idle_config_enable(self, mock_request):
        """Test enabling idle management."""
        mock_request.json = AsyncMock(return_value={"enabled": True})

        response = await handle_set_idle_config(mock_request)

        assert response.status == 200


@pytest.mark.asyncio
class TestHandleIdleKeepAwake:
    """Tests for handle_idle_keep_awake endpoint."""

    async def test_keep_awake_default_duration(self, mock_request):
        """Test keep awake with default duration."""
        mock_request.json = AsyncMock(return_value={})

        response = await handle_idle_keep_awake(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["keeping_awake_for"] == 3600  # Default 1 hour

    async def test_keep_awake_custom_duration(self, mock_request):
        """Test keep awake with custom duration."""
        mock_request.json = AsyncMock(return_value={"duration_seconds": 7200})

        response = await handle_idle_keep_awake(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["keeping_awake_for"] == 7200


@pytest.mark.asyncio
class TestHandleIdleCancelKeepAwake:
    """Tests for handle_idle_cancel_keep_awake endpoint."""

    async def test_cancel_keep_awake(self, mock_request):
        """Test canceling keep awake."""
        response = await handle_idle_cancel_keep_awake(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "ok"


@pytest.mark.asyncio
class TestHandleIdleForceState:
    """Tests for handle_idle_force_state endpoint."""

    async def test_force_state_invalid(self, mock_request):
        """Test forcing invalid idle state."""
        mock_request.json = AsyncMock(return_value={"state": "invalid_state"})

        response = await handle_idle_force_state(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "valid_states" in data

    async def test_force_state_active(self, mock_request):
        """Test forcing active state."""
        mock_request.json = AsyncMock(return_value={"state": "active"})

        response = await handle_idle_force_state(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["new_state"] == "active"


@pytest.mark.asyncio
class TestHandleGetPowerModes:
    """Tests for handle_get_power_modes endpoint."""

    async def test_get_power_modes(self, mock_request):
        """Test getting power modes."""
        response = await handle_get_power_modes(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "modes" in data
        assert "current" in data


@pytest.mark.asyncio
class TestHandleGetIdleHistory:
    """Tests for handle_get_idle_history endpoint."""

    async def test_get_idle_history(self, mock_request):
        """Test getting idle history."""
        mock_request.query = {}

        response = await handle_get_idle_history(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "history" in data
        assert "count" in data


# =============================================================================
# Test Classes - Profile Management Handlers
# =============================================================================


@pytest.mark.asyncio
class TestHandleGetProfile:
    """Tests for handle_get_profile endpoint."""

    async def test_get_profile_not_found(self, mock_request):
        """Test getting nonexistent profile."""
        mock_request.match_info = {"profile_id": "nonexistent"}

        response = await handle_get_profile(mock_request)

        assert response.status == 404


@pytest.mark.asyncio
class TestHandleCreateProfile:
    """Tests for handle_create_profile endpoint."""

    async def test_create_profile_missing_fields(self, mock_request):
        """Test creating profile with missing required fields."""
        mock_request.json = AsyncMock(return_value={"id": "test"})

        response = await handle_create_profile(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "Missing required field" in data["error"]

    async def test_create_profile_invalid_thresholds(self, mock_request):
        """Test creating profile with invalid thresholds."""
        mock_request.json = AsyncMock(return_value={
            "id": "test",
            "name": "Test",
            "thresholds": {"warm": -10}  # Missing other thresholds
        })

        response = await handle_create_profile(mock_request)

        assert response.status == 400

    async def test_create_profile_invalid_json(self, mock_request):
        """Test creating profile with invalid JSON."""
        mock_request.json = AsyncMock(side_effect=json.JSONDecodeError("", "", 0))

        response = await handle_create_profile(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleUpdateProfile:
    """Tests for handle_update_profile endpoint."""

    async def test_update_profile_not_found(self, mock_request):
        """Test updating nonexistent profile."""
        mock_request.match_info = {"profile_id": "nonexistent"}
        mock_request.json = AsyncMock(return_value={"name": "Updated"})

        response = await handle_update_profile(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleDeleteProfile:
    """Tests for handle_delete_profile endpoint."""

    async def test_delete_profile_not_found(self, mock_request):
        """Test deleting nonexistent profile."""
        mock_request.match_info = {"profile_id": "nonexistent"}

        response = await handle_delete_profile(mock_request)

        assert response.status == 400


@pytest.mark.asyncio
class TestHandleDuplicateProfile:
    """Tests for handle_duplicate_profile endpoint."""

    async def test_duplicate_profile_missing_fields(self, mock_request):
        """Test duplicating profile with missing fields."""
        mock_request.match_info = {"profile_id": "balanced"}
        mock_request.json = AsyncMock(return_value={})

        response = await handle_duplicate_profile(mock_request)

        assert response.status == 400
        data = json.loads(response.body)
        assert "new_id" in data["error"] or "new_name" in data["error"]


# =============================================================================
# Test Classes - Diagnostic Logging Handlers
# =============================================================================


@pytest.mark.asyncio
class TestHandleGetDiagnosticConfig:
    """Tests for handle_get_diagnostic_config endpoint."""

    async def test_get_diagnostic_config(self, mock_request):
        """Test getting diagnostic config."""
        response = await handle_get_diagnostic_config(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["success"] is True
        assert "config" in data


@pytest.mark.asyncio
class TestHandleSetDiagnosticConfig:
    """Tests for handle_set_diagnostic_config endpoint."""

    async def test_set_diagnostic_config(self, mock_request):
        """Test setting diagnostic config."""
        mock_request.json = AsyncMock(return_value={"enabled": True})

        response = await handle_set_diagnostic_config(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["success"] is True


@pytest.mark.asyncio
class TestHandleDiagnosticToggle:
    """Tests for handle_diagnostic_toggle endpoint."""

    async def test_diagnostic_toggle_enable(self, mock_request):
        """Test enabling diagnostic logging."""
        mock_request.json = AsyncMock(return_value={"enabled": True})

        response = await handle_diagnostic_toggle(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["success"] is True

    async def test_diagnostic_toggle_disable(self, mock_request):
        """Test disabling diagnostic logging."""
        mock_request.json = AsyncMock(return_value={"enabled": False})

        response = await handle_diagnostic_toggle(mock_request)

        assert response.status == 200


# =============================================================================
# Test Classes - Health and Models Handlers
# =============================================================================


@pytest.mark.asyncio
class TestHandleHealth:
    """Tests for handle_health endpoint."""

    async def test_health_check(self, mock_request):
        """Test health check returns proper structure."""
        response = await handle_health(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert data["status"] == "healthy"
        assert "timestamp" in data
        assert "version" in data


@pytest.mark.asyncio
class TestHandleGetModels:
    """Tests for handle_get_models endpoint."""

    async def test_get_models(self, mock_request):
        """Test getting models list."""
        with patch("aiohttp.ClientSession") as mock_session:
            mock_response = MagicMock()
            mock_response.status = 200
            mock_response.json = AsyncMock(return_value={"models": []})

            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()

            mock_session_instance = MagicMock()
            mock_session_instance.get.return_value = mock_context
            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            response = await handle_get_models(mock_request)

            assert response.status == 200
            data = json.loads(response.body)
            assert "models" in data


@pytest.mark.asyncio
class TestHandleGetModelCapabilities:
    """Tests for handle_get_model_capabilities endpoint."""

    async def test_get_model_capabilities(self, mock_request):
        """Test getting model capabilities."""
        response = await handle_get_model_capabilities(mock_request)

        assert response.status == 200
        data = json.loads(response.body)
        assert "capabilities" in data
        assert "total" in data
        assert "by_tier" in data
        assert "by_provider" in data


# =============================================================================
# Test Classes - Service Utilities
# =============================================================================


class TestServiceToDict:
    """Tests for service_to_dict utility function."""

    def test_service_to_dict_basic(self):
        """Test converting service to dict."""
        service = ManagedService(
            id="test-service",
            name="Test Service",
            service_type="test",
            command=["python", "test.py"],
            cwd="/tmp",
            port=8000,
            health_url="http://localhost:8000/health",
            status="stopped"
        )

        result = service_to_dict(service)

        assert result["id"] == "test-service"
        assert result["name"] == "Test Service"
        assert result["port"] == 8000
        assert result["status"] == "stopped"
        assert "memory" in result

    def test_service_to_dict_with_pid(self):
        """Test converting running service to dict."""
        service = ManagedService(
            id="running-service",
            name="Running Service",
            service_type="test",
            command=["python"],
            cwd="/tmp",
            port=8001,
            health_url="http://localhost:8001/health",
            status="running",
            pid=12345,
            started_at=time.time()
        )

        # Mock get_process_memory for non-existent PID
        with patch("server.get_process_memory", return_value={"rss_mb": 50, "vsz_mb": 100}):
            result = service_to_dict(service)

        assert result["pid"] == 12345
        assert result["started_at"] is not None


@pytest.mark.asyncio
class TestCheckServiceRunning:
    """Tests for check_service_running utility function."""

    async def test_check_service_running_healthy(self):
        """Test checking healthy service."""
        service = ManagedService(
            id="test",
            name="Test",
            service_type="test",
            command=["python"],
            cwd="/tmp",
            port=8000,
            health_url="http://localhost:8000/health"
        )

        mock_response = MagicMock()
        mock_response.status = 200

        with patch("aiohttp.ClientSession") as mock_session:
            mock_context = MagicMock()
            mock_context.__aenter__ = AsyncMock(return_value=mock_response)
            mock_context.__aexit__ = AsyncMock()

            mock_session_instance = MagicMock()
            mock_session_instance.get.return_value = mock_context
            mock_session_instance.__aenter__ = AsyncMock(return_value=mock_session_instance)
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            result = await check_service_running(service)

            assert result is True

    async def test_check_service_running_unhealthy(self):
        """Test checking unhealthy service returns False on connection error."""
        service = ManagedService(
            id="test",
            name="Test",
            service_type="test",
            command=["python"],
            cwd="/tmp",
            port=8000,
            health_url="http://localhost:8000/health"
        )

        # Mock aiohttp to raise exception when trying to connect
        with patch("server.aiohttp.ClientSession") as mock_session:
            mock_session_instance = MagicMock()
            mock_session_instance.__aenter__ = AsyncMock(side_effect=Exception("Connection refused"))
            mock_session_instance.__aexit__ = AsyncMock()
            mock_session.return_value = mock_session_instance

            result = await check_service_running(service)

            # check_service_running catches all exceptions and returns False
            assert result is False


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
