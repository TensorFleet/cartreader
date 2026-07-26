#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname "$SCRIPT_DIR")
APP_DIR="$PROJECT_DIR/dist/OSCR Companion.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$PROJECT_DIR"
swift build -c release --disable-sandbox
BIN_DIR=$(swift build -c release --disable-sandbox --show-bin-path)

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/OSCRCompanion" "$CONTENTS_DIR/MacOS/OSCRCompanion"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo "$APP_DIR"
