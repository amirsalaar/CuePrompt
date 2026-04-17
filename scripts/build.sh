#!/bin/bash
# CuePrompt Release Build Script
# Adapted from VoiceFlow build system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
source "$SCRIPT_DIR/signing-common.sh"

NOTARIZE=false
while [[ $# -gt 0 ]]; do
  case $1 in
  --notarize) NOTARIZE=true; shift ;;
  *) echo "Usage: $0 [--notarize]"; exit 1 ;;
  esac
done

VERSION=$(cat VERSION | tr -d '[:space:]')
BUILD_NUMBER="${VERSION//./}"
GIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

echo "Building CuePrompt v$VERSION..."

# Clean
rm -rf .build/release
rm -rf CuePrompt.app

# Build universal binary
echo "Building for release..."
swift build -c release --arch arm64 --arch x86_64

if [ ! -f ".build/apple/Products/Release/CuePrompt" ]; then
  echo "Build failed - binary not found!"
  exit 1
fi

# Create app bundle
echo "Creating app bundle..."
mkdir -p CuePrompt.app/Contents/{MacOS,Resources}

cp .build/apple/Products/Release/CuePrompt CuePrompt.app/Contents/MacOS/
chmod +x CuePrompt.app/Contents/MacOS/CuePrompt

# Info.plist
cat > CuePrompt.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CuePrompt</string>
    <key>CFBundleIdentifier</key>
    <string>com.cueprompt.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CuePrompt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>CuePrompt uses your microphone to scroll your script as you speak. Audio is processed entirely on your device.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>CuePrompt uses speech recognition to match your spoken words to your script. All recognition happens on-device.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Code sign
ENTITLEMENTS="$SCRIPT_DIR/../Entitlements/CuePrompt.entitlements"
SIGNING_IDENTITY="$(cueprompt_detect_signing_identity || true)"
SIGNING_NAME="$(cueprompt_detect_signing_identity_name || true)"

if [ -n "$SIGNING_IDENTITY" ]; then
  if [ -n "$SIGNING_NAME" ]; then
    echo "🔍 Using signing identity: $SIGNING_NAME"
  fi

  echo "🔏 Code signing app with stable identity..."
  cueprompt_sign_app_bundle \
    "CuePrompt.app" \
    "$ENTITLEMENTS" \
    "$SIGNING_IDENTITY"
  codesign --verify --verbose CuePrompt.app
else
  echo "⚠️  No stable signing identity found. Falling back to ad-hoc signing."
  echo "⚠️  macOS may re-prompt for Microphone permissions after each rebuild."
  echo "💡 Run 'make setup-local-signing' once to create a persistent local signing identity for development."

  cueprompt_sign_app_bundle \
    "CuePrompt.app" \
    "$ENTITLEMENTS"
fi

echo "Build complete!"
open -R CuePrompt.app
