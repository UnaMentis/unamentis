#!/bin/bash
# Feature Flag Audit Script
# Scans codebase for feature flag usage and checks for stale flags
#
# Usage:
#   ./scripts/feature-flag-audit.sh           # Run full audit
#   ./scripts/feature-flag-audit.sh --list    # List all flags found in code
#   ./scripts/feature-flag-audit.sh --check   # Check for issues (CI mode)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MAX_FLAG_AGE_DAYS=${MAX_FLAG_AGE_DAYS:-90}
WARNING_AGE_DAYS=${WARNING_AGE_DAYS:-60}

# Patterns to search for feature flag usage
SWIFT_PATTERNS=(
    'isEnabled\s*\(\s*"[^"]+"\s*\)'
    'featureFlag\s*\(\s*"[^"]+"\s*\)'
    'FeatureFlagService.*isEnabled'
)

TS_PATTERNS=(
    'isEnabled\s*\(\s*['"'"'"][^'"'"'"]+['"'"'"]\s*\)'
    'useFlag\s*\(\s*['"'"'"][^'"'"'"]+['"'"'"]\s*\)'
    '<FeatureGate\s+flag=['"'"'"][^'"'"'"]+['"'"'"]'
)

PYTHON_PATTERNS=(
    'is_enabled\s*\(\s*['"'"'"][^'"'"'"]+['"'"'"]\s*\)'
    'feature_flags.*is_enabled'
)

# Temporary files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

FOUND_FLAGS="$TEMP_DIR/found_flags.txt"
FLAG_LOCATIONS="$TEMP_DIR/flag_locations.txt"

# Functions

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Feature Flag Audit - UnaMentis${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

find_swift_flags() {
    echo -e "${BLUE}Scanning Swift files...${NC}"

    # Find all Swift files (excluding build artifacts)
    find . -name "*.swift" \
        -not -path "./.build/*" \
        -not -path "./DerivedData/*" \
        -not -path "*/Pods/*" \
        -print0 2>/dev/null | while IFS= read -r -d '' file; do

        for pattern in "${SWIFT_PATTERNS[@]}"; do
            grep -oE "$pattern" "$file" 2>/dev/null | while read -r match; do
                # Extract flag name from match
                flag_name=$(echo "$match" | grep -oE '"[^"]+"' | tr -d '"')
                if [ -n "$flag_name" ]; then
                    echo "$flag_name" >> "$FOUND_FLAGS"
                    echo "$flag_name|$file" >> "$FLAG_LOCATIONS"
                fi
            done
        done
    done
}

find_typescript_flags() {
    echo -e "${BLUE}Scanning TypeScript/JavaScript files...${NC}"

    # Find all TS/JS files (excluding node_modules)
    find . \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
        -not -path "*/node_modules/*" \
        -not -path "./.next/*" \
        -print0 2>/dev/null | while IFS= read -r -d '' file; do

        for pattern in "${TS_PATTERNS[@]}"; do
            grep -oE "$pattern" "$file" 2>/dev/null | while read -r match; do
                # Extract flag name from match
                flag_name=$(echo "$match" | grep -oE "['\"][^'\"]+['\"]" | head -1 | tr -d "'" | tr -d '"')
                if [ -n "$flag_name" ]; then
                    echo "$flag_name" >> "$FOUND_FLAGS"
                    echo "$flag_name|$file" >> "$FLAG_LOCATIONS"
                fi
            done
        done
    done
}

find_python_flags() {
    echo -e "${BLUE}Scanning Python files...${NC}"

    # Find all Python files
    find . -name "*.py" \
        -not -path "./.venv/*" \
        -not -path "*/__pycache__/*" \
        -print0 2>/dev/null | while IFS= read -r -d '' file; do

        for pattern in "${PYTHON_PATTERNS[@]}"; do
            grep -oE "$pattern" "$file" 2>/dev/null | while read -r match; do
                # Extract flag name from match
                flag_name=$(echo "$match" | grep -oE "['\"][^'\"]+['\"]" | head -1 | tr -d "'" | tr -d '"')
                if [ -n "$flag_name" ]; then
                    echo "$flag_name" >> "$FOUND_FLAGS"
                    echo "$flag_name|$file" >> "$FLAG_LOCATIONS"
                fi
            done
        done
    done
}

list_flags() {
    echo -e "\n${GREEN}Feature Flags Found in Codebase:${NC}\n"

    if [ ! -s "$FOUND_FLAGS" ]; then
        echo "  No feature flags found."
        return
    fi

    # Get unique flags with counts
    sort "$FOUND_FLAGS" | uniq -c | sort -rn | while read -r count flag; do
        echo -e "  ${YELLOW}$flag${NC} (used $count times)"

        # Show locations
        grep "^$flag|" "$FLAG_LOCATIONS" 2>/dev/null | cut -d'|' -f2 | sort -u | head -5 | while read -r loc; do
            echo -e "    └── $loc"
        done
    done
}

check_flag_metadata() {
    echo -e "\n${BLUE}Checking flag metadata...${NC}\n"

    # Check if metadata DB is available
    local metadata_file="server/feature-flags/flag_metadata.json"

    if [ ! -f "$metadata_file" ]; then
        echo -e "${YELLOW}  No local flag metadata file found.${NC}"
        echo "  Create $metadata_file to track flag ownership and expiration."
        return 0
    fi

    local issues=0
    local warnings=0

    # Parse metadata and check for issues
    if command -v python3 &> /dev/null; then
        python3 <<PYTHON_SCRIPT
import json
import sys
from datetime import datetime, timedelta

MAX_AGE = int('${MAX_FLAG_AGE_DAYS}')
WARNING_AGE = int('${WARNING_AGE_DAYS}')

try:
    with open('server/feature-flags/flag_metadata.json') as f:
        metadata = json.load(f)
except Exception as e:
    print(f"  Error reading metadata: {e}")
    sys.exit(0)

today = datetime.now().date()
issues = 0
warnings = 0

for flag_name, info in metadata.get('flags', {}).items():
    owner = info.get('owner', 'unknown')
    created = info.get('created_at', '')
    removal_date = info.get('target_removal_date', '')
    is_permanent = info.get('is_permanent', False)

    if is_permanent:
        continue

    if removal_date:
        removal = datetime.strptime(removal_date, '%Y-%m-%d').date()
        days_until = (removal - today).days

        if days_until < 0:
            print(f"  \033[0;31m[OVERDUE]\033[0m {flag_name}")
            print(f"           Owner: {owner}")
            print(f"           Was due: {removal_date} ({-days_until} days ago)")
            issues += 1
        elif days_until <= 14:
            print(f"  \033[1;33m[DUE SOON]\033[0m {flag_name}")
            print(f"            Owner: {owner}")
            print(f"            Due: {removal_date} ({days_until} days)")
            warnings += 1

print(f"\n  Summary: {issues} overdue, {warnings} due soon")

if issues > 0:
    sys.exit(1)
PYTHON_SCRIPT
        return $?
    fi

    return 0
}

generate_report() {
    echo -e "\n${BLUE}Generating audit report...${NC}\n"

    local report_file="$TEMP_DIR/audit_report.md"

    {
        echo "# Feature Flag Audit Report"
        echo ""
        echo "**Generated:** $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
        echo ""
        echo "## Summary"
        echo ""

        if [ -s "$FOUND_FLAGS" ]; then
            local total=$(sort "$FOUND_FLAGS" | uniq | wc -l | tr -d ' ')
            echo "- **Total unique flags:** $total"
            echo ""
            echo "## Flags by Usage"
            echo ""
            echo "| Flag Name | Usage Count |"
            echo "|-----------|-------------|"
            sort "$FOUND_FLAGS" | uniq -c | sort -rn | while read -r count flag; do
                echo "| \`$flag\` | $count |"
            done
        else
            echo "No feature flags found in codebase."
        fi

        echo ""
        echo "## Recommendations"
        echo ""
        echo "1. Ensure all flags have owners assigned"
        echo "2. Set target removal dates for non-permanent flags"
        echo "3. Review and remove flags older than $MAX_FLAG_AGE_DAYS days"
        echo "4. Document flag purpose in metadata"
    } > "$report_file"

    cat "$report_file"
}

# Main

main() {
    local mode="${1:-full}"

    print_header

    # Initialize files
    touch "$FOUND_FLAGS"
    touch "$FLAG_LOCATIONS"

    # Scan codebase
    find_swift_flags
    find_typescript_flags
    find_python_flags

    case "$mode" in
        --list)
            list_flags
            ;;
        --check)
            list_flags
            check_flag_metadata
            exit_code=$?
            if [ $exit_code -ne 0 ]; then
                echo -e "\n${RED}Audit failed: Overdue flags detected${NC}"
                exit 1
            fi
            echo -e "\n${GREEN}Audit passed${NC}"
            ;;
        *)
            list_flags
            check_flag_metadata || true
            generate_report
            ;;
    esac

    echo ""
}

main "$@"
