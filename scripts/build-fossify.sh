#!/bin/bash
set -e

# Build Fossify Messages with API Server Integration
# This script clones Fossify Messages, applies our API patches, and builds the APK

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOSSIFY_DIR="${PROJECT_DIR}/../fossify-messages"
FOSSIFY_API_DIR="${PROJECT_DIR}/fossify-api"
BUILD_DIR="${PROJECT_DIR}/build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "====================================="
echo "Fossify Messages + API Builder"
echo "====================================="
echo

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    # Check Java
    if ! command -v java &> /dev/null; then
        echo -e "${RED}✗ Java not found${NC}"
        echo "Install Java: sudo apt-get install openjdk-17-jdk"
        exit 1
    fi
    echo -e "${GREEN}✓ Java $(java -version 2>&1 | head -1)${NC}"
    
    # Check Gradle
    if ! command -v gradle &> /dev/null; then
        echo -e "${YELLOW}⚠ Gradle not in PATH${NC}"
        echo "Will use gradle wrapper from cloned repo"
    else
        echo -e "${GREEN}✓ Gradle$(gradle -v 2>&1 | head -1)${NC}"
    fi
    
    # Check git
    if ! command -v git &> /dev/null; then
        echo -e "${RED}✗ Git not found${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Git available${NC}"
    
    echo
}

# Clone Fossify Messages repo
clone_fossify() {
    echo "Step 1: Cloning Fossify Messages..."
    
    if [ -d "$FOSSIFY_DIR" ]; then
        echo -e "${YELLOW}⚠ Fossify directory already exists, skipping clone${NC}"
        return
    fi
    
    cd "${PROJECT_DIR}/.."
    git clone https://github.com/FossifyOrg/Messages.git fossify-messages
    cd fossify-messages
    echo -e "${GREEN}✓ Cloned Fossify Messages${NC}"
    echo
}

# Create API directory structure
create_api_dirs() {
    echo "Step 2: Creating API directory structure..."
    
    mkdir -p "${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api"
    echo -e "${GREEN}✓ Created directories${NC}"
    echo
}

# Copy API implementation files
copy_api_files() {
    echo "Step 3: Copying API implementation files..."
    
    cp "${FOSSIFY_API_DIR}/ApiServer.kt" \
        "${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api/ApiServer.kt"
    
    cp "${FOSSIFY_API_DIR}/ApiService.kt" \
        "${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api/ApiService.kt"
    
    echo -e "${GREEN}✓ Copied API files${NC}"
    echo
}

# Update build.gradle.kts
update_gradle() {
    echo "Step 4: Updating build.gradle.kts..."
    
    GRADLE_FILE="${FOSSIFY_DIR}/app/build.gradle.kts"
    
    # Check if dependencies already added
    if grep -q "nanohttpd" "${GRADLE_FILE}"; then
        echo -e "${YELLOW}⚠ Dependencies already present, skipping${NC}"
    else
        # Find the dependencies block and add our dependencies
        # This is a simplified approach - may need manual adjustment
        cat >> "${GRADLE_FILE}" << 'EOF'

// API Server dependencies
dependencies {
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    implementation("com.google.code.gson:gson:2.10.1")
}
EOF
        echo -e "${YELLOW}⚠ Added dependency placeholders - review build.gradle.kts manually${NC}"
    fi
    echo
}

# Build debug APK
build_debug_apk() {
    echo "Step 5: Building debug APK..."
    
    cd "${FOSSIFY_DIR}"
    
    if [ -f "gradlew" ]; then
        ./gradlew assembleDebug
    else
        gradle assembleDebug
    fi
    
    APK_PATH=$(find . -name "*.apk" -type f 2>/dev/null | head -1)
    if [ -n "$APK_PATH" ]; then
        echo -e "${GREEN}✓ Built APK: $APK_PATH${NC}"
        
        # Copy to build directory
        mkdir -p "${BUILD_DIR}"
        cp "${APK_PATH}" "${BUILD_DIR}/fossify-messages-api-debug.apk"
        echo -e "${GREEN}✓ Copied to ${BUILD_DIR}/fossify-messages-api-debug.apk${NC}"
    else
        echo -e "${RED}✗ No APK found after build${NC}"
        exit 1
    fi
    echo
}

# Build release APK
build_release_apk() {
    echo "Step 6: Building release APK (requires signing key)..."
    
    cd "${FOSSIFY_DIR}"
    
    if [ -f "gradlew" ]; then
        ./gradlew assembleRelease
    else
        gradle assembleRelease
    fi
    
    APK_PATH=$(find . -name "*release*.apk" -type f 2>/dev/null | head -1)
    if [ -n "$APK_PATH" ]; then
        echo -e "${GREEN}✓ Built release APK: $APK_PATH${NC}"
        
        # Copy to build directory
        mkdir -p "${BUILD_DIR}"
        cp "${APK_PATH}" "${BUILD_DIR}/fossify-messages-api-release.apk"
        echo -e "${GREEN}✓ Copied to ${BUILD_DIR}/fossify-messages-api-release.apk${NC}"
    else
        echo -e "${YELLOW}⚠ No release APK found (might need signing key)${NC}"
    fi
    echo
}

# Display next steps
show_next_steps() {
    echo "====================================="
    echo "Build Complete!"
    echo "====================================="
    echo
    echo "Next steps:"
    echo "1. Review API integration in:"
    echo "   - ${FOSSIFY_DIR}/app/build.gradle.kts"
    echo "   - ${FOSSIFY_DIR}/app/src/main/java/org/fossify/messages/api/"
    echo
    echo "2. Manually add to AndroidManifest.xml:"
    echo "   <service android:name=\".api.ApiService\" android:enabled=\"true\" />"
    echo
    echo "3. Manual SmsReceiver.kt integration:"
    echo "   Add webhook notification code from ${FOSSIFY_API_DIR}/SmsReceiver.kt"
    echo
    echo "4. Install debug APK on Android:"
    echo "   adb install ${BUILD_DIR}/fossify-messages-api-debug.apk"
    echo
    echo "5. Enable API in Fossify settings:"
    echo "   - Settings → API Server → Enable"
    echo "   - Set Port: 8080"
    echo "   - Set Auth Token (generate random)"
    echo "   - Set Webhook URL: http://bridge-server:5000/webhook/fossify"
    echo
}

# Main execution
main() {
    check_prerequisites
    clone_fossify
    create_api_dirs
    copy_api_files
    update_gradle
    
    # Build debug APK (required)
    read -p "Build debug APK? (y/n, default: y) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]?$ ]]; then
        build_debug_apk
    fi
    
    # Build release APK (optional)
    read -p "Build release APK? (y/n, default: n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        build_release_apk
    fi
    
    show_next_steps
}

main
