#!/bin/bash
# ==============================================================================
# Lumina iOS - Run Unit Tests on iOS Simulator
# ==============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

DEVICE_NAME="${1:-iPhone 15 Pro}"
SCHEME="Lumina"
PROJECT="Lumina.xcodeproj"

echo "=================================================="
echo "  🧪 Running XCTest Suite on iOS Simulator ($DEVICE_NAME)"
echo "=================================================="

xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
    CODE_SIGNING_ALLOWED=NO

echo "=================================================="
echo "  ✅ All XCTest Units PASSED successfully!"
echo "=================================================="
