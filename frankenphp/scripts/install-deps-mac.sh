#!/bin/bash
set -e

echo "Installing build dependencies for macOS..."
echo

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    export HOMEBREW_PREFIX=/opt/homebrew
    echo "Detected Apple Silicon (arm64)"
else
    export HOMEBREW_PREFIX=/usr/local
    echo "Detected Intel (x86_64)"
fi

echo "Homebrew prefix: $HOMEBREW_PREFIX"
echo

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew is not installed"
    echo "Install from: https://brew.sh"
    exit 1
fi

echo "Installing Homebrew packages..."
brew install \
    shivammathur/php/php@8.4-zts \
    go \
    brotli \
    libiconv \
    pkg-config \
    composer \
    || true

# Make sure PHP-ZTS is linked
brew link --overwrite --force shivammathur/php/php@8.4-zts || true

echo
echo "Dependencies installed successfully!"
echo
echo "Environment variables:"
echo "  HOMEBREW_PREFIX=$HOMEBREW_PREFIX"
echo "  PATH=$HOMEBREW_PREFIX/bin:\$PATH"
echo

# Check versions
echo "Checking installed versions..."
php --version 2>/dev/null || echo "  PHP: Not in PATH"
go version 2>/dev/null || echo "  Go: Not installed"
composer --version 2>/dev/null || echo "  Composer: Not installed"

echo
echo "Ready to build!"
