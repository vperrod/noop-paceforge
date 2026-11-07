#!/usr/bin/env bash
# Runs the My Day walk-or-workout logic tests on Linux with a bare Swift toolchain (swiftc + XCTest), no Xcode:
# DetectedSegmentClassifierTests (walk rules, recorded match, auto-save rule) and DayTimelineTests (the pure My Day
# builder, including how a detected stretch is labelled). DayTimeline*.swift and DetectedSegmentClassifier.swift are
# Foundation only, so they are compiled straight into the test binary; `@testable import StrandAnalytics` is dropped.
# Usage: scripts/myday-walk-logic-tests-linux.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkg="$root/Packages/StrandAnalytics"
suites=(DetectedSegmentClassifierTests DayTimelineTests)
files=()
{ echo "import XCTest"; echo -n "XCTMain(["; } > "$work/main.swift"
for t in "${suites[@]}"; do
  sed '/^@testable import StrandAnalytics$/d' "$pkg/Tests/StrandAnalyticsTests/$t.swift" > "$work/$t.swift"
  names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
  { echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
    for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
  files+=("$work/$t.swift" "$work/$t.all.swift")
  echo -n "testCase($t.allTests)," >> "$work/main.swift"
done
echo "])" >> "$work/main.swift"
src="$pkg/Sources/StrandAnalytics"
swiftc -o "$work/run" "$work/main.swift" "$src/DayTimeline.swift" "$src/DayTimelineBuilder.swift" \
  "$src/DetectedSegmentClassifier.swift" "${files[@]}"
"$work/run"
