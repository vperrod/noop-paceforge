#!/bin/bash
# Stage 1a: the synthetic fixture, and the simulator booting while the app builds.
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

echo "::group::simulator (boot now, wait later)"
for i in $(seq 1 36); do
  if xcrun simctl list devices available | grep -q "iPhone 17 Pro ("; then break; fi
  sleep 10
done
UDID=$(xcrun simctl list devices available | grep "iPhone 17 Pro (" | tail -1 | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')
echo "udid $UDID"
save_state UDID "$UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl list runtimes | tee "$OUT/runtimes.txt"
xcodebuild -version | tee "$OUT/xcode-version.txt"
echo "::endgroup::"
