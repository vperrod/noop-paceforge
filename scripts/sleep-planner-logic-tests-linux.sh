#!/usr/bin/env bash
# Runs the Sleep Planner maths tests (Packages/StrandAnalytics SleepPlannerTests) on Linux with a bare Swift toolchain.
# The package itself does not build here (GRDB needs sqlite headers), so SleepPlanner.swift and the one type it
# borrows (StageSegment, cut out of SleepStager.swift) are compiled straight into the test binary.
# Usage: scripts/sleep-planner-logic-tests-linux.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkg="$root/Packages/StrandAnalytics"
t=SleepPlannerTests
{ echo "import Foundation"; sed -n '/^public struct StageSegment/,/^}/p' "$pkg/Sources/StrandAnalytics/SleepStager.swift"; } > "$work/StageSegment.swift"
sed '/^@testable import StrandAnalytics$/d' "$pkg/Tests/StrandAnalyticsTests/$t.swift" > "$work/$t.swift"
names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
{ echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
  for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
{ echo "import XCTest"; echo "XCTMain([testCase($t.allTests)])"; } > "$work/main.swift"
swiftc -o "$work/run" "$work/main.swift" "$work/StageSegment.swift" "$pkg/Sources/StrandAnalytics/SleepPlanner.swift" "$work/$t.swift" "$work/$t.all.swift"
"$work/run"
