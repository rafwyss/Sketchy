#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SketchPad"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME (release)..."
cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"
BIN_PATH="$BUILD_DIR/$APP_NAME"
swiftc -O \
    -target x86_64-apple-macosx14.0 \
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
    -parse-as-library \
    Sources/SketchPad/Models/Stroke.swift \
    Sources/SketchPad/Services/CanvasGeometry.swift \
    Sources/SketchPad/Services/ImageCompositor.swift \
    Sources/SketchPad/ViewModels/SketchViewModel.swift \
    Sources/SketchPad/Views/EmptyDropZoneView.swift \
    Sources/SketchPad/Views/AnnotationToolbar.swift \
    Sources/SketchPad/Views/SketchCanvasView.swift \
    Sources/SketchPad/Views/ContentView.swift \
    Sources/SketchPad/SketchPadApp.swift \
    -o "$BIN_PATH"

echo "Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SketchPad</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.raffaelewyss.SketchPad</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SketchPad</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Image</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.image</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# Generate AppIcon.icns programmatically using Swift + iconutil
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT_EOF'
import AppKit
import Foundation

let outDir = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]

func renderIcon(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(pixelSize)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let inset = s * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: cardRect, xRadius: s * 0.22, yRadius: s * 0.22)

    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.16, green: 0.38, blue: 0.96, alpha: 1.0),
        ending: NSColor(srgbRed: 0.45, green: 0.22, blue: 0.88, alpha: 1.0)
    )
    gradient?.draw(in: path, angle: -45)

    // Draw a stylized brush stroke curve
    let strokePath = NSBezierPath()
    strokePath.move(to: NSPoint(x: s * 0.26, y: s * 0.34))
    strokePath.curve(
        to: NSPoint(x: s * 0.74, y: s * 0.66),
        controlPoint1: NSPoint(x: s * 0.42, y: s * 0.72),
        controlPoint2: NSPoint(x: s * 0.58, y: s * 0.28)
    )
    strokePath.lineWidth = max(2.0, s * 0.09)
    strokePath.lineCapStyle = .round
    NSColor.white.setStroke()
    strokePath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    if let data = renderIcon(pixelSize: size) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size).png"))
    }
    if let data2x = renderIcon(pixelSize: size * 2) {
        try? data2x.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size)@2x.png"))
    }
}
SWIFT_EOF

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "Signing $APP_BUNDLE..."
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Installing to /Applications/$APP_NAME.app..."
rm -rf "/Applications/$APP_NAME.app"
cp -XR "$APP_BUNDLE" "/Applications/$APP_NAME.app"
xattr -cr "/Applications/$APP_NAME.app"
codesign --force --deep --sign - "/Applications/$APP_NAME.app"

echo "Done! Installed at /Applications/$APP_NAME.app"
