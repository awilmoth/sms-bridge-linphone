#!/bin/bash
set -e

# Build Fossify Messages APK with Docker
# Uses Android SDK container to avoid local setup complexity

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOSSIFY_DIR="${PROJECT_DIR}/../fossify-messages"
BUILD_DIR="${PROJECT_DIR}/build"

mkdir -p "${BUILD_DIR}"

echo "====================================="
echo "Fossify Messages + API Builder"
echo "====================================="
echo
echo "Using Docker-based Android build"
echo

# Check if Fossify is already cloned
if [ ! -d "$FOSSIFY_DIR" ]; then
    echo "Cloning Fossify Messages..."
    cd "${PROJECT_DIR}/.."
    git clone https://github.com/FossifyOrg/Messages.git fossify-messages
    cd fossify-messages
    echo "✓ Cloned"
else
    echo "✓ Fossify Messages already cloned"
    cd "$FOSSIFY_DIR"
fi

echo
echo "Project structure:"
echo "  Source: $FOSSIFY_DIR"
echo "  Build output: $BUILD_DIR"
echo

# Create API directory if needed
echo "Setting up API integration..."
mkdir -p "${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api"
cp "${PROJECT_DIR}/fossify-api/ApiServer.kt" \
   "${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api/ApiServer.kt"
cp "${PROJECT_DIR}/fossify-api/ApiService.kt" \
   "${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api/ApiService.kt"
echo "✓ API files copied"
echo

# Build using Docker
echo "Building APK with Docker (android-sdk container)..."
echo "This will:"
echo "  1. Run Gradle in a container with Android SDK pre-installed"
echo "  2. Build debug APK (no signing needed)"
echo "  3. Copy APK to: $BUILD_DIR"
echo
echo "Build starting..."
echo

cd "$FOSSIFY_DIR"

docker run --rm \
  -v "$(pwd):/app" \
  -v "${BUILD_DIR}:/build" \
  -w /app \
  -e ANDROID_SDK_ROOT=/opt/android-sdk-linux \
  thyrlian/android-sdk:latest \
  bash -c '
    echo "Installing dependencies..."
    ./gradlew clean
    
    echo "Building debug APK..."
    ./gradlew assembleDebug
    
    echo "Copying APK..."
    find . -name "*.apk" -type f -exec cp {} /build/ \;
    ls -lh /build/*.apk || echo "No APK found"
  '

if [ -f "${BUILD_DIR}/app-debug.apk" ] || [ -f "${BUILD_DIR}"/app-*debug.apk ]; then
    echo
    echo "====================================="
    echo "✓ BUILD SUCCESSFUL!"
    echo "====================================="
    echo
    ls -lh "${BUILD_DIR}"/*.apk 2>/dev/null || echo "Build artifacts:"
    find "${BUILD_DIR}" -name "*.apk" -exec echo "  - {}" \;
    echo
    
    # Show installation instructions
    APK_FILE=$(find "${BUILD_DIR}" -name "*.apk" | head -1)
    echo "Next: Install on Android device"
    echo "  1. Connect Android phone via USB"
    echo "  2. Enable USB debugging"
    echo "  3. Run: adb install ${APK_FILE}"
    echo "  4. Or scan QR code (if available)"
else
    echo
    echo "====================================="
    echo "✗ BUILD FAILED - No APK generated"
    echo "====================================="
    echo "Common issues:"
    echo "  1. Docker not running"
    echo "  2. Not enough disk space"
    echo "  3. Network issues downloading dependencies"
    echo
    echo "Try:"
    echo "  docker run --rm -it registry.hub.docker.com/cirrusci/android-sdk:latest bash"
    exit 1
fi
