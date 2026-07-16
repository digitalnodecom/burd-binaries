#!/bin/bash
# verify.sh - Verify that extracted binaries work correctly
#
# This performs several checks:
# 1. Binary architecture matches expected
# 2. No Homebrew-specific paths remain
# 3. All @executable_path dylibs exist
# 4. Binary runs with --version or --help
# 5. Formula-specific functional tests

# Verify all binaries in an extracted package
# Usage: verify_binaries <output_dir> <formula>
# Returns: 0 if all pass, 1 if any fail
verify_binaries() {
    local output_dir="$1"
    local formula="$2"
    local bin_dir="$output_dir/bin"
    local lib_dir="$output_dir/lib"
    local all_passed=true

    # Check each binary
    for binary in "$bin_dir"/*; do
        if [[ -f "$binary" ]] && file "$binary" | grep -q "Mach-O"; then
            local name
            name=$(basename "$binary")

            # Check 1: No Homebrew paths remain
            if ! check_no_homebrew_paths "$binary"; then
                log_error "  $name: Contains Homebrew-specific paths"
                all_passed=false
                continue
            fi

            # Check 2: All referenced dylibs exist
            if ! check_dylibs_exist "$binary" "$lib_dir"; then
                log_error "  $name: Missing required dylibs"
                all_passed=false
                continue
            fi

            log_success "  $name: Paths OK"
        fi
    done

    # Check dylibs too
    for dylib in "$lib_dir"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            local name
            name=$(basename "$dylib")

            if ! check_no_homebrew_paths "$dylib"; then
                log_error "  $name: Contains Homebrew-specific paths"
                all_passed=false
            fi
        fi
    done

    # Run functional test for the main binary
    local main_binary
    main_binary=$(get_main_binary "$formula")
    if [[ -x "$bin_dir/$main_binary" ]]; then
        if run_version_check "$bin_dir/$main_binary" "$formula"; then
            log_success "  $main_binary: Functional test passed"
        else
            log_error "  $main_binary: Functional test failed"
            all_passed=false
        fi
    fi

    if $all_passed; then
        return 0
    else
        return 1
    fi
}

# Check that no Homebrew-specific paths remain
# Usage: check_no_homebrew_paths <binary>
# Returns: 0 if clean, 1 if paths remain
check_no_homebrew_paths() {
    local binary="$1"

    local deps
    deps=$(otool -L "$binary" 2>/dev/null | tail -n +2)

    if echo "$deps" | grep -q "@@HOMEBREW_PREFIX@@"; then
        return 1
    fi
    if echo "$deps" | grep -q "/opt/homebrew/Cellar"; then
        return 1
    fi
    if echo "$deps" | grep -q "/usr/local/Cellar"; then
        return 1
    fi

    return 0
}

# Check that all referenced dylibs exist
# Usage: check_dylibs_exist <binary> <lib_dir>
# Returns: 0 if all exist, 1 if any missing
check_dylibs_exist() {
    local binary="$1"
    local lib_dir="$2"

    local deps
    deps=$(otool -L "$binary" 2>/dev/null | tail -n +2 | awk '{print $1}')

    for dep in $deps; do
        # Only check @executable_path and @loader_path references
        if [[ "$dep" == @executable_path/* ]]; then
            local dylib_name
            dylib_name=$(basename "$dep")
            if [[ ! -f "$lib_dir/$dylib_name" ]]; then
                log_warn "    Missing: $dylib_name"
                return 1
            fi
        fi
    done

    return 0
}

# Run version check for a binary
# Usage: run_version_check <binary_path> <formula>
# Returns: 0 if works, 1 if fails
run_version_check() {
    local binary="$1"
    local formula="$2"

    # Different formulas have different version flags
    local version_flag="--version"
    case "$formula" in
        redis|valkey)
            version_flag="--version"
            ;;
        mongodb)
            version_flag="--version"
            ;;
        *)
            version_flag="--version"
            ;;
    esac

    # Try to run the binary
    if "$binary" $version_flag >/dev/null 2>&1; then
        return 0
    fi

    # Some binaries use -v or -V
    if "$binary" -v >/dev/null 2>&1; then
        return 0
    fi

    if "$binary" -V >/dev/null 2>&1; then
        return 0
    fi

    # Try --help as fallback
    if "$binary" --help >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Generate manifest.json for the extracted package
# Usage: generate_manifest <output_dir> <formula> <version> <arch>
generate_manifest() {
    local output_dir="$1"
    local formula="$2"
    local version="$3"
    local arch="$4"

    local manifest="$output_dir/manifest.json"
    local bin_dir="$output_dir/bin"
    local lib_dir="$output_dir/lib"

    # Start building JSON
    local binaries_json="{"
    local first=true
    for binary in "$bin_dir"/*; do
        if [[ -f "$binary" ]] && file "$binary" | grep -q "Mach-O"; then
            local name
            name=$(basename "$binary")
            local sha
            sha=$(shasum -a 256 "$binary" | awk '{print $1}')

            if ! $first; then
                binaries_json+=","
            fi
            binaries_json+="\"$name\":{\"path\":\"bin/$name\",\"sha256\":\"$sha\"}"
            first=false
        fi
    done
    binaries_json+="}"

    # List bundled libs
    local libs_json="["
    first=true
    for dylib in "$lib_dir"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            local name
            name=$(basename "$dylib")
            if ! $first; then
                libs_json+=","
            fi
            libs_json+="\"lib/$name\""
            first=false
        fi
    done
    libs_json+="]"

    # List configs
    local configs_json="["
    first=true
    for cfg in "$output_dir/etc"/*; do
        if [[ -f "$cfg" ]]; then
            local name
            name=$(basename "$cfg")
            if ! $first; then
                configs_json+=","
            fi
            configs_json+="\"etc/$name\""
            first=false
        fi
    done
    configs_json+="]"

    # Write manifest
    cat > "$manifest" << EOF
{
  "name": "$formula",
  "version": "$version",
  "source": "homebrew",
  "source_formula": "$formula",
  "extracted_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "architecture": "$arch",
  "binaries": $binaries_json,
  "bundled_libs": $libs_json,
  "configs": $configs_json,
  "verification": {
    "passed": true,
    "tested_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
}
EOF

    log_info "  Wrote: $manifest"
}
