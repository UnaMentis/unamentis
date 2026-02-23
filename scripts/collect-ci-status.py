#!/usr/bin/env python3
"""Collect CI/CD status from GitHub API and produce status-overlay.json.

Uses only Python standard library. Requires GITHUB_TOKEN environment variable
for API authentication (automatically available in GitHub Actions).

Output matches the StatusOverlay TypeScript interface defined in
viewer/src/types.ts.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

GITHUB_API = "https://api.github.com"

# Map GitHub conclusion values to status levels
CONCLUSION_MAP = {
    "success": "ok",
    "failure": "error",
    "timed_out": "error",
    "cancelled": "warning",
    "skipped": "warning",
    "action_required": "warning",
    "stale": "warning",
    "neutral": "ok",
    "startup_failure": "error",
}


def github_api_get(url: str, token: str) -> dict:
    """Make an authenticated GET request to the GitHub API."""
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get_workflow_runs(repo: str, sha: str, token: str) -> list:
    """Get workflow runs for a specific commit SHA."""
    url = f"{GITHUB_API}/repos/{repo}/actions/runs?head_sha={sha}&per_page=100"
    data = github_api_get(url, token)
    return data.get("workflow_runs", [])


def get_check_suites(repo: str, sha: str, token: str) -> list:
    """Get check suites for a specific commit SHA."""
    url = f"{GITHUB_API}/repos/{repo}/commits/{sha}/check-suites?per_page=100"
    data = github_api_get(url, token)
    return data.get("check_suites", [])


def slugify(name: str) -> str:
    """Convert a workflow name to a URL-safe slug."""
    slug = name.lower().strip()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = slug.strip("-")
    return slug


def map_conclusion(conclusion, status=None) -> str:
    """Map a GitHub conclusion/status to a level string."""
    if conclusion is None:
        if status in ("in_progress", "queued", "waiting", "pending", "requested"):
            return "info"
        return "warning"
    return CONCLUSION_MAP.get(conclusion, "warning")


def format_title(name: str, conclusion, status=None) -> str:
    """Format a human-readable status title."""
    if conclusion is None:
        if status == "in_progress":
            return f"{name} running"
        if status in ("queued", "waiting", "requested", "pending"):
            return f"{name} queued"
        return f"{name} in progress"
    if conclusion == "success":
        return f"{name} passed"
    if conclusion == "failure":
        return f"{name} failed"
    if conclusion == "cancelled":
        return f"{name} cancelled"
    if conclusion == "timed_out":
        return f"{name} timed out"
    if conclusion == "skipped":
        return f"{name} skipped"
    return f"{name}: {conclusion}"


def format_detail(run: dict) -> str:
    """Format detail text for a workflow run."""
    run_number = run.get("run_number", "")
    conclusion = run.get("conclusion")
    if conclusion is None:
        return f"Run #{run_number} is in progress"
    return f"Run #{run_number} {conclusion}"


def now_iso() -> str:
    """Return current UTC time as ISO 8601 string."""
    return datetime.now(timezone.utc).isoformat()


def build_status_overlay(repo: str, sha: str, token: str) -> dict:
    """Build the StatusOverlay JSON from GitHub API data."""
    architecture = {}

    # Collect workflow runs
    try:
        runs = get_workflow_runs(repo, sha, token)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        print(f"Warning: Failed to fetch workflow runs: {e}", file=sys.stderr)
        runs = []

    for run in runs:
        name = run.get("name", "Unknown Workflow")
        key = f"ci:{slugify(name)}"
        conclusion = run.get("conclusion")
        status = run.get("status")
        html_url = run.get("html_url", "")
        updated = run.get("updated_at", now_iso())

        architecture[key] = {
            "level": map_conclusion(conclusion, status),
            "title": format_title(name, conclusion, status),
            "detail": format_detail(run),
            "url": html_url,
            "category": "ci",
            "updated_at": updated,
        }

    # Collect check suites (filter out GitHub Actions to avoid duplication)
    try:
        suites = get_check_suites(repo, sha, token)
    except (urllib.error.URLError, urllib.error.HTTPError, OSError) as e:
        print(f"Warning: Failed to fetch check suites: {e}", file=sys.stderr)
        suites = []

    for suite in suites:
        app = suite.get("app", {})
        app_slug = app.get("slug", "unknown")

        # Skip GitHub Actions check suites since we already have workflow runs
        if app_slug == "github-actions":
            continue

        app_name = app.get("name", app_slug)
        key = f"check:{app_slug}"
        conclusion = suite.get("conclusion")
        status = suite.get("status")
        updated = suite.get("updated_at", now_iso())

        architecture[key] = {
            "level": map_conclusion(conclusion, status),
            "title": format_title(app_name, conclusion, status),
            "category": "check",
            "updated_at": updated,
        }

    return {
        "components": {},
        "architecture": architecture,
        "updated_at": now_iso(),
        "commit_sha": sha,
    }


def empty_overlay(sha: str) -> dict:
    """Return a valid but empty StatusOverlay."""
    return {
        "components": {},
        "architecture": {},
        "updated_at": now_iso(),
        "commit_sha": sha,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Collect CI/CD status from GitHub API"
    )
    parser.add_argument(
        "--repo",
        required=True,
        help="GitHub repository (owner/repo)",
    )
    parser.add_argument(
        "--sha",
        required=True,
        help="Commit SHA to collect status for",
    )
    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Output file path for status-overlay.json",
    )
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print(
            "Warning: GITHUB_TOKEN not set. Producing empty overlay.",
            file=sys.stderr,
        )
        overlay = empty_overlay(args.sha)
    else:
        overlay = build_status_overlay(args.repo, args.sha, token)

    # Ensure output directory exists
    output_dir = os.path.dirname(args.output)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    with open(args.output, "w") as f:
        json.dump(overlay, f, indent=2)

    status_count = len(overlay["architecture"])
    print(f"Collected {status_count} CI status entries -> {args.output}")


if __name__ == "__main__":
    main()
