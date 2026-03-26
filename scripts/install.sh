#!/usr/bin/env bash
#
# install.sh — Build Local Whisper and install as a macOS .app bundle.
#
# Usage:
#   ./scripts/install.sh            # installs to /Applications/Local Whisper.app
#   ./scripts/install.sh ~/Desktop  # installs to ~/Desktop/Local Whisper.app
#
set -euo pipefail

APP_NAME="Local Whisper"
BUNDLE_ID="com.localwhisper.app"
EXECUTABLE_NAME="LocalWhisper"
MODEL_FILE="ggml-whisper-small-pl.bin"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${1:-/Applications}"

APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"

# ---------- Preflight checks ----------

if [ ! -f "$REPO_ROOT/Package.swift" ]; then
    echo "ERROR: Package.swift not found. Run this script from the repo root or scripts/ directory."
    exit 1
fi

MODEL_PATH="$REPO_ROOT/models/$MODEL_FILE"
if [ ! -f "$MODEL_PATH" ]; then
    echo "ERROR: Model not found at $MODEL_PATH"
    echo "Run ./scripts/convert_model.sh first."
    exit 1
fi

XCFRAMEWORK="$REPO_ROOT/LocalWhisper/Frameworks/whisper.xcframework"
if [ ! -d "$XCFRAMEWORK" ]; then
    echo "ERROR: whisper.xcframework not found at $XCFRAMEWORK"
    echo "See README.md for download instructions."
    exit 1
fi

# ---------- Build ----------

echo "==> Building $EXECUTABLE_NAME (release)..."
swift build -c release --package-path "$REPO_ROOT" 2>&1

BINARY="$(swift build -c release --package-path "$REPO_ROOT" --show-bin-path)/$EXECUTABLE_NAME"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found after build."
    exit 1
fi

# ---------- Assemble .app bundle ----------

echo "==> Assembling $APP_NAME.app..."

# Remove old bundle if it exists
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/models" "$FRAMEWORKS_DIR"

# Copy binary
cp "$BINARY" "$MACOS_DIR/$EXECUTABLE_NAME"

# Copy model
echo "==> Copying model ($MODEL_FILE)..."
cp "$MODEL_PATH" "$RESOURCES_DIR/models/$MODEL_FILE"

# Copy whisper.framework (preserve symlinks — dyld expects the full framework structure)
FRAMEWORK_SRC="$XCFRAMEWORK/macos-arm64_x86_64/whisper.framework"
if [ -d "$FRAMEWORK_SRC" ]; then
    cp -a "$FRAMEWORK_SRC" "$FRAMEWORKS_DIR/whisper.framework"
    # Ensure rpath points into the Frameworks directory
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$EXECUTABLE_NAME" 2>/dev/null || true
fi

# Copy entitlements (for reference, not strictly needed for non-sandboxed)
cp "$REPO_ROOT/LocalWhisper/Sources/App/LocalWhisper.entitlements" "$CONTENTS/LocalWhisper.entitlements"

# Generate Info.plist with LSEnvironment pointing model path into the bundle
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Local Whisper needs access to your microphone to transcribe speech to text.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign the bundle (required on macOS for microphone access)
echo "==> Signing..."
codesign --force --deep --sign - \
    --entitlements "$CONTENTS/LocalWhisper.entitlements" \
    "$APP_BUNDLE"

# ---------- Done ----------

echo ""
echo "==> Installed: $APP_BUNDLE"
echo ""
echo "    Model inside bundle: $RESOURCES_DIR/models/$MODEL_FILE"
echo "    Binary: $MACOS_DIR/$EXECUTABLE_NAME"
echo ""
echo "    Open with:  open \"$APP_BUNDLE\""
echo ""
