#!/usr/bin/env bash
#
# Build a standalone static PHP CLI binary with Burd's full extension set,
# driven entirely by a craft.yml (php-version + extensions + libs).
#
# Usage: ./build-cli.sh <php-line> [arch] [os]
#   e.g. ./build-cli.sh 8.4
set -e

PHP_VERSION=${1:-8.4}
ARCH=${2:-$(uname -m)}
OS=${3:-$(uname -s | tr '[:upper:]' '[:lower:]')}

echo "======================================"
echo "Building PHP CLI  ${PHP_VERSION} (${ARCH}, ${OS})"
echo "======================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

CONFIG_FILE="configs/craft-${PHP_VERSION}.yml"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config not found: $CONFIG_FILE"
    exit 1
fi

# static-php-cli drives the whole build from craft.yml via `spc craft`.
if [ ! -d "static-php-cli" ]; then
    echo "Cloning static-php-cli..."
    git clone --depth 1 https://github.com/crazywhalecc/static-php-cli.git
fi
cd static-php-cli

if [ ! -d "vendor" ]; then
    echo "Installing composer dependencies..."
    composer install --no-dev --optimize-autoloader
fi

cp "../${CONFIG_FILE}" ./craft.yml

echo "Running doctor (auto-fix build env)..."
php bin/spc doctor --auto-fix || true

echo "Crafting PHP CLI (download + build, ~20-30 min)..."
# `craft` reads craft.yml end to end: fetch sources, build libs, build the
# static CLI binary with every configured extension.
php bin/spc craft

BINARY="./buildroot/bin/php"
if [ ! -f "$BINARY" ]; then
    echo "Error: CLI binary not found at $BINARY"
    exit 1
fi

echo
"$BINARY" -v
echo
"$BINARY" -m | head -30
echo

OUTPUT_NAME="php-cli-${PHP_VERSION}-${OS}-${ARCH}"
cp "$BINARY" "../${OUTPUT_NAME}"
cd ..
chmod +x "${OUTPUT_NAME}"

echo "Build complete: ${OUTPUT_NAME} ($(du -h "${OUTPUT_NAME}" | cut -f1))"
