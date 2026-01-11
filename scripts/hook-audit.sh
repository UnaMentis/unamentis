#!/bin/bash
# UnaMentis Hook Audit Script
# Analyzes git hook execution logs and detects potential bypasses
#
# Usage:
#   ./scripts/hook-audit.sh          # Show summary
#   ./scripts/hook-audit.sh --full   # Show detailed log
#   ./scripts/hook-audit.sh --detect # Detect potential bypasses

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOOK_LOG_DIR="${HOME}/.unamentis/hook-logs"
PRE_COMMIT_LOG="${HOOK_LOG_DIR}/pre-commit.log"
PRE_PUSH_LOG="${HOOK_LOG_DIR}/pre-push.log"

# Ensure log directory exists
mkdir -p "$HOOK_LOG_DIR"

show_summary() {
    echo -e "${BLUE}=== Git Hook Audit Summary ===${NC}"
    echo ""

    # Pre-commit statistics
    if [ -f "$PRE_COMMIT_LOG" ]; then
        local total=$(wc -l < "$PRE_COMMIT_LOG" | tr -d ' ')
        local passed=$(grep -c "|PASSED|" "$PRE_COMMIT_LOG" 2>/dev/null || echo 0)
        local failed=$(grep -c "|FAILED|" "$PRE_COMMIT_LOG" 2>/dev/null || echo 0)
        local started=$(grep -c "|STARTED|" "$PRE_COMMIT_LOG" 2>/dev/null || echo 0)

        echo -e "${YELLOW}Pre-commit Hook:${NC}"
        echo "  Total executions: $started"
        echo "  Passed: $passed"
        echo "  Failed: $failed"

        # Calculate bypass estimate (started - passed - failed)
        local completed=$((passed + failed))
        if [ "$started" -gt "$completed" ]; then
            local interrupted=$((started - completed))
            echo -e "  ${RED}Interrupted/Incomplete: $interrupted${NC}"
        fi
        echo ""
    else
        echo -e "${YELLOW}Pre-commit Hook:${NC} No log file found"
        echo ""
    fi

    # Pre-push statistics
    if [ -f "$PRE_PUSH_LOG" ]; then
        local total=$(wc -l < "$PRE_PUSH_LOG" | tr -d ' ')
        local passed=$(grep -c "|PASSED|" "$PRE_PUSH_LOG" 2>/dev/null || echo 0)
        local failed=$(grep -c "|FAILED|" "$PRE_PUSH_LOG" 2>/dev/null || echo 0)
        local started=$(grep -c "|STARTED|" "$PRE_PUSH_LOG" 2>/dev/null || echo 0)

        echo -e "${YELLOW}Pre-push Hook:${NC}"
        echo "  Total executions: $started"
        echo "  Passed: $passed"
        echo "  Failed: $failed"

        local completed=$((passed + failed))
        if [ "$started" -gt "$completed" ]; then
            local interrupted=$((started - completed))
            echo -e "  ${RED}Interrupted/Incomplete: $interrupted${NC}"
        fi
        echo ""
    else
        echo -e "${YELLOW}Pre-push Hook:${NC} No log file found"
        echo ""
    fi

    # Recent activity
    echo -e "${BLUE}Recent Activity (last 10 entries):${NC}"
    echo ""

    if [ -f "$PRE_COMMIT_LOG" ]; then
        echo -e "${YELLOW}Pre-commit:${NC}"
        tail -10 "$PRE_COMMIT_LOG" | while IFS='|' read timestamp status branch user pid; do
            local color=$NC
            case $status in
                PASSED) color=$GREEN ;;
                FAILED) color=$RED ;;
                STARTED) color=$YELLOW ;;
            esac
            echo -e "  $timestamp | ${color}$status${NC} | $branch | $user"
        done
        echo ""
    fi

    if [ -f "$PRE_PUSH_LOG" ]; then
        echo -e "${YELLOW}Pre-push:${NC}"
        tail -10 "$PRE_PUSH_LOG" | while IFS='|' read timestamp status branch user pid; do
            local color=$NC
            case $status in
                PASSED) color=$GREEN ;;
                FAILED) color=$RED ;;
                STARTED) color=$YELLOW ;;
            esac
            echo -e "  $timestamp | ${color}$status${NC} | $branch | $user"
        done
        echo ""
    fi
}

show_full() {
    echo -e "${BLUE}=== Full Hook Execution Log ===${NC}"
    echo ""

    if [ -f "$PRE_COMMIT_LOG" ]; then
        echo -e "${YELLOW}=== Pre-commit Log ===${NC}"
        cat "$PRE_COMMIT_LOG"
        echo ""
    fi

    if [ -f "$PRE_PUSH_LOG" ]; then
        echo -e "${YELLOW}=== Pre-push Log ===${NC}"
        cat "$PRE_PUSH_LOG"
        echo ""
    fi
}

detect_bypasses() {
    echo -e "${BLUE}=== Potential Hook Bypass Detection ===${NC}"
    echo ""
    echo "Analyzing recent commits to detect potential --no-verify usage..."
    echo ""

    local bypass_detected=0

    # Get recent commits and check if hooks should have caught issues
    # This is a heuristic - we look for lint violations in committed code

    # Check for SwiftLint violations in recent commits
    if command -v swiftlint &> /dev/null; then
        echo -e "${YELLOW}Checking for SwiftLint violations in recent commits...${NC}"

        # Get files changed in last 10 commits
        local swift_files=$(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '\.swift$' || true)

        if [ -n "$swift_files" ]; then
            local violations=$(echo "$swift_files" | xargs swiftlint lint --quiet 2>/dev/null | wc -l | tr -d ' ')
            if [ "$violations" -gt 0 ]; then
                echo -e "  ${RED}Found $violations SwiftLint violations in recently committed files${NC}"
                echo "  This may indicate hook bypasses or new violations added post-commit"
                bypass_detected=1
            else
                echo -e "  ${GREEN}No SwiftLint violations found${NC}"
            fi
        else
            echo "  No Swift files in recent commits"
        fi
        echo ""
    fi

    # Check for Ruff violations in recent commits
    if command -v ruff &> /dev/null; then
        echo -e "${YELLOW}Checking for Ruff violations in recent commits...${NC}"

        local python_files=$(git diff --name-only HEAD~10..HEAD 2>/dev/null | grep -E '\.py$' || true)

        if [ -n "$python_files" ]; then
            local violations=$(echo "$python_files" | xargs ruff check --quiet 2>/dev/null | wc -l | tr -d ' ')
            if [ "$violations" -gt 0 ]; then
                echo -e "  ${RED}Found $violations Ruff violations in recently committed files${NC}"
                echo "  This may indicate hook bypasses or new violations added post-commit"
                bypass_detected=1
            else
                echo -e "  ${GREEN}No Ruff violations found${NC}"
            fi
        else
            echo "  No Python files in recent commits"
        fi
        echo ""
    fi

    # Check for secrets in recent commits
    if command -v gitleaks &> /dev/null; then
        echo -e "${YELLOW}Checking for secrets in recent commits...${NC}"

        local secrets=$(gitleaks detect --source . --log-opts="HEAD~10..HEAD" --no-banner 2>&1 | grep -c "Secret Detected" || echo 0)
        if [ "$secrets" -gt 0 ]; then
            echo -e "  ${RED}Found potential secrets in recent commits!${NC}"
            bypass_detected=1
        else
            echo -e "  ${GREEN}No secrets detected${NC}"
        fi
        echo ""
    fi

    # Summary
    if [ $bypass_detected -eq 1 ]; then
        echo -e "${RED}=== Potential bypasses detected ===${NC}"
        echo "Review the violations above. They may indicate:"
        echo "  1. Commits made with --no-verify"
        echo "  2. Hooks not installed on some machines"
        echo "  3. New violations introduced after initial commit"
        echo ""
        echo "Run './scripts/install-hooks.sh' to ensure hooks are installed."
        exit 1
    else
        echo -e "${GREEN}=== No obvious bypasses detected ===${NC}"
    fi
}

# Main
case "${1:-}" in
    --full)
        show_full
        ;;
    --detect)
        detect_bypasses
        ;;
    --help|-h)
        echo "Usage: $0 [--full|--detect|--help]"
        echo ""
        echo "  (no args)  Show summary of hook executions"
        echo "  --full     Show full hook execution log"
        echo "  --detect   Detect potential hook bypasses in recent commits"
        echo "  --help     Show this help message"
        ;;
    *)
        show_summary
        ;;
esac
