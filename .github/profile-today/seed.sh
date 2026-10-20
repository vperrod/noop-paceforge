#!/bin/bash
# Stage 1c: wait for the simulator, install, seed the demo database once.
set -eo pipefail
. "$(dirname "$0")/common.sh"
echo "::group::wait for boot, install"
xcrun simctl bootstatus "$UDID" -b
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
