#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Build first
"$SCRIPT_DIR/build.sh" || exit 1

# Install
echo "Installing to /Applications..."
rm -rf /Applications/CuePrompt.app
cp -R CuePrompt.app /Applications/
echo "Installed to /Applications/CuePrompt.app"
