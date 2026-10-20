#!/bin/bash
# Stage 1b: the optimized arm64 simulator build.
set -eo pipefail
. "$(dirname "$0")/common.sh"
echo "::group::build"
xcodebuild -scheme NOOPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$W/dd" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES STRIP_INSTALLED_PRODUCT=NO COPY_PHASE_STRIP=NO build 2>&1 | tail -n 400 > "$OUT/xcodebuild-tail.log" \
  || { tail -n 80 "$OUT/xcodebuild-tail.log"; exit 1; }
tail -n 15 "$OUT/xcodebuild-tail.log"
ls "$W/dd/Build/Products"
APP=$(find "$W/dd/Build/Products" -maxdepth 2 -name '*.app' -path '*Debug-iphonesimulator*' | head -1)
[ -n "$APP" ] || { echo "no .app built"; exit 1; }
BID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
echo "app $APP bundle $BID"
save_state APP "$APP"
save_state BID "$BID"
echo "::endgroup::"

