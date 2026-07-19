#!/usr/bin/env bash
#
# Merge companion Homebrew extensions (e.g. pgvector, pg_partman) into an
# already-extracted service package, so the binary ships with them available.
#
# Reads `companion_extensions` from formulas/<formula>.json, fetches each
# companion's bottle, and copies its extension library + control/SQL files into
# the package's lib/ and share/extension/ dirs. The companion bottles are built
# against the same Homebrew PostgreSQL major, so they are ABI-compatible, and
# PostgreSQL extension libs resolve server symbols at load time (no relinking).
#
# Usage: ./merge-companions.sh <formula> <arch> <package-dir>
#   arch: arm64 | x86_64  (bottle codename is auto-detected from the host)
#   e.g. ./merge-companions.sh postgresql arm64 output/postgresql/17.10-arm64
set -euo pipefail

FORMULA="${1:?usage: merge-companions.sh <formula> <arch> <package-dir>}"
ARCH="${2:?arch required (arm64|x86_64)}"
PKG_DIR="${3:?package-dir required}"

# Map host macOS to its Homebrew bottle codename (same logic as extract.sh).
detect_macos_codename() {
    case "$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)" in
        13) echo ventura ;; 14) echo sonoma ;; 15) echo sequoia ;;
        26) echo tahoe ;; *) echo sequoia ;;
    esac
}
OS="$(detect_macos_codename)"
if [ "$ARCH" = "arm64" ]; then BOTTLE_ARCH="arm64_${OS}"; else BOTTLE_ARCH="${OS}"; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/formulas/${FORMULA}.json"
[ -f "$CFG" ] || { echo "No formula config: $CFG" >&2; exit 1; }

companions=$(jq -r '.companion_extensions[]?' "$CFG" 2>/dev/null || true)
if [ -z "$companions" ]; then
  echo "No companion extensions for $FORMULA"
  exit 0
fi

# PostgreSQL major from the homebrew formula name (postgresql@17 -> 17), used to
# pick the matching per-version subdir inside companion bottles.
hb_formula=$(jq -r '.homebrew_formula' "$CFG")
pg_major="${hb_formula##*@}"
echo "Merging companions into $FORMULA (pg $pg_major, $BOTTLE_ARCH): $companions"

mkdir -p "$PKG_DIR/lib" "$PKG_DIR/share/extension"

for ext in $companions; do
  echo "  == $ext =="
  brew fetch --bottle-tag="$BOTTLE_ARCH" "$ext" >/dev/null 2>&1 || {
    echo "    failed to fetch $ext bottle" >&2; exit 1; }
  bottle=$(brew --cache --bottle-tag="$BOTTLE_ARCH" "$ext" 2>/dev/null)
  [ -f "$bottle" ] || { echo "    no cached bottle for $ext" >&2; exit 1; }

  tmp=$(mktemp -d)
  tar -xzf "$bottle" -C "$tmp"

  # Extension shared libs -> package lib/  (pg looks here as $libdir)
  libsrc=$(find "$tmp" -type d -path "*/lib/postgresql@${pg_major}" | head -1)
  if [ -n "$libsrc" ]; then
    find "$libsrc" -maxdepth 1 \( -name "*.dylib" -o -name "*.so" \) -exec cp -f {} "$PKG_DIR/lib/" \;
  fi

  # Extension control + SQL -> package share/extension/
  sharesrc=$(find "$tmp" -type d -path "*/share/postgresql@${pg_major}/extension" | head -1)
  if [ -n "$sharesrc" ]; then
    cp -f "$sharesrc/"* "$PKG_DIR/share/extension/" 2>/dev/null || true
  fi

  if [ -z "$libsrc" ] && [ -z "$sharesrc" ]; then
    echo "    warning: no pg${pg_major} files found in $ext bottle" >&2
  fi
  rm -rf "$tmp"
  echo "    merged"
done

echo "Companion merge complete."
