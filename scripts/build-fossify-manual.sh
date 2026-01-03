#!/bin/bash
set -e

# Simpler Fossify Build - Uses GitHub Actions or Pre-built APK
# Since local build environment has dependency issues, we offer alternatives

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOSSIFY_DIR="${PROJECT_DIR}/../fossify-messages"

echo "=========================================="
echo "Fossify Messaging with API Integration"
echo "=========================================="
echo

# Option 1: Manual fork and build
echo "OPTION 1: Manual Fork & Build (Recommended)"
echo "==========================================="
echo
echo "Steps:"
echo "1. Fork Fossify Messages: https://github.com/FossifyOrg/Messages"
echo "2. Follow integration steps in: fossify-api/README.md"
echo "3. Build using Android Studio or:"
echo "   ./gradlew assembleDebug"
echo
echo "Files to integrate:"
echo "  • fossify-api/ApiServer.kt"
echo "  • fossify-api/ApiService.kt"
echo "  • fossify-api/SmsReceiver.kt (patch)"
echo

# Option 2: Use GitHub Actions
echo "OPTION 2: GitHub Actions (Fastest)"
echo "==================================="
echo
echo "Steps:"
echo "1. Push your fork to GitHub"
echo "2. Add GitHub Actions workflow to .github/workflows/build.yml"
echo "3. Actions will build APK automatically"
echo "4. Download APK from Releases"
echo
cat << 'EOF'
Workflow template:
```yaml
name: Build APK
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: android-actions/setup-android@v2
      - run: ./gradlew assembleDebug
      - uses: softprops/action-gh-release@v1
        with:
          files: app/build/outputs/apk/debug/*.apk
```
EOF
echo

# Option 3: Cloud build services
echo "OPTION 3: Cloud Build Services"
echo "==============================="
echo
echo "Free alternatives:"
echo "  • Codemagic: https://codemagic.io/"
echo "  • App Center: https://appcenter.ms/"
echo "  • Travis CI: https://travis-ci.org/"
echo
echo "All support building Android APKs from GitHub repos"
echo

# Show current integration status
echo "=========================================="
echo "Current Integration Status"
echo "=========================================="
echo
if [ -d "$FOSSIFY_DIR" ]; then
    echo "✓ Fossify Messages cloned at: $FOSSIFY_DIR"
    echo
    echo "API files ready to integrate:"
    ls -lh "${PROJECT_DIR}/fossify-api"/*.kt
else
    echo "⚠ Fossify not yet cloned"
    echo "Run: git clone https://github.com/FossifyOrg/Messages.git ../fossify-messages"
fi
echo

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo "1. Choose your build method (Options 1-3)"
echo "2. Follow integration steps in fossify-api/README.md"
echo "3. Configure Fossify app settings:"
echo "   • Enable API Server"
echo "   • Set Port: 8080"
echo "   • Set Auth Token"
echo "   • Set Webhook URL"
echo "4. Test with bridge"
echo
