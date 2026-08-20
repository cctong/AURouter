#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
BUILD_ROOT="$PROJECT_ROOT/.build"
APP_PATH="$BUILD_ROOT/AURouter.app"

env \
  CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swiftpm-module-cache" \
  swift build \
    --configuration "$CONFIGURATION" \
    --cache-path "$BUILD_ROOT/cache" \
    --config-path "$BUILD_ROOT/config" \
    --security-path "$BUILD_ROOT/security"

BIN_PATH="$(env \
  CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swiftpm-module-cache" \
  swift build \
    --configuration "$CONFIGURATION" \
    --show-bin-path \
    --cache-path "$BUILD_ROOT/cache" \
    --config-path "$BUILD_ROOT/config" \
    --security-path "$BUILD_ROOT/security")"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$PROJECT_ROOT/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/Support/AURouter.icns" "$APP_PATH/Contents/Resources/AURouter.icns"
cp "$BIN_PATH/AURouter" "$APP_PATH/Contents/MacOS/AURouter"
chmod 755 "$APP_PATH/Contents/MacOS/AURouter"

codesign --force --sign - --timestamp=none "$APP_PATH"

echo "$APP_PATH"
