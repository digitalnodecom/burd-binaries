#!/bin/bash
# relink.sh - Fix dynamic library paths to make binaries portable
#
# Homebrew bottles contain placeholders like:
#   @@HOMEBREW_PREFIX@@/opt/openssl@3/lib/libssl.3.dylib
#
# We convert these to relative paths:
#   @executable_path/../lib/libssl.3.dylib
#
# This makes the binary portable and self-contained.

# Fix __LINKEDIT segment by truncating extra bytes at end of file
# This is needed after removing code signatures which can leave padding bytes
# Usage: fix_linkedit_segment <binary>
fix_linkedit_segment() {
    local binary="$1"

    # Get file size and __LINKEDIT segment info
    local file_size
    file_size=$(stat -f%z "$binary" 2>/dev/null || stat -c%s "$binary" 2>/dev/null)

    # Parse __LINKEDIT segment end from otool output
    local linkedit_end
    linkedit_end=$(otool -l "$binary" 2>/dev/null | awk '
        /__LINKEDIT/,/filesize/ {
            if (/fileoff/) fileoff=$2
            if (/filesize/) { print fileoff + $2; exit }
        }
    ')

    if [[ -n "$linkedit_end" ]] && [[ "$file_size" -gt "$linkedit_end" ]]; then
        # Truncate extra bytes using head for accuracy
        local temp_file
        temp_file=$(mktemp)
        head -c "$linkedit_end" "$binary" > "$temp_file"
        mv "$temp_file" "$binary"
        chmod +x "$binary"
    fi
}

# Patch hardcoded Homebrew paths in a binary (PostgreSQL specific)
# This replaces paths like /opt/homebrew/share/postgresql@17 with relative paths
# Usage: patch_postgresql_paths <binary>
patch_share_paths() {
    local binary="$1"
    local needs_patch=false

    # Check if binary contains any paths we need to patch
    if grep -q '/opt/homebrew/share/postgresql@17' "$binary" 2>/dev/null; then
        needs_patch=true
    fi
    if grep -q '/opt/homebrew/lib/postgresql@17' "$binary" 2>/dev/null; then
        needs_patch=true
    fi

    if [[ "$needs_patch" != "true" ]]; then
        return 0
    fi

    log_info "    Patching PostgreSQL paths in $(basename "$binary")"

    # Use LC_ALL=C perl for true binary mode replacement
    # The -0777 slurps the whole file, avoiding line-based processing issues
    #
    # Patch 1: SHAREDIR
    # Original: /opt/homebrew/share/postgresql@17 (33 chars)
    # Replace:  ../share + 25 null bytes (33 - 8 = 25)
    #
    # Patch 2: PKGLIBDIR (for extensions like dict_snowball)
    # Original: /opt/homebrew/lib/postgresql@17 (31 chars)
    # Replace:  ../lib + 25 null bytes (31 - 6 = 25)
    LC_ALL=C perl -0777 -pe '
        s|/opt/homebrew/share/postgresql\@17|../share\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00|g;
        s|/opt/homebrew/lib/postgresql\@17|../lib\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00|g;
    ' "$binary" > "${binary}.patched" 2>/dev/null

    if [[ -f "${binary}.patched" ]]; then
        local old_size new_size
        old_size=$(stat -f%z "$binary" 2>/dev/null || stat -c%s "$binary" 2>/dev/null)
        new_size=$(stat -f%z "${binary}.patched" 2>/dev/null || stat -c%s "${binary}.patched" 2>/dev/null)

        if [[ "$old_size" == "$new_size" ]]; then
            mv "${binary}.patched" "$binary"
            chmod +x "$binary"
        else
            log_info "    WARNING: Size mismatch after patching $(basename "$binary") ($old_size -> $new_size), skipping"
            rm -f "${binary}.patched"
        fi
    fi
}

# Relink a single binary
# Usage: relink_single_binary <binary_path> <lib_dir>
relink_single_binary() {
    local binary="$1"
    local lib_dir="$2"

    # Get all dylib references
    local deps
    deps=$(otool -L "$binary" | tail -n +2 | awk '{print $1}')

    for dep in $deps; do
        # Skip system libraries
        if [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == /System/* ]]; then
            continue
        fi

        # Handle any @@HOMEBREW* placeholders (PREFIX, CELLAR, etc.)
        if [[ "$dep" == *"@@HOMEBREW"* ]]; then
            local dylib_name
            dylib_name=$(basename "$dep")
            local new_path="@executable_path/../lib/$dylib_name"

            install_name_tool -change "$dep" "$new_path" "$binary" 2>/dev/null || true
            continue
        fi

        # Handle absolute Homebrew paths (e.g., /opt/homebrew/opt/...)
        if [[ "$dep" == /opt/homebrew/* ]] || [[ "$dep" == /usr/local/* ]]; then
            local dylib_name
            dylib_name=$(basename "$dep")
            local new_path="@executable_path/../lib/$dylib_name"

            install_name_tool -change "$dep" "$new_path" "$binary" 2>/dev/null || true
            continue
        fi

        # Handle @rpath references
        if [[ "$dep" == @rpath/* ]]; then
            local dylib_name
            dylib_name=$(basename "$dep")
            local new_path="@executable_path/../lib/$dylib_name"

            install_name_tool -change "$dep" "$new_path" "$binary" 2>/dev/null || true
        fi
    done
}

# Relink a single dylib (update its install name and dependencies)
# Usage: relink_single_dylib <dylib_path> <lib_dir>
relink_single_dylib() {
    local dylib="$1"
    local lib_dir="$2"
    local dylib_name
    dylib_name=$(basename "$dylib")

    # Update the dylib's own install name (LC_ID_DYLIB)
    install_name_tool -id "@loader_path/$dylib_name" "$dylib" 2>/dev/null || true

    # Get all dylib references within this dylib
    local deps
    deps=$(otool -L "$dylib" | tail -n +2 | awk '{print $1}')

    for dep in $deps; do
        # Skip system libraries
        if [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == /System/* ]]; then
            continue
        fi

        # Skip self-references and already-fixed paths
        if [[ "$(basename "$dep")" == "$dylib_name" ]]; then
            continue
        fi
        if [[ "$dep" == @loader_path/* ]]; then
            continue
        fi

        # Handle any Homebrew placeholder (@@HOMEBREW_PREFIX@@, @@HOMEBREW_CELLAR@@, etc.)
        if [[ "$dep" == *"@@HOMEBREW"* ]]; then
            local ref_name
            ref_name=$(basename "$dep")
            local new_path="@loader_path/$ref_name"

            install_name_tool -change "$dep" "$new_path" "$dylib" 2>/dev/null || true
            continue
        fi

        # Handle absolute Homebrew paths
        if [[ "$dep" == /opt/homebrew/* ]] || [[ "$dep" == /usr/local/* ]]; then
            local ref_name
            ref_name=$(basename "$dep")
            local new_path="@loader_path/$ref_name"

            install_name_tool -change "$dep" "$new_path" "$dylib" 2>/dev/null || true
            continue
        fi

        # Handle @rpath references
        if [[ "$dep" == @rpath/* ]]; then
            local ref_name
            ref_name=$(basename "$dep")
            local new_path="@loader_path/$ref_name"

            install_name_tool -change "$dep" "$new_path" "$dylib" 2>/dev/null || true
        fi
    done
}

# Relink all binaries in the output directory
# Usage: relink_binaries <output_dir>
relink_binaries() {
    local output_dir="$1"
    local bin_dir="$output_dir/bin"
    local lib_dir="$output_dir/lib"

    # Make all binaries and dylibs writable so we can modify them
    chmod -R u+w "$bin_dir" 2>/dev/null || true
    chmod -R u+w "$lib_dir" 2>/dev/null || true

    # Ad-hoc sign all binaries and dylibs first to normalize Mach-O structure
    # This fixes __LINKEDIT segment issues that prevent install_name_tool from working
    for binary in "$bin_dir"/*; do
        if [[ -f "$binary" ]] && file "$binary" | grep -q "Mach-O"; then
            codesign --force --sign - "$binary" 2>/dev/null || true
        fi
    done
    for dylib in "$lib_dir"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            codesign --force --sign - "$dylib" 2>/dev/null || true
        fi
    done

    # Process each binary
    for binary in "$bin_dir"/*; do
        if [[ -f "$binary" ]] && file "$binary" | grep -q "Mach-O"; then
            log_info "  Relinking: $(basename "$binary")"
            relink_single_binary "$binary" "$lib_dir"
            # Note: PostgreSQL path patching is done at installation time,
            # not during extraction, because absolute paths are needed.
        fi
    done

    # Process each dylib (they may reference each other)
    for dylib in "$lib_dir"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            log_info "  Relinking dylib: $(basename "$dylib")"
            relink_single_dylib "$dylib" "$lib_dir"
        fi
    done

    # Re-sign all binaries and dylibs (required after modification on Apple Silicon)
    log_info "  Re-signing binaries..."
    for binary in "$bin_dir"/*; do
        if [[ -f "$binary" ]] && file "$binary" | grep -q "Mach-O"; then
            codesign --force --sign - "$binary" 2>/dev/null || true
        fi
    done
    for dylib in "$lib_dir"/*.dylib; do
        if [[ -f "$dylib" ]]; then
            codesign --force --sign - "$dylib" 2>/dev/null || true
        fi
    done
}

# Check if a binary has any non-portable paths remaining
# Usage: check_portable <binary>
# Returns: 0 if portable, 1 if not
check_portable() {
    local binary="$1"

    local deps
    deps=$(otool -L "$binary" | tail -n +2 | awk '{print $1}')

    for dep in $deps; do
        # Check for remaining Homebrew placeholders
        if [[ "$dep" == *"@@HOMEBREW"* ]]; then
            return 1
        fi
        if [[ "$dep" == /opt/homebrew/* ]]; then
            return 1
        fi
        if [[ "$dep" == /usr/local/Cellar/* ]]; then
            return 1
        fi
    done

    return 0
}

# Print dependency info for debugging
# Usage: print_deps <binary>
print_deps() {
    local binary="$1"
    echo "Dependencies for $(basename "$binary"):"
    otool -L "$binary" | tail -n +2
}
