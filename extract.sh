#!/bin/bash
# Homebrew Bottle Extractor
# Extracts pre-compiled binaries from Homebrew bottles and relinks them to be self-contained
#
# Usage: ./extract.sh <formula> [version] [arch] [os]
# Example: ./extract.sh redis 8.4.0 arm64 sonoma

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
FORMULAS_DIR="$SCRIPT_DIR/formulas"
OUTPUT_DIR="$SCRIPT_DIR/output"
CACHE_DIR="$SCRIPT_DIR/cache"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
FORMULA="${1:?Usage: $0 <formula> [version] [arch] [os]}"
VERSION="${2:-latest}"
ARCH="${3:-arm64}"
OS="${4:-sonoma}"

# Validate architecture
if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    log_error "Invalid architecture: $ARCH (must be arm64 or x86_64)"
    exit 1
fi

# Construct bottle architecture string
if [[ "$ARCH" == "arm64" ]]; then
    BOTTLE_ARCH="arm64_${OS}"
else
    BOTTLE_ARCH="${OS}"
fi

log_info "Extracting $FORMULA (version: $VERSION, arch: $BOTTLE_ARCH)"

# Source library functions
source "$LIB_DIR/fetch.sh"
source "$LIB_DIR/extract_bottle.sh"
source "$LIB_DIR/relink.sh"
source "$LIB_DIR/bundle-deps.sh"
source "$LIB_DIR/verify.sh"

# Load formula config if exists
FORMULA_CONFIG="$FORMULAS_DIR/${FORMULA}.json"
HOMEBREW_FORMULA="$FORMULA"  # Default to same name
if [[ -f "$FORMULA_CONFIG" ]]; then
    log_info "Loading formula config: $FORMULA_CONFIG"
    # Check if there's a different homebrew formula name (e.g., postgresql vs postgresql@17)
    HB_FORMULA=$(jq -r '.homebrew_formula // empty' "$FORMULA_CONFIG" 2>/dev/null)
    if [[ -n "$HB_FORMULA" ]]; then
        HOMEBREW_FORMULA="$HB_FORMULA"
        log_info "Using Homebrew formula: $HOMEBREW_FORMULA"
    fi
fi

# Step 1: Fetch the bottle
log_info "Step 1/6: Fetching bottle..."
BOTTLE_PATH=$(fetch_bottle "$HOMEBREW_FORMULA" "$VERSION" "$BOTTLE_ARCH")
log_success "Bottle cached at: $BOTTLE_PATH"

# Step 2: Get version from bottle path if we used "latest"
if [[ "$VERSION" == "latest" ]]; then
    # Extract version from filename like: redis--8.4.0.arm64_sonoma.bottle.tar.gz
    # or postgresql@17--17.7_1.arm64_sonoma.bottle.tar.gz
    VERSION=$(basename "$BOTTLE_PATH" | sed -E 's/.*--([0-9]+\.[0-9]+(\.[0-9]+)?(_[0-9]+)?).*/\1/' | sed 's/_[0-9]*$//')
    log_info "Detected version: $VERSION"
fi

# Step 3: Extract bottle contents
EXTRACT_DIR="$OUTPUT_DIR/$FORMULA/$VERSION-$ARCH"
log_info "Step 2/6: Extracting bottle to $EXTRACT_DIR..."
extract_bottle "$BOTTLE_PATH" "$EXTRACT_DIR" "$HOMEBREW_FORMULA" "$VERSION"
log_success "Extracted to: $EXTRACT_DIR"

# Step 4: Fetch and bundle dependencies
log_info "Step 3/6: Bundling dependencies..."
bundle_dependencies "$HOMEBREW_FORMULA" "$EXTRACT_DIR" "$BOTTLE_ARCH"
log_success "Dependencies bundled"

# Step 5: Relink binaries to use bundled dylibs
log_info "Step 4/6: Relinking binaries..."
relink_binaries "$EXTRACT_DIR"
log_success "Binaries relinked"

# Step 6: Verify everything works
log_info "Step 5/6: Verifying binaries..."
if verify_binaries "$EXTRACT_DIR" "$FORMULA"; then
    log_success "Verification passed"
else
    log_error "Verification failed!"
    exit 1
fi

# Step 7: Generate manifest
log_info "Step 6/6: Generating manifest..."
generate_manifest "$EXTRACT_DIR" "$FORMULA" "$VERSION" "$ARCH"
log_success "Manifest generated"

echo ""
log_success "Extraction complete!"
echo ""
echo "Output directory: $EXTRACT_DIR"
echo ""
echo "Contents:"
ls -la "$EXTRACT_DIR"
echo ""
echo "To test: $EXTRACT_DIR/bin/${FORMULA}-server --version"
