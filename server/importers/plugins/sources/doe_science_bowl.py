"""
DOE Science Bowl Question Importer

Imports questions from SciBowlDB (https://scibowldb.com/), which aggregates
DOE National Science Bowl questions in text format.

Source: U.S. Department of Energy, Office of Science
License: Public Domain (US Government Work)

This importer is different from curriculum source handlers as it imports
questions directly rather than course content.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any, List, Optional, Dict, Tuple


class KBDomain(str, Enum):
    """Knowledge Bowl domains matching iOS app."""
    SCIENCE = "science"
    MATHEMATICS = "mathematics"
    TECHNOLOGY = "technology"
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


# SciBowlDB category to KB domain mapping
CATEGORY_MAPPING: dict[str, tuple[KBDomain, str]] = {
    "PHYSICS": (KBDomain.SCIENCE, "Physics"),
    "CHEMISTRY": (KBDomain.SCIENCE, "Chemistry"),
    "BIOLOGY": (KBDomain.SCIENCE, "Biology"),
    "EARTH SCIENCE": (KBDomain.SCIENCE, "Earth Science"),
    "EARTH AND SPACE": (KBDomain.SCIENCE, "Earth and Space"),
    "ASTRONOMY": (KBDomain.SCIENCE, "Astronomy"),
    "GENERAL SCIENCE": (KBDomain.SCIENCE, "General Science"),
    "ENERGY": (KBDomain.SCIENCE, "Energy"),
    "MATH": (KBDomain.MATHEMATICS, "General"),
    "COMPUTER SCIENCE": (KBDomain.TECHNOLOGY, "Computer Science"),
}


@dataclass
class ImportedQuestion:
    """Intermediate representation of an imported question."""
    id: str
    text: str
    answer_primary: str
    answer_acceptable: list[str] | None
    answer_type: KBAnswerType
    domain: KBDomain
    subdomain: str | None
    difficulty: KBDifficulty
    grade_level: KBGradeLevel
    mcq_options: list[str] | None
    source: str
    source_attribution: str
    tags: list[str] | None


def parse_mcq_answer(answer: str) -> tuple[str, list[str] | None]:
    """
    Parse MCQ answer format like 'W) BASIC' or 'X) POSITIVE, NEGATIVE'.
    Returns (primary_answer, acceptable_alternatives).
    """
    # Check for MCQ letter prefix pattern
    if len(answer) >= 3 and answer[0] in "WXYZ" and answer[1] == ")":
        # Extract the actual answer after the letter
        actual_answer = answer[3:].strip()
        # Also accept the full answer with letter
        return actual_answer, [answer]
    return answer, None


def parse_answer_with_accepts(answer: str) -> tuple[str, list[str] | None]:
    """
    Parse answers that include ACCEPT alternatives.
    Example: 'NORTH STAR  (ACCEPT:  POLARIS or ALPHA URSA MINORIS)'
    """
    if "(ACCEPT:" in answer.upper():
        # Split at ACCEPT
        parts = answer.split("(ACCEPT:")
        primary = parts[0].strip()
        if len(parts) > 1:
            alternatives_part = parts[1].rstrip(")").strip()
            # Split on 'or' and clean up
            alternatives = [
                alt.strip()
                for alt in alternatives_part.replace(" OR ", " or ").split(" or ")
            ]
            return primary, alternatives
    return answer, None


def infer_answer_type(
    answer: str,
    question: str,
    is_mcq: bool,
    category: str
) -> KBAnswerType:
    """Infer the answer type based on content and context."""
    if is_mcq:
        return KBAnswerType.MULTIPLE_CHOICE

    answer_lower = answer.lower()

    # Check for numeric answers
    try:
        float(answer.replace(",", ""))
        return KBAnswerType.NUMBER
    except ValueError:
        pass

    # Check for scientific terms (chemistry, biology, physics terms)
    scientific_indicators = [
        "formula", "element", "compound", "molecule", "reaction",
        "equation", "unit", "constant", "theorem", "law"
    ]
    if any(ind in question.lower() for ind in scientific_indicators):
        return KBAnswerType.SCIENTIFIC

    # Check for person names (common patterns)
    if "who" in question.lower():
        return KBAnswerType.PERSON

    # Check for places
    if "where" in question.lower() or "planet" in question.lower():
        return KBAnswerType.PLACE

    # Check for dates/years
    if "when" in question.lower() or "year" in question.lower():
        return KBAnswerType.DATE

    return KBAnswerType.TEXT


def infer_difficulty(source: str, level: str | None) -> KBDifficulty:
    """Infer difficulty based on source and level."""
    # Official sets are typically varsity level
    if source.startswith("Official"):
        return KBDifficulty.VARSITY
    elif "Nats" in source:  # Nationals are harder
        return KBDifficulty.CHAMPIONSHIP
    elif source.startswith("HW"):  # Housewrites vary
        return KBDifficulty.VARSITY
    else:
        return KBDifficulty.INTERMEDIATE


def transform_question(
    scibowl_question: dict[str, Any],
    question_type: str  # "tossup" or "bonus"
) -> ImportedQuestion | None:
    """Transform a SciBowlDB question to KB format."""
    category = scibowl_question.get("category", "GENERAL SCIENCE")
    source = scibowl_question.get("source", "Unknown")

    # Get question and answer based on type
    if question_type == "tossup":
        question_text = scibowl_question.get("tossup_question", "")
        answer_raw = scibowl_question.get("tossup_answer", "")
        format_type = scibowl_question.get("tossup_format", "Short Answer")
    else:
        question_text = scibowl_question.get("bonus_question", "")
        answer_raw = scibowl_question.get("bonus_answer", "")
        format_type = scibowl_question.get("bonus_format", "Short Answer")

    # Skip empty questions
    if not question_text or not answer_raw:
        return None

    # Map category to domain
    domain_info = CATEGORY_MAPPING.get(category, (KBDomain.MISCELLANEOUS, category))
    domain, subdomain = domain_info

    # Determine if MCQ
    is_mcq = "Multiple Choice" in format_type or "MULTIPLE CHOICE" in format_type

    # Parse answer
    if is_mcq:
        primary, acceptable = parse_mcq_answer(answer_raw)
    else:
        primary, acceptable = parse_answer_with_accepts(answer_raw)
        if acceptable is None:
            primary, acceptable = parse_mcq_answer(answer_raw)

    # Extract MCQ options from question text if present
    mcq_options = None
    if is_mcq and "\n" in question_text:
        lines = question_text.split("\n")
        options = []
        main_question = []
        for line in lines:
            stripped = line.strip()
            if stripped and stripped[0] in "WXYZ" and ")" in stripped[:3]:
                options.append(stripped[3:].strip())
            else:
                main_question.append(line)
        if options:
            mcq_options = options
            question_text = "\n".join(main_question).strip()

    # Infer answer type
    answer_type = infer_answer_type(answer_raw, question_text, is_mcq, category)

    # Infer difficulty
    difficulty = infer_difficulty(source, None)

    # Determine grade level based on source if available
    grade_level = KBGradeLevel.HIGH_SCHOOL  # Default for Science Bowl

    # Generate unique ID
    question_id = str(uuid.uuid4())

    return ImportedQuestion(
        id=question_id,
        text=question_text,
        answer_primary=primary,
        answer_acceptable=acceptable,
        answer_type=answer_type,
        domain=domain,
        subdomain=subdomain,
        difficulty=difficulty,
        grade_level=grade_level,
        mcq_options=mcq_options,
        source=f"DOE Science Bowl ({source})",
        source_attribution="U.S. Department of Energy, Office of Science - Public Domain",
        tags=[category.lower().replace(" ", "-"), question_type]
    )


def to_kb_json(question: ImportedQuestion) -> dict[str, Any]:
    """Convert to KB JSON format matching iOS app expectations."""
    return {
        "id": question.id,
        "text": question.text,
        "answer": {
            "primary": question.answer_primary,
            "acceptable": question.answer_acceptable,
            "answerType": question.answer_type.value
        },
        "domain": question.domain.value,
        "subdomain": question.subdomain.lower() if question.subdomain else None,
        "difficulty": question.difficulty.value,
        "gradeLevel": question.grade_level.value,
        "suitability": {
            "forWritten": True,
            "forOral": question.answer_type != KBAnswerType.MULTIPLE_CHOICE,
            "mcqPossible": True,
            "requiresVisual": False
        },
        "mcqOptions": question.mcq_options,
        "source": question.source,
        "sourceAttribution": question.source_attribution,
        "tags": question.tags
    }


async def fetch_scibowldb_questions() -> list[dict[str, Any]]:
    """Fetch questions from SciBowlDB API."""
    import aiohttp

    async with aiohttp.ClientSession() as session:
        async with session.get("https://scibowldb.com/api/questions") as response:
            if response.status != 200:
                raise RuntimeError(f"Failed to fetch questions: {response.status}")
            data = await response.json()
            return data.get("questions", [])


def load_cached_questions(cache_path: Path) -> list[dict[str, Any]] | None:
    """Load questions from local cache if available."""
    if cache_path.exists():
        with open(cache_path) as f:
            data = json.load(f)
            return data.get("questions", [])
    return None


def save_cache(questions: list[dict[str, Any]], cache_path: Path) -> None:
    """Save questions to local cache."""
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    with open(cache_path, "w") as f:
        json.dump({"questions": questions}, f)


async def import_science_bowl_questions(
    output_path: Path,
    cache_path: Path | None = None,
    official_only: bool = True,
    limit: int | None = None
) -> dict[str, Any]:
    """
    Import DOE Science Bowl questions and output as KB format JSON.

    Args:
        output_path: Where to write the output JSON file
        cache_path: Optional path to cache the raw API response
        official_only: If True, only import questions from Official DOE sources
        limit: Optional limit on number of questions to import

    Returns:
        Statistics about the import
    """
    # Try to load from cache first
    raw_questions = None
    if cache_path:
        raw_questions = load_cached_questions(cache_path)

    # Fetch from API if not cached
    if raw_questions is None:
        print("Fetching questions from SciBowlDB API...")
        raw_questions = await fetch_scibowldb_questions()
        if cache_path:
            save_cache(raw_questions, cache_path)
            print(f"Cached {len(raw_questions)} question pairs to {cache_path}")

    print(f"Processing {len(raw_questions)} question pairs...")

    # Filter to official sources if requested
    if official_only:
        raw_questions = [
            q for q in raw_questions
            if q.get("source", "").startswith("Official")
        ]
        print(f"Filtered to {len(raw_questions)} official DOE question pairs")

    # Transform questions
    kb_questions: list[dict[str, Any]] = []
    stats = {
        "total_pairs": len(raw_questions),
        "tossups": 0,
        "bonuses": 0,
        "skipped": 0,
        "by_domain": {},
        "by_subdomain": {}
    }

    for scibowl_q in raw_questions:
        if limit and len(kb_questions) >= limit:
            break

        # Import tossup
        tossup = transform_question(scibowl_q, "tossup")
        if tossup:
            kb_questions.append(to_kb_json(tossup))
            stats["tossups"] += 1
            domain = tossup.domain.value
            subdomain = tossup.subdomain or "general"
            stats["by_domain"][domain] = stats["by_domain"].get(domain, 0) + 1
            stats["by_subdomain"][subdomain] = stats["by_subdomain"].get(subdomain, 0) + 1
        else:
            stats["skipped"] += 1

        if limit and len(kb_questions) >= limit:
            break

        # Import bonus
        bonus = transform_question(scibowl_q, "bonus")
        if bonus:
            kb_questions.append(to_kb_json(bonus))
            stats["bonuses"] += 1
            domain = bonus.domain.value
            subdomain = bonus.subdomain or "general"
            stats["by_domain"][domain] = stats["by_domain"].get(domain, 0) + 1
            stats["by_subdomain"][subdomain] = stats["by_subdomain"].get(subdomain, 0) + 1
        else:
            stats["skipped"] += 1

    stats["total_questions"] = len(kb_questions)

    # Create output bundle
    bundle = {
        "version": "1.1.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": "DOE National Science Bowl via SciBowlDB",
        "sourceUrl": "https://scibowldb.com/",
        "license": "Public Domain (US Government Work)",
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
        description="Import DOE Science Bowl questions from SciBowlDB"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("output/kb-science-bowl-questions.json"),
        help="Output file path"
    )
    parser.add_argument(
        "-c", "--cache",
        type=Path,
        default=Path("data/scibowldb_cache.json"),
        help="Cache file path for raw API data"
    )
    parser.add_argument(
        "--all-sources",
        action="store_true",
        help="Include all sources, not just Official DOE"
    )
    parser.add_argument(
        "-n", "--limit",
        type=int,
        help="Limit number of questions to import"
    )

    args = parser.parse_args()

    stats = asyncio.run(
        import_science_bowl_questions(
            output_path=args.output,
            cache_path=args.cache,
            official_only=not args.all_sources,
            limit=args.limit
        )
    )

    print("\n=== Import Statistics ===")
    print(f"Total question pairs processed: {stats['total_pairs']}")
    print(f"Total questions imported: {stats['total_questions']}")
    print(f"  - Tossups: {stats['tossups']}")
    print(f"  - Bonuses: {stats['bonuses']}")
    print(f"  - Skipped: {stats['skipped']}")
    print("\nBy Domain:")
    for domain, count in sorted(stats["by_domain"].items()):
        print(f"  {domain}: {count}")
    print("\nBy Subdomain:")
    for subdomain, count in sorted(stats["by_subdomain"].items()):
        print(f"  {subdomain}: {count}")


if __name__ == "__main__":
    main()
