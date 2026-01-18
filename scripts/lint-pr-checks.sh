#!/bin/bash
# lint-pr-checks.sh - Validates common issues caught by PR reviews
# Run this before submitting PRs to catch issues early
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FAILED=0
WARNINGS=0

echo -e "${BLUE}Running PR validation checks...${NC}"
echo ""

# =============================================================================
# 1. Swift Version Consistency
# =============================================================================
echo "1. Checking Swift version consistency..."

# Check Package.swift files for swift-tools-version (exclude third-party)
for pkg in $(find "$PROJECT_DIR" -name "Package.swift" \
    -not -path "*/DerivedData/*" \
    -not -path "*/.build/*" \
    -not -path "*/build/*" \
    -not -path "*/llama.cpp/*" \
    -not -path "*/.venv/*" \
    -not -path "*/node_modules/*"); do
    version=$(head -1 "$pkg" | grep -oE '[0-9]+\.[0-9]+' || echo "unknown")
    if [[ "$version" == "6.1" ]]; then
        echo -e "   ${RED}ERROR: $pkg uses swift-tools-version 6.1 (invalid, use 6.0)${NC}"
        FAILED=1
    elif [[ "$version" != "unknown" ]]; then
        echo -e "   ${GREEN}OK: $pkg uses swift-tools-version $version${NC}"
    fi
done

# Check pbxproj files for SWIFT_VERSION consistency (exclude third-party)
for proj in $(find "$PROJECT_DIR" -name "project.pbxproj" \
    -not -path "*/DerivedData/*" \
    -not -path "*/.build/*" \
    -not -path "*/build/*" \
    -not -path "*/llama.cpp/*" \
    -not -path "*/.venv/*" \
    -not -path "*/node_modules/*"); do
    versions=$(grep "SWIFT_VERSION" "$proj" | grep -oE '[0-9]+\.[0-9]+' | sort -u)
    count=$(echo "$versions" | wc -l | tr -d ' ')
    if [[ $count -gt 1 ]]; then
        echo -e "   ${YELLOW}WARNING: $proj has multiple SWIFT_VERSION values: $(echo $versions | tr '\n' ' ')${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
    if echo "$versions" | grep -q "5.0"; then
        echo -e "   ${YELLOW}WARNING: $proj still uses SWIFT_VERSION 5.0 (consider 6.0)${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
done

echo ""

# =============================================================================
# 2. Bundle ID Uniqueness (Test targets)
# =============================================================================
echo "2. Checking bundle ID uniqueness..."

# Find xcconfig files and check for duplicate bundle IDs between app and test targets
for config_dir in $(find "$PROJECT_DIR/server/server-manager" -type d -name "Config" 2>/dev/null); do
    shared=$(grep "PRODUCT_BUNDLE_IDENTIFIER" "$config_dir/Shared.xcconfig" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
    tests=$(grep "PRODUCT_BUNDLE_IDENTIFIER" "$config_dir/Tests.xcconfig" 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")

    if [[ -n "$shared" && -n "$tests" && "$shared" == "$tests" ]]; then
        echo -e "   ${RED}ERROR: Test bundle ID matches app bundle ID in $config_dir${NC}"
        echo -e "   ${RED}       App: $shared, Test: $tests${NC}"
        echo -e "   ${RED}       Add .uitests or .tests suffix to test bundle ID${NC}"
        FAILED=1
    elif [[ -n "$shared" && -n "$tests" ]]; then
        echo -e "   ${GREEN}OK: Bundle IDs are unique in $config_dir${NC}"
    fi
done

echo ""

# =============================================================================
# 3. LSUIElement for Menu Bar Apps
# =============================================================================
echo "3. Checking LSUIElement for menu bar apps..."

for xcconfig in $(find "$PROJECT_DIR/server/server-manager" -name "Shared.xcconfig" 2>/dev/null); do
    if grep -q "MenuBarExtra\|menu.bar\|menubar" "$(dirname "$xcconfig")/../"*.swift 2>/dev/null || \
       grep -q "MenuBarIcon" "$(dirname "$xcconfig")/../"*.swift 2>/dev/null; then
        lsui=$(grep "INFOPLIST_KEY_LSUIElement" "$xcconfig" | tail -1 | cut -d'=' -f2 | tr -d ' ')
        if [[ "$lsui" == "NO" ]]; then
            echo -e "   ${YELLOW}WARNING: $xcconfig has LSUIElement=NO (menu bar apps should be YES in release)${NC}"
            WARNINGS=$((WARNINGS + 1))
        elif [[ "$lsui" == "YES" ]]; then
            echo -e "   ${GREEN}OK: $xcconfig has LSUIElement=YES${NC}"
        fi
    fi
done

echo ""

# =============================================================================
# 4. Hardcoded User Paths
# =============================================================================
echo "4. Checking for hardcoded user paths..."

# Look for absolute paths with /Users/ in non-binary files (exclude third-party)
hardcoded=$(grep -rn "/Users/[a-z]" "$PROJECT_DIR" \
    --include="*.md" \
    --include="*.swift" \
    --include="*.xcconfig" \
    --include="*.toml" \
    --include="*.json" \
    --exclude-dir=".git" \
    --exclude-dir="DerivedData" \
    --exclude-dir="node_modules" \
    --exclude-dir=".build" \
    --exclude-dir="build" \
    --exclude-dir="llama.cpp" \
    --exclude-dir=".venv" \
    2>/dev/null | grep -v "PROJECT_ROOT" | grep -v "# Or use" | head -10 || true)

if [[ -n "$hardcoded" ]]; then
    echo -e "   ${YELLOW}WARNING: Found hardcoded user paths:${NC}"
    echo "$hardcoded" | while read line; do
        echo -e "   ${YELLOW}  $line${NC}"
    done
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "   ${GREEN}OK: No hardcoded user paths found${NC}"
fi

echo ""

# =============================================================================
# 5. Accessibility Labels on Buttons
# =============================================================================
echo "5. Checking accessibility labels on SwiftUI buttons..."

# Find Button declarations without accessibilityLabel
missing_a11y=0
while IFS= read -r swift_file; do
    [[ -z "$swift_file" ]] && continue
    # Simple heuristic: Button with Image but no accessibilityLabel nearby
    buttons_with_images=$(grep -c "Button.*{" "$swift_file" 2>/dev/null) || buttons_with_images=0
    a11y_labels=$(grep -c "accessibilityLabel" "$swift_file" 2>/dev/null) || a11y_labels=0

    if [[ "$buttons_with_images" -gt 0 && "$a11y_labels" -eq 0 ]]; then
        echo -e "   ${YELLOW}WARNING: $swift_file has $buttons_with_images Button(s) but no accessibilityLabel${NC}"
        missing_a11y=$((missing_a11y + 1))
    fi
done < <(find "$PROJECT_DIR/server/server-manager" -name "*.swift" -not -path "*/DerivedData/*" 2>/dev/null)

if [[ $missing_a11y -eq 0 ]]; then
    echo -e "   ${GREEN}OK: SwiftUI files have accessibility labels${NC}"
else
    WARNINGS=$((WARNINGS + missing_a11y))
fi

echo ""

# =============================================================================
# 6. Asset Catalog Completeness
# =============================================================================
echo "6. Checking asset catalog completeness..."

for contents in $(find "$PROJECT_DIR/server/server-manager" -name "Contents.json" -path "*colorset*" 2>/dev/null); do
    if ! grep -q '"color"' "$contents"; then
        echo -e "   ${YELLOW}WARNING: $contents is missing color definition${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
done

for contents in $(find "$PROJECT_DIR/server/server-manager" -name "Contents.json" -path "*appiconset*" 2>/dev/null); do
    if ! grep -q '"filename"' "$contents"; then
        echo -e "   ${YELLOW}WARNING: $contents may be missing icon filenames (using default)${NC}"
        # This is a warning, not an error - default icons are acceptable
    fi
done

echo -e "   ${GREEN}OK: Asset catalogs checked${NC}"
echo ""

# =============================================================================
# 7. Encoder/Decoder Symmetry Check
# =============================================================================
echo "7. Checking Codable encoder/decoder symmetry..."

for swift_file in $(find "$PROJECT_DIR/server/server-manager" -name "*.swift" -not -path "*/DerivedData/*" 2>/dev/null); do
    # Check if file has both encode(to:) and init(from:)
    if grep -q "func encode(to encoder" "$swift_file" && grep -q "init(from decoder" "$swift_file"; then
        # Look for potential case mismatches (PascalCase in encoder, snake_case in decoder)
        encoder_cases=$(grep -A1 'try container.encode("' "$swift_file" 2>/dev/null | grep -oE '"[A-Z][a-zA-Z]+"' | head -5 || true)
        decoder_cases=$(grep 'case "' "$swift_file" 2>/dev/null | grep -oE '"[a-z_]+"' | head -5 || true)

        if [[ -n "$encoder_cases" && -n "$decoder_cases" ]]; then
            # Check if encoder uses PascalCase while decoder uses snake_case
            if echo "$encoder_cases" | grep -qE '"[A-Z]' && echo "$decoder_cases" | grep -qE '"[a-z_]+_'; then
                echo -e "   ${YELLOW}WARNING: $swift_file may have encoder/decoder case mismatch${NC}"
                WARNINGS=$((WARNINGS + 1))
            fi
        fi
    fi
done

echo -e "   ${GREEN}OK: Codable files checked${NC}"
echo ""

# =============================================================================
# 8. prefers-reduced-motion in CSS/HTML
# =============================================================================
echo "8. Checking for prefers-reduced-motion in animated content..."

for html_file in $(find "$PROJECT_DIR/docs" -name "*.html" 2>/dev/null); do
    if grep -q "@keyframes\|animation:" "$html_file"; then
        if ! grep -q "prefers-reduced-motion" "$html_file"; then
            echo -e "   ${YELLOW}WARNING: $html_file has animations but no prefers-reduced-motion${NC}"
            WARNINGS=$((WARNINGS + 1))
        fi
    fi
done

echo -e "   ${GREEN}OK: Animation accessibility checked${NC}"
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=============================================="
if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}PR validation FAILED with $FAILED error(s) and $WARNINGS warning(s)${NC}"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}PR validation passed with $WARNINGS warning(s)${NC}"
    echo -e "${YELLOW}Consider fixing warnings before submitting PR${NC}"
    exit 0
else
    echo -e "${GREEN}PR validation passed! All checks OK.${NC}"
    exit 0
fi
