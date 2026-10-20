#!/bin/bash
# Stage 1: fixture, optimized simulator build, boot, install, seed the demo database once.
set -eo pipefail
. "$(dirname "$0")/common.sh"

echo "::group::fixture"
mkdir -p "$W/fx"
cp NOOPiOSUITests/PerfFixtureBuilder.swift NOOPiOSUITests/PerfRealCounts.swift "$W/fx/"
cp .github/profile-today/fixture-main.swift "$W/fx/main.swift"
swiftc -O "$W"/fx/*.swift -o "$W/fixgen"
"$W/fixgen" StrandTests/LiveShapes/PaceForgeRealShapes.json "$W/pf-fixture.json"
python3 - "$W/pf-fixture.json" <<'PY' | tee "$OUT/fixture-counts.txt"
import json, sys
d = json.load(open(sys.argv[1]))
print("activities", len(d.get("data/activities.json", [])), "today", d.get("today"))
print("keys", len(d))
PY
save_state FIX "$W/pf-fixture.json"
echo "::endgroup::"

echo "::group::build"
xcodebuild -scheme NOOPiOS -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$W/dd" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule GCC_OPTIMIZATION_LEVEL=s \
  STRIP_INSTALLED_PRODUCT=NO COPY_PHASE_STRIP=NO build 2>&1 | tail -n 400 > "$OUT/xcodebuild-tail.log" \
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

echo "::group::simulator"
for i in $(seq 1 36); do
  if xcrun simctl list devices available | grep -q "iPhone 17 Pro ("; then break; fi
  sleep 10
done
UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro (" | tail -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')
echo "udid $UDID"
save_state UDID "$UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl list runtimes | tee "$OUT/runtimes.txt"
xcodebuild -version | tee "$OUT/xcode-version.txt"
xcrun xctrace list templates 2>&1 | tee "$OUT/xctrace-templates.txt" | head -40
xcrun simctl install "$UDID" "$APP"
echo "::endgroup::"

echo "::group::seed the demo database once"
# The seed runs on the first launch with --demo-seed; later launches find the data, as a phone does. Wait until the
# database stops growing before the app is killed.
xcrun simctl launch "$UDID" "$BID" $(common_args)
sleep 20
C=$(container)
prev=-1; same=0
for i in $(seq 1 30); do
  size=$(du -sk "$C" | awk '{print $1}')
  if [ "$size" = "$prev" ]; then same=$((same+1)); else same=0; fi
  prev=$size
  [ $same -ge 3 ] && break
  sleep 5
done
echo "container $C size ${prev} KB"
xcrun simctl terminate "$UDID" "$BID" || true
du -sk "$C"/Library "$C"/Documents 2>/dev/null || true
echo "::endgroup::"
