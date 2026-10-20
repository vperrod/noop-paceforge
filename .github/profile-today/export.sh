#!/bin/bash
# Stage 4: export the tables, pack the traces that are small enough.
set -o pipefail
. "$(dirname "$0")/common.sh"
mkdir -p "$OUT/tables" "$OUT/trace-packs"
for t in "$OUT"/traces/*.trace; do
  [ -d "$t" ] || continue
  echo "::group::export $t"
  python3 .github/profile-today/export_tables.py "$t" "$OUT/tables" 2>&1 | tail -n 60
  echo "::endgroup::"
  n=$(basename "$t" .trace)
  tar -C "$OUT/traces" -czf "$W/$n.trace.tgz" "$n.trace"
  size=$(stat -f%z "$W/$n.trace.tgz")
  echo "$n.trace.tgz $size bytes"
  if [ "$size" -lt 300000000 ]; then mv "$W/$n.trace.tgz" "$OUT/trace-packs/"; fi
  rm -rf "$t"
done
du -sh "$OUT"/* 2>/dev/null
