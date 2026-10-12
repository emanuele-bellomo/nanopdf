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

echo "🎨 Processing App Icon..."
if [ -f "img/logo.png" ]; then
    if [ ! -f "AppIcon.icns" ] || [ "img/logo.png" -nt "AppIcon.icns" ]; then
        echo "   Generating AppIcon.icns from img/logo.png..."
        rm -rf AppIcon.iconset
        mkdir -p AppIcon.iconset
        sips -z 16 16     img/logo.png --out AppIcon.iconset/icon_16x16.png > /dev/null
        sips -z 32 32     img/logo.png --out AppIcon.iconset/icon_16x16@2x.png > /dev/null
        sips -z 32 32     img/logo.png --out AppIcon.iconset/icon_32x32.png > /dev/null
        sips -z 64 64     img/logo.png --out AppIcon.iconset/icon_32x32@2x.png > /dev/null
        sips -z 128 128   img/logo.png --out AppIcon.iconset/icon_128x128.png > /dev/null
        sips -z 256 256   img/logo.png --out AppIcon.iconset/icon_128x128@2x.png > /dev/null
        sips -z 256 256   img/logo.png --out AppIcon.iconset/icon_256x256.png > /dev/null
        sips -z 512 512   img/logo.png --out AppIcon.iconset/icon_256x256@2x.png > /dev/null
        sips -z 512 512   img/logo.png --out AppIcon.iconset/icon_512x512.png > /dev/null
        sips -z 1024 1024 img/logo.png --out AppIcon.iconset/icon_512x512@2x.png > /dev/null
        iconutil -c icns AppIcon.iconset -o AppIcon.icns
        rm -rf AppIcon.iconset
    fi
    cp AppIcon.icns "$RESOURCES_DIR/"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Refresh LaunchServices cache so macOS Finder and Dock display the new icon immediately
touch "$APP_DIR"
if [ -f "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" > /dev/null 2>&1 || true
fi

echo "✅ App bundle created successfully: $APP_DIR"
echo "You can now open it with: open $APP_DIR"

