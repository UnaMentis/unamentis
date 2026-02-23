#!/usr/bin/env python3
"""Generate admin summary JSON for the live monitoring dashboard.

Reads architecture.json and version.json to produce admin-summary.json
matching the AdminSummary TypeScript interface in viewer/src/types.ts.

Uses only Python standard library.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone


def now_iso() -> str:
    """Return current UTC time as ISO 8601 string."""
    return datetime.now(timezone.utc).isoformat()


def count_components(arch: dict) -> int:
    """Recursively count all components including children."""
    total = 0
    for comp in arch.get("components", []):
        total += 1
        total += _count_children(comp)
    return total


def _count_children(component: dict) -> int:
    """Count children recursively."""
    total = 0
    for child in component.get("children", []):
        total += 1
        total += _count_children(child)
    return total


def determine_repo_status(version: dict) -> str:
    """Determine repo health status based on version timestamp.

    Returns "ok" if last update was within 24 hours, "stale" otherwise.
    """
    updated_at = version.get("updated_at", "")
    if not updated_at:
        return "stale"

    try:
        # Handle both Z suffix and +00:00 timezone formats
        updated_at = updated_at.replace("Z", "+00:00")
        last_update = datetime.fromisoformat(updated_at)
        age_seconds = (datetime.now(timezone.utc) - last_update).total_seconds()
        if age_seconds > 86400:  # 24 hours
            return "stale"
        return "ok"
    except (ValueError, TypeError):
        return "stale"


def get_recent_activity(limit: int = 20) -> list:
    """Get recent git commits as activity entries.

    Returns a list matching AdminSummaryActivity shape. Component-level
    diff counts are 0 until Stream G/K provides _diff_summary metadata.
    """
    activity = []

    try:
        # Get recent commits with format: hash|timestamp|message
        result = subprocess.run(
            [
                "git",
                "log",
                f"-{limit}",
                "--format=%H|%aI|%s",
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return []

        for line in result.stdout.strip().split("\n"):
            if not line:
                continue
            parts = line.split("|", 2)
            if len(parts) < 3:
                continue

            sha, timestamp, message = parts

            # Get files changed count for this commit
            files_changed = _get_files_changed(sha)

            activity.append(
                {
                    "timestamp": timestamp,
                    "commit_sha": sha,
                    "commit_message": message,
                    "diff_summary": {
                        "components_added": 0,
                        "components_removed": 0,
                        "components_modified": 0,
                        "relationships_changed": 0,
                        "files_changed": files_changed,
                    },
                }
            )

    except (subprocess.SubprocessError, OSError) as e:
        print(f"Warning: Failed to get git history: {e}", file=sys.stderr)

    return activity


def _get_files_changed(sha: str) -> int:
    """Get the number of files changed in a commit."""
    try:
        result = subprocess.run(
            ["git", "show", "--stat", "--format=", sha],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return 0

        # The last line of --stat output contains "N files changed"
        lines = result.stdout.strip().split("\n")
        if not lines:
            return 0

        last_line = lines[-1]
        # Match patterns like "3 files changed" or "1 file changed"
        for part in last_line.split(","):
            part = part.strip()
            if "file" in part and "changed" in part:
                try:
                    return int(part.split()[0])
                except (ValueError, IndexError):
                    pass
        return 0

    except (subprocess.SubprocessError, OSError):
        return 0


def compute_daily_counts(activity: list) -> dict:
    """Group activity entries by date and count commits per day."""
    counts = {}
    for entry in activity:
        timestamp = entry.get("timestamp", "")
        if not timestamp:
            continue
        # Extract date portion (YYYY-MM-DD)
        date = timestamp[:10]
        if len(date) == 10 and date[4] == "-" and date[7] == "-":
            counts[date] = counts.get(date, 0) + 1
    return counts


def build_admin_summary(
    arch: dict, version: dict, repo: str, sha: str
) -> dict:
    """Build the AdminSummary JSON."""
    repo_name = repo.split("/")[-1] if "/" in repo else repo

    activity = get_recent_activity()
    daily_counts = compute_daily_counts(activity)

    return {
        "repos": [
            {
                "name": repo_name,
                "last_update": version.get("updated_at", now_iso()),
                "version": version.get("version", 0),
                "component_count": count_components(arch),
                "status": determine_repo_status(version),
            }
        ],
        "activity": activity,
        "daily_counts": daily_counts,
        "generated_at": now_iso(),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Generate admin summary for live monitoring dashboard"
    )
    parser.add_argument(
        "--arch",
        required=True,
        help="Path to architecture.json",
    )
    parser.add_argument(
        "--version",
        required=True,
        help="Path to version.json",
    )
    parser.add_argument(
        "--repo",
        required=True,
        help="GitHub repository (owner/repo)",
    )
    parser.add_argument(
        "--sha",
        required=True,
        help="Current commit SHA",
    )
    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Output file path for admin-summary.json",
    )
    args = parser.parse_args()

    # Load architecture.json
    try:
        with open(args.arch) as f:
            arch = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Warning: Failed to load architecture.json: {e}", file=sys.stderr)
        arch = {"components": [], "stats": {}}

    # Load version.json
    try:
        with open(args.version) as f:
            version = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"Warning: Failed to load version.json: {e}", file=sys.stderr)
        version = {
            "version": 0,
            "updated_at": now_iso(),
            "commit_sha": args.sha,
        }

    summary = build_admin_summary(arch, version, args.repo, args.sha)

    # Ensure output directory exists
    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    with open(args.output, "w") as f:
        json.dump(summary, f, indent=2)

    print(
        f"Generated admin summary: "
        f"{len(summary['repos'])} repos, "
        f"{len(summary['activity'])} activity entries -> {args.output}"
    )


if __name__ == "__main__":
    main()
