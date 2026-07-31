#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE="$ROOT/dist/Model Meter.app"
CONTENTS="$BUNDLE/Contents"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

cd "$ROOT"
SWIFT_BUILD_ARGUMENTS=(--configuration "$CONFIGURATION")
if [[ "${MODEL_METER_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    SWIFT_BUILD_ARGUMENTS+=(--disable-sandbox)
fi
if [[ -n "${MODEL_METER_ARCHS:-}" ]]; then
    read -r -a MODEL_METER_ARCH_LIST <<< "$MODEL_METER_ARCHS"
    for ARCH in "${MODEL_METER_ARCH_LIST[@]}"; do
        SWIFT_BUILD_ARGUMENTS+=(--arch "$ARCH")
    done
fi
swift build "${SWIFT_BUILD_ARGUMENTS[@]}"
BIN_PATH="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"

if [[ ! -d "$BIN_PATH/Sparkle.framework" ]]; then
    echo "Sparkle.framework was not produced at $BIN_PATH" >&2
    exit 1
fi
if [[ ! -f "$ROOT/.build/checkouts/Sparkle/LICENSE" ]]; then
    echo "Sparkle license was not found in the package checkout" >&2
    exit 1
fi

rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"
cp "$BIN_PATH/ModelMeter" "$CONTENTS/MacOS/ModelMeter"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp \
    "$ROOT/.build/checkouts/Sparkle/LICENSE" \
    "$CONTENTS/Resources/Sparkle-LICENSE.txt"
ditto \
    "$ROOT/Sources/ModelMeter/Resources/Brand" \
    "$CONTENTS/Resources/Brand"
ditto \
    "$BIN_PATH/Sparkle.framework" \
    "$CONTENTS/Frameworks/Sparkle.framework"

# UserNotifications only resolves named sounds from the app container or bundle.
# Copy macOS's installed alert sounds before signing so the picker and delivered
# notifications use the same native sound files.
for SOUND in /System/Library/Sounds/*.aiff; do
    if [[ -f "$SOUND" ]]; then
        cp "$SOUND" "$CONTENTS/Resources/"
    fi
done

plutil -lint "$CONTENTS/Info.plist" >/dev/null

SIGNING_ARGUMENTS=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
    SIGNING_ARGUMENTS+=(--options runtime --timestamp)
    if [[ -n "${CODE_SIGN_KEYCHAIN:-}" ]]; then
        SIGNING_ARGUMENTS+=(--keychain "$CODE_SIGN_KEYCHAIN")
    fi

    SPARKLE="$CONTENTS/Frameworks/Sparkle.framework"
    SPARKLE_VERSION="$SPARKLE/Versions/Current"
    codesign "${SIGNING_ARGUMENTS[@]}" \
        "$SPARKLE_VERSION/XPCServices/Installer.xpc"
    codesign "${SIGNING_ARGUMENTS[@]}" \
        --preserve-metadata=entitlements \
        "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
    codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE_VERSION/Autoupdate"
    codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE_VERSION/Updater.app"
    codesign "${SIGNING_ARGUMENTS[@]}" "$SPARKLE"
fi

codesign "${SIGNING_ARGUMENTS[@]}" "$BUNDLE"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

echo "$BUNDLE"
