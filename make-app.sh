#!/bin/bash
# 将 SPM 编译产物打包成 .app bundle 并签名
# 使用方法：./make-app.sh [release|debug]

set -e

CONFIG="${1:-debug}"
BINARY_PATH=".build/arm64-apple-macosx/${CONFIG}/CreatorRecorder"
APP_DIR="CreatorRecorder.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ICON_SOURCE="Sources/CreatorRecorder/Resources/AppIcon.svg"
ICON_OUTPUT="Sources/CreatorRecorder/Resources/CreatorRecorder.icns"

generate_app_icon() {
    if [ ! -f "${ICON_SOURCE}" ]; then
        echo "⚠️  App icon source not found, skipping icon generation."
        return
    fi

    echo "🎨 Generating app icon..."
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/creatorrecorder-icon.XXXXXX)"
    local rendered_png="${tmp_dir}/AppIcon.svg.png"
    local base_png="${tmp_dir}/AppIcon-1024.png"
    local iconset="${tmp_dir}/AppIcon.iconset"

    qlmanage -t -s 1024 -o "${tmp_dir}" "${ICON_SOURCE}" >/dev/null 2>&1
    if [ -f "${rendered_png}" ]; then
        mv "${rendered_png}" "${base_png}"
    else
        sips -s format png "${ICON_SOURCE}" --out "${base_png}" >/dev/null
    fi

    mkdir -p "${iconset}"
    for size in 16 32 128 256 512; do
        sips -z "${size}" "${size}" "${base_png}" --out "${iconset}/icon_${size}x${size}.png" >/dev/null
        local scale_size=$((size * 2))
        sips -z "${scale_size}" "${scale_size}" "${base_png}" --out "${iconset}/icon_${size}x${size}@2x.png" >/dev/null
    done

    iconutil -c icns "${iconset}" -o "${ICON_OUTPUT}"
    rm -rf "${tmp_dir}"
}

echo "📦 Building ${CONFIG}..."
swift build -c "${CONFIG}"
generate_app_icon

echo "🗂  Creating .app bundle structure..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

echo "📋 Copying binary..."
cp "${BINARY_PATH}" "${MACOS}/CreatorRecorder"

if [ -f "${ICON_OUTPUT}" ]; then
    echo "🖼  Copying app icon..."
    cp "${ICON_OUTPUT}" "${RESOURCES}/CreatorRecorder.icns"
fi

echo "📝 Writing Info.plist..."
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CreatorRecorder</string>
    <key>CFBundleIdentifier</key>
    <string>com.creatorrecorder.app</string>
    <key>CFBundleName</key>
    <string>CreatorRecorder</string>
    <key>CFBundleIconFile</key>
    <string>CreatorRecorder</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSCameraUsageDescription</key>
    <string>CreatorRecorder 需要访问摄像头，以便在录制时显示画中画（PiP）预览。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>CreatorRecorder 需要访问麦克风，以便在录制时同步录制您的声音。</string>
    <key>NSScreenCaptureDescription</key>
    <string>CreatorRecorder 需要屏幕录制权限，以便捕获屏幕内容。</string>
    <key>NSSystemAudioDescription</key>
    <string>CreatorRecorder 需要录制系统声音，以便在录制视频时同步录制电脑播放的音频。</string>
</dict>
</plist>
PLIST

echo "🔑 Writing entitlements..."
cat > /tmp/CreatorRecorder.entitlements << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <!-- 屏幕录制权限（SCShareableContent / ScreenCaptureKit 访问屏幕内容） -->
    <key>com.apple.security.screen-recording</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# 注意：ad-hoc 签名不加 --options runtime（Hardened Runtime 会让 TCC 行为更严格，
# 对于未经公证的开发版 App 反而会导致 ScreenCaptureKit 权限弹窗无法触发）
echo "✍️  Signing .app bundle (ad-hoc, without Hardened Runtime)..."
codesign --force --deep --sign - \
    --entitlements /tmp/CreatorRecorder.entitlements \
    "${APP_DIR}"

echo "🔓 Removing Gatekeeper quarantine flag..."
xattr -dr com.apple.quarantine "${APP_DIR}" 2>/dev/null || true

echo ""
echo "✅ Done! App bundle: ${APP_DIR}"
echo ""
echo "🚀 To launch: open ${APP_DIR}"
echo "   Or:         ${MACOS}/CreatorRecorder"
