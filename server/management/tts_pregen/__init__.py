# TTS Pre-Generation Module
# Batch audio generation and voice profile management

from .models import (
    TTSProfile,
    TTSProfileSettings,
    TTSModuleProfile,
    TTSPregenJob,
    TTSJobItem,
    TTSComparisonSession,
    TTSComparisonVariant,
    TTSComparisonRating,
    JobStatus,
    ItemStatus,
    SessionStatus,
    VariantStatus,
)
from .repository import TTSPregenRepository
from .profile_manager import TTSProfileManager
from .comparison_manager import TTSComparisonManager
from .job_manager import JobManager
from .orchestrator import TTSPregenOrchestrator
from .content_extractors import (
    ContentExtractor,
    KnowledgeBowlExtractor,
    CurriculumExtractor,
    CustomTextExtractor,
    get_extractor,
)

__all__ = [
    # Models
    "TTSProfile",
    "TTSProfileSettings",
    "TTSModuleProfile",
    "TTSPregenJob",
    "TTSJobItem",
    "TTSComparisonSession",
    "TTSComparisonVariant",
    "TTSComparisonRating",
    # Enums
    "JobStatus",
    "ItemStatus",
    "SessionStatus",
    "VariantStatus",
    # Services
    "TTSPregenRepository",
    "TTSProfileManager",
    "TTSComparisonManager",
    "JobManager",
    "TTSPregenOrchestrator",
    # Content Extractors
    "ContentExtractor",
    "KnowledgeBowlExtractor",
    "CurriculumExtractor",
    "CustomTextExtractor",
    "get_extractor",
]
