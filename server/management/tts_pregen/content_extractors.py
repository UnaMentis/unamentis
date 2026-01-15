# TTS Content Extractors
# Extract text content from various sources for TTS pre-generation

import json
import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)


class ContentExtractor:
    """Base class for content extractors."""

    def extract(self) -> List[Dict[str, str]]:
        """Extract text items for TTS generation.

        Returns:
            List of dicts with 'text' and optional 'source_ref' keys
        """
        raise NotImplementedError


class KnowledgeBowlExtractor(ContentExtractor):
    """Extract text from Knowledge Bowl questions for TTS pre-generation.

    Extracts:
    - Question text
    - Answer text
    - Hints
    - Explanations
    """

    DEFAULT_PATH = "data/modules/knowledge-bowl.json"

    def __init__(
        self,
        data_path: Optional[str] = None,
        include_questions: bool = True,
        include_answers: bool = True,
        include_hints: bool = True,
        include_explanations: bool = True,
        domains: Optional[List[str]] = None,
        difficulties: Optional[List[int]] = None,
    ):
        """Initialize Knowledge Bowl extractor.

        Args:
            data_path: Path to knowledge-bowl.json (defaults to standard location)
            include_questions: Include question text
            include_answers: Include answer text
            include_hints: Include hints
            include_explanations: Include explanations
            domains: Optional list of domain IDs to filter by
            difficulties: Optional list of difficulty levels to filter by
        """
        self.data_path = data_path or self.DEFAULT_PATH
        self.include_questions = include_questions
        self.include_answers = include_answers
        self.include_hints = include_hints
        self.include_explanations = include_explanations
        self.domains = set(domains) if domains else None
        self.difficulties = set(difficulties) if difficulties else None

    def extract(self) -> List[Dict[str, str]]:
        """Extract text items from Knowledge Bowl data.

        Returns:
            List of dicts with 'text' and 'source_ref' keys
        """
        items = []

        try:
            with open(self.data_path, "r") as f:
                data = json.load(f)
        except FileNotFoundError:
            logger.error(f"Knowledge Bowl data not found: {self.data_path}")
            return []
        except json.JSONDecodeError as e:
            logger.error(f"Invalid Knowledge Bowl JSON: {e}")
            return []

        domains = data.get("domains", [])

        for domain in domains:
            domain_id = domain.get("id", "")

            # Filter by domain if specified
            if self.domains and domain_id not in self.domains:
                continue

            questions = domain.get("questions", [])

            for question in questions:
                question_id = question.get("id", "")
                difficulty = question.get("difficulty", 1)

                # Filter by difficulty if specified
                if self.difficulties and difficulty not in self.difficulties:
                    continue

                # Extract question text
                if self.include_questions:
                    question_text = question.get("question_text", "")
                    if question_text:
                        items.append({
                            "text": question_text,
                            "source_ref": f"{question_id}:question",
                        })

                # Extract answer text
                if self.include_answers:
                    answer_text = question.get("answer_text", "")
                    if answer_text:
                        items.append({
                            "text": answer_text,
                            "source_ref": f"{question_id}:answer",
                        })

                # Extract hints
                if self.include_hints:
                    hints = question.get("hints", [])
                    for idx, hint in enumerate(hints):
                        if hint:
                            items.append({
                                "text": hint,
                                "source_ref": f"{question_id}:hint:{idx}",
                            })

                # Extract explanations
                if self.include_explanations:
                    explanation = question.get("explanation", "")
                    if explanation:
                        items.append({
                            "text": explanation,
                            "source_ref": f"{question_id}:explanation",
                        })

        logger.info(f"Extracted {len(items)} items from Knowledge Bowl")
        return items

    def get_stats(self) -> Dict[str, Any]:
        """Get statistics about the Knowledge Bowl content.

        Returns:
            Dict with domain counts, question counts, etc.
        """
        try:
            with open(self.data_path, "r") as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

        domains = data.get("domains", [])
        total_questions = 0
        domain_counts = {}

        for domain in domains:
            domain_id = domain.get("id", "unknown")
            question_count = len(domain.get("questions", []))
            domain_counts[domain_id] = question_count
            total_questions += question_count

        return {
            "total_domains": len(domains),
            "total_questions": total_questions,
            "domain_counts": domain_counts,
        }


class CurriculumExtractor(ContentExtractor):
    """Extract text from UMCF curriculum for TTS pre-generation.

    Extracts segment content that might benefit from TTS.
    """

    def __init__(
        self,
        curriculum_path: str,
        segment_types: Optional[List[str]] = None,
    ):
        """Initialize curriculum extractor.

        Args:
            curriculum_path: Path to curriculum directory or file
            segment_types: Optional list of segment types to include
        """
        self.curriculum_path = curriculum_path
        self.segment_types = set(segment_types) if segment_types else None

    def extract(self) -> List[Dict[str, str]]:
        """Extract text items from curriculum.

        Returns:
            List of dicts with 'text' and 'source_ref' keys
        """
        items = []
        path = Path(self.curriculum_path)

        if path.is_file():
            items.extend(self._extract_from_file(path))
        elif path.is_dir():
            for json_file in path.glob("**/*.json"):
                items.extend(self._extract_from_file(json_file))

        logger.info(f"Extracted {len(items)} items from curriculum")
        return items

    def _extract_from_file(self, file_path: Path) -> List[Dict[str, str]]:
        """Extract items from a single curriculum file."""
        items = []

        try:
            with open(file_path, "r") as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as e:
            logger.warning(f"Could not read curriculum file {file_path}: {e}")
            return []

        # Extract from segments
        segments = data.get("segments", [])
        for segment in segments:
            segment_id = segment.get("id", "")
            segment_type = segment.get("type", "")

            # Filter by segment type if specified
            if self.segment_types and segment_type not in self.segment_types:
                continue

            # Extract content that might need TTS
            content = segment.get("content", {})

            # Instruction text
            instruction = content.get("instruction", "")
            if instruction:
                items.append({
                    "text": instruction,
                    "source_ref": f"{segment_id}:instruction",
                })

            # Questions
            questions = content.get("questions", [])
            for idx, q in enumerate(questions):
                q_text = q.get("text", "")
                if q_text:
                    items.append({
                        "text": q_text,
                        "source_ref": f"{segment_id}:question:{idx}",
                    })

            # Prompts
            prompts = content.get("prompts", [])
            for idx, prompt in enumerate(prompts):
                if isinstance(prompt, str) and prompt:
                    items.append({
                        "text": prompt,
                        "source_ref": f"{segment_id}:prompt:{idx}",
                    })

        return items


class CustomTextExtractor(ContentExtractor):
    """Extract custom text items provided directly."""

    def __init__(self, texts: List[str]):
        """Initialize with custom texts.

        Args:
            texts: List of text strings to generate TTS for
        """
        self.texts = texts

    def extract(self) -> List[Dict[str, str]]:
        """Extract custom text items.

        Returns:
            List of dicts with 'text' and 'source_ref' keys
        """
        return [
            {"text": text, "source_ref": f"custom:{idx}"}
            for idx, text in enumerate(self.texts)
            if text.strip()
        ]


def get_extractor(
    source_type: str,
    source_config: Optional[Dict[str, Any]] = None,
) -> ContentExtractor:
    """Factory function to get appropriate extractor.

    Args:
        source_type: Type of source ('knowledge-bowl', 'curriculum', 'custom')
        source_config: Optional configuration for the extractor

    Returns:
        Appropriate ContentExtractor instance

    Raises:
        ValueError: If source_type is unknown
    """
    config = source_config or {}

    if source_type == "knowledge-bowl":
        return KnowledgeBowlExtractor(
            data_path=config.get("data_path"),
            include_questions=config.get("include_questions", True),
            include_answers=config.get("include_answers", True),
            include_hints=config.get("include_hints", True),
            include_explanations=config.get("include_explanations", True),
            domains=config.get("domains"),
            difficulties=config.get("difficulties"),
        )
    elif source_type == "curriculum":
        curriculum_path = config.get("curriculum_path", "")
        if not curriculum_path:
            raise ValueError("curriculum_path is required for curriculum source")
        return CurriculumExtractor(
            curriculum_path=curriculum_path,
            segment_types=config.get("segment_types"),
        )
    elif source_type == "custom":
        texts = config.get("texts", [])
        return CustomTextExtractor(texts=texts)
    else:
        raise ValueError(f"Unknown source type: {source_type}")
