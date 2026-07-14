#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE="$ROOT/dist/Model Meter.app"
CONTENTS="$BUNDLE/Contents"

cd "$ROOT"
swift build --configuration "$CONFIGURATION"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/$CONFIGURATION/ModelMeter" "$CONTENTS/MacOS/ModelMeter"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# UserNotifications only resolves named sounds from the app container or bundle.
# Copy macOS's installed alert sounds before signing so the picker and delivered
# notifications use the same native sound files.
for SOUND in /System/Library/Sounds/*.aiff; do
    if [[ -f "$SOUND" ]]; then
        cp "$SOUND" "$CONTENTS/Resources/"
    fi
done

plutil -lint "$CONTENTS/Info.plist" >/dev/null
codesign --force --deep --sign - "$BUNDLE" >/dev/null

echo "$BUNDLE"
