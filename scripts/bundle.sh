#!/bin/bash
# Builds build/shotX.app and signs it. Signing identity (SHA-1) comes from ./signing.local.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
BIN="$(swift build --show-bin-path)/shotX"
APP=build/shotX.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/shotX"
cp Support/Info.plist "$APP/Contents/Info.plist"
if [ -f Support/AppIcon.icns ]; then cp Support/AppIcon.icns "$APP/Contents/Resources/"; fi

if [ ! -s signing.local ]; then
    IDS="$(security find-identity -v -p codesigning | awk '/^ *[0-9]+\)/ {print $2}')"
    if [ "$(printf '%s' "$IDS" | grep -c .)" = 1 ]; then echo "$IDS" > signing.local; fi
fi
if [ -s signing.local ]; then
    ID="$(tr -d '[:space:]' < signing.local)"
else
    ID=-
    echo "WARNING: no signing identity (signing.local missing and no single valid identity found)." >&2
    echo "WARNING: signing AD-HOC. Screen Recording permission will RESET ON EVERY BUILD." >&2
fi

codesign --force --sign "$ID" --identifier local.shotx.app "$APP"
echo "built $APP (signed: $ID)"
