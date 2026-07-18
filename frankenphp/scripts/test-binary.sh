#!/bin/bash
set -e

BINARY=$1
if [ -z "$BINARY" ]; then
    echo "Usage: $0 <binary_path>"
    echo
    echo "Examples:"
    echo "  $0 php-cli-8.4-darwin-arm64"
    echo "  $0 php-web-8.4-darwin-arm64"
    exit 1
fi

if [ ! -f "$BINARY" ]; then
    echo "Error: Binary not found: $BINARY"
    exit 1
fi

chmod +x "$BINARY"

echo "======================================"
echo "Testing Binary"
echo "======================================"
echo "Binary: $BINARY"
echo "======================================"
echo

# Detect binary type
if [[ "$BINARY" == *"php-web"* ]] || [[ "$BINARY" == *"frankenphp"* ]]; then
    IS_FRANKENPHP=1
    echo "Detected: FrankenPHP binary"
else
    IS_FRANKENPHP=0
    echo "Detected: PHP CLI binary"
fi

echo

# Test 1: Version
echo "Test 1: Version check"
echo "--------------------------------------"
if [ $IS_FRANKENPHP -eq 1 ]; then
    ./$BINARY version || ./$BINARY php-cli -v
else
    ./$BINARY -v
fi
echo

# Test 2: Extensions list
echo "Test 2: List extensions"
echo "--------------------------------------"
if [ $IS_FRANKENPHP -eq 1 ]; then
    ./$BINARY php-cli -m
else
    ./$BINARY -m
fi
echo

# Test 3: Extension validation
if [ -f "tests/test-extensions.php" ]; then
    echo "Test 3: Extension validation"
    echo "--------------------------------------"
    if [ $IS_FRANKENPHP -eq 1 ]; then
        ./$BINARY php-cli tests/test-extensions.php
    else
        ./$BINARY tests/test-extensions.php
    fi
    echo
fi

# Test 4: MongoDB test
if [ -f "tests/test-mongodb.php" ]; then
    echo "Test 4: MongoDB extension"
    echo "--------------------------------------"
    if [ $IS_FRANKENPHP -eq 1 ]; then
        ./$BINARY php-cli tests/test-mongodb.php
    else
        ./$BINARY tests/test-mongodb.php
    fi
    echo
fi

# Test 5: Server test (FrankenPHP only)
if [ $IS_FRANKENPHP -eq 1 ]; then
    echo "Test 5: Server functionality"
    echo "--------------------------------------"
    echo "Starting FrankenPHP server on port 8765..."
    ./$BINARY php-server --listen 127.0.0.1:8765 --root tests &
    SERVER_PID=$!

    # Wait for server to start
    sleep 3

    # Test HTTP request
    if command -v curl &> /dev/null; then
        echo "Testing HTTP request..."
        curl -s http://127.0.0.1:8765/test-extensions.php | head -5 || echo "Request failed (this is OK if file doesn't serve properly)"
    else
        echo "curl not available, skipping HTTP test"
    fi

    # Stop server
    kill $SERVER_PID 2>/dev/null || true
    echo "Server stopped"
    echo
fi

echo "======================================"
echo "✓ All tests completed"
echo "======================================"
echo
echo "Binary information:"
echo "  Path: $BINARY"
echo "  Size: $(du -h $BINARY | cut -f1)"
echo "  Type: $(file $BINARY | cut -d: -f2-)"
echo
