"""Property-based tests for TTS Pre-generation models.

Tests invariants that should always hold:
- Job progress calculations are consistent
- Serialization roundtrips preserve all data
- State machine transitions are valid
- Hash functions are deterministic
- Variant matrices are complete
"""

import pytest
from datetime import datetime, timedelta
from uuid import uuid4, UUID
from hypothesis import given, strategies as st, assume, settings

from tts_pregen.models import (
    JobStatus,
    ItemStatus,
    SessionStatus,
    VariantStatus,
    TTSProfileSettings,
    TTSProfile,
    TTSPregenJob,
    TTSJobItem,
    TTSComparisonSession,
    TTSComparisonVariant,
    TTSComparisonRating,
)


# --- Strategies for generating test data ---

def job_status_strategy():
    """Generate valid job statuses."""
    return st.sampled_from(list(JobStatus))


def item_status_strategy():
    """Generate valid item statuses."""
    return st.sampled_from(list(ItemStatus))


def session_status_strategy():
    """Generate valid session statuses."""
    return st.sampled_from(list(SessionStatus))


def variant_status_strategy():
    """Generate valid variant statuses."""
    return st.sampled_from(list(VariantStatus))


def provider_strategy():
    """Generate valid TTS provider names."""
    return st.sampled_from(["chatterbox", "vibevoice", "piper", "deepgram"])


def voice_id_strategy():
    """Generate valid voice IDs."""
    return st.text(min_size=1, max_size=50, alphabet=st.characters(whitelist_categories=("L", "N", "Pd")))


def name_strategy():
    """Generate valid names."""
    return st.text(min_size=1, max_size=100, alphabet=st.characters(whitelist_categories=("L", "N", "Zs")))


def text_content_strategy():
    """Generate text content for TTS."""
    return st.text(min_size=1, max_size=1000)


def tts_config_strategy():
    """Generate TTS configuration dictionaries."""
    return st.fixed_dictionaries({
        "provider": provider_strategy(),
        "voice_id": voice_id_strategy(),
    })


class TestJobProgressInvariants:
    """Property tests for job progress calculations."""

    @given(
        total=st.integers(min_value=0, max_value=10000),
        completed=st.integers(min_value=0, max_value=10000),
        failed=st.integers(min_value=0, max_value=10000),
    )
    def test_pending_items_formula(self, total: int, completed: int, failed: int):
        """pending_items = total - completed - failed."""
        # Assume valid state: completed + failed <= total
        assume(completed + failed <= total)

        job = TTSPregenJob(
            id=uuid4(),
            name="test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            total_items=total,
            completed_items=completed,
            failed_items=failed,
        )

        expected_pending = total - completed - failed
        assert job.pending_items == expected_pending, (
            f"pending_items should be {expected_pending}, got {job.pending_items}"
        )

    @given(
        total=st.integers(min_value=1, max_value=10000),
        completed=st.integers(min_value=0, max_value=10000),
    )
    def test_percent_complete_bounds(self, total: int, completed: int):
        """percent_complete should be in [0, 100]."""
        assume(completed <= total)

        job = TTSPregenJob(
            id=uuid4(),
            name="test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            total_items=total,
            completed_items=completed,
            failed_items=0,
        )

        assert 0.0 <= job.percent_complete <= 100.0, (
            f"percent_complete should be in [0, 100], got {job.percent_complete}"
        )

    @given(
        total=st.integers(min_value=1, max_value=10000),
        completed=st.integers(min_value=0, max_value=10000),
    )
    def test_percent_complete_calculation(self, total: int, completed: int):
        """percent_complete = (completed / total) * 100."""
        assume(completed <= total)

        job = TTSPregenJob(
            id=uuid4(),
            name="test",
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            total_items=total,
            completed_items=completed,
            failed_items=0,
        )

        expected = (completed / total) * 100
        assert abs(job.percent_complete - expected) < 0.001, (
            f"percent_complete should be {expected}, got {job.percent_complete}"
        )

    def test_percent_complete_zero_total(self):
        """percent_complete should be 0 when total_items is 0."""
        job = TTSPregenJob(
            id=uuid4(),
            name="test",
            job_type="batch",
            status=JobStatus.PENDING,
            source_type="custom",
            total_items=0,
            completed_items=0,
            failed_items=0,
        )

        assert job.percent_complete == 0.0, "percent_complete should be 0 for empty job"


class TestJobStatusMachine:
    """Property tests for job status transitions."""

    @given(status=job_status_strategy())
    def test_is_resumable_only_paused_or_failed(self, status: JobStatus):
        """is_resumable should be True only for PAUSED or FAILED."""
        job = TTSPregenJob(
            id=uuid4(),
            name="test",
            job_type="batch",
            status=status,
            source_type="custom",
        )

        expected = status in (JobStatus.PAUSED, JobStatus.FAILED)
        assert job.is_resumable == expected, (
            f"is_resumable for {status} should be {expected}, got {job.is_resumable}"
        )

    @given(status=job_status_strategy())
    def test_status_value_matches_enum(self, status: JobStatus):
        """Status value should match enum string."""
        assert status.value == status.name.lower(), (
            f"Status {status} value '{status.value}' doesn't match name.lower()"
        )


class TestTextHashInvariants:
    """Property tests for text hashing."""

    @given(text=text_content_strategy())
    def test_hash_is_deterministic(self, text: str):
        """Same text should always produce same hash."""
        hash1 = TTSJobItem.hash_text(text)
        hash2 = TTSJobItem.hash_text(text)
        assert hash1 == hash2, "Hash should be deterministic"

    @given(text=text_content_strategy())
    def test_hash_is_sha256_hex(self, text: str):
        """Hash should be 64 character hex string (SHA-256)."""
        hash_value = TTSJobItem.hash_text(text)
        assert len(hash_value) == 64, f"SHA-256 hash should be 64 chars, got {len(hash_value)}"
        assert all(c in "0123456789abcdef" for c in hash_value), "Hash should be hex"

    @given(text1=text_content_strategy(), text2=text_content_strategy())
    def test_different_texts_different_hashes(self, text1: str, text2: str):
        """Different texts should produce different hashes (with high probability)."""
        assume(text1 != text2)
        hash1 = TTSJobItem.hash_text(text1)
        hash2 = TTSJobItem.hash_text(text2)
        assert hash1 != hash2, "Different texts should have different hashes"

    @given(text=text_content_strategy())
    def test_item_creation_sets_hash(self, text: str):
        """Creating an item should set the correct hash."""
        item = TTSJobItem.create(
            job_id=uuid4(),
            item_index=0,
            text_content=text,
        )
        expected_hash = TTSJobItem.hash_text(text)
        assert item.text_hash == expected_hash, "Item hash should match hash_text()"


class TestSerializationRoundtrip:
    """Property tests for serialization roundtrips."""

    @given(
        speed=st.floats(min_value=0.1, max_value=3.0, allow_nan=False),
        exaggeration=st.one_of(st.none(), st.floats(min_value=0.0, max_value=2.0, allow_nan=False)),
    )
    def test_profile_settings_roundtrip(self, speed: float, exaggeration):
        """TTSProfileSettings should survive to_dict/from_dict roundtrip."""
        settings = TTSProfileSettings(
            speed=speed,
            exaggeration=exaggeration,
        )

        d = settings.to_dict()
        restored = TTSProfileSettings.from_dict(d)

        assert abs(restored.speed - speed) < 0.001, "Speed should be preserved"
        if exaggeration is not None:
            assert restored.exaggeration is not None
            assert abs(restored.exaggeration - exaggeration) < 0.001
        else:
            assert restored.exaggeration is None

    @given(
        name=name_strategy(),
        provider=provider_strategy(),
        voice_id=voice_id_strategy(),
    )
    def test_profile_roundtrip(self, name: str, provider: str, voice_id: str):
        """TTSProfile should survive to_dict/from_dict roundtrip."""
        assume(len(name.strip()) > 0)
        assume(len(voice_id.strip()) > 0)

        profile = TTSProfile.create(
            name=name,
            provider=provider,
            voice_id=voice_id,
        )

        d = profile.to_dict()
        restored = TTSProfile.from_dict(d)

        assert restored.name == name, "Name should be preserved"
        assert restored.provider == provider, "Provider should be preserved"
        assert restored.voice_id == voice_id, "Voice ID should be preserved"
        assert restored.id == profile.id, "ID should be preserved"

    @given(
        name=name_strategy(),
        total_items=st.integers(min_value=0, max_value=1000),
        completed_items=st.integers(min_value=0, max_value=1000),
    )
    def test_job_roundtrip(self, name: str, total_items: int, completed_items: int):
        """TTSPregenJob should survive to_dict/from_dict roundtrip."""
        assume(len(name.strip()) > 0)
        assume(completed_items <= total_items)

        job = TTSPregenJob(
            id=uuid4(),
            name=name,
            job_type="batch",
            status=JobStatus.RUNNING,
            source_type="custom",
            total_items=total_items,
            completed_items=completed_items,
            failed_items=0,
        )

        d = job.to_dict()
        restored = TTSPregenJob.from_dict(d)

        assert restored.name == name, "Name should be preserved"
        assert restored.total_items == total_items, "Total items should be preserved"
        assert restored.completed_items == completed_items, "Completed items should be preserved"
        assert restored.id == job.id, "ID should be preserved"
        assert restored.status == job.status, "Status should be preserved"

    @given(
        text=text_content_strategy(),
        item_index=st.integers(min_value=0, max_value=10000),
    )
    def test_job_item_roundtrip(self, text: str, item_index: int):
        """TTSJobItem should survive to_dict/from_dict roundtrip."""
        item = TTSJobItem.create(
            job_id=uuid4(),
            item_index=item_index,
            text_content=text,
        )

        d = item.to_dict()
        restored = TTSJobItem.from_dict(d)

        assert restored.text_content == text, "Text should be preserved"
        assert restored.item_index == item_index, "Index should be preserved"
        assert restored.text_hash == item.text_hash, "Hash should be preserved"
        assert restored.id == item.id, "ID should be preserved"


class TestComparisonSessionInvariants:
    """Property tests for comparison sessions."""

    @given(
        num_samples=st.integers(min_value=1, max_value=10),
        num_configs=st.integers(min_value=1, max_value=10),
    )
    def test_total_variants_formula(self, num_samples: int, num_configs: int):
        """total_variants = sample_count * config_count."""
        samples = [{"text": f"sample{i}"} for i in range(num_samples)]
        configs = [{"provider": "test", "voice_id": f"voice{i}"} for i in range(num_configs)]

        session = TTSComparisonSession.create(
            name="test",
            samples=samples,
            configurations=configs,
        )

        assert session.sample_count == num_samples, "Sample count should match"
        assert session.config_count == num_configs, "Config count should match"
        assert session.total_variants == num_samples * num_configs, (
            f"Total variants should be {num_samples * num_configs}, got {session.total_variants}"
        )

    @given(
        sample_index=st.integers(min_value=0, max_value=100),
        config_index=st.integers(min_value=0, max_value=100),
    )
    def test_variant_indices_preserved(self, sample_index: int, config_index: int):
        """Variant indices should be preserved through roundtrip."""
        variant = TTSComparisonVariant.create(
            session_id=uuid4(),
            sample_index=sample_index,
            config_index=config_index,
            text_content="test text",
            tts_config={"provider": "test"},
        )

        d = variant.to_dict()
        restored = TTSComparisonVariant.from_dict(d)

        assert restored.sample_index == sample_index, "Sample index should be preserved"
        assert restored.config_index == config_index, "Config index should be preserved"


class TestRatingBounds:
    """Property tests for rating validation."""

    @given(rating=st.integers(min_value=1, max_value=5))
    def test_valid_ratings_accepted(self, rating: int):
        """Ratings 1-5 should be valid."""
        variant_rating = TTSComparisonRating.create(
            variant_id=uuid4(),
            rating=rating,
        )
        assert variant_rating.rating == rating, "Rating should be preserved"

    def test_none_rating_allowed(self):
        """None rating (unrated) should be allowed."""
        variant_rating = TTSComparisonRating.create(
            variant_id=uuid4(),
            rating=None,
        )
        assert variant_rating.rating is None, "None rating should be allowed"

    @given(rating=st.one_of(st.none(), st.integers(min_value=1, max_value=5)))
    def test_rating_roundtrip(self, rating):
        """Rating should survive roundtrip."""
        variant_rating = TTSComparisonRating.create(
            variant_id=uuid4(),
            rating=rating,
        )

        d = variant_rating.to_dict()
        restored = TTSComparisonRating.from_dict(d)

        assert restored.rating == rating, "Rating should be preserved through roundtrip"


class TestEnumConsistency:
    """Property tests for enum consistency."""

    @given(status=job_status_strategy())
    def test_job_status_roundtrip(self, status: JobStatus):
        """JobStatus should roundtrip through value."""
        value = status.value
        restored = JobStatus(value)
        assert restored == status

    @given(status=item_status_strategy())
    def test_item_status_roundtrip(self, status: ItemStatus):
        """ItemStatus should roundtrip through value."""
        value = status.value
        restored = ItemStatus(value)
        assert restored == status

    @given(status=session_status_strategy())
    def test_session_status_roundtrip(self, status: SessionStatus):
        """SessionStatus should roundtrip through value."""
        value = status.value
        restored = SessionStatus(value)
        assert restored == status

    @given(status=variant_status_strategy())
    def test_variant_status_roundtrip(self, status: VariantStatus):
        """VariantStatus should roundtrip through value."""
        value = status.value
        restored = VariantStatus(value)
        assert restored == status


class TestUUIDHandling:
    """Property tests for UUID handling in models."""

    @given(st.uuids())
    def test_profile_id_roundtrip(self, profile_id: UUID):
        """Profile ID should survive roundtrip as both UUID and string."""
        profile = TTSProfile(
            id=profile_id,
            name="test",
            provider="test",
            voice_id="test",
            settings=TTSProfileSettings(),
        )

        d = profile.to_dict()
        assert d["id"] == str(profile_id), "ID should serialize to string"

        restored = TTSProfile.from_dict(d)
        assert restored.id == profile_id, "ID should deserialize back to UUID"

    @given(st.uuids(), st.uuids())
    def test_job_item_ids_roundtrip(self, item_id: UUID, job_id: UUID):
        """Job item IDs should survive roundtrip."""
        item = TTSJobItem(
            id=item_id,
            job_id=job_id,
            item_index=0,
            text_content="test",
            text_hash=TTSJobItem.hash_text("test"),
        )

        d = item.to_dict()
        restored = TTSJobItem.from_dict(d)

        assert restored.id == item_id, "Item ID should be preserved"
        assert restored.job_id == job_id, "Job ID should be preserved"
