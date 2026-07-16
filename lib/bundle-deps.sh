#!/bin/bash
# bundle-deps.sh - Bundle dependency libraries with the extracted package
#
# For each dependency (like openssl@3), we:
# 1. Fetch the dependency bottle
# 2. Extract the required dylibs
# 3. Copy them to the output lib/ directory
# 4. Handle transitive dependencies recursively

# Get the dylibs needed for a dependency formula
# Usage: get_dependency_libs <formula>
get_dependency_libs() {
    local formula="$1"
    case "$formula" in
        openssl@3)   echo "libssl.3.dylib libcrypto.3.dylib" ;;
        openssl@1.1) echo "libssl.1.1.dylib libcrypto.1.1.dylib" ;;
        icu4c)       echo "libicudata.dylib libicui18n.dylib libicuio.dylib libicuuc.dylib" ;;
        zstd)        echo "libzstd.1.5.7.dylib libzstd.1.dylib libzstd.dylib" ;;
        lz4)         echo "liblz4.1.10.0.dylib liblz4.dylib liblz4.1.dylib" ;;
        snappy)      echo "libsnappy.dylib" ;;
        pcre2)       echo "libpcre2-8.dylib libpcre2-8.0.dylib libpcre2-posix.dylib libpcre2-posix.3.dylib" ;;
        libevent)    echo "libevent-2.1.7.dylib libevent_core-2.1.7.dylib libevent_extra-2.1.7.dylib libevent_openssl-2.1.7.dylib libevent_pthreads-2.1.7.dylib" ;;
        xz)          echo "liblzma.5.dylib" ;;
        lzo)         echo "liblzo2.2.dylib" ;;
        groonga)     echo "" ;;  # Optional, skip
        icu4c@78)    echo "" ;;  # Copy all dylibs
        protobuf)    echo "" ;;  # Copy all dylibs
        abseil)      echo "" ;;  # Copy all dylibs (many libs)
        zlib)        echo "libz.1.dylib libz.1.3.1.dylib libz.dylib" ;;
        krb5)        echo "" ;;  # Copy all dylibs
        readline)    echo "" ;;  # Copy all dylibs
        gettext)     echo "" ;;  # Copy all dylibs
        *)           echo "" ;;  # Will copy all dylibs
    esac
}

# Bundle dependencies for a formula
# Usage: bundle_dependencies <formula> <output_dir> <arch>
bundle_dependencies() {
    local formula="$1"
    local output_dir="$2"
    local arch="$3"
    local lib_dir="$output_dir/lib"

    # Get dependencies from formula API
    local deps
    deps=$(get_dependencies "$formula")

    if [[ -z "$deps" ]]; then
        log_info "  No dependencies to bundle"
        return 0
    fi

    log_info "  Dependencies: $deps"

    for dep in $deps; do
        bundle_single_dependency "$dep" "$lib_dir" "$arch"
    done
}

# Bundle a single dependency
# Usage: bundle_single_dependency <dep_formula> <lib_dir> <arch>
bundle_single_dependency() {
    local dep_formula="$1"
    local lib_dir="$2"
    local arch="$3"

    log_info "  Bundling dependency: $dep_formula"

    # Fetch the dependency bottle
    local dep_bottle
    dep_bottle=$(fetch_bottle "$dep_formula" "latest" "$arch" 2>/dev/null)

    if [[ -z "$dep_bottle" ]] || [[ ! -f "$dep_bottle" ]]; then
        log_warn "  Could not fetch bottle for $dep_formula"
        return 0
    fi

    # Extract to temp directory
    local temp_dir
    temp_dir=$(mktemp -d)
    tar -xzf "$dep_bottle" -C "$temp_dir"

    # Find the lib directory in the extracted bottle
    local dep_lib_dir
    dep_lib_dir=$(find "$temp_dir" -type d -name "lib" | head -1)

    if [[ -z "$dep_lib_dir" ]] || [[ ! -d "$dep_lib_dir" ]]; then
        log_warn "  No lib directory found in $dep_formula bottle"
        rm -rf "$temp_dir"
        return 0
    fi

    # Get list of dylibs to copy
    local libs_to_copy
    libs_to_copy=$(get_dependency_libs "$dep_formula")
    if [[ -z "$libs_to_copy" ]]; then
        # Copy all dylibs if we don't have a specific list
        libs_to_copy=$(ls "$dep_lib_dir"/*.dylib 2>/dev/null | xargs -I{} basename {} 2>/dev/null || echo "")
    fi

    # Copy dylibs
    for lib in $libs_to_copy; do
        local lib_path="$dep_lib_dir/$lib"
        local dest_path="$lib_dir/$lib"
        # Skip if already exists
        if [[ -f "$dest_path" ]]; then
            continue
        fi
        if [[ -f "$lib_path" ]]; then
            cp -a "$lib_path" "$lib_dir/"
            log_info "    Copied: $lib"
        else
            # Try to find it (might have version in name)
            local found_lib
            found_lib=$(find "$dep_lib_dir" -name "${lib%.*}*" -type f | head -1)
            if [[ -n "$found_lib" ]]; then
                local found_basename
                found_basename=$(basename "$found_lib")
                if [[ ! -f "$lib_dir/$found_basename" ]]; then
                    cp -a "$found_lib" "$lib_dir/"
                    log_info "    Copied: $found_basename"
                fi
            fi
        fi
    done

    # Clean up
    rm -rf "$temp_dir"

    # Recursively bundle transitive dependencies
    local transitive_deps
    transitive_deps=$(get_dependencies "$dep_formula")
    for trans_dep in $transitive_deps; do
        # Avoid infinite loops - don't re-process already bundled deps
        if [[ ! -f "$lib_dir/.bundled_$trans_dep" ]]; then
            touch "$lib_dir/.bundled_$trans_dep"
            bundle_single_dependency "$trans_dep" "$lib_dir" "$arch"
        fi
    done
}

# Find all dylibs needed by binaries that aren't already bundled
# Usage: find_missing_dylibs <output_dir>
find_missing_dylibs() {
    local output_dir="$1"
    local bin_dir="$output_dir/bin"
    local lib_dir="$output_dir/lib"

    local missing=""

    for binary in "$bin_dir"/*; do
        if [[ -f "$binary" ]] && file "$binary" | grep -q "Mach-O"; then
            local deps
            deps=$(otool -L "$binary" | tail -n +2 | awk '{print $1}')

            for dep in $deps; do
                if [[ "$dep" == *"@@HOMEBREW"* ]] || \
                   [[ "$dep" == /opt/homebrew/* ]] || \
                   [[ "$dep" == /usr/local/* ]]; then
                    local dylib_name
                    dylib_name=$(basename "$dep")
                    if [[ ! -f "$lib_dir/$dylib_name" ]]; then
                        missing="$missing $dylib_name"
                    fi
                fi
            done
        fi
    done

    echo "$missing" | tr ' ' '\n' | sort -u | tr '\n' ' '
}
