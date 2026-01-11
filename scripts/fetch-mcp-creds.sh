#!/usr/bin/env bash
# Shared credential fetching logic

set -euo pipefail

REPO="sirfifer/unamentis-learning"
WORKFLOW="get-mcp-creds.yml"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/unamentis"
CACHE_FILE="$CACHE_DIR/creds.json"
AGE_KEY="$HOME/.config/unamentis/age-key.txt"
CACHE_TTL="${MCP_CACHE_TTL:-3600}"  # Default 1 hour

ensure_credentials() {
    # Check if age key exists
    if [[ ! -f "$AGE_KEY" ]]; then
        echo "ERROR: Age key not found at $AGE_KEY" >&2
        echo "Run: age-keygen -o $AGE_KEY" >&2
        exit 1
    fi

    # Check if cache is valid
    if [[ -f "$CACHE_FILE" ]]; then
        local age_minutes=$((CACHE_TTL / 60))
        if [[ -z $(find "$CACHE_FILE" -mmin +${age_minutes} 2>/dev/null) ]]; then
            # Cache is fresh
            return 0
        fi
    fi

    # Need to fetch fresh credentials
    fetch_credentials
}

fetch_credentials() {
    echo "Fetching MCP credentials..." >&2
    mkdir -p "$CACHE_DIR"

    # Get public key
    local public_key
    public_key=$(grep "public key:" "$AGE_KEY" | cut -d' ' -f4)

    if [[ -z "$public_key" ]]; then
        echo "ERROR: Could not extract public key from $AGE_KEY" >&2
        exit 1
    fi

    # Trigger workflow
    echo "Triggering credential workflow..." >&2
    gh workflow run "$WORKFLOW" -R "$REPO" -f public_key="$public_key"

    # Wait for workflow to start
    sleep 5

    # Get run ID
    local run_id
    run_id=$(gh run list -R "$REPO" -w "$WORKFLOW" --limit 1 --json databaseId -q '.[0].databaseId')

    if [[ -z "$run_id" ]]; then
        echo "ERROR: Could not find workflow run" >&2
        exit 1
    fi

    echo "Waiting for workflow run $run_id to complete..." >&2
    gh run watch "$run_id" -R "$REPO" --exit-status

    # Download artifact
    echo "Downloading encrypted credentials..." >&2
    rm -rf "$CACHE_DIR/mcp-creds"  # Clean any old download
    gh run download "$run_id" -R "$REPO" -n mcp-creds -D "$CACHE_DIR"

    # Decrypt
    if [[ ! -f "$CACHE_DIR/creds.age" ]]; then
        echo "ERROR: Downloaded artifact missing creds.age" >&2
        exit 1
    fi

    echo "Decrypting credentials..." >&2
    age -d -i "$AGE_KEY" "$CACHE_DIR/creds.age" > "$CACHE_FILE"
    chmod 600 "$CACHE_FILE"
    rm -f "$CACHE_DIR/creds.age"

    echo "Credentials ready." >&2
}

get_credential() {
    local key="$1"
    ensure_credentials
    jq -r ".$key" "$CACHE_FILE"
}

# Export for use by other scripts
export -f ensure_credentials fetch_credentials get_credential
export CACHE_FILE AGE_KEY
