#!/usr/bin/env bash
# Runs the Effort v2 scorer tests (StrainScorerAllDayTests) on Linux with a bare Swift toolchain, no Xcode and no GRDB.
# StrainScorer and EffortBreakdown are Foundation only apart from HRSample and WorkoutDetector's number formatters, so they
# are compiled straight into the test binary with those two stubbed; the engine-level tests (AnalyticsEngine) need the
# whole package and run in Xcode / `swift test` on a machine with SQLite headers.
# Usage: scripts/effort-v2-logic-tests-linux.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkg="$root/Packages/StrandAnalytics"
t=StrainScorerAllDayTests
mkdir -p "$work/EffortV2Data"
cp "$pkg/Tests/StrandAnalyticsTests/EffortV2Data/effort_v2_cases.json" "$work/EffortV2Data/"
cat > "$work/Stubs.swift" <<'SWIFT'
import Foundation
public struct HRSample: Equatable { public let ts: Int; public let bpm: Int; public init(ts: Int, bpm: Int) { self.ts = ts; self.bpm = bpm } }
enum WorkoutDetector {
    static let printableMagnitudeLimit = 1e15
    static func round0(_ v: Double?) -> String {
        guard let v, v.isFinite, abs(v) < printableMagnitudeLimit else { return "nil" }
        return (v < 0 ? "-" : "") + String(Int(abs(v).rounded()))
    }
}
SWIFT
for f in StrainScorer EffortBreakdown; do
  sed '/^import WhoopProtocol$/d' "$pkg/Sources/StrandAnalytics/$f.swift" > "$work/$f.swift"
done
cp "$pkg/Sources/StrandAnalytics/AnalyticsMemo.swift" "$work/AnalyticsMemo.swift"
sed -e '/^@testable import StrandAnalytics$/d' -e '/^import WhoopProtocol$/d' -e '/^import WhoopStore$/d' \
  "$pkg/Tests/StrandAnalyticsTests/$t.swift" > "$work/$t.swift"
names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
{ echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
  for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
{ echo "import XCTest"; echo "XCTMain([testCase($t.allTests)])"; } > "$work/main.swift"
swiftc -o "$work/run" "$work/main.swift" "$work/Stubs.swift" "$work/StrainScorer.swift" "$work/EffortBreakdown.swift" \
  "$work/AnalyticsMemo.swift" "$work/$t.swift" "$work/$t.all.swift"
"$work/run"
