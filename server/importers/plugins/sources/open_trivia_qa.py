"""
OpenTriviaQA Importer

Imports questions from the OpenTriviaQA dataset (GitHub: uberspot/OpenTriviaQA).
This is a Creative Commons (CC BY-SA 4.0) dataset of trivia questions.

Source: https://github.com/uberspot/OpenTriviaQA
License: CC BY-SA 4.0 (Creative Commons Attribution-ShareAlike 4.0)
"""

from __future__ import annotations

import json
import re
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


# OpenTriviaQA category to KB domain mapping
CATEGORY_MAPPING: dict[str, tuple[KBDomain, str]] = {
    "history": (KBDomain.HISTORY, "General"),
    "literature": (KBDomain.LITERATURE, "General"),
    "humanities": (KBDomain.ARTS, "Humanities"),
    "geography": (KBDomain.SOCIAL_STUDIES, "Geography"),
    "music": (KBDomain.ARTS, "Music"),
    "religion-faith": (KBDomain.RELIGION_PHILOSOPHY, "Religion"),
    "movies": (KBDomain.POP_CULTURE, "Film"),
    "television": (KBDomain.POP_CULTURE, "Television"),
    "celebrities": (KBDomain.POP_CULTURE, "Celebrities"),
    "entertainment": (KBDomain.POP_CULTURE, "Entertainment"),
    "sports": (KBDomain.MISCELLANEOUS, "Sports"),
    "science-technology": (KBDomain.SCIENCE, "General"),
    "animals": (KBDomain.SCIENCE, "Biology"),
    "general": (KBDomain.MISCELLANEOUS, "General"),
    "for-kids": (KBDomain.MISCELLANEOUS, "General"),
    "world": (KBDomain.SOCIAL_STUDIES, "World"),
    "people": (KBDomain.HISTORY, "People"),
    "hobbies": (KBDomain.MISCELLANEOUS, "Hobbies"),
    "brain-teasers": (KBDomain.MISCELLANEOUS, "Brain Teasers"),
    "video-games": (KBDomain.POP_CULTURE, "Video Games"),
}


@dataclass
class ParsedQuestion:
    """A parsed question from OpenTriviaQA format."""
    question_text: str
    correct_answer: str
    options: list[str]  # A, B, C, D options
    correct_letter: str  # Which letter is correct


def parse_opentrivia_file(file_path: Path) -> list[ParsedQuestion]:
    """
    Parse an OpenTriviaQA category file.

    Format:
    #Q Question text here?
    ^ Correct Answer
    A Option A
    B Option B
    C Option C
    D Option D

    (blank line between questions)
    """
    questions: list[ParsedQuestion] = []

    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    # Split by questions (start with #Q)
    question_blocks = re.split(r"\n\s*\n", content)

    for block in question_blocks:
        block = block.strip()
        if not block or "#Q" not in block:
            continue

        lines = block.split("\n")

        question_text = ""
        correct_answer = ""
        options = []
        correct_letter = ""

        for line in lines:
            line = line.strip()
            if line.startswith("#Q "):
                question_text = line[3:].strip()
            elif line.startswith("^ "):
                correct_answer = line[2:].strip()
            elif len(line) >= 2 and line[0] in "ABCD" and line[1] == " ":
                option_letter = line[0]
                option_text = line[2:].strip()
                options.append(option_text)
                # Check if this option matches the correct answer
                if option_text.lower() == correct_answer.lower():
                    correct_letter = option_letter

        # Validate we have a complete question
        if question_text and correct_answer and len(options) >= 2:
            # If we couldn't match correct_letter, try to find it
            if not correct_letter:
                for i, opt in enumerate(options):
                    if opt.lower() == correct_answer.lower():
                        correct_letter = chr(ord("A") + i)
                        break

            questions.append(ParsedQuestion(
                question_text=question_text,
                correct_answer=correct_answer,
                options=options,
                correct_letter=correct_letter or "A"
            ))

    return questions


def infer_answer_type(answer: str, question: str) -> KBAnswerType:
    """Infer the answer type based on content and context."""
    question_lower = question.lower()
    answer_lower = answer.lower()

    # Check for person names
    if "who " in question_lower or "whom " in question_lower:
        return KBAnswerType.PERSON

    # Check for places
    place_words = ["where", "country", "city", "state", "capital", "continent"]
    if any(word in question_lower for word in place_words):
        return KBAnswerType.PLACE

    # Check for dates
    if "when" in question_lower or "year" in question_lower or "what date" in question_lower:
        return KBAnswerType.DATE

    # Check for titles (books, movies, songs)
    title_words = ["book", "novel", "movie", "film", "song", "album", "play", "title"]
    if any(word in question_lower for word in title_words):
        return KBAnswerType.TITLE

    # Check for numbers
    try:
        float(answer.replace(",", "").replace("$", ""))
        return KBAnswerType.NUMBER
    except ValueError:
        pass

    return KBAnswerType.MULTIPLE_CHOICE


def to_kb_json(
    parsed: ParsedQuestion,
    domain: KBDomain,
    subdomain: str,
    category_name: str
) -> dict[str, Any]:
    """Convert a parsed question to KB JSON format."""
    question_id = str(uuid.uuid4())

    answer_type = infer_answer_type(parsed.correct_answer, parsed.question_text)

    return {
        "id": question_id,
        "text": parsed.question_text,
        "answer": {
            "primary": parsed.correct_answer,
            "acceptable": None,
            "answerType": answer_type.value
        },
        "domain": domain.value,
        "subdomain": subdomain.lower(),
        "difficulty": KBDifficulty.INTERMEDIATE.value,
        "gradeLevel": KBGradeLevel.HIGH_SCHOOL.value,
        "suitability": {
            "forWritten": True,
            "forOral": answer_type != KBAnswerType.MULTIPLE_CHOICE,
            "mcqPossible": True,
            "requiresVisual": False
        },
        "mcqOptions": parsed.options if len(parsed.options) >= 4 else None,
        "source": f"OpenTriviaQA ({category_name})",
        "sourceAttribution": "CC BY-SA 4.0 - https://github.com/uberspot/OpenTriviaQA",
        "tags": [category_name.lower().replace(" ", "-")]
    }


def import_opentrivia_category(
    file_path: Path,
    category_name: str,
    limit: int | None = None
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    """
    Import questions from a single OpenTriviaQA category file.

    Returns:
        Tuple of (questions list, stats dict)
    """
    domain_info = CATEGORY_MAPPING.get(
        category_name,
        (KBDomain.MISCELLANEOUS, "General")
    )
    domain, subdomain = domain_info

    parsed_questions = parse_opentrivia_file(file_path)

    if limit:
        parsed_questions = parsed_questions[:limit]

    kb_questions = [
        to_kb_json(q, domain, subdomain, category_name)
        for q in parsed_questions
    ]

    stats = {
        "category": category_name,
        "domain": domain.value,
        "total": len(kb_questions)
    }

    return kb_questions, stats


def import_all_categories(
    data_dir: Path,
    output_path: Path,
    categories: list[str] | None = None,
    limit_per_category: int | None = None
) -> dict[str, Any]:
    """
    Import questions from all (or specified) OpenTriviaQA categories.

    Args:
        data_dir: Path to OpenTriviaQA/categories directory
        output_path: Where to write the output JSON
        categories: Optional list of category names to import (default: all)
        limit_per_category: Optional limit on questions per category

    Returns:
        Statistics about the import
    """
    all_questions: list[dict[str, Any]] = []
    category_stats: list[dict[str, int]] = []

    # Default categories that map well to KB domains
    if categories is None:
        categories = [
            "history",
            "literature",
            "humanities",
            "geography",
            "music",
            "religion-faith",
            "world",
            "people",
        ]

    for category in categories:
        file_path = data_dir / category
        if not file_path.exists():
            # Try with .txt extension
            file_path = data_dir / f"{category}.txt"
            if not file_path.exists():
                print(f"Warning: Category file not found: {category}")
                continue

        print(f"Processing {category}...")
        questions, stats = import_opentrivia_category(
            file_path,
            category,
            limit=limit_per_category
        )
        all_questions.extend(questions)
        category_stats.append(stats)
        print(f"  Imported {stats['total']} questions")

    # Create output bundle
    bundle = {
        "version": "1.0.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": "OpenTriviaQA",
        "sourceUrl": "https://github.com/uberspot/OpenTriviaQA",
        "license": "CC BY-SA 4.0",
        "questions": all_questions
    }

    # Write output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(bundle, f, indent=2)

    print(f"\nWrote {len(all_questions)} questions to {output_path}")

    return {
        "total_questions": len(all_questions),
        "categories": category_stats,
        "by_domain": _count_by_domain(all_questions)
    }


def _count_by_domain(questions: list[dict[str, Any]]) -> dict[str, int]:
    """Count questions by domain."""
    counts: dict[str, int] = {}
    for q in questions:
        domain = q.get("domain", "miscellaneous")
        counts[domain] = counts.get(domain, 0) + 1
    return counts


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Import questions from OpenTriviaQA dataset"
    )
    parser.add_argument(
        "-d", "--data-dir",
        type=Path,
        default=Path("/tmp/OpenTriviaQA/categories"),
        help="Path to OpenTriviaQA categories directory"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("output/kb-opentrivia-questions.json"),
        help="Output file path"
    )
    parser.add_argument(
        "-c", "--categories",
        nargs="+",
        help="Specific categories to import (default: all KB-relevant)"
    )
    parser.add_argument(
        "-n", "--limit",
        type=int,
        help="Limit questions per category"
    )

    args = parser.parse_args()

    stats = import_all_categories(
        data_dir=args.data_dir,
        output_path=args.output,
        categories=args.categories,
        limit_per_category=args.limit
    )

    print("\n=== Import Statistics ===")
    print(f"Total questions imported: {stats['total_questions']}")
    print("\nBy Category:")
    for cat_stat in stats["categories"]:
        print(f"  {cat_stat['category']}: {cat_stat['total']}")
    print("\nBy Domain:")
    for domain, count in sorted(stats["by_domain"].items()):
        print(f"  {domain}: {count}")


if __name__ == "__main__":
    main()
