#!/bin/bash
set -e

# Configuration
PHP_VERSION=${1:-8.4}
ARCH=${2:-$(uname -m)}
OS=${3:-$(uname -s | tr '[:upper:]' '[:lower:]')}

echo "======================================"
echo "Building FrankenPHP"
echo "======================================"
echo "PHP Version: ${PHP_VERSION}"
echo "Architecture: ${ARCH}"
echo "OS: ${OS}"
echo "======================================"
echo

# Determine project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Load configuration
CONFIG_FILE="configs/build-${PHP_VERSION}.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

echo "Loading config: $CONFIG_FILE"
source "$CONFIG_FILE"
echo

# Clone FrankenPHP at the pinned version (falls back to default branch if the
# ref isn't a tag/branch, e.g. FRANKENPHP_VERSION=main).
if [ ! -d "frankenphp" ]; then
    echo "Cloning FrankenPHP ${FRANKENPHP_VERSION}..."
    if ! git clone --depth 1 --branch "${FRANKENPHP_VERSION}" \
        https://github.com/dunglas/frankenphp.git 2>/dev/null; then
        echo "Ref ${FRANKENPHP_VERSION} not found as tag/branch; cloning default branch"
        git clone --depth 1 https://github.com/dunglas/frankenphp.git
    fi
    echo
fi

cd frankenphp

# Build
echo "Building FrankenPHP with PHP ${PHP_VERSION}..."
echo "This may take 40-60 minutes..."
echo

if [ "$OS" = "darwin" ]; then
    # macOS build. FrankenPHP's build-static.sh names the macOS output
    # "frankenphp-mac-<arch>" (not "-darwin-"), so match that.
    ./build-static.sh
    BINARY_PATH="./dist/frankenphp-mac-${ARCH}"
    if [ ! -f "$BINARY_PATH" ]; then
        # Fall back to whatever single frankenphp-* the build produced.
        BINARY_PATH="$(ls dist/frankenphp-*-${ARCH} 2>/dev/null | head -1)"
    fi
else
    # Linux build (Docker)
    echo "Using Docker for Linux build..."
    docker buildx bake --load static-builder-musl
    docker cp $(docker create --name static-builder-tmp dunglas/frankenphp:static-builder-musl):/go/src/app/dist/frankenphp-linux-${ARCH} ./frankenphp-linux-${ARCH}
    docker rm static-builder-tmp
    BINARY_PATH="./frankenphp-${OS}-${ARCH}"
fi

# Test binary
echo
echo "Testing binary..."
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
fi

$BINARY_PATH version
echo
$BINARY_PATH php-cli -v
echo
$BINARY_PATH php-cli -m | head -20
echo

# Copy and rename output
OUTPUT_NAME="php-web-${PHP_VERSION}-${OS}-${ARCH}"
echo "Copying binary to: ${OUTPUT_NAME}"
cp "$BINARY_PATH" "../${OUTPUT_NAME}"

cd ..

# Make executable
chmod +x "${OUTPUT_NAME}"

# Get size
SIZE=$(du -h "${OUTPUT_NAME}" | cut -f1)

echo
echo "======================================"
echo "Build complete!"
echo "======================================"
echo "Binary: ${OUTPUT_NAME}"
echo "Size: ${SIZE}"
echo "======================================"
echo
echo "Test with:"
echo "  ./${OUTPUT_NAME} version"
echo "  ./${OUTPUT_NAME} php-cli -v"
echo "  ./${OUTPUT_NAME} php-server --listen :8080"
echo
