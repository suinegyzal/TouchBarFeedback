#!/bin/zsh
# 빌드 후 ~/Applications/TouchBarFeedback.app 에 설치
set -e
cd "$(dirname "$0")"
APP=build/TouchBarFeedback.app
rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O -swift-version 5 main.swift -o $APP/Contents/MacOS/TouchBarFeedback
mkdir -p $APP/Contents/Resources && cp sounds/*.wav $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.touchbarfeedback</string>
  <key>CFBundleName</key><string>TouchBarFeedback</string>
  <key>CFBundleExecutable</key><string>TouchBarFeedback</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
# ad-hoc 서명: 다시 빌드하면 서명이 바뀌므로 손쉬운 사용 권한을 다시 허용해야 한다.
codesign --force --sign - $APP
mkdir -p ~/Applications
pkill -x TouchBarFeedback || true
rm -rf ~/Applications/TouchBarFeedback.app
cp -R $APP ~/Applications/
echo "설치 완료: ~/Applications/TouchBarFeedback.app"
