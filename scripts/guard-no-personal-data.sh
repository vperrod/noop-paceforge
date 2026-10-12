#!/usr/bin/env bash
# Rejects staged files that could carry real PaceForge/health data: this repo is PUBLIC.
# The app reads live data; the only allowed bundled JSON is the synthetic UI-test fixture.
set -u
fixture="NOOPiOSUITests/PaceForgeFixture.json"
bad=0
while IFS= read -r f; do
  case "$f" in
    StrandiOS/Resources/PaceForge*|*[Pp]review*.json|*[Ss]napshot*.json) echo "guard: $f looks like a bundled data snapshot"; bad=1; continue ;;
  esac
  [ "${f##*.}" = json ] || continue
  blob=$(git show ":$f")
  if [ "$f" = "$fixture" ]; then
    grep -q Synthetic <<<"$blob" || { echo "guard: $f must stay synthetic"; bad=1; }
  elif grep -qE '"(daily_brief|hrv_ms|rhr_bpm|readiness_score)"|HYROX Dublin' <<<"$blob"; then
    echo "guard: $f contains health/race data markers"; bad=1
  fi
done < <(git diff --cached --name-only --diff-filter=ACMR)
[ "$bad" = 0 ] || { echo "guard: refusing commit. Never commit real PaceForge data; use live data or a synthetic fixture."; exit 1; }
