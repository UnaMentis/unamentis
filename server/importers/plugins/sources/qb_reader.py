"""
QB Reader Importer

Imports questions from QB Reader API (https://www.qbreader.org/), which provides
access to publicly released quiz bowl packets from quizbowlpackets.com.

Source: https://www.qbreader.org/
Data License: Questions are from publicly released quiz bowl packets
(typically released after tournaments for practice use)

API Docs: https://www.qbreader.org/tools/api-docs/
Rate Limit: 20 requests per second
"""

from __future__ import annotations

import asyncio
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any


class KBDomain(str, Enum):
    """Knowledge Bowl domains matching iOS app."""
    SCIENCE = "science"
    MATHEMATICS = "mathematics"
    LITERATURE = "literature"
    HISTORY = "history"
    SOCIAL_STUDIES = "socialStudies"
    ARTS = "arts"
    CURRENT_EVENTS = "currentEvents"
    LANGUAGE = "language"
    TECHNOLOGY = "technology"
    POP_CULTURE = "popCulture"
    RELIGION_PHILOSOPHY = "religionPhilosophy"
    MISCELLANEOUS = "miscellaneous"


class KBDifficulty(str, Enum):
    """Difficulty levels."""
    OVERVIEW = "overview"
    FOUNDATIONAL = "foundational"
    INTERMEDIATE = "intermediate"
    VARSITY = "varsity"
    CHAMPIONSHIP = "championship"
    RESEARCH = "research"


class KBGradeLevel(str, Enum):
    """Grade levels."""
    MIDDLE_SCHOOL = "middleSchool"
    HIGH_SCHOOL = "highSchool"
    ADVANCED = "advanced"


class KBAnswerType(str, Enum):
    """Answer types for smart matching."""
    TEXT = "text"
    PERSON = "person"
    PLACE = "place"
    NUMBER = "number"
    DATE = "date"
    TITLE = "title"
    SCIENTIFIC = "scientific"
    MULTIPLE_CHOICE = "multipleChoice"


# QB Reader category to KB domain mapping
CATEGORY_MAPPING: dict[str, tuple[KBDomain, str]] = {
    # Core academic categories
    "Literature": (KBDomain.LITERATURE, "General"),
    "History": (KBDomain.HISTORY, "General"),
    "Science": (KBDomain.SCIENCE, "General"),
    "Fine Arts": (KBDomain.ARTS, "Fine Arts"),
    "Religion": (KBDomain.RELIGION_PHILOSOPHY, "Religion"),
    "Mythology": (KBDomain.RELIGION_PHILOSOPHY, "Mythology"),
    "Philosophy": (KBDomain.RELIGION_PHILOSOPHY, "Philosophy"),
    "Social Science": (KBDomain.SOCIAL_STUDIES, "Social Science"),
    "Geography": (KBDomain.SOCIAL_STUDIES, "Geography"),
    "Current Events": (KBDomain.CURRENT_EVENTS, "General"),
    "Trash": (KBDomain.POP_CULTURE, "Pop Culture"),
    "Other Academic": (KBDomain.MISCELLANEOUS, "Academic"),
}

# Subcategory refinements
SUBCATEGORY_MAPPING: dict[str, str] = {
    # Literature subcategories
    "American Literature": "American",
    "British Literature": "British",
    "European Literature": "European",
    "World Literature": "World",
    "Classical Literature": "Classical",
    # History subcategories
    "American History": "American",
    "European History": "European",
    "World History": "World",
    "Ancient History": "Ancient",
    "Other History": "Other",
    # Science subcategories
    "Biology": "Biology",
    "Chemistry": "Chemistry",
    "Physics": "Physics",
    "Math": "Mathematics",
    "Other Science": "General",
    # Fine Arts subcategories
    "Visual Fine Arts": "Visual Arts",
    "Auditory Fine Arts": "Music",
    "Other Fine Arts": "Other",
}


# QB Reader difficulty (1-9) to KB difficulty mapping
def map_difficulty(qb_difficulty: int) -> KBDifficulty:
    """Map QB Reader difficulty (1-9) to KB difficulty."""
    if qb_difficulty <= 2:
        return KBDifficulty.FOUNDATIONAL
    elif qb_difficulty <= 4:
        return KBDifficulty.INTERMEDIATE
    elif qb_difficulty <= 6:
        return KBDifficulty.VARSITY
    elif qb_difficulty <= 8:
        return KBDifficulty.CHAMPIONSHIP
    else:
        return KBDifficulty.RESEARCH


def map_grade_level(qb_difficulty: int) -> KBGradeLevel:
    """Map QB Reader difficulty to grade level."""
    if qb_difficulty <= 3:
        return KBGradeLevel.MIDDLE_SCHOOL
    elif qb_difficulty <= 6:
        return KBGradeLevel.HIGH_SCHOOL
    else:
        return KBGradeLevel.ADVANCED


def clean_html(text: str) -> str:
    """Remove HTML tags from text."""
    import re
    # Remove HTML tags
    clean = re.sub(r'<[^>]+>', '', text)
    # Normalize whitespace
    clean = re.sub(r'\s+', ' ', clean).strip()
    return clean


def extract_primary_answer(answer: str) -> tuple[str, list[str] | None]:
    """
    Extract primary answer and acceptable alternatives from QB answer format.

    QB format often includes:
    - Primary answer in bold: <b>answer</b>
    - Alternatives in brackets: [accept: alt1 or alt2]
    - Prompts: [prompt on partial]
    """
    import re

    # Clean the answer
    answer = clean_html(answer)

    # Extract text in brackets as alternatives
    bracket_pattern = r'\[(?:accept|or|also accept)[:\s]*([^\]]+)\]'
    alternatives = []
    for match in re.finditer(bracket_pattern, answer, re.IGNORECASE):
        alt_text = match.group(1)
        # Split on "or" to get individual alternatives
        for alt in re.split(r'\s+or\s+', alt_text, flags=re.IGNORECASE):
            alt = alt.strip()
            if alt:
                alternatives.append(alt)

    # Remove bracketed content from primary answer
    primary = re.sub(r'\[[^\]]*\]', '', answer).strip()

    # Clean up primary (remove leading/trailing punctuation)
    primary = primary.strip('.,;: ')

    return primary, alternatives if alternatives else None


def infer_answer_type(answer: str, question: str, category: str) -> KBAnswerType:
    """Infer the answer type based on content and context."""
    question_lower = question.lower()
    category_lower = category.lower()

    # Literature titles
    if "literature" in category_lower:
        title_indicators = ["novel", "poem", "play", "work", "story", "book"]
        if any(ind in question_lower for ind in title_indicators):
            return KBAnswerType.TITLE
        # Authors are persons
        if "author" in question_lower or "wrote" in question_lower:
            return KBAnswerType.PERSON

    # History people
    if "history" in category_lower:
        if "who" in question_lower:
            return KBAnswerType.PERSON
        if "where" in question_lower:
            return KBAnswerType.PLACE
        if "when" in question_lower or "year" in question_lower:
            return KBAnswerType.DATE

    # Science terms
    if "science" in category_lower:
        return KBAnswerType.SCIENTIFIC

    # Fine Arts
    if "fine arts" in category_lower or "arts" in category_lower:
        if "composer" in question_lower or "artist" in question_lower:
            return KBAnswerType.PERSON
        return KBAnswerType.TITLE

    # Geography
    if "geography" in category_lower:
        return KBAnswerType.PLACE

    # Default to text
    return KBAnswerType.TEXT


def transform_question(qb_question: dict[str, Any]) -> dict[str, Any] | None:
    """Transform a QB Reader question to KB format."""
    # Get question text (prefer sanitized version)
    question_text = qb_question.get("question_sanitized") or qb_question.get("question", "")
    answer_raw = qb_question.get("answer_sanitized") or qb_question.get("answer", "")

    if not question_text or not answer_raw:
        return None

    # Clean question text
    question_text = clean_html(question_text)

    # Map category
    category = qb_question.get("category", "Other Academic")
    subcategory = qb_question.get("subcategory", "")

    domain_info = CATEGORY_MAPPING.get(category, (KBDomain.MISCELLANEOUS, "General"))
    domain, default_subdomain = domain_info

    # Refine subdomain if available
    kb_subdomain = SUBCATEGORY_MAPPING.get(subcategory, default_subdomain)

    # Get difficulty
    qb_difficulty = qb_question.get("difficulty", 5)
    difficulty = map_difficulty(qb_difficulty)
    grade_level = map_grade_level(qb_difficulty)

    # Parse answer
    primary, acceptable = extract_primary_answer(answer_raw)

    # Infer answer type
    answer_type = infer_answer_type(primary, question_text, category)

    # Get source info
    set_info = qb_question.get("set", {})
    set_name = set_info.get("name", "Unknown")
    set_year = set_info.get("year", "")
    packet_info = qb_question.get("packet", {})
    packet_name = packet_info.get("name", "")

    source = f"QB Reader: {set_name}"
    if set_year:
        source = f"QB Reader: {set_name} ({set_year})"

    # Generate unique ID
    question_id = str(uuid.uuid4())

    return {
        "id": question_id,
        "text": question_text,
        "answer": {
            "primary": primary,
            "acceptable": acceptable,
            "answerType": answer_type.value
        },
        "domain": domain.value,
        "subdomain": kb_subdomain.lower(),
        "difficulty": difficulty.value,
        "gradeLevel": grade_level.value,
        "suitability": {
            "forWritten": True,
            "forOral": True,
            "mcqPossible": False,  # QB questions are typically short answer
            "requiresVisual": False
        },
        "mcqOptions": None,
        "source": source,
        "sourceAttribution": f"QB Reader / quizbowlpackets.com - {set_name}",
        "tags": [category.lower().replace(" ", "-"), subcategory.lower().replace(" ", "-")]
    }


async def fetch_questions(
    categories: list[str] | None = None,
    max_per_category: int = 1000,
    min_difficulty: int = 1,
    max_difficulty: int = 9
) -> list[dict[str, Any]]:
    """
    Fetch questions from QB Reader API.

    Args:
        categories: List of categories to fetch (default: all KB-relevant)
        max_per_category: Maximum questions per category
        min_difficulty: Minimum difficulty (1-9)
        max_difficulty: Maximum difficulty (1-9)

    Returns:
        List of raw QB Reader questions
    """
    import aiohttp

    if categories is None:
        # Focus on categories we need most
        categories = [
            "Literature",
            "History",
            "Fine Arts",
            "Science",
            "Religion",
            "Mythology",
            "Philosophy",
            "Social Science",
            "Geography",
        ]

    all_questions: list[dict[str, Any]] = []

    async with aiohttp.ClientSession() as session:
        for category in categories:
            print(f"Fetching {category}...")

            # Query for tossups in this category
            params = {
                "questionType": "tossup",
                "categories": category,
                "minDifficulty": str(min_difficulty),
                "maxDifficulty": str(max_difficulty),
                "maxReturnLength": str(max_per_category),
            }

            url = "https://www.qbreader.org/api/query"

            try:
                async with session.get(url, params=params) as response:
                    if response.status == 200:
                        data = await response.json()
                        tossups = data.get("tossups", {}).get("questionArray", [])
                        all_questions.extend(tossups)
                        print(f"  Got {len(tossups)} {category} questions")
                    else:
                        print(f"  Error fetching {category}: {response.status}")
            except Exception as e:
                print(f"  Error fetching {category}: {e}")

            # Respect rate limit
            await asyncio.sleep(0.1)

    return all_questions


async def import_qb_reader_questions(
    output_path: Path,
    categories: list[str] | None = None,
    max_per_category: int = 1000,
    min_difficulty: int = 1,
    max_difficulty: int = 7,  # Default to exclude hardest college-level
    cache_path: Path | None = None
) -> dict[str, Any]:
    """
    Import questions from QB Reader API.

    Args:
        output_path: Where to write the output JSON
        categories: Categories to import (default: all KB-relevant)
        max_per_category: Max questions per category
        min_difficulty: Minimum QB difficulty (1-9)
        max_difficulty: Maximum QB difficulty (1-9)
        cache_path: Optional cache file for raw API data

    Returns:
        Statistics about the import
    """
    # Try to load from cache
    raw_questions = None
    if cache_path and cache_path.exists():
        print(f"Loading from cache: {cache_path}")
        with open(cache_path) as f:
            raw_questions = json.load(f)

    # Fetch from API if not cached
    if raw_questions is None:
        raw_questions = await fetch_questions(
            categories=categories,
            max_per_category=max_per_category,
            min_difficulty=min_difficulty,
            max_difficulty=max_difficulty
        )

        # Save cache
        if cache_path:
            cache_path.parent.mkdir(parents=True, exist_ok=True)
            with open(cache_path, "w") as f:
                json.dump(raw_questions, f)
            print(f"Cached {len(raw_questions)} questions to {cache_path}")

    print(f"\nTransforming {len(raw_questions)} questions...")

    # Transform questions
    kb_questions: list[dict[str, Any]] = []
    stats: dict[str, Any] = {
        "total_raw": len(raw_questions),
        "by_domain": {},
        "by_category": {},
        "skipped": 0
    }

    for qb_q in raw_questions:
        kb_q = transform_question(qb_q)
        if kb_q:
            kb_questions.append(kb_q)
            domain = kb_q["domain"]
            stats["by_domain"][domain] = stats["by_domain"].get(domain, 0) + 1

            category = qb_q.get("category", "Unknown")
            stats["by_category"][category] = stats["by_category"].get(category, 0) + 1
        else:
            stats["skipped"] += 1

    stats["total_questions"] = len(kb_questions)

    # Create output bundle
    bundle = {
        "version": "1.0.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": "QB Reader",
        "sourceUrl": "https://www.qbreader.org/",
        "license": "Publicly released quiz bowl packets",
        "questions": kb_questions
    }

    # Write output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(bundle, f, indent=2)

    print(f"\nWrote {len(kb_questions)} questions to {output_path}")

    return stats


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Import questions from QB Reader API"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("output/kb-qbreader-questions.json"),
        help="Output file path"
    )
    parser.add_argument(
        "-c", "--cache",
        type=Path,
        default=Path("data/qbreader_cache.json"),
        help="Cache file path"
    )
    parser.add_argument(
        "--categories",
        nargs="+",
        help="Specific categories to import"
    )
    parser.add_argument(
        "-n", "--max-per-category",
        type=int,
        default=1000,
        help="Maximum questions per category"
    )
    parser.add_argument(
        "--min-difficulty",
        type=int,
        default=1,
        help="Minimum difficulty (1-9)"
    )
    parser.add_argument(
        "--max-difficulty",
        type=int,
        default=7,
        help="Maximum difficulty (1-9, default 7 excludes hardest college)"
    )

    args = parser.parse_args()

    stats = asyncio.run(
        import_qb_reader_questions(
            output_path=args.output,
            categories=args.categories,
            max_per_category=args.max_per_category,
            min_difficulty=args.min_difficulty,
            max_difficulty=args.max_difficulty,
            cache_path=args.cache
        )
    )

    print("\n=== Import Statistics ===")
    print(f"Total raw questions: {stats['total_raw']}")
    print(f"Total imported: {stats['total_questions']}")
    print(f"Skipped: {stats['skipped']}")
    print("\nBy Domain:")
    for domain, count in sorted(stats["by_domain"].items()):
        print(f"  {domain}: {count}")
    print("\nBy QB Category:")
    for category, count in sorted(stats["by_category"].items()):
        print(f"  {category}: {count}")


if __name__ == "__main__":
    main()
