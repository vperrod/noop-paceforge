#!/bin/bash
# Stage 2: bisect. Each variant is one 32 s launch with the simulated sync (sync starts at 5 s); the app's own stall meter
# (NoopPerfSimulateSync) says how long the main thread was blocked, and the baseline run is sampled with sample(1) twice.
set -o pipefail
. "$(dirname "$0")/common.sh"
VARIANTS="${VARIANTS:-nosync sync nofits quiet nobattery cap0 cap2}"
RUN_SECONDS="${RUN_SECONDS:-32}"
mkdir -p "$OUT/variants"
: > "$OUT/variants/summary.tsv"
printf 'variant\tstalled_s_total\tstalled_s_after_sync_start\tlongest_s\tevents\n' >> "$OUT/variants/summary.tsv"

extra_for() {
  case "$1" in
    nosync)     echo "-NoopPerfStallLog stall-nosync.json" ;;
    sync)       echo "-NoopPerfSimulateSync -NoopPerfStallLog stall-sync.json" ;;
    nofits)     echo "-NoopPerfSimulateSync -NoopPerfNoViewThatFits -NoopPerfStallLog stall-nofits.json" ;;
    quiet)      echo "-NoopPerfSimulateSync -noop.quietMotion YES -NoopPerfStallLog stall-quiet.json" ;;
    nobattery)  echo "-NoopPerfSimulateSync -NoopPerfNoBattery -NoopPerfStallLog stall-nobattery.json" ;;
    cap0)       echo "-NoopPerfSimulateSync -NoopPerfMountCap 0 -NoopPerfStallLog stall-cap0.json" ;;
    cap2)       echo "-NoopPerfSimulateSync -NoopPerfMountCap 2 -NoopPerfStallLog stall-cap2.json" ;;
    *)          echo "-NoopPerfSimulateSync -NoopPerfStallLog stall-$1.json" ;;
  esac
}

for v in $VARIANTS; do
  echo "::group::variant $v"
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
  C=$(container); rm -f "$C"/tmp/stall-*.json
  line=$(xcrun simctl launch "$UDID" "$BID" $(common_args) $(extra_for "$v") 2>&1)
  echo "$line"
  PID=$(echo "$line" | awk -F': ' '{print $2}' | tr -d ' ')
  if [ "$v" = "sync" ] && [ -n "$PID" ]; then
    sleep 16
    run_limited 40 sample "$PID" 5 -file "$OUT/variants/sample-sync-t16.txt" >/dev/null 2>&1
    sleep 6
    run_limited 40 sample "$PID" 5 -file "$OUT/variants/sample-sync-t27.txt" >/dev/null 2>&1
    sleep 2
  else
    sleep "$RUN_SECONDS"
  fi
  cp "$C"/tmp/stall-"$v".json "$OUT/variants/stall-$v.json" 2>/dev/null || echo "no stall log for $v"
  python3 - "$v" "$OUT/variants/stall-$v.json" >> "$OUT/variants/summary.tsv" <<'PY'
import json, sys
v, p = sys.argv[1:3]
try:
    d = json.load(open(p))
    print("\t".join(map(str, [v, round(d["stalled_s_total"], 2), round(d["stalled_s_after_sync_start"], 2), round(d["longest_s"], 2), d["stall_events"]])))
except Exception as e:
    print(f"{v}\tNA\tNA\tNA\t{e}")
PY
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
  echo "::endgroup::"
done
cat "$OUT/variants/summary.tsv"
{ echo '### Stall per variant'; echo '```'; column -t -s $'\t' "$OUT/variants/summary.tsv"; echo '```'; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
