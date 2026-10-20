#!/bin/bash
# Stage 3: xctrace. Time Profiler, then the SwiftUI template if this Xcode has one; 45 s each, simulated sync on.
set -o pipefail
. "$(dirname "$0")/common.sh"
mkdir -p "$OUT/traces"

record() {  # record NAME TEMPLATE
  local name="$1" template="$2" trace="$OUT/traces/$1.trace" args
  args="$(common_args) -NoopPerfSimulateSync -NoopPerfStallLog stall-$name.json"
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
  rm -rf "$trace"
  echo "::group::xctrace $name ($template): launch by bundle id"
  run_limited 100 xcrun xctrace record --template "$template" --device "$UDID" --time-limit 45s --no-prompt \
    --output "$trace" --launch -- "$BID" $args 2>&1 | tail -n 30 | tee "$OUT/traces/$name.log"
  echo "::endgroup::"
  if [ ! -d "$trace" ]; then
    echo "::group::xctrace $name: launch by app path"
    run_limited 100 xcrun xctrace record --template "$template" --device "$UDID" --time-limit 45s --no-prompt \
      --output "$trace" --launch -- "$APP" $args 2>&1 | tail -n 30 | tee -a "$OUT/traces/$name.log"
    echo "::endgroup::"
  fi
  if [ ! -d "$trace" ]; then
    echo "::group::xctrace $name: attach"
    xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
    local line pid
    line=$(xcrun simctl launch "$UDID" "$BID" $args 2>&1); echo "$line"
    pid=$(echo "$line" | awk -F': ' '{print $2}' | tr -d ' ')
    run_limited 100 xcrun xctrace record --template "$template" --device "$UDID" --time-limit 45s --no-prompt \
      --output "$trace" --attach "$pid" 2>&1 | tail -n 30 | tee -a "$OUT/traces/$name.log"
    echo "::endgroup::"
  fi
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
  cp "$(container)/tmp/stall-$name.json" "$OUT/traces/stall-$name.json" 2>/dev/null
  [ -d "$trace" ] && du -sh "$trace"
}

record timeprofiler 'Time Profiler'
if xcrun xctrace list templates 2>&1 | grep -qx 'SwiftUI'; then
  record swiftui 'SwiftUI'
else
  echo "no SwiftUI template in this Xcode"
fi
