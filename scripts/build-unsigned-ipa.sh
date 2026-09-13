#!/usr/bin/env bash
#
# build-unsigned-ipa.sh
#
# Archives flashcard-widget for a generic iOS device with code signing
# disabled, then repackages the resulting .app into a standard
# Payload/App.app IPA zip structure. The output is unsigned -- it won't
# install via the App Store, TestFlight, or a plain device install; it
# needs a resigning step (e.g. a provisioning profile, or a sideloading
# tool like AltStore/Sideloadly) before it can run on a real device.
#
# Usage:
#   scripts/build-unsigned-ipa.sh [output-directory]
#
# output-directory defaults to ./build at the repo root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_PATH="$REPO_ROOT/flashcard-widget.xcodeproj"
SCHEME="flashcard-widget"
APP_NAME="flashcard-widget"

OUTPUT_DIR="${1:-$REPO_ROOT/build}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE_PATH="$WORK_DIR/$APP_NAME.xcarchive"

echo "Archiving $SCHEME (unsigned, generic iOS device)..."
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: expected app bundle not found at $APP_PATH" >&2
  exit 1
fi

echo "Packaging IPA..."
PAYLOAD_DIR="$WORK_DIR/ipa/Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

mkdir -p "$OUTPUT_DIR"
IPA_PATH="$OUTPUT_DIR/$APP_NAME-unsigned.ipa"
rm -f "$IPA_PATH"

(cd "$WORK_DIR/ipa" && zip -rq "$IPA_PATH" Payload)

echo "Built unsigned IPA: $IPA_PATH"
