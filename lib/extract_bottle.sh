#!/bin/bash
# extract_bottle.sh - Extract and organize bottle contents
#
# Bottles have structure like:
# redis/8.4.0/
# ├── .bottle/
# │   └── etc/redis.conf
# ├── .brew/
# │   └── redis.rb
# ├── bin/
# │   ├── redis-server
# │   └── redis-cli
# └── ...
#
# We reorganize to:
# output/redis/8.4.0-arm64/
# ├── bin/
# ├── lib/          (for bundled dylibs)
# ├── etc/          (config files)
# └── manifest.json

# Extract a bottle tarball to organized structure
# Usage: extract_bottle <bottle_path> <output_dir> <formula> <version>
extract_bottle() {
    local bottle_path="$1"
    local output_dir="$2"
    local formula="$3"
    local version="$4"

    # Clean previous extraction
    rm -rf "$output_dir"
    mkdir -p "$output_dir"

    # Create temp dir for extraction
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    # Extract bottle
    tar -xzf "$bottle_path" -C "$temp_dir"

    # Find the extracted formula directory
    local extracted_dir="$temp_dir/$formula/$version"
    if [[ ! -d "$extracted_dir" ]]; then
        # Try to find it (version might differ slightly)
        extracted_dir=$(find "$temp_dir" -mindepth 2 -maxdepth 2 -type d | head -1)
    fi

    if [[ ! -d "$extracted_dir" ]]; then
        log_error "Could not find extracted formula directory"
        return 1
    fi

    # Create output structure
    mkdir -p "$output_dir/bin"
    mkdir -p "$output_dir/lib"
    mkdir -p "$output_dir/etc"

    # Copy binaries
    if [[ -d "$extracted_dir/bin" ]]; then
        cp -a "$extracted_dir/bin/"* "$output_dir/bin/" 2>/dev/null || true
    fi

    # Copy libraries (some formulas have their own libs)
    if [[ -d "$extracted_dir/lib" ]]; then
        # Copy top-level dylibs
        cp -a "$extracted_dir/lib/"*.dylib "$output_dir/lib/" 2>/dev/null || true

        # Copy dylibs from subdirectories (e.g., lib/postgresql/, lib/mariadb/)
        # These are formula-specific libraries
        find "$extracted_dir/lib" -mindepth 2 -name "*.dylib" -exec cp -a {} "$output_dir/lib/" \; 2>/dev/null || true
    fi

    # Copy config files from .bottle/etc
    if [[ -d "$extracted_dir/.bottle/etc" ]]; then
        cp -a "$extracted_dir/.bottle/etc/"* "$output_dir/etc/" 2>/dev/null || true
    fi

    # Copy any other config files from etc
    if [[ -d "$extracted_dir/etc" ]]; then
        cp -a "$extracted_dir/etc/"* "$output_dir/etc/" 2>/dev/null || true
    fi

    # Copy share folder if present (needed for MariaDB, etc.)
    if [[ -d "$extracted_dir/share" ]]; then
        cp -a "$extracted_dir/share" "$output_dir/" 2>/dev/null || true
    fi

    # PostgreSQL special case: Homebrew puts share files in share/postgresql@XX/
    # but PostgreSQL expects them at ../share/ relative to bin/
    # Move share/postgresql/* up to share/ for PostgreSQL
    if [[ "$formula" == "postgresql"* ]] && [[ -d "$output_dir/share/postgresql" ]]; then
        # Move contents of share/postgresql/ to share/
        mv "$output_dir/share/postgresql/"* "$output_dir/share/" 2>/dev/null || true
        rmdir "$output_dir/share/postgresql" 2>/dev/null || true
    fi

    # Copy license and readme if present
    cp "$extracted_dir/LICENSE"* "$output_dir/" 2>/dev/null || true
    cp "$extracted_dir/README"* "$output_dir/" 2>/dev/null || true
    cp "$extracted_dir/COPYING"* "$output_dir/" 2>/dev/null || true

    # Clean up temp dir
    rm -rf "$temp_dir"
    trap - EXIT

    return 0
}

# List binaries in an extracted package
# Usage: list_binaries <output_dir>
list_binaries() {
    local output_dir="$1"
    find "$output_dir/bin" -type f -perm +111 2>/dev/null | xargs -I{} basename {}
}

# Get the main binary name for a formula
# Usage: get_main_binary <formula>
get_main_binary() {
    local formula="$1"

    case "$formula" in
        redis)      echo "redis-server" ;;
        valkey)     echo "valkey-server" ;;
        mongodb)    echo "mongod" ;;
        mariadb)    echo "mariadbd" ;;
        postgresql) echo "postgres" ;;
        meilisearch) echo "meilisearch" ;;
        minio)      echo "minio" ;;
        *)          echo "$formula" ;;
    esac
}
