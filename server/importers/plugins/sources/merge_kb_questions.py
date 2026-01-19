"""
Merge KB Questions

Merges questions from multiple sources (DOE Science Bowl, OpenTriviaQA, etc.)
into a unified Knowledge Bowl question bundle.

Can create:
1. Full bundle (all questions for server/download)
2. iOS bundle (balanced subset for app bundle)
"""

from __future__ import annotations

import json
import random
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


# Target distribution for iOS bundle (based on competition weights)
TARGET_DISTRIBUTION = {
    "science": 0.20,
    "mathematics": 0.15,
    "literature": 0.12,
    "history": 0.12,
    "socialStudies": 0.10,
    "arts": 0.08,
    "currentEvents": 0.08,  # Will have 0 for now
    "language": 0.05,  # Will have 0 for now
    "technology": 0.04,
    "popCulture": 0.03,
    "religionPhilosophy": 0.02,
    "miscellaneous": 0.01,
}


def load_question_bundle(path: Path) -> list[dict[str, Any]]:
    """Load questions from a JSON bundle file."""
    with open(path) as f:
        data = json.load(f)
        return data.get("questions", [])


def merge_questions(
    *bundles: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Merge multiple question lists, deduplicating by ID."""
    seen_ids: set[str] = set()
    merged: list[dict[str, Any]] = []

    for bundle in bundles:
        for q in bundle:
            qid = q.get("id")
            if qid and qid not in seen_ids:
                seen_ids.add(qid)
                merged.append(q)

    return merged


def group_by_domain(questions: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    """Group questions by domain."""
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for q in questions:
        domain = q.get("domain", "miscellaneous")
        grouped[domain].append(q)
    return dict(grouped)


def select_balanced_subset(
    questions: list[dict[str, Any]],
    target_count: int,
    distribution: dict[str, float] | None = None
) -> list[dict[str, Any]]:
    """
    Select a balanced subset of questions based on target distribution.

    Args:
        questions: All available questions
        target_count: Total number of questions to select
        distribution: Target distribution by domain (default: competition weights)

    Returns:
        Balanced subset of questions
    """
    if distribution is None:
        distribution = TARGET_DISTRIBUTION

    grouped = group_by_domain(questions)
    selected: list[dict[str, Any]] = []

    # Calculate target counts per domain
    for domain, weight in sorted(distribution.items(), key=lambda x: -x[1]):
        target = int(target_count * weight)
        available = grouped.get(domain, [])

        if len(available) >= target:
            # Random sample from available
            selected.extend(random.sample(available, target))
        else:
            # Take all available
            selected.extend(available)
            # Note: shortfall will be made up by other domains

    # If we're short, add more from domains with excess
    shortfall = target_count - len(selected)
    if shortfall > 0:
        remaining = [q for q in questions if q not in selected]
        if remaining:
            additional = min(shortfall, len(remaining))
            selected.extend(random.sample(remaining, additional))

    return selected


def create_bundle(
    questions: list[dict[str, Any]],
    version: str,
    sources: list[str]
) -> dict[str, Any]:
    """Create a question bundle with metadata."""
    return {
        "version": version,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sources": sources,
        "totalQuestions": len(questions),
        "questions": questions
    }


def print_stats(questions: list[dict[str, Any]], label: str) -> None:
    """Print statistics about a question set."""
    grouped = group_by_domain(questions)

    print(f"\n=== {label} ===")
    print(f"Total: {len(questions)}")
    print("\nBy Domain:")
    for domain in sorted(grouped.keys()):
        count = len(grouped[domain])
        pct = count / len(questions) * 100 if questions else 0
        target_pct = TARGET_DISTRIBUTION.get(domain, 0) * 100
        print(f"  {domain}: {count} ({pct:.1f}%, target: {target_pct:.0f}%)")


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Merge KB questions from multiple sources"
    )
    parser.add_argument(
        "-s", "--sources",
        nargs="+",
        type=Path,
        default=[
            Path("output/kb-science-bowl-questions.json"),
            Path("output/kb-opentrivia-questions.json"),
        ],
        help="Source question bundle files"
    )
    parser.add_argument(
        "-o", "--output",
        type=Path,
        default=Path("output/kb-all-questions.json"),
        help="Output file for full merged bundle"
    )
    parser.add_argument(
        "--ios-output",
        type=Path,
        default=Path("output/kb-ios-bundle.json"),
        help="Output file for iOS app bundle"
    )
    parser.add_argument(
        "--ios-count",
        type=int,
        default=1000,
        help="Number of questions for iOS bundle"
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for reproducibility"
    )

    args = parser.parse_args()

    random.seed(args.seed)

    # Load all sources
    all_questions: list[dict[str, Any]] = []
    source_names: list[str] = []

    for source_path in args.sources:
        if source_path.exists():
            print(f"Loading {source_path}...")
            questions = load_question_bundle(source_path)
            all_questions = merge_questions(all_questions, questions)
            source_names.append(source_path.stem)
            print(f"  Loaded {len(questions)} questions")
        else:
            print(f"Warning: Source not found: {source_path}")

    print_stats(all_questions, "Full Merged Dataset")

    # Create full bundle
    full_bundle = create_bundle(all_questions, "2.0.0", source_names)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with open(args.output, "w") as f:
        json.dump(full_bundle, f, indent=2)
    print(f"\nWrote full bundle to {args.output}")

    # Create iOS bundle (balanced subset)
    ios_questions = select_balanced_subset(all_questions, args.ios_count)
    print_stats(ios_questions, f"iOS Bundle ({args.ios_count} questions)")

    ios_bundle = create_bundle(ios_questions, "2.0.0", source_names)
    with open(args.ios_output, "w") as f:
        json.dump(ios_bundle, f, indent=2)
    print(f"\nWrote iOS bundle to {args.ios_output}")


if __name__ == "__main__":
    main()
