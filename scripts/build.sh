#!/bin/bash
# CuePrompt Release Build Script
# Adapted from VoiceFlow build system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

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

# Entitlements
cat > /tmp/CuePrompt.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
</dict>
</plist>
EOF

# Code sign
DETECTED_HASH=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
if [ -n "$DETECTED_HASH" ]; then
  echo "Signing with Developer ID..."
  codesign --force --deep --sign "$DETECTED_HASH" --options runtime --entitlements /tmp/CuePrompt.entitlements CuePrompt.app
  codesign --verify --verbose CuePrompt.app
else
  echo "No Developer ID found. App will be unsigned."
fi

rm -f /tmp/CuePrompt.entitlements

echo "Build complete!"
open -R CuePrompt.app
