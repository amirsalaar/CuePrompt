#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
source "$SCRIPT_DIR/signing-common.sh"

# Build first
"$SCRIPT_DIR/build.sh" || exit 1

# Install
echo "Installing to /Applications..."
rm -rf /Applications/CuePrompt.app
cp -R CuePrompt.app /Applications/

SIGNATURE_KIND="$(cueprompt_signature_kind /Applications/CuePrompt.app)"

echo ""
echo "✅ CuePrompt successfully installed to /Applications/CuePrompt.app"
echo ""
if [ "$SIGNATURE_KIND" = "stable" ]; then
    echo "✅ Stable code signing detected. Existing Microphone permissions should persist across reinstalls."
else
    echo "⚠️  Installed app is not stably signed ($SIGNATURE_KIND). macOS privacy permissions can reset after each install."
    echo "⚠️  Re-grant these permissions if CuePrompt stops working after a rebuild:"
    echo "   1. System Settings → Privacy & Security → Microphone"
    echo ""
    echo "💡 To avoid this during development, run 'make setup-local-signing' once, then reinstall CuePrompt."
fi
