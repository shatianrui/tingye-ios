#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "需要 macOS 与完整 Xcode；请先选择 Xcode Developer 目录。" >&2
  exit 1
fi
# Always use a new staging directory; never reuse stale app bundles.
mkdir -p "$ROOT/build"
STAGE="$(mktemp -d "$ROOT/build/unsigned.XXXXXX")"
xcodebuild -project "$ROOT/Tingye.xcodeproj" -scheme Tingye \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -xcconfig "$ROOT/Configuration/Unsigned.xcconfig" \
  -derivedDataPath "$STAGE/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= build
APP="$STAGE/DerivedData/Build/Products/Release-iphoneos/Tingye.app"
test -d "$APP"
if codesign --display "$APP" >/dev/null 2>&1; then
  echo "构建产物意外包含签名，停止打包。" >&2
  exit 1
fi
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/Tingye.app"
python3 "$ROOT/scripts/verify-unsigned.py" "$STAGE/Payload/Tingye.app"
(cd "$STAGE" && /usr/bin/zip -qry Tingye-unsigned.ipa Payload)
cp "$STAGE/Tingye-unsigned.ipa" "$ROOT/build/Tingye-unsigned.ipa"
(cd "$ROOT/build" && shasum -a 256 Tingye-unsigned.ipa > Tingye-unsigned.ipa.sha256)
echo "已生成：$ROOT/build/Tingye-unsigned.ipa（安装前需自行签名）"
