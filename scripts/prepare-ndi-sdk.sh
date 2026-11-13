#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/ndi-sdk.zip" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="$1"

if [ ! -f "$ZIP_PATH" ]; then
    echo "NDI SDK zip not found: $ZIP_PATH" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

unzip -q "$ZIP_PATH" -d "$TMP_DIR"

HEADER_PATH="$(find "$TMP_DIR" -name 'Processing.NDI.Lib.h' -print -quit)"
LIB_PATH="$(find "$TMP_DIR" -name 'libndi_ios.a' -print -quit)"

if [ -z "$HEADER_PATH" ]; then
    echo "Processing.NDI.Lib.h was not found in the SDK zip." >&2
    exit 1
fi

if [ -z "$LIB_PATH" ]; then
    echo "libndi_ios.a was not found in the SDK zip." >&2
    exit 1
fi

HEADER_DIR="$(dirname "$HEADER_PATH")"

mkdir -p "$ROOT/Vendor/NDI/include" "$ROOT/Vendor/NDI/lib/iOS"
cp "$HEADER_DIR"/*.h "$ROOT/Vendor/NDI/include/"
cp "$LIB_PATH" "$ROOT/Vendor/NDI/lib/iOS/libndi_ios.a"

echo "NDI headers: $(find "$ROOT/Vendor/NDI/include" -name '*.h' | wc -l | tr -d ' ')"
echo "NDI library: $ROOT/Vendor/NDI/lib/iOS/libndi_ios.a"

