# Tests for TTS Pre-Generation API
# aiohttp handler tests with mocked profile manager

import json
import pytest
from datetime import datetime
from pathlib import Path
from typing import Any, Dict
from unittest.mock import AsyncMock, MagicMock, patch, PropertyMock
from uuid import UUID, uuid4

from aiohttp import web
from aiohttp.test_utils import AioHTTPTestCase, unittest_run_loop

from tts_pregen.models import (
    TTSProfile,
    TTSProfileSettings,
    TTSModuleProfile,
)


# =============================================================================
# Fixtures and Test Utilities
# =============================================================================


def create_mock_profile(**kwargs) -> TTSProfile:
    """Create a mock profile for testing."""
    defaults = {
        "name": "Test Profile",
        "provider": "chatterbox",
        "voice_id": "nova",
        "settings": TTSProfileSettings(speed=1.0, exaggeration=0.5, cfg_weight=0.5),
        "description": "Test description",
        "tags": ["test"],
        "use_case": "testing",
    }
    defaults.update(kwargs)
    return TTSProfile.create(**defaults)


def create_mock_module_profile(profile: TTSProfile, **kwargs) -> TTSModuleProfile:
    """Create a mock module profile association."""
    defaults = {
        "id": uuid4(),
        "module_id": "knowledge-bowl",
        "profile_id": profile.id,
        "context": None,
        "priority": 0,
    }
    defaults.update(kwargs)
    return TTSModuleProfile(**defaults)


@pytest.fixture
def mock_profile():
    """Create a sample mock profile."""
    return create_mock_profile()


@pytest.fixture
def mock_manager():
    """Create a mock profile manager."""
    manager = AsyncMock()
    return manager


# =============================================================================
# Profile CRUD API Tests
# =============================================================================


class TestCreateProfileAPI:
    """Tests for POST /api/tts/profiles."""

    @pytest.mark.asyncio
    async def test_create_profile_success(self, mock_manager, mock_profile):
        """Test successful profile creation."""
        mock_manager.create_profile = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test Profile",
                "provider": "chatterbox",
                "voice_id": "nova",
                "settings": {"speed": 1.0},
            })

            response = await handle_create_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert "profile" in body

    @pytest.mark.asyncio
    async def test_create_profile_missing_name(self, mock_manager):
        """Test profile creation without name."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "provider": "chatterbox",
                "voice_id": "nova",
            })

            response = await handle_create_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert body["success"] is False
            assert "name is required" in body["error"]

    @pytest.mark.asyncio
    async def test_create_profile_missing_provider(self, mock_manager):
        """Test profile creation without provider."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test",
                "voice_id": "nova",
            })

            response = await handle_create_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "provider is required" in body["error"]

    @pytest.mark.asyncio
    async def test_create_profile_missing_voice_id(self, mock_manager):
        """Test profile creation without voice_id."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test",
                "provider": "chatterbox",
            })

            response = await handle_create_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "voice_id is required" in body["error"]

    @pytest.mark.asyncio
    async def test_create_profile_duplicate_name(self, mock_manager):
        """Test profile creation with duplicate name."""
        mock_manager.create_profile = AsyncMock(
            side_effect=ValueError("Profile with name 'Test' already exists")
        )

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test",
                "provider": "chatterbox",
                "voice_id": "nova",
            })

            response = await handle_create_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "already exists" in body["error"]


class TestListProfilesAPI:
    """Tests for GET /api/tts/profiles."""

    @pytest.mark.asyncio
    async def test_list_profiles_success(self, mock_manager, mock_profile):
        """Test listing profiles."""
        mock_manager.list_profiles = AsyncMock(return_value=([mock_profile], 1))

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_list_profiles

            request = AsyncMock()
            request.query = {}

            response = await handle_list_profiles(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert len(body["profiles"]) == 1
            assert body["total"] == 1

    @pytest.mark.asyncio
    async def test_list_profiles_with_filters(self, mock_manager, mock_profile):
        """Test listing profiles with filters."""
        mock_manager.list_profiles = AsyncMock(return_value=([mock_profile], 1))

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_list_profiles

            request = AsyncMock()
            request.query = {
                "provider": "chatterbox",
                "tags": "test,unit",
                "use_case": "testing",
                "is_active": "true",
                "limit": "50",
                "offset": "10",
            }

            response = await handle_list_profiles(request)

            assert response.status == 200
            mock_manager.list_profiles.assert_called_once_with(
                provider="chatterbox",
                tags=["test", "unit"],
                use_case="testing",
                is_active=True,
                limit=50,
                offset=10,
            )


class TestGetProfileAPI:
    """Tests for GET /api/tts/profiles/{profile_id}."""

    @pytest.mark.asyncio
    async def test_get_profile_success(self, mock_manager, mock_profile):
        """Test getting a profile by ID."""
        mock_manager.get_profile = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_get_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(mock_profile.id)}

            response = await handle_get_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["profile"]["name"] == "Test Profile"

    @pytest.mark.asyncio
    async def test_get_profile_not_found(self, mock_manager):
        """Test getting non-existent profile."""
        mock_manager.get_profile = AsyncMock(return_value=None)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_get_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}

            response = await handle_get_profile(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_get_profile_invalid_uuid(self, mock_manager):
        """Test getting profile with invalid UUID."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_get_profile

            request = AsyncMock()
            request.match_info = {"profile_id": "not-a-uuid"}

            response = await handle_get_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "Invalid" in body["error"]


class TestUpdateProfileAPI:
    """Tests for PUT /api/tts/profiles/{profile_id}."""

    @pytest.mark.asyncio
    async def test_update_profile_success(self, mock_manager, mock_profile):
        """Test updating a profile."""
        mock_manager.update_profile = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_update_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(mock_profile.id)}
            request.json = AsyncMock(return_value={
                "description": "Updated description",
            })

            response = await handle_update_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_update_profile_not_found(self, mock_manager):
        """Test updating non-existent profile."""
        mock_manager.update_profile = AsyncMock(
            side_effect=ValueError("Profile not found")
        )

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_update_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}
            request.json = AsyncMock(return_value={"name": "New Name"})

            response = await handle_update_profile(request)

            assert response.status == 400


class TestDeleteProfileAPI:
    """Tests for DELETE /api/tts/profiles/{profile_id}."""

    @pytest.mark.asyncio
    async def test_delete_profile_soft(self, mock_manager):
        """Test soft deleting a profile."""
        mock_manager.delete_profile = AsyncMock(return_value=True)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_delete_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}
            request.query = {}

            response = await handle_delete_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["permanent"] is False

    @pytest.mark.asyncio
    async def test_delete_profile_hard(self, mock_manager):
        """Test hard deleting a profile."""
        mock_manager.delete_profile = AsyncMock(return_value=True)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_delete_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}
            request.query = {"hard": "true"}

            response = await handle_delete_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["permanent"] is True

    @pytest.mark.asyncio
    async def test_delete_profile_not_found(self, mock_manager):
        """Test deleting non-existent profile."""
        mock_manager.delete_profile = AsyncMock(return_value=False)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_delete_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}
            request.query = {}

            response = await handle_delete_profile(request)

            assert response.status == 404


class TestSetDefaultProfileAPI:
    """Tests for POST /api/tts/profiles/{profile_id}/set-default."""

    @pytest.mark.asyncio
    async def test_set_default_success(self, mock_manager):
        """Test setting default profile."""
        mock_manager.set_default_profile = AsyncMock()

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_set_default_profile

            profile_id = uuid4()
            request = AsyncMock()
            request.match_info = {"profile_id": str(profile_id)}

            response = await handle_set_default_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["default_profile_id"] == str(profile_id)

    @pytest.mark.asyncio
    async def test_set_default_not_found(self, mock_manager):
        """Test setting default for non-existent profile."""
        mock_manager.set_default_profile = AsyncMock(
            side_effect=ValueError("Profile not found")
        )

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_set_default_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}

            response = await handle_set_default_profile(request)

            assert response.status == 400


class TestPreviewProfileAPI:
    """Tests for POST /api/tts/profiles/{profile_id}/preview."""

    @pytest.mark.asyncio
    async def test_preview_profile_success(self, mock_manager, mock_profile):
        """Test generating profile preview."""
        mock_profile.sample_audio_path = "/tmp/sample.wav"
        mock_manager.regenerate_sample = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_preview_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(mock_profile.id)}
            request.body_exists = True
            request.json = AsyncMock(return_value={"sample_text": "Custom text"})

            response = await handle_preview_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["sample_audio_path"] == "/tmp/sample.wav"

    @pytest.mark.asyncio
    async def test_preview_profile_no_body(self, mock_manager, mock_profile):
        """Test preview with no request body."""
        mock_manager.regenerate_sample = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_preview_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(mock_profile.id)}
            request.body_exists = False

            response = await handle_preview_profile(request)

            assert response.status == 200


class TestDuplicateProfileAPI:
    """Tests for POST /api/tts/profiles/{profile_id}/duplicate."""

    @pytest.mark.asyncio
    async def test_duplicate_profile_success(self, mock_manager, mock_profile):
        """Test duplicating a profile."""
        mock_manager.duplicate_profile = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_duplicate_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(mock_profile.id)}
            request.json = AsyncMock(return_value={
                "name": "Duplicate Profile",
                "description": "Copy of original",
            })

            response = await handle_duplicate_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_duplicate_profile_missing_name(self, mock_manager):
        """Test duplicating without name."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_duplicate_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}
            request.json = AsyncMock(return_value={})

            response = await handle_duplicate_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "name is required" in body["error"]


class TestExportProfileAPI:
    """Tests for GET /api/tts/profiles/{profile_id}/export."""

    @pytest.mark.asyncio
    async def test_export_profile_success(self, mock_manager):
        """Test exporting a profile."""
        export_data = {
            "name": "Test Profile",
            "provider": "chatterbox",
            "voice_id": "nova",
            "settings": {"speed": 1.0},
            "exported_at": datetime.now().isoformat(),
        }
        mock_manager.export_profile = AsyncMock(return_value=export_data)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_export_profile

            request = AsyncMock()
            request.match_info = {"profile_id": str(uuid4())}

            response = await handle_export_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["export"]["name"] == "Test Profile"


class TestImportProfileAPI:
    """Tests for POST /api/tts/profiles/import."""

    @pytest.mark.asyncio
    async def test_import_profile_success(self, mock_manager, mock_profile):
        """Test importing a profile."""
        mock_manager.import_profile = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_import_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "export": {
                    "name": "Imported Profile",
                    "provider": "chatterbox",
                    "voice_id": "nova",
                },
            })

            response = await handle_import_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_import_profile_missing_export(self, mock_manager):
        """Test importing without export data."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_import_profile

            request = AsyncMock()
            request.json = AsyncMock(return_value={})

            response = await handle_import_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "export data is required" in body["error"]


# =============================================================================
# Module Profile API Tests
# =============================================================================


class TestGetModuleProfilesAPI:
    """Tests for GET /api/tts/modules/{module_id}/profiles."""

    @pytest.mark.asyncio
    async def test_get_module_profiles_success(self, mock_manager, mock_profile):
        """Test getting module profiles."""
        assoc = create_mock_module_profile(mock_profile)
        mock_manager.get_module_profiles = AsyncMock(return_value=[(assoc, mock_profile)])

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_get_module_profiles

            request = AsyncMock()
            request.match_info = {"module_id": "knowledge-bowl"}
            request.query = {}

            response = await handle_get_module_profiles(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["module_id"] == "knowledge-bowl"
            assert len(body["profiles"]) == 1


class TestAssignModuleProfileAPI:
    """Tests for POST /api/tts/modules/{module_id}/profiles."""

    @pytest.mark.asyncio
    async def test_assign_module_profile_success(self, mock_manager, mock_profile):
        """Test assigning profile to module."""
        assoc = create_mock_module_profile(mock_profile)
        mock_manager.assign_to_module = AsyncMock(return_value=assoc)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_assign_module_profile

            request = AsyncMock()
            request.match_info = {"module_id": "knowledge-bowl"}
            request.json = AsyncMock(return_value={
                "profile_id": str(mock_profile.id),
                "context": "questions",
                "priority": 10,
            })

            response = await handle_assign_module_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_assign_module_profile_missing_id(self, mock_manager):
        """Test assigning without profile_id."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_assign_module_profile

            request = AsyncMock()
            request.match_info = {"module_id": "knowledge-bowl"}
            request.json = AsyncMock(return_value={})

            response = await handle_assign_module_profile(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "profile_id is required" in body["error"]


class TestRemoveModuleProfileAPI:
    """Tests for DELETE /api/tts/modules/{module_id}/profiles/{profile_id}."""

    @pytest.mark.asyncio
    async def test_remove_module_profile_success(self, mock_manager):
        """Test removing profile from module."""
        mock_manager.remove_from_module = AsyncMock(return_value=True)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_remove_module_profile

            request = AsyncMock()
            request.match_info = {
                "module_id": "knowledge-bowl",
                "profile_id": str(uuid4()),
            }

            response = await handle_remove_module_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["removed"] is True

    @pytest.mark.asyncio
    async def test_remove_module_profile_not_found(self, mock_manager):
        """Test removing non-existent assignment."""
        mock_manager.remove_from_module = AsyncMock(return_value=False)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_remove_module_profile

            request = AsyncMock()
            request.match_info = {
                "module_id": "knowledge-bowl",
                "profile_id": str(uuid4()),
            }

            response = await handle_remove_module_profile(request)

            assert response.status == 404


class TestGetBestModuleProfileAPI:
    """Tests for GET /api/tts/modules/{module_id}/best-profile."""

    @pytest.mark.asyncio
    async def test_get_best_profile_found(self, mock_manager, mock_profile):
        """Test getting best profile for module."""
        mock_manager.get_best_profile_for_module = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_get_best_module_profile

            request = AsyncMock()
            request.match_info = {"module_id": "knowledge-bowl"}
            request.query = {"context": "questions"}

            response = await handle_get_best_module_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["profile"] is not None

    @pytest.mark.asyncio
    async def test_get_best_profile_none(self, mock_manager):
        """Test getting best profile when none exists."""
        mock_manager.get_best_profile_for_module = AsyncMock(return_value=None)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_get_best_module_profile

            request = AsyncMock()
            request.match_info = {"module_id": "unknown-module"}
            request.query = {}

            response = await handle_get_best_module_profile(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert body["profile"] is None


# =============================================================================
# Profile from Variant API Tests
# =============================================================================


class TestCreateProfileFromVariantAPI:
    """Tests for POST /api/tts/profiles/from-variant/{variant_id}."""

    @pytest.mark.asyncio
    async def test_create_from_variant_success(self, mock_manager, mock_profile):
        """Test creating profile from variant."""
        mock_manager.create_from_variant = AsyncMock(return_value=mock_profile)

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile_from_variant

            request = AsyncMock()
            request.match_info = {"variant_id": str(uuid4())}
            request.json = AsyncMock(return_value={
                "name": "Winner Profile",
                "description": "Best from comparison",
                "tags": ["comparison-winner"],
            })

            response = await handle_create_profile_from_variant(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_create_from_variant_missing_name(self, mock_manager):
        """Test creating from variant without name."""
        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile_from_variant

            request = AsyncMock()
            request.match_info = {"variant_id": str(uuid4())}
            request.json = AsyncMock(return_value={})

            response = await handle_create_profile_from_variant(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "name is required" in body["error"]

    @pytest.mark.asyncio
    async def test_create_from_variant_not_found(self, mock_manager):
        """Test creating from non-existent variant."""
        mock_manager.create_from_variant = AsyncMock(
            side_effect=ValueError("Variant not found")
        )

        with patch("tts_pregen_api._get_profile_manager", return_value=mock_manager):
            from tts_pregen_api import handle_create_profile_from_variant

            request = AsyncMock()
            request.match_info = {"variant_id": str(uuid4())}
            request.json = AsyncMock(return_value={"name": "Test"})

            response = await handle_create_profile_from_variant(request)

            assert response.status == 400


# =============================================================================
# Utility Function Tests
# =============================================================================


class TestUtilityFunctions:
    """Tests for API utility functions."""

    def test_parse_uuid_valid(self):
        """Test parsing valid UUID."""
        from tts_pregen_api import _parse_uuid

        valid_uuid = str(uuid4())
        result = _parse_uuid(valid_uuid)

        assert isinstance(result, UUID)

    def test_parse_uuid_invalid(self):
        """Test parsing invalid UUID."""
        from tts_pregen_api import _parse_uuid

        with pytest.raises(ValueError, match="Invalid"):
            _parse_uuid("not-a-uuid")

    def test_parse_uuid_custom_name(self):
        """Test error message uses custom name."""
        from tts_pregen_api import _parse_uuid

        with pytest.raises(ValueError, match="Invalid profile_id"):
            _parse_uuid("invalid", "profile_id")


# =============================================================================
# Initialization Tests
# =============================================================================


class TestInitialization:
    """Tests for API initialization."""

    def test_init_without_db_pool(self):
        """Test initialization without database pool."""
        from tts_pregen_api import init_tts_pregen_system, _profile_manager

        app = MagicMock()
        app.get.return_value = None  # No db_pool

        with patch("tts_pregen_api.PREGEN_OUTPUT_DIR", Path("/tmp/test")):
            with patch.object(Path, "mkdir"):
                init_tts_pregen_system(app)

        # Should not crash, just log warning

    def test_init_with_db_pool(self):
        """Test initialization with database pool."""
        from tts_pregen_api import init_tts_pregen_system

        app = MagicMock()
        db_pool = MagicMock()
        app.get.side_effect = lambda key: db_pool if key == "db_pool" else None

        with patch("tts_pregen_api.PREGEN_OUTPUT_DIR", Path("/tmp/test")):
            with patch.object(Path, "mkdir"):
                with patch("tts_pregen_api.TTSProfileManager") as mock_manager_class:
                    init_tts_pregen_system(app)
                    mock_manager_class.assert_called_once_with(db_pool, None)

    def test_register_routes(self):
        """Test route registration."""
        from tts_pregen_api import register_tts_pregen_routes

        app = MagicMock()
        app.get.return_value = MagicMock()  # Mock db_pool
        app.router = MagicMock()

        with patch("tts_pregen_api.PREGEN_OUTPUT_DIR", Path("/tmp/test")):
            with patch.object(Path, "mkdir"):
                register_tts_pregen_routes(app)

        # Should have registered many routes
        assert app.router.add_post.call_count > 0
        assert app.router.add_get.call_count > 0
        assert app.router.add_put.call_count > 0
        assert app.router.add_delete.call_count > 0


# =============================================================================
# Comparison Session API Tests
# =============================================================================

from tts_pregen.models import (
    TTSComparisonSession,
    TTSComparisonVariant,
    TTSComparisonRating,
)


def create_mock_session(**kwargs) -> TTSComparisonSession:
    """Create a mock comparison session for testing."""
    defaults = {
        "name": "Test Session",
        "samples": [{"text": "Hello"}, {"text": "World"}],
        "configurations": [
            {"name": "A", "provider": "chatterbox", "voice_id": "nova"},
            {"name": "B", "provider": "piper", "voice_id": "default"},
        ],
        "description": "Test session",
    }
    defaults.update(kwargs)
    return TTSComparisonSession.create(**defaults)


def create_mock_variant(session_id, **kwargs) -> TTSComparisonVariant:
    """Create a mock variant for testing."""
    defaults = {
        "session_id": session_id,
        "sample_index": 0,
        "config_index": 0,
        "text_content": "Test text",
        "tts_config": {"provider": "chatterbox", "voice_id": "nova"},
    }
    defaults.update(kwargs)
    return TTSComparisonVariant.create(**defaults)


@pytest.fixture
def mock_comparison_manager():
    """Create a mock comparison manager."""
    return AsyncMock()


@pytest.fixture
def mock_session():
    """Create a sample mock session."""
    return create_mock_session()


class TestCreateSessionAPI:
    """Tests for POST /api/tts/pregen/sessions."""

    @pytest.mark.asyncio
    async def test_create_session_success(self, mock_comparison_manager, mock_session):
        """Test successful session creation."""
        mock_comparison_manager.create_session = AsyncMock(return_value=mock_session)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_create_session

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test Session",
                "samples": [{"text": "Hello"}],
                "configurations": [{"name": "A", "provider": "chatterbox", "voice_id": "nova"}],
            })

            response = await handle_create_session(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert "session" in body

    @pytest.mark.asyncio
    async def test_create_session_missing_name(self, mock_comparison_manager):
        """Test session creation without name."""
        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_create_session

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "samples": [{"text": "Hello"}],
                "configurations": [{"name": "A", "provider": "chatterbox", "voice_id": "nova"}],
            })

            response = await handle_create_session(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "name is required" in body["error"]

    @pytest.mark.asyncio
    async def test_create_session_missing_samples(self, mock_comparison_manager):
        """Test session creation without samples."""
        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_create_session

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test",
                "configurations": [{"name": "A", "provider": "chatterbox", "voice_id": "nova"}],
            })

            response = await handle_create_session(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "samples is required" in body["error"]

    @pytest.mark.asyncio
    async def test_create_session_missing_configurations(self, mock_comparison_manager):
        """Test session creation without configurations."""
        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_create_session

            request = AsyncMock()
            request.json = AsyncMock(return_value={
                "name": "Test",
                "samples": [{"text": "Hello"}],
            })

            response = await handle_create_session(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "configurations is required" in body["error"]


class TestListSessionsAPI:
    """Tests for GET /api/tts/pregen/sessions."""

    @pytest.mark.asyncio
    async def test_list_sessions_success(self, mock_comparison_manager, mock_session):
        """Test successful session listing."""
        mock_comparison_manager.list_sessions = AsyncMock(return_value=([mock_session], 1))

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_list_sessions

            request = AsyncMock()
            request.query = {}

            response = await handle_list_sessions(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert len(body["sessions"]) == 1
            assert body["total"] == 1

    @pytest.mark.asyncio
    async def test_list_sessions_with_status_filter(self, mock_comparison_manager):
        """Test listing sessions with status filter."""
        mock_comparison_manager.list_sessions = AsyncMock(return_value=([], 0))

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_list_sessions

            request = AsyncMock()
            request.query = {"status": "ready"}

            response = await handle_list_sessions(request)

            assert response.status == 200
            mock_comparison_manager.list_sessions.assert_called_once()


class TestGetSessionAPI:
    """Tests for GET /api/tts/pregen/sessions/{session_id}."""

    @pytest.mark.asyncio
    async def test_get_session_success(self, mock_comparison_manager, mock_session):
        """Test getting an existing session."""
        mock_variant = create_mock_variant(mock_session.id)
        mock_comparison_manager.get_session_with_variants = AsyncMock(
            return_value=(mock_session, [mock_variant], {})
        )

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_get_session

            request = AsyncMock()
            request.match_info = {"session_id": str(mock_session.id)}

            response = await handle_get_session(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert "session" in body
            assert "variants" in body

    @pytest.mark.asyncio
    async def test_get_session_not_found(self, mock_comparison_manager):
        """Test getting non-existent session."""
        mock_comparison_manager.get_session_with_variants = AsyncMock(
            return_value=(None, [], {})
        )

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_get_session

            request = AsyncMock()
            request.match_info = {"session_id": str(uuid4())}

            response = await handle_get_session(request)

            assert response.status == 404

    @pytest.mark.asyncio
    async def test_get_session_invalid_uuid(self, mock_comparison_manager):
        """Test getting session with invalid UUID."""
        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_get_session

            request = AsyncMock()
            request.match_info = {"session_id": "invalid-uuid"}

            response = await handle_get_session(request)

            assert response.status == 400


class TestDeleteSessionAPI:
    """Tests for DELETE /api/tts/pregen/sessions/{session_id}."""

    @pytest.mark.asyncio
    async def test_delete_session_success(self, mock_comparison_manager, mock_session):
        """Test successful session deletion."""
        mock_comparison_manager.delete_session = AsyncMock(return_value=True)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_delete_session

            request = AsyncMock()
            request.match_info = {"session_id": str(mock_session.id)}

            response = await handle_delete_session(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_delete_session_not_found(self, mock_comparison_manager):
        """Test deleting non-existent session."""
        mock_comparison_manager.delete_session = AsyncMock(return_value=False)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_delete_session

            request = AsyncMock()
            request.match_info = {"session_id": str(uuid4())}

            response = await handle_delete_session(request)

            assert response.status == 404


class TestGenerateVariantsAPI:
    """Tests for POST /api/tts/pregen/sessions/{session_id}/generate."""

    @pytest.mark.asyncio
    async def test_generate_variants_success(self, mock_comparison_manager, mock_session):
        """Test successful variant generation."""
        mock_comparison_manager.generate_variants = AsyncMock(return_value=mock_session)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_generate_session_variants

            request = AsyncMock()
            request.match_info = {"session_id": str(mock_session.id)}
            request.json = AsyncMock(return_value={})

            response = await handle_generate_session_variants(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True

    @pytest.mark.asyncio
    async def test_generate_variants_regenerate(self, mock_comparison_manager, mock_session):
        """Test regenerate all variants."""
        mock_comparison_manager.generate_variants = AsyncMock(return_value=mock_session)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_generate_session_variants

            request = AsyncMock()
            request.match_info = {"session_id": str(mock_session.id)}
            request.json = AsyncMock(return_value={"regenerate": True})

            response = await handle_generate_session_variants(request)

            assert response.status == 200
            mock_comparison_manager.generate_variants.assert_called_once()
            call_kwargs = mock_comparison_manager.generate_variants.call_args[1]
            assert call_kwargs.get("regenerate") is True

    @pytest.mark.asyncio
    async def test_generate_variants_no_tts_pool(self, mock_comparison_manager):
        """Test generation fails without TTS pool."""
        mock_comparison_manager.generate_variants = AsyncMock(
            side_effect=ValueError("No TTS pool available")
        )

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_generate_session_variants

            request = AsyncMock()
            request.match_info = {"session_id": str(uuid4())}
            request.json = AsyncMock(return_value={})

            response = await handle_generate_session_variants(request)

            assert response.status == 400


class TestRateVariantAPI:
    """Tests for POST /api/tts/pregen/variants/{variant_id}/rate."""

    @pytest.mark.asyncio
    async def test_rate_variant_success(self, mock_comparison_manager, mock_session):
        """Test successful variant rating."""
        variant = create_mock_variant(mock_session.id)
        rating = TTSComparisonRating.create(variant_id=variant.id, rating=4, notes="Good")
        mock_comparison_manager.rate_variant = AsyncMock(return_value=rating)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_rate_variant

            request = AsyncMock()
            request.match_info = {"variant_id": str(variant.id)}
            request.json = AsyncMock(return_value={"rating": 4, "notes": "Good"})

            response = await handle_rate_variant(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert "rating" in body

    @pytest.mark.asyncio
    async def test_rate_variant_missing_rating(self, mock_comparison_manager):
        """Test rating without rating value."""
        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_rate_variant

            request = AsyncMock()
            request.match_info = {"variant_id": str(uuid4())}
            request.json = AsyncMock(return_value={})

            response = await handle_rate_variant(request)

            assert response.status == 400
            body = json.loads(response.text)
            assert "rating is required" in body["error"]

    @pytest.mark.asyncio
    async def test_rate_variant_invalid_rating(self, mock_comparison_manager):
        """Test rating with invalid value."""
        mock_comparison_manager.rate_variant = AsyncMock(
            side_effect=ValueError("Rating must be between 1 and 5")
        )

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_rate_variant

            request = AsyncMock()
            request.match_info = {"variant_id": str(uuid4())}
            request.json = AsyncMock(return_value={"rating": 10})

            response = await handle_rate_variant(request)

            assert response.status == 400


class TestGetSessionSummaryAPI:
    """Tests for GET /api/tts/pregen/sessions/{session_id}/summary."""

    @pytest.mark.asyncio
    async def test_get_summary_success(self, mock_comparison_manager, mock_session):
        """Test successful summary retrieval."""
        mock_comparison_manager.get_session_summary = AsyncMock(
            return_value={
                "session_id": str(mock_session.id),
                "session_name": mock_session.name,
                "status": "ready",
                "configuration_rankings": [],
            }
        )

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_get_session_summary

            request = AsyncMock()
            request.match_info = {"session_id": str(mock_session.id)}

            response = await handle_get_session_summary(request)

            assert response.status == 200
            body = json.loads(response.text)
            assert body["success"] is True
            assert "summary" in body

    @pytest.mark.asyncio
    async def test_get_summary_not_found(self, mock_comparison_manager):
        """Test summary for non-existent session."""
        mock_comparison_manager.get_session_summary = AsyncMock(return_value=None)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_get_session_summary

            request = AsyncMock()
            request.match_info = {"session_id": str(uuid4())}

            response = await handle_get_session_summary(request)

            assert response.status == 404


class TestGetVariantAudioAPI:
    """Tests for GET /api/tts/pregen/variants/{variant_id}/audio."""

    @pytest.mark.asyncio
    async def test_get_audio_not_found(self, mock_comparison_manager):
        """Test getting audio for variant without file."""
        mock_comparison_manager.get_audio_file_path = AsyncMock(return_value=None)

        with patch("tts_pregen_api._get_comparison_manager", return_value=mock_comparison_manager):
            from tts_pregen_api import handle_get_variant_audio

            request = AsyncMock()
            request.match_info = {"variant_id": str(uuid4())}

            response = await handle_get_variant_audio(request)

            assert response.status == 404
