#!/bin/bash
# Actual SwiftUI simulator screenshots with DEBUG-only public-domain demo fixtures.
# No user library, cloud speech, or publishing. Run after building the simulator app.
set -euo pipefail
cd "$(dirname "$0")/../.."
device="${1:-9084423E-1DBA-4CBA-8B87-392FC4DB58B0}"
app="build/MarginV19DerivedData/Build/Products/Debug-iphonesimulator/Tingye.app"
bundle="com.shatianrui.wereader"
out="Design/v19-margin/runtime"
mkdir -p "$out"
xcrun simctl install "$device" "$app"
capture() {
  local appearance="$1" scene="$2"
  xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$device" "$bundle" \
    -ui-fixture -ui-showcase -ui-reset-preferences -ui-reduce-motion \
    -uireview "$scene" -ui-appearance "$appearance" \
    -privacy.appLock NO -reader.font system -reader.original NO \
    -reader.scrolling NO -shelf.kind books -voice.rate 1.0
  # Allow navigation, local covers, and layout to settle before capturing pixels.
  sleep 8
  xcrun simctl io "$device" screenshot "$out/$appearance-$scene.png"
}
for appearance in light dark; do
  for scene in now shelf stats detail player reader; do capture "$appearance" "$scene"; done
done
for scene in sources appearance backup reader-preferences reader-contents player-voice; do
  capture light "$scene"
done
