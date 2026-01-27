"""
Pytest configuration for management server tests.

Configures Hypothesis profiles for different environments:
- default: Standard local development (100 examples)
- ci: Faster CI runs (50 examples)
- thorough: Comprehensive testing (500 examples)

TESTING PHILOSOPHY: Real Over Mock
==================================
- Use REAL implementations wherever possible
- MockTTSCache, MockResourcePool, etc. are FORBIDDEN
- Use tmp_path for file-based services (TTSCache)
- Use aioresponses for external HTTP calls (TTS servers)
- Use in-memory SQLite for database tests
"""

import logging
import os

import pytest
import aiosqlite

from hypothesis import settings, Verbosity, Phase

logger = logging.getLogger(__name__)

# Detect CI environment
IS_CI = os.environ.get("CI") == "true" or os.environ.get("GITHUB_ACTIONS") == "true"


# =============================================================================
# REAL FIXTURES - NO MOCKS ALLOWED
# =============================================================================

@pytest.fixture
async def real_tts_cache(tmp_path):
    """Real TTSCache with temporary directory.

    Use this instead of MockTTSCache. The cache is fully functional
    and uses the tmp_path fixture for isolation.
    """
    from tts_cache.cache import TTSCache

    cache_dir = tmp_path / "tts_cache"
    cache = TTSCache(
        cache_dir=cache_dir,
        max_size_bytes=100 * 1024 * 1024,  # 100MB for tests
        default_ttl_days=1,
    )
    await cache.initialize()
    yield cache
    # Cleanup handled by tmp_path fixture


@pytest.fixture
def real_resource_pool():
    """Real TTSResourcePool with test configuration.

    Use this instead of MockResourcePool. For HTTP calls to TTS servers,
    use aioresponses to mock at the network layer (acceptable).
    """
    from tts_cache.resource_pool import TTSResourcePool

    pool = TTSResourcePool(
        max_concurrent_live=2,
        max_concurrent_background=1,
        request_timeout=5.0,
    )
    return pool


@pytest.fixture
async def real_db(tmp_path):
    """Real SQLite database with in-memory or file-based storage.

    Use this instead of MockConnection/MockDBPool.
    """
    db_path = tmp_path / "test.db"
    async with aiosqlite.connect(db_path) as db:
        db.row_factory = aiosqlite.Row
        yield db


@pytest.fixture
async def in_memory_db():
    """In-memory SQLite database for fast tests.

    Use this instead of MockConnection/MockDBPool.
    """
    async with aiosqlite.connect(":memory:") as db:
        db.row_factory = aiosqlite.Row
        yield db

# Configure Hypothesis profiles
settings.register_profile(
    "default",
    max_examples=100,
    verbosity=Verbosity.normal,
    deadline=None,  # Disable deadline for potentially slow tests
)

settings.register_profile(
    "ci",
    max_examples=50,
    verbosity=Verbosity.normal,
    deadline=None,
    suppress_health_check=[],
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.shrink],
)

settings.register_profile(
    "thorough",
    max_examples=500,
    verbosity=Verbosity.verbose,
    deadline=None,
)

settings.register_profile(
    "debug",
    max_examples=10,
    verbosity=Verbosity.verbose,
    deadline=None,
)

# Load appropriate profile
profile_name = os.environ.get("HYPOTHESIS_PROFILE", "ci" if IS_CI else "default")
settings.load_profile(profile_name)

logger.info(f"Hypothesis profile: {profile_name}")
