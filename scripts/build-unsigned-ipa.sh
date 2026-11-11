#!/bin/bash
# Build an unsigned, slimmed Tingye IPA for sideloading.
#
# Usage:
#   scripts/build-unsigned-ipa.sh [--full-fonts] [--osize] [--keep-dsym] [--help]
#
# Defaults:
#   --slim-fonts   Remove the two optional LXGW reader fonts from the
#                  packaged .app (see docs/UNSIGNED-IPA.md). This is the
#                  default. Pass --full-fonts to keep all four fonts.
#   Release, arm64 only, dwarf (no .dSYM in the IPA), strip on.
#
# What this does NOT touch:
#   - Tingye.xcodeproj / ExportOptions.plist / Tingye.entitlements:
#     the signed App Store flow is unchanged. All unsigned overrides are
#     passed on the xcodebuild command line only.
#   - No version is hardcoded: MARKETING_VERSION / CURRENT_PROJECT_VERSION
#     are read from project.pbxproj. (Note: pbxproj currently says
#     1.24.0 (128) while README says 1.24.0 (123); the script trusts
#     pbxproj, which is what Xcode actually builds.)
#
# Requirements: macOS + Xcode (xcodebuild, ditto/zip, lipo, codesign).
# The resulting IPA is UNSIGNED. It cannot be installed on stock iOS
# as-is; re-sign it with your own personal certificate (AltStore,
# Sideloadly, etc.) or install it via TrollStore / a jailbroken device.
# See docs/UNSIGNED-IPA.md for what works and what does not.
set -euo pipefail

SLIM_FONTS=1
OPT_SIZE=0
KEEP_DSYM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --full-fonts) SLIM_FONTS=0 ;;
    --slim-fonts) SLIM_FONTS=1 ;;
    --osize) OPT_SIZE=1 ;;
    --keep-dsym) KEEP_DSYM=1 ;;
    --help|-h)
      echo "Usage: $0 [--full-fonts] [--slim-fonts] [--osize] [--keep-dsym]"
      echo "  --full-fonts  Keep all four bundled CJK fonts (larger IPA)."
      echo "  --slim-fonts  Remove LXGW WenKai + LXGW NeoXiHei from the IPA (default)."
      echo "  --osize       Use -Osize instead of -O (smaller binary, may be slower)."
      echo "  --keep-dsym   Copy the .dSYM out to build/ instead of discarding it."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: this script must run on macOS with Xcode installed." >&2
  exit 1
fi
command -v xcodebuild >/dev/null || { echo "error: xcodebuild not found." >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f "Tingye.xcodeproj/project.pbxproj" ] || { echo "error: run from the repo root (Tingye.xcodeproj not found)." >&2; exit 1; }

MARKETING_VERSION="$(grep -m1 'MARKETING_VERSION =' Tingye.xcodeproj/project.pbxproj | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ')"
BUILD_NUMBER="$(grep -m1 'CURRENT_PROJECT_VERSION =' Tingye.xcodeproj/project.pbxproj | sed -E 's/.*= *([^;]+);.*/\1/' | tr -d ' ')"
echo "Tingye ${MARKETING_VERSION:-?} (${BUILD_NUMBER:-?}) — unsigned IPA build"

if [ "$OPT_SIZE" -eq 1 ]; then
  SWIFT_OPT="-Osize"
else
  SWIFT_OPT="-O"
fi

ARCHIVE="build/Tingye-unsigned.xcarchive"
DERIVED="build/DerivedData-unsigned"
IPA="build/Tingye-unsigned.ipa"

echo "==> Archiving (Release, generic iOS, unsigned)…"
xcodebuild -project Tingye.xcodeproj -scheme Tingye \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED" \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_ENTITLEMENTS="Tingye/Tingye-unsigned.entitlements" \
  DEVELOPMENT_TEAM="" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  SWIFT_OPTIMIZATION_LEVEL="$SWIFT_OPT" \
  SWIFT_COMPILATION_MODE=wholemodule \
  DEBUG_INFORMATION_FORMAT=dwarf \
  STRIP_INSTALLED_PRODUCT=YES \
  STRIP_SWIFT_SYMBOLS=YES \
  DEAD_CODE_STRIPPING=YES \
  COPY_PHASE_STRIP=YES \
  DEPLOYMENT_POSTPROCESSING=YES

APP="$ARCHIVE/Products/Applications/Tingye.app"
[ -d "$APP" ] || { echo "error: $APP not found after archive." >&2; exit 1; }

if [ "$KEEP_DSYM" -eq 1 ]; then
  mkdir -p build/dSYM
  cp -R "$ARCHIVE/dSYMs/"*.dSYM build/dSYM/ 2>/dev/null || true
  echo "dSYM copied to build/dSYM/ (not included in the IPA)."
fi

echo "==> Packaging Payload…"
rm -rf build/Payload "$IPA"
mkdir -p build/Payload
cp -R "$APP" build/Payload/
rm -rf build/Payload/Tingye.app/_CodeSignature \
       build/Payload/Tingye.app/embedded.mobileprovision

APP_SIZE_BEFORE="$(du -sh build/Payload/Tingye.app | cut -f1)"

# --- Slim: drop the two optional LXGW fonts from this unsigned variant only.
# NotoSerif + NotoSans stay: they are the UI / default reader fonts.
# Removed: LXGWWenKaiLite-Regular.ttf (~13.2 MB), LXGWNeoXiHei.ttf (~7.1 MB).
# Runtime fallback is already in the app: UIFont(name:) returns nil and the
# reader falls back to the system font; OriginalBookView CSS falls back to
# "Kaiti SC" (kai) and sans-serif (xixihei). A saved kai/xixihei preference
# will therefore render in the fallback font in this variant, not crash.
# The signed App Store build is untouched: its bundle still has all 4 fonts.
if [ "$SLIM_FONTS" -eq 1 ]; then
  echo "==> Slimming fonts (removing LXGW WenKai + LXGW NeoXiHei)…"
  rm -f build/Payload/Tingye.app/LXGWWenKaiLite-Regular.ttf \
        build/Payload/Tingye.app/LXGWNeoXiHei.ttf
  # Also drop those two entries from the packaged Info.plist UIAppFonts,
  # and drop NSUbiquitousContainers (its iCloud container has no
  # entitlements in this unsigned variant).
  python3 - "$PWD/build/Payload/Tingye.app/Info.plist" <<'PYEOF'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    plist = plistlib.load(f)
fonts = plist.get("UIAppFonts", [])
plist["UIAppFonts"] = [f for f in fonts if f not in (
    "LXGWWenKaiLite-Regular.ttf", "LXGWNeoXiHei.ttf")]
plist.pop("NSUbiquitousContainers", None)
with open(path, "wb") as f:
    plistlib.dump(plist, f)
print("UIAppFonts now:", plist.get("UIAppFonts"))
PYEOF
fi

echo "==> Creating IPA…"
(cd build && ditto -c -k --keepParent --zlibCompressionLevel 9 Payload Tingye-unsigned.ipa) \
  || (cd build && zip -r -y -9 Tingye-unsigned.ipa Payload >/dev/null)
rm -rf build/Payload

echo "==> Verifying…"
echo "--- app size before slim: $APP_SIZE_BEFORE"
ls -lh "$IPA"
lipo -info "$ARCHIVE/Products/Applications/Tingye.app/Tingye" || true
echo "--- codesign (expect unsigned / no signature):"
codesign -dv "$ARCHIVE/Products/Applications/Tingye.app" 2>&1 || true
echo "--- IPA contents (expect no .dSYM, no _CodeSignature):"
unzip -l "$IPA" | grep -E 'dSYM|_CodeSignature|mobileprovision' && echo "WARNING: unexpected signing/symbol entries above" || echo "OK: no dSYM / signature entries"
if [ "$SLIM_FONTS" -eq 1 ]; then
  unzip -l "$IPA" | grep -E 'LXGW' && echo "WARNING: LXGW fonts still in IPA" || echo "OK: LXGW fonts removed from IPA"
fi
echo "--- version in packaged Info.plist:"
plutil -p "$ARCHIVE/Products/Applications/Tingye.app/Info.plist" | grep -E 'CFBundleShortVersionString|CFBundleVersion' || true

echo ""
echo "Done: $IPA"
echo "Unsigned — re-sign with your own certificate before installing on stock iOS."
