#!/bin/bash
set -e

APP_NAME="NanoPDF"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MUPDF_LIB="/opt/homebrew/opt/mupdf/lib/libmupdf.dylib"

echo "🔨 Building release executable..."
swift build -c release -Xcc -I/opt/homebrew/opt/mupdf/include

echo "📦 Creating .app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

echo "📋 Copying executable..."
cp .build/release/$APP_NAME "$MACOS_DIR/"

echo "📚 Bundling libmupdf.dylib..."
cp "$MUPDF_LIB" "$FRAMEWORKS_DIR/"

echo "🔗 Rewiring dynamic library links..."
# Find the exact path it currently links to (could have version numbers)
LINKED_DYLIB=$(otool -L "$MACOS_DIR/$APP_NAME" | grep libmupdf | awk '{print $1}')
install_name_tool -change "$LINKED_DYLIB" "@executable_path/../Frameworks/libmupdf.dylib" "$MACOS_DIR/$APP_NAME"

echo "📝 Generating Info.plist..."
cat << PLIST > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NanoPDF</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.NanoPDF</string>
    <key>CFBundleName</key>
    <string>NanoPDF</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✅ App bundle created successfully: $APP_DIR"
echo "You can now open it with: open $APP_DIR"
