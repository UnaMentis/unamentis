# Tests for TTS Comparison Manager
# High-level service tests with mocked repository

import pytest
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

from tts_pregen.models import (
    TTSComparisonSession,
    TTSComparisonVariant,
    TTSComparisonRating,
    TTSProfile,
    TTSProfileSettings,
    SessionStatus,
    VariantStatus,
)
from tts_pregen.comparison_manager import TTSComparisonManager, DEFAULT_COMPARISON_DIR


# =============================================================================
# Fixtures
# =============================================================================


@pytest.fixture
def mock_repo():
    """Create a mock repository."""
    repo = AsyncMock()
    return repo


@pytest.fixture
def mock_tts_pool():
    """Create a mock TTS resource pool."""
    pool = AsyncMock()
    pool.generate_with_priority = AsyncMock(return_value=(b"\x00\x00" * 11025, 22050, 1.0))
    return pool


@pytest.fixture
def manager(mock_repo, tmp_path):
    """Create a comparison manager without TTS pool."""
    return TTSComparisonManager(
        repo=mock_repo,
        tts_pool=None,
        storage_dir=str(tmp_path / "comparisons"),
    )


@pytest.fixture
def manager_with_tts(mock_repo, mock_tts_pool, tmp_path):
    """Create a comparison manager with TTS pool."""
    return TTSComparisonManager(
        repo=mock_repo,
        tts_pool=mock_tts_pool,
        storage_dir=str(tmp_path / "comparisons"),
    )


@pytest.fixture
def sample_session():
    """Create a sample comparison session."""
    return TTSComparisonSession.create(
        name="Test Comparison",
        samples=[
            {"text": "Hello world"},
            {"text": "How are you?"},
        ],
        configurations=[
            {"name": "Config A", "provider": "chatterbox", "voice_id": "nova"},
            {"name": "Config B", "provider": "chatterbox", "voice_id": "echo"},
        ],
        description="Test session",
    )


@pytest.fixture
def sample_variants(sample_session):
    """Create sample variants for a session."""
    variants = []
    for s_idx in range(2):
        for c_idx in range(2):
            variants.append(
                TTSComparisonVariant.create(
                    session_id=sample_session.id,
                    sample_index=s_idx,
                    config_index=c_idx,
                    text_content=f"Text {s_idx}",
                    tts_config={"provider": "chatterbox", "voice_id": "nova"},
                )
            )
    return variants


# =============================================================================
# Session Management Tests
# =============================================================================


class TestCreateSession:
    """Tests for session creation."""

    @pytest.mark.asyncio
    async def test_create_session_success(self, manager, mock_repo):
        """Test successful session creation."""
        mock_repo.create_session = AsyncMock()
        mock_repo.create_variants = AsyncMock()

        session = await manager.create_session(
            name="Test Session",
            samples=[{"text": "Hello"}],
            configurations=[{"name": "A", "provider": "chatterbox", "voice_id": "nova"}],
            description="Testing",
        )

        assert session.name == "Test Session"
        assert session.sample_count == 1
        assert session.config_count == 1
        mock_repo.create_session.assert_called_once()
        mock_repo.create_variants.assert_called_once()

    @pytest.mark.asyncio
    async def test_create_session_multiple_variants(self, manager, mock_repo):
        """Test session creation creates correct number of variants."""
        mock_repo.create_session = AsyncMock()
        mock_repo.create_variants = AsyncMock()

        session = await manager.create_session(
            name="Multi Session",
            samples=[{"text": "Sample 1"}, {"text": "Sample 2"}, {"text": "Sample 3"}],
            configurations=[
                {"name": "A", "provider": "chatterbox", "voice_id": "nova"},
                {"name": "B", "provider": "piper", "voice_id": "default"},
            ],
        )

        # 3 samples x 2 configs = 6 variants
        assert session.total_variants == 6
        # Check variants were created
        call_args = mock_repo.create_variants.call_args
        variants = call_args[0][0]
        assert len(variants) == 6

    @pytest.mark.asyncio
    async def test_create_session_empty_samples_fails(self, manager):
        """Test creating session with no samples fails."""
        with pytest.raises(ValueError, match="At least one sample"):
            await manager.create_session(
                name="Empty Session",
                samples=[],
                configurations=[{"name": "A", "provider": "chatterbox", "voice_id": "nova"}],
            )

    @pytest.mark.asyncio
    async def test_create_session_empty_configurations_fails(self, manager):
        """Test creating session with no configurations fails."""
        with pytest.raises(ValueError, match="At least one configuration"):
            await manager.create_session(
                name="Empty Session",
                samples=[{"text": "Hello"}],
                configurations=[],
            )

    @pytest.mark.asyncio
    async def test_create_session_missing_provider_fails(self, manager):
        """Test creating session with missing provider fails."""
        with pytest.raises(ValueError, match="missing 'provider'"):
            await manager.create_session(
                name="Bad Config",
                samples=[{"text": "Hello"}],
                configurations=[{"name": "A", "voice_id": "nova"}],
            )

    @pytest.mark.asyncio
    async def test_create_session_missing_voice_id_fails(self, manager):
        """Test creating session with missing voice_id fails."""
        with pytest.raises(ValueError, match="missing 'voice_id'"):
            await manager.create_session(
                name="Bad Config",
                samples=[{"text": "Hello"}],
                configurations=[{"name": "A", "provider": "chatterbox"}],
            )

    @pytest.mark.asyncio
    async def test_create_session_auto_name_configs(self, manager, mock_repo):
        """Test configs without names get auto-named."""
        mock_repo.create_session = AsyncMock()
        mock_repo.create_variants = AsyncMock()

        await manager.create_session(
            name="Test Session",
            samples=[{"text": "Hello"}],
            configurations=[
                {"provider": "chatterbox", "voice_id": "nova"},  # No name
                {"provider": "piper", "voice_id": "default"},  # No name
            ],
        )

        # Check variants have auto-named configs
        call_args = mock_repo.create_variants.call_args
        variants = call_args[0][0]
        assert variants[0].tts_config.get("name") == "Config 1"
        assert variants[1].tts_config.get("name") == "Config 2"


class TestGetSession:
    """Tests for getting sessions."""

    @pytest.mark.asyncio
    async def test_get_session_success(self, manager, mock_repo, sample_session):
        """Test getting an existing session."""
        mock_repo.get_session = AsyncMock(return_value=sample_session)

        result = await manager.get_session(sample_session.id)

        assert result is not None
        assert result.id == sample_session.id
        mock_repo.get_session.assert_called_once_with(sample_session.id)

    @pytest.mark.asyncio
    async def test_get_session_not_found(self, manager, mock_repo):
        """Test getting non-existent session returns None."""
        mock_repo.get_session = AsyncMock(return_value=None)

        result = await manager.get_session(uuid4())

        assert result is None


class TestListSessions:
    """Tests for listing sessions."""

    @pytest.mark.asyncio
    async def test_list_sessions_success(self, manager, mock_repo, sample_session):
        """Test listing sessions."""
        mock_repo.list_sessions = AsyncMock(return_value=([sample_session], 1))

        sessions, total = await manager.list_sessions()

        assert len(sessions) == 1
        assert total == 1
        mock_repo.list_sessions.assert_called_once()

    @pytest.mark.asyncio
    async def test_list_sessions_with_status_filter(self, manager, mock_repo):
        """Test listing sessions with status filter."""
        mock_repo.list_sessions = AsyncMock(return_value=([], 0))

        await manager.list_sessions(status=SessionStatus.READY)

        mock_repo.list_sessions.assert_called_once_with(
            status=SessionStatus.READY,
            limit=50,
            offset=0,
        )

    @pytest.mark.asyncio
    async def test_list_sessions_with_pagination(self, manager, mock_repo):
        """Test listing sessions with pagination."""
        mock_repo.list_sessions = AsyncMock(return_value=([], 0))

        await manager.list_sessions(limit=10, offset=20)

        mock_repo.list_sessions.assert_called_once_with(
            status=None,
            limit=10,
            offset=20,
        )


class TestDeleteSession:
    """Tests for deleting sessions."""

    @pytest.mark.asyncio
    async def test_delete_session_success(self, manager, mock_repo, sample_session, tmp_path):
        """Test successful session deletion."""
        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.delete_session = AsyncMock(return_value=True)

        # Create session directory
        session_dir = Path(manager.storage_dir) / str(sample_session.id)
        session_dir.mkdir(parents=True)
        (session_dir / "test.wav").touch()

        result = await manager.delete_session(sample_session.id)

        assert result is True
        mock_repo.delete_session.assert_called_once_with(sample_session.id)
        # Directory should be cleaned up
        assert not session_dir.exists()

    @pytest.mark.asyncio
    async def test_delete_session_not_found(self, manager, mock_repo):
        """Test deleting non-existent session."""
        mock_repo.get_session = AsyncMock(return_value=None)

        result = await manager.delete_session(uuid4())

        assert result is False
        mock_repo.delete_session.assert_not_called()


# =============================================================================
# Variant Generation Tests
# =============================================================================


class TestGenerateVariants:
    """Tests for variant audio generation."""

    @pytest.mark.asyncio
    async def test_generate_variants_no_pool_fails(self, manager, mock_repo, sample_session):
        """Test generation fails without TTS pool."""
        mock_repo.get_session = AsyncMock(return_value=sample_session)

        with pytest.raises(ValueError, match="No TTS pool"):
            await manager.generate_variants(sample_session.id)

    @pytest.mark.asyncio
    async def test_generate_variants_session_not_found(self, manager_with_tts, mock_repo):
        """Test generation fails for non-existent session."""
        mock_repo.get_session = AsyncMock(return_value=None)

        with pytest.raises(ValueError, match="not found"):
            await manager_with_tts.generate_variants(uuid4())

    @pytest.mark.asyncio
    async def test_generate_variants_success(
        self, manager_with_tts, mock_repo, mock_tts_pool, sample_session, sample_variants
    ):
        """Test successful variant generation."""
        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.update_session_status = AsyncMock()
        mock_repo.get_session_variants = AsyncMock(return_value=sample_variants)
        mock_repo.update_variant_status = AsyncMock()

        result = await manager_with_tts.generate_variants(sample_session.id)

        # Check session status was updated
        assert mock_repo.update_session_status.call_count >= 2
        # Check variants were processed
        assert mock_repo.update_variant_status.call_count == len(sample_variants) * 2  # GENERATING + READY

    @pytest.mark.asyncio
    async def test_generate_variants_skips_ready(
        self, manager_with_tts, mock_repo, mock_tts_pool, sample_session, sample_variants
    ):
        """Test generation skips already ready variants."""
        # Mark one variant as ready
        sample_variants[0].status = VariantStatus.READY

        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.update_session_status = AsyncMock()
        mock_repo.get_session_variants = AsyncMock(return_value=sample_variants)
        mock_repo.update_variant_status = AsyncMock()

        await manager_with_tts.generate_variants(sample_session.id, regenerate=False)

        # Only 3 variants should be processed (not 4)
        expected_calls = 3 * 2  # 3 variants, 2 status updates each (GENERATING + READY)
        assert mock_repo.update_variant_status.call_count == expected_calls

    @pytest.mark.asyncio
    async def test_generate_variants_regenerate_all(
        self, manager_with_tts, mock_repo, mock_tts_pool, sample_session, sample_variants
    ):
        """Test regenerate=True regenerates all variants."""
        # Mark all variants as ready
        for v in sample_variants:
            v.status = VariantStatus.READY

        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.update_session_status = AsyncMock()
        mock_repo.get_session_variants = AsyncMock(return_value=sample_variants)
        mock_repo.update_variant_status = AsyncMock()

        await manager_with_tts.generate_variants(sample_session.id, regenerate=True)

        # All 4 variants should be processed
        expected_calls = 4 * 2  # 4 variants, 2 status updates each
        assert mock_repo.update_variant_status.call_count == expected_calls


class TestGetSessionWithVariants:
    """Tests for getting session with variants and ratings."""

    @pytest.mark.asyncio
    async def test_get_session_with_variants_success(
        self, manager, mock_repo, sample_session, sample_variants
    ):
        """Test getting session with all data."""
        rating = TTSComparisonRating.create(
            variant_id=sample_variants[0].id,
            rating=5,
            notes="Great!",
        )
        ratings_dict = {sample_variants[0].id: rating}

        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.get_session_variants = AsyncMock(return_value=sample_variants)
        mock_repo.get_session_ratings = AsyncMock(return_value=ratings_dict)

        session, variants, ratings = await manager.get_session_with_variants(sample_session.id)

        assert session is not None
        assert len(variants) == 4
        assert len(ratings) == 1

    @pytest.mark.asyncio
    async def test_get_session_with_variants_not_found(self, manager, mock_repo):
        """Test getting non-existent session returns empty data."""
        mock_repo.get_session = AsyncMock(return_value=None)

        session, variants, ratings = await manager.get_session_with_variants(uuid4())

        assert session is None
        assert variants == []
        assert ratings == {}


# =============================================================================
# Rating Tests
# =============================================================================


class TestRateVariant:
    """Tests for rating variants."""

    @pytest.mark.asyncio
    async def test_rate_variant_success(self, manager, mock_repo, sample_variants):
        """Test successful variant rating."""
        variant = sample_variants[0]
        mock_repo.get_variant = AsyncMock(return_value=variant)
        mock_repo.create_or_update_rating = AsyncMock(
            return_value=TTSComparisonRating.create(
                variant_id=variant.id,
                rating=4,
                notes="Good",
            )
        )

        result = await manager.rate_variant(variant.id, rating=4, notes="Good")

        assert result.rating == 4
        assert result.notes == "Good"
        mock_repo.create_or_update_rating.assert_called_once()

    @pytest.mark.asyncio
    async def test_rate_variant_invalid_rating_low(self, manager):
        """Test rating below 1 fails."""
        with pytest.raises(ValueError, match="between 1 and 5"):
            await manager.rate_variant(uuid4(), rating=0)

    @pytest.mark.asyncio
    async def test_rate_variant_invalid_rating_high(self, manager):
        """Test rating above 5 fails."""
        with pytest.raises(ValueError, match="between 1 and 5"):
            await manager.rate_variant(uuid4(), rating=6)

    @pytest.mark.asyncio
    async def test_rate_variant_not_found(self, manager, mock_repo):
        """Test rating non-existent variant fails."""
        mock_repo.get_variant = AsyncMock(return_value=None)

        with pytest.raises(ValueError, match="not found"):
            await manager.rate_variant(uuid4(), rating=3)


# =============================================================================
# Profile Creation Tests
# =============================================================================


class TestCreateProfileFromVariant:
    """Tests for creating profiles from variants."""

    @pytest.mark.asyncio
    async def test_create_profile_success(self, manager, mock_repo, sample_session, sample_variants):
        """Test successful profile creation from variant."""
        variant = sample_variants[0]
        variant.output_file = "/path/to/audio.wav"

        mock_repo.get_variant = AsyncMock(return_value=variant)
        mock_repo.get_profile_by_name = AsyncMock(return_value=None)
        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.create_profile = AsyncMock()

        profile = await manager.create_profile_from_variant(
            variant_id=variant.id,
            name="Winning Profile",
            description="The best one",
            tags=["winner"],
        )

        assert profile.name == "Winning Profile"
        mock_repo.create_profile.assert_called_once()

    @pytest.mark.asyncio
    async def test_create_profile_variant_not_found(self, manager, mock_repo):
        """Test profile creation fails for non-existent variant."""
        mock_repo.get_variant = AsyncMock(return_value=None)

        with pytest.raises(ValueError, match="not found"):
            await manager.create_profile_from_variant(
                variant_id=uuid4(),
                name="Profile",
            )

    @pytest.mark.asyncio
    async def test_create_profile_duplicate_name(self, manager, mock_repo, sample_variants):
        """Test profile creation fails for duplicate name."""
        variant = sample_variants[0]
        existing_profile = TTSProfile.create(
            name="Existing",
            provider="chatterbox",
            voice_id="nova",
        )

        mock_repo.get_variant = AsyncMock(return_value=variant)
        mock_repo.get_profile_by_name = AsyncMock(return_value=existing_profile)

        with pytest.raises(ValueError, match="already exists"):
            await manager.create_profile_from_variant(
                variant_id=variant.id,
                name="Existing",
            )


# =============================================================================
# Utility Method Tests
# =============================================================================


class TestGetAudioFilePath:
    """Tests for getting audio file paths."""

    @pytest.mark.asyncio
    async def test_get_audio_file_path_success(self, manager, mock_repo, sample_variants, tmp_path):
        """Test getting existing audio file path."""
        variant = sample_variants[0]
        audio_file = tmp_path / "test.wav"
        audio_file.touch()
        variant.output_file = str(audio_file)

        mock_repo.get_variant = AsyncMock(return_value=variant)

        result = await manager.get_audio_file_path(variant.id)

        assert result == str(audio_file)

    @pytest.mark.asyncio
    async def test_get_audio_file_path_no_output(self, manager, mock_repo, sample_variants):
        """Test getting path when variant has no output file."""
        variant = sample_variants[0]
        variant.output_file = None

        mock_repo.get_variant = AsyncMock(return_value=variant)

        result = await manager.get_audio_file_path(variant.id)

        assert result is None

    @pytest.mark.asyncio
    async def test_get_audio_file_path_file_missing(self, manager, mock_repo, sample_variants):
        """Test getting path when file doesn't exist."""
        variant = sample_variants[0]
        variant.output_file = "/nonexistent/path.wav"

        mock_repo.get_variant = AsyncMock(return_value=variant)

        result = await manager.get_audio_file_path(variant.id)

        assert result is None

    @pytest.mark.asyncio
    async def test_get_audio_file_path_variant_not_found(self, manager, mock_repo):
        """Test getting path for non-existent variant."""
        mock_repo.get_variant = AsyncMock(return_value=None)

        result = await manager.get_audio_file_path(uuid4())

        assert result is None


class TestGetSessionSummary:
    """Tests for session summary generation."""

    @pytest.mark.asyncio
    async def test_get_session_summary_success(
        self, manager, mock_repo, sample_session, sample_variants
    ):
        """Test getting session summary with ratings."""
        # Add some ratings
        ratings = {}
        for i, v in enumerate(sample_variants[:2]):
            v.status = VariantStatus.READY
            ratings[v.id] = TTSComparisonRating.create(
                variant_id=v.id,
                rating=4 + (i % 2),
                notes=f"Note {i}",
            )

        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.get_session_variants = AsyncMock(return_value=sample_variants)
        mock_repo.get_session_ratings = AsyncMock(return_value=ratings)

        summary = await manager.get_session_summary(sample_session.id)

        assert summary is not None
        assert summary["session_name"] == sample_session.name
        assert "configuration_rankings" in summary
        assert len(summary["configuration_rankings"]) == 2

    @pytest.mark.asyncio
    async def test_get_session_summary_not_found(self, manager, mock_repo):
        """Test summary for non-existent session."""
        mock_repo.get_session = AsyncMock(return_value=None)

        summary = await manager.get_session_summary(uuid4())

        assert summary is None

    @pytest.mark.asyncio
    async def test_get_session_summary_rankings_sorted(
        self, manager, mock_repo, sample_session, sample_variants
    ):
        """Test that rankings are sorted by average rating."""
        # Set all variants to ready
        for v in sample_variants:
            v.status = VariantStatus.READY

        # Config 0 gets low ratings, Config 1 gets high ratings
        ratings = {}
        for v in sample_variants:
            rating_value = 2 if v.config_index == 0 else 5
            ratings[v.id] = TTSComparisonRating.create(
                variant_id=v.id,
                rating=rating_value,
            )

        mock_repo.get_session = AsyncMock(return_value=sample_session)
        mock_repo.get_session_variants = AsyncMock(return_value=sample_variants)
        mock_repo.get_session_ratings = AsyncMock(return_value=ratings)

        summary = await manager.get_session_summary(sample_session.id)

        rankings = summary["configuration_rankings"]
        # Config 1 (rating 5) should be first
        assert rankings[0]["config_index"] == 1
        assert rankings[0]["average_rating"] == 5.0
        # Config 0 (rating 2) should be second
        assert rankings[1]["config_index"] == 0
        assert rankings[1]["average_rating"] == 2.0
