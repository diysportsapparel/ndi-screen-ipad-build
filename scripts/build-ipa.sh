#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

if [ ! -f "$ROOT/Vendor/NDI/lib/iOS/libndi_ios.a" ]; then
    echo "NDI iOS static library not found:" >&2
    echo "  $ROOT/Vendor/NDI/lib/iOS/libndi_ios.a" >&2
    exit 1
fi

if [ ! -f "$ROOT/Vendor/NDI/include/Processing.NDI.Lib.h" ]; then
    echo "NDI headers not found:" >&2
    echo "  $ROOT/Vendor/NDI/include/Processing.NDI.Lib.h" >&2
    exit 1
fi

if [ ! -f "$ROOT/ExportOptions.plist" ]; then
    echo "ExportOptions.plist is missing." >&2
    echo "Copy ExportOptions.example.plist to ExportOptions.plist and set your teamID." >&2
    exit 1
fi

xcodegen generate

rm -rf "$ROOT/build/NDIScreen.xcarchive" "$ROOT/build/ipa"
mkdir -p "$ROOT/build"

xcodebuild \
    -project "$ROOT/NDIScreenBroadcast.xcodeproj" \
    -scheme NDIScreen \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ROOT/build/NDIScreen.xcarchive" \
    archive \
    -allowProvisioningUpdates

xcodebuild \
    -exportArchive \
    -archivePath "$ROOT/build/NDIScreen.xcarchive" \
    -exportOptionsPlist "$ROOT/ExportOptions.plist" \
    -exportPath "$ROOT/build/ipa" \
    -allowProvisioningUpdates

echo
echo "IPA output:"
find "$ROOT/build/ipa" -maxdepth 1 -name '*.ipa' -print

