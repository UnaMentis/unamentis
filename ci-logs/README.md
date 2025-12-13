# CI Logs

This folder contains the latest CI run results, automatically updated by GitHub Actions.

## Files

- `latest-results.md` - Results from the most recent CI run (auto-generated)

## How it works

After each push to `main` or `develop`, the CI workflow:
1. Runs lint checks and unit tests
2. Generates a summary in `latest-results.md`
3. Commits the results back to this folder

This allows tools (like Claude Code) to read CI results directly from the repo.

## Avoiding infinite loops

Commits from CI include `[skip-ci-log]` in the message to prevent triggering another CI run.
