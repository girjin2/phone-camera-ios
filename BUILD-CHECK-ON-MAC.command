#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
CI_BUNDLE_ID="${IOS_BUNDLE_ID:-com.churchstudio.phonecamera.localcheck}"
echo "[1/3] Xcode version"
xcodebuild -version
echo "[2/3] Xcode project list"
xcodebuild -project ChurchStudioPhoneCameraIOS.xcodeproj -list
echo "[3/3] Compile check (iOS Simulator, no signing)"
xcodebuild -project ChurchStudioPhoneCameraIOS.xcodeproj \
  -scheme ChurchStudioPhoneCameraIOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER="$CI_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION=1 \
  build
echo "PASS: source compiled for iOS Simulator. Real camera/USB still requires a physical iPhone."
