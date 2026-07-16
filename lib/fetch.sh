#!/bin/bash
# fetch.sh - Download Homebrew bottles using brew fetch
#
# This uses `brew fetch` as a wrapper which handles:
# - Finding the correct bottle URL from formula
# - Downloading from ghcr.io with authentication
# - Verifying SHA256 checksums
# - Caching in Homebrew's cache directory

# Fetch a bottle and return its path
# Usage: fetch_bottle <formula> [version] [arch]
# Returns: path to downloaded bottle tarball
fetch_bottle() {
    local formula="$1"
    local version="${2:-latest}"
    local arch="${3:-arm64_sonoma}"

    # For specific versions, we need to use the versioned formula
    local fetch_formula="$formula"

    # Use brew fetch to download the bottle
    # --bottle-tag specifies the exact architecture to fetch
    if ! brew fetch --bottle-tag="$arch" "$fetch_formula" 2>/dev/null; then
        log_error "Failed to fetch bottle for $formula"
        return 1
    fi

    # Get the cached bottle path
    local bottle_path
    bottle_path=$(brew --cache "$fetch_formula" 2>/dev/null)

    if [[ ! -f "$bottle_path" ]]; then
        log_error "Bottle not found in cache: $bottle_path"
        return 1
    fi

    echo "$bottle_path"
}

# Get formula info from Homebrew API
# Usage: get_formula_info <formula>
# Returns: JSON with formula metadata
get_formula_info() {
    local formula="$1"
    curl -sL "https://formulae.brew.sh/api/formula/${formula}.json"
}

# Get the latest version of a formula
# Usage: get_latest_version <formula>
# Returns: version string (e.g., "8.4.0")
get_latest_version() {
    local formula="$1"
    get_formula_info "$formula" | jq -r '.versions.stable'
}

# Get dependencies of a formula
# Usage: get_dependencies <formula>
# Returns: space-separated list of dependency names
get_dependencies() {
    local formula="$1"
    get_formula_info "$formula" | jq -r '.dependencies[]?' 2>/dev/null || echo ""
}

# Check if a bottle exists for given formula/arch
# Usage: bottle_exists <formula> <arch>
# Returns: 0 if exists, 1 if not
bottle_exists() {
    local formula="$1"
    local arch="$2"

    local info
    info=$(get_formula_info "$formula")

    if echo "$info" | jq -e ".bottle.stable.files.${arch}" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
