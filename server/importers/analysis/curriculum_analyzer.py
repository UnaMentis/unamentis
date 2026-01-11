"""
Curriculum Analyzer - Detects quality issues in UMCF curricula.

This module provides comprehensive analysis of curriculum content to identify:
- Broken or placeholder images
- Improperly chunked segments (too long or too short)
- Missing learning objectives
- Missing comprehension checkpoints
- Missing alternative explanations
- Incomplete metadata
"""

import asyncio
import logging
import time
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

import aiohttp

from ..core.reprocess_models import (
    AnalysisIssue,
    AnalysisStats,
    CurriculumAnalysis,
    IssueSeverity,
    IssueType,
)

logger = logging.getLogger(__name__)

# Analysis thresholds
MAX_SEGMENT_LENGTH = 2000  # Characters - longer is hard to follow in voice
MIN_SEGMENT_LENGTH = 100   # Characters - shorter may be too fragmented
CHECKPOINT_EVERY_N_SEGMENTS = 3  # Expected checkpoint frequency

# Valid Bloom taxonomy levels
VALID_BLOOM_LEVELS = {
    "remember", "understand", "apply", "analyze", "evaluate", "create"
}

# Required metadata fields
REQUIRED_METADATA = ["title", "description"]


class CurriculumAnalyzer:
    """
    Analyzes UMCF curricula for quality issues.

    This analyzer walks the entire curriculum tree and checks for various
    quality issues that can be automatically fixed through reprocessing.
    """

    def __init__(self, http_timeout: float = 5.0):
        """
        Initialize the analyzer.

        Args:
            http_timeout: Timeout for HTTP requests (image validation)
        """
        self.http_timeout = http_timeout
        self._issue_counter = 0

    def _next_issue_id(self) -> str:
        """Generate next issue ID."""
        self._issue_counter += 1
        return f"issue-{self._issue_counter:04d}"

    async def analyze(self, curriculum: Dict[str, Any]) -> CurriculumAnalysis:
        """
        Run full analysis on a curriculum.

        Args:
            curriculum: The UMCF curriculum dict

        Returns:
            CurriculumAnalysis with all detected issues
        """
        start_time = time.time()
        self._issue_counter = 0

        curriculum_id = curriculum.get("id", "unknown")
        curriculum_title = curriculum.get("title", "Untitled")

        logger.info(f"Starting analysis of curriculum: {curriculum_title}")

        # Run all checks
        issues: List[AnalysisIssue] = []

        # Image checks (async for HTTP requests)
        image_issues = await self.check_images(curriculum)
        issues.extend(image_issues)

        # Content structure checks (sync)
        chunking_issues = self.check_chunking(curriculum)
        issues.extend(chunking_issues)

        objective_issues = self.check_objectives(curriculum)
        issues.extend(objective_issues)

        checkpoint_issues = self.check_checkpoints(curriculum)
        issues.extend(checkpoint_issues)

        alternative_issues = self.check_alternatives(curriculum)
        issues.extend(alternative_issues)

        metadata_issues = self.check_metadata(curriculum)
        issues.extend(metadata_issues)

        # Calculate stats
        stats = self._calculate_stats(issues)

        duration_ms = int((time.time() - start_time) * 1000)

        logger.info(
            f"Analysis complete: {stats.total_issues} issues found "
            f"({stats.critical_count} critical, {stats.warning_count} warning, "
            f"{stats.info_count} info) in {duration_ms}ms"
        )

        return CurriculumAnalysis(
            curriculum_id=curriculum_id,
            curriculum_title=curriculum_title,
            analyzed_at=datetime.utcnow(),
            analysis_duration_ms=duration_ms,
            issues=issues,
            stats=stats,
        )

    def _calculate_stats(self, issues: List[AnalysisIssue]) -> AnalysisStats:
        """Calculate summary statistics from issues list."""
        stats = AnalysisStats()
        stats.total_issues = len(issues)

        for issue in issues:
            # Count by severity
            if issue.severity == IssueSeverity.CRITICAL.value:
                stats.critical_count += 1
            elif issue.severity == IssueSeverity.WARNING.value:
                stats.warning_count += 1
            elif issue.severity == IssueSeverity.INFO.value:
                stats.info_count += 1

            # Count auto-fixable
            if issue.auto_fixable:
                stats.auto_fixable_count += 1

            # Count by type
            if issue.issue_type not in stats.issues_by_type:
                stats.issues_by_type[issue.issue_type] = 0
            stats.issues_by_type[issue.issue_type] += 1

        return stats

    # =========================================================================
    # Image Validation
    # =========================================================================

    async def check_images(self, curriculum: Dict[str, Any]) -> List[AnalysisIssue]:
        """
        Validate image URLs with HEAD requests.

        Checks for:
        - Broken URLs (404, timeout, etc.)
        - Images marked as placeholder
        """
        issues = []
        images = self._find_all_images(curriculum)

        if not images:
            return issues

        logger.debug(f"Checking {len(images)} images")

        # Check images concurrently with rate limiting
        semaphore = asyncio.Semaphore(10)  # Max 10 concurrent requests

        async def check_single_image(image_info: Tuple[str, Dict[str, Any]]) -> Optional[AnalysisIssue]:
            location, asset = image_info
            async with semaphore:
                return await self._validate_image(location, asset)

        tasks = [check_single_image(img) for img in images]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        for result in results:
            if isinstance(result, AnalysisIssue):
                issues.append(result)
            elif isinstance(result, Exception):
                logger.warning(f"Image check error: {result}")

        return issues

    async def _validate_image(
        self,
        location: str,
        asset: Dict[str, Any]
    ) -> Optional[AnalysisIssue]:
        """Validate a single image asset."""

        # Check for placeholder flag
        if asset.get("isPlaceholder"):
            return AnalysisIssue(
                id=self._next_issue_id(),
                issue_type=IssueType.PLACEHOLDER_IMAGE.value,
                severity=IssueSeverity.WARNING.value,
                location=location,
                node_id=asset.get("id"),
                description=f"Image is marked as placeholder: {asset.get('alt', 'Unknown')}",
                suggested_fix="Search Wikimedia Commons for replacement image",
                auto_fixable=True,
                details={
                    "alt": asset.get("alt", ""),
                    "title": asset.get("title", ""),
                },
            )

        # Check URL if present
        url = asset.get("url")
        if not url:
            # No URL and has embedded data is fine
            if asset.get("data"):
                return None
            return AnalysisIssue(
                id=self._next_issue_id(),
                issue_type=IssueType.BROKEN_IMAGE.value,
                severity=IssueSeverity.CRITICAL.value,
                location=location,
                node_id=asset.get("id"),
                description="Image has no URL or embedded data",
                suggested_fix="Search Wikimedia Commons for replacement image",
                auto_fixable=True,
                details={},
            )

        # Validate URL with HEAD request
        try:
            timeout = aiohttp.ClientTimeout(total=self.http_timeout)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.head(url, allow_redirects=True) as resp:
                    if resp.status != 200:
                        return AnalysisIssue(
                            id=self._next_issue_id(),
                            issue_type=IssueType.BROKEN_IMAGE.value,
                            severity=IssueSeverity.CRITICAL.value,
                            location=location,
                            node_id=asset.get("id"),
                            description=f"Image URL returns HTTP {resp.status}",
                            suggested_fix="Search Wikimedia Commons for replacement image",
                            auto_fixable=True,
                            details={
                                "url": url,
                                "httpStatus": resp.status,
                            },
                        )
        except asyncio.TimeoutError:
            return AnalysisIssue(
                id=self._next_issue_id(),
                issue_type=IssueType.BROKEN_IMAGE.value,
                severity=IssueSeverity.CRITICAL.value,
                location=location,
                node_id=asset.get("id"),
                description=f"Image URL timed out after {self.http_timeout}s",
                suggested_fix="Search Wikimedia Commons for replacement image",
                auto_fixable=True,
                details={"url": url, "timeout": self.http_timeout},
            )
        except Exception as e:
            return AnalysisIssue(
                id=self._next_issue_id(),
                issue_type=IssueType.BROKEN_IMAGE.value,
                severity=IssueSeverity.CRITICAL.value,
                location=location,
                node_id=asset.get("id"),
                description=f"Image URL validation failed: {str(e)}",
                suggested_fix="Search Wikimedia Commons for replacement image",
                auto_fixable=True,
                details={"url": url, "error": str(e)},
            )

        return None

    def _find_all_images(self, curriculum: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
        """Find all image assets in the curriculum."""
        images = []

        def walk(obj: Any, path: str):
            if isinstance(obj, dict):
                # Check if this is an image asset
                if obj.get("type") == "image" or "mimeType" in obj and "image" in obj.get("mimeType", ""):
                    images.append((path, obj))

                # Check assets array
                if "assets" in obj:
                    for i, asset in enumerate(obj["assets"]):
                        if isinstance(asset, dict):
                            asset_type = asset.get("type", "")
                            mime_type = asset.get("mimeType", "")
                            if asset_type == "image" or "image" in mime_type:
                                images.append((f"{path}/assets/{i}", asset))

                # Recurse into children
                for key, value in obj.items():
                    if key not in ("assets",):  # Already handled
                        walk(value, f"{path}/{key}")

            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    walk(item, f"{path}/{i}")

        walk(curriculum, "")
        return images

    # =========================================================================
    # Chunking Analysis
    # =========================================================================

    def check_chunking(self, curriculum: Dict[str, Any]) -> List[AnalysisIssue]:
        """
        Find segments with inappropriate length.

        Checks for:
        - Oversized segments (> 2000 characters)
        - Undersized segments (< 100 characters)
        """
        issues = []
        segments = self._find_all_segments(curriculum)

        logger.debug(f"Checking {len(segments)} segments for chunking issues")

        for location, segment in segments:
            content = segment.get("content", "")
            char_count = len(content)
            segment_type = segment.get("type", "content")

            # Skip checkpoint/summary segments for undersized check
            if char_count > MAX_SEGMENT_LENGTH:
                issues.append(AnalysisIssue(
                    id=self._next_issue_id(),
                    issue_type=IssueType.OVERSIZED_SEGMENT.value,
                    severity=IssueSeverity.WARNING.value,
                    location=location,
                    node_id=segment.get("id"),
                    description=f"Segment has {char_count:,} characters (max {MAX_SEGMENT_LENGTH:,})",
                    suggested_fix="Use LLM to split into 2-3 smaller conversational segments",
                    auto_fixable=True,
                    details={
                        "charCount": char_count,
                        "recommendedMax": MAX_SEGMENT_LENGTH,
                        "segmentType": segment_type,
                        "preview": content[:100] + "..." if len(content) > 100 else content,
                    },
                ))
            elif char_count < MIN_SEGMENT_LENGTH and segment_type not in ("checkpoint", "summary", "question"):
                issues.append(AnalysisIssue(
                    id=self._next_issue_id(),
                    issue_type=IssueType.UNDERSIZED_SEGMENT.value,
                    severity=IssueSeverity.INFO.value,
                    location=location,
                    node_id=segment.get("id"),
                    description=f"Segment has only {char_count} characters (min {MIN_SEGMENT_LENGTH})",
                    suggested_fix="Consider merging with adjacent segment",
                    auto_fixable=True,
                    details={
                        "charCount": char_count,
                        "recommendedMin": MIN_SEGMENT_LENGTH,
                        "segmentType": segment_type,
                        "content": content,
                    },
                ))

        return issues

    def _find_all_segments(self, curriculum: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
        """Find all transcript segments in the curriculum."""
        segments = []

        def walk(obj: Any, path: str):
            if isinstance(obj, dict):
                # Check for transcript with segments
                if "transcript" in obj and isinstance(obj["transcript"], dict):
                    transcript = obj["transcript"]
                    if "segments" in transcript and isinstance(transcript["segments"], list):
                        for i, seg in enumerate(transcript["segments"]):
                            if isinstance(seg, dict) and "content" in seg:
                                segments.append((f"{path}/transcript/segments/{i}", seg))

                # Recurse
                for key, value in obj.items():
                    walk(value, f"{path}/{key}")

            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    walk(item, f"{path}/{i}")

        walk(curriculum, "")
        return segments

    # =========================================================================
    # Learning Objectives Check
    # =========================================================================

    def check_objectives(self, curriculum: Dict[str, Any]) -> List[AnalysisIssue]:
        """
        Find topics missing learning objectives.
        """
        issues = []
        topics = self._find_all_topics(curriculum)

        logger.debug(f"Checking {len(topics)} topics for learning objectives")

        for location, topic in topics:
            objectives = topic.get("learningObjectives", [])

            if not objectives:
                issues.append(AnalysisIssue(
                    id=self._next_issue_id(),
                    issue_type=IssueType.MISSING_OBJECTIVES.value,
                    severity=IssueSeverity.WARNING.value,
                    location=location,
                    node_id=topic.get("id"),
                    description=f"Topic '{topic.get('title', 'Untitled')}' has no learning objectives",
                    suggested_fix="Use LLM to generate Bloom-aligned learning objectives",
                    auto_fixable=True,
                    details={
                        "topicTitle": topic.get("title", ""),
                    },
                ))
            else:
                # Check for invalid Bloom levels
                for i, obj in enumerate(objectives):
                    bloom_level = obj.get("bloomLevel", "").lower()
                    if bloom_level and bloom_level not in VALID_BLOOM_LEVELS:
                        issues.append(AnalysisIssue(
                            id=self._next_issue_id(),
                            issue_type=IssueType.INVALID_BLOOM_LEVEL.value,
                            severity=IssueSeverity.INFO.value,
                            location=f"{location}/learningObjectives/{i}",
                            node_id=obj.get("id"),
                            description=f"Invalid Bloom level: '{bloom_level}'",
                            suggested_fix=f"Update to valid level: {', '.join(VALID_BLOOM_LEVELS)}",
                            auto_fixable=True,
                            details={
                                "currentLevel": bloom_level,
                                "validLevels": list(VALID_BLOOM_LEVELS),
                            },
                        ))

        return issues

    # =========================================================================
    # Checkpoints Check
    # =========================================================================

    def check_checkpoints(self, curriculum: Dict[str, Any]) -> List[AnalysisIssue]:
        """
        Find topics missing comprehension checkpoints.
        """
        issues = []
        topics = self._find_all_topics(curriculum)

        for location, topic in topics:
            # Count segments and checkpoints
            segments = []
            checkpoints = []

            transcript = topic.get("transcript", {})
            if isinstance(transcript, dict):
                for seg in transcript.get("segments", []):
                    if isinstance(seg, dict):
                        segments.append(seg)
                        if seg.get("type") == "checkpoint" or seg.get("checkpoint"):
                            checkpoints.append(seg)

            # Check if there should be checkpoints
            content_segments = [s for s in segments if s.get("type") not in ("checkpoint", "summary")]
            expected_checkpoints = len(content_segments) // CHECKPOINT_EVERY_N_SEGMENTS

            if expected_checkpoints > 0 and len(checkpoints) == 0:
                issues.append(AnalysisIssue(
                    id=self._next_issue_id(),
                    issue_type=IssueType.MISSING_CHECKPOINTS.value,
                    severity=IssueSeverity.WARNING.value,
                    location=location,
                    node_id=topic.get("id"),
                    description=f"Topic '{topic.get('title', 'Untitled')}' has {len(content_segments)} segments but no comprehension checks",
                    suggested_fix=f"Use LLM to generate {expected_checkpoints} comprehension checkpoints",
                    auto_fixable=True,
                    details={
                        "topicTitle": topic.get("title", ""),
                        "segmentCount": len(content_segments),
                        "expectedCheckpoints": expected_checkpoints,
                    },
                ))

        return issues

    # =========================================================================
    # Alternative Explanations Check
    # =========================================================================

    def check_alternatives(self, curriculum: Dict[str, Any]) -> List[AnalysisIssue]:
        """
        Find segments missing alternative explanations.
        """
        issues = []
        segments = self._find_all_segments(curriculum)

        # Only check substantial explanation segments
        for location, segment in segments:
            segment_type = segment.get("type", "")
            content = segment.get("content", "")

            # Only check explanation-type segments with substantial content
            if segment_type in ("explanation", "lecture", "content") and len(content) > 300:
                alternatives = segment.get("alternativeExplanations", [])

                if not alternatives:
                    issues.append(AnalysisIssue(
                        id=self._next_issue_id(),
                        issue_type=IssueType.MISSING_ALTERNATIVES.value,
                        severity=IssueSeverity.INFO.value,
                        location=location,
                        node_id=segment.get("id"),
                        description="Explanation segment has no alternative explanations",
                        suggested_fix="Use LLM to generate simpler/technical/analogy alternatives",
                        auto_fixable=True,
                        details={
                            "segmentType": segment_type,
                            "charCount": len(content),
                        },
                    ))

        return issues

    # =========================================================================
    # Metadata Check
    # =========================================================================

    def check_metadata(self, curriculum: Dict[str, Any]) -> List[AnalysisIssue]:
        """
        Find missing or invalid metadata.
        """
        issues = []

        # Check top-level required fields
        for field in REQUIRED_METADATA:
            value = curriculum.get(field, "")
            if not value or (isinstance(value, str) and not value.strip()):
                issues.append(AnalysisIssue(
                    id=self._next_issue_id(),
                    issue_type=IssueType.MISSING_METADATA.value,
                    severity=IssueSeverity.WARNING.value,
                    location=f"/{field}",
                    node_id=None,
                    description=f"Required metadata field '{field}' is missing or empty",
                    suggested_fix=f"Infer {field} from content or source metadata",
                    auto_fixable=field != "title",  # Title requires manual input
                    details={"field": field},
                ))

        # Check time estimates
        topics = self._find_all_topics(curriculum)
        for location, topic in topics:
            if not topic.get("typicalLearningTime") and not topic.get("timeEstimates"):
                # Only flag if topic has substantial content
                transcript = topic.get("transcript", {})
                segments = transcript.get("segments", []) if isinstance(transcript, dict) else []
                if len(segments) > 2:
                    issues.append(AnalysisIssue(
                        id=self._next_issue_id(),
                        issue_type=IssueType.MISSING_TIME_ESTIMATE.value,
                        severity=IssueSeverity.INFO.value,
                        location=location,
                        node_id=topic.get("id"),
                        description=f"Topic '{topic.get('title', 'Untitled')}' has no time estimate",
                        suggested_fix="Calculate from segment count and average reading pace",
                        auto_fixable=True,
                        details={
                            "topicTitle": topic.get("title", ""),
                            "segmentCount": len(segments),
                        },
                    ))

        return issues

    # =========================================================================
    # Helper Methods
    # =========================================================================

    def _find_all_topics(self, curriculum: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
        """Find all topic nodes in the curriculum."""
        topics = []

        def walk(obj: Any, path: str, depth: int = 0):
            if isinstance(obj, dict):
                # Check if this looks like a topic
                # Topics have title and usually transcript or children
                if "title" in obj and ("transcript" in obj or "children" in obj or depth > 1):
                    topics.append((path, obj))

                # Recurse into content structure
                if "content" in obj:
                    walk(obj["content"], f"{path}/content", depth + 1)
                if "modules" in obj:
                    for i, mod in enumerate(obj["modules"]):
                        walk(mod, f"{path}/modules/{i}", depth + 1)
                if "topics" in obj:
                    for i, topic in enumerate(obj["topics"]):
                        walk(topic, f"{path}/topics/{i}", depth + 1)
                if "children" in obj:
                    for i, child in enumerate(obj["children"]):
                        walk(child, f"{path}/children/{i}", depth + 1)

            elif isinstance(obj, list):
                for i, item in enumerate(obj):
                    walk(item, f"{path}/{i}", depth)

        walk(curriculum, "")
        return topics
