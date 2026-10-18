#!/usr/bin/env bash
# Runs the steps-source logic tests on Linux with a bare Swift toolchain (swiftc + XCTest), no Xcode:
#   StepsSourceResolverTests  the steps order, labels, day-cycle merge and the missing-Apple-steps notice
#   FusionResolverTests       the shared fusion engine the steps order is a table entry of
#   AppleSyncLedgerTests     per-metric Apple Health read outcomes (a failed steps read must not abort the sync)
#   WorkoutMirrorDedupeTests  a PaceForge (Garmin mirror) workout dedupes against any overlapping row
# The sources under test are Foundation-only, so they are compiled straight into the test binary and
# `@testable import ...` lines are dropped (same approach as scripts/myday-walk-logic-tests-linux.sh).
# Usage: scripts/steps-source-logic-tests-linux.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkg="$root/Packages/StrandAnalytics"
src="$pkg/Sources/StrandAnalytics"
suites=(
  "$pkg/Tests/StrandAnalyticsTests/StepsSourceResolverTests.swift"
  "$pkg/Tests/StrandAnalyticsTests/FusionResolverTests.swift"
  "$root/StrandTests/AppleSyncLedgerTests.swift"
  "$root/StrandTests/WorkoutMirrorDedupeTests.swift"
)
files=()
{ echo "import XCTest"; echo -n "XCTMain(["; } > "$work/main.swift"
for path in "${suites[@]}"; do
  t="$(basename "$path" .swift)"
  sed -e '/^@testable import StrandAnalytics$/d' -e '/^@testable import Strand$/d' \
      -e '/^import WhoopStore$/d' -e '/^import StrandAnalytics$/d' "$path" > "$work/$t.swift"
  names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
  { echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
    for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
  files+=("$work/$t.swift" "$work/$t.all.swift")
  echo -n "testCase($t.allTests)," >> "$work/main.swift"
done
echo "])" >> "$work/main.swift"
# WorkoutSource.swift needs WhoopStore's GRDB-backed WorkoutRow; lift just that struct into a stub module file.
sed -n '/^public struct WorkoutRow: Equatable, Codable {/,/^}/p' \
  "$root/Packages/WhoopStore/Sources/WhoopStore/JournalWorkoutAppleCache.swift" > "$work/WorkoutRowStub.body"
{ echo "import Foundation"; cat "$work/WorkoutRowStub.body"; } > "$work/WorkoutRowStub.swift"
sed -e '/^import WhoopStore$/d' -e '/^import StrandAnalytics/d' "$root/Strand/Data/WorkoutSource.swift" > "$work/WorkoutSource.swift"
# WorkoutsTrace lives behind the WhoopProtocol-dependent detector file; the dedupe tests only need its two line
# formatters to exist, so a stub with the same signatures stands in.
cat > "$work/WorkoutsTraceStub.swift" <<'STUB'
enum WorkoutsTrace {
    static func detectedBoutLine(verdict: String, durMin: Int, avgBpm: Int, overlapSource: String? = nil) -> String {
        "detectedBout verdict=\(verdict)"
    }
    static func dedupLine(sportKey: String, keptSource: String, droppedSource: String,
                          keptRichness: Int, droppedRichness: Int) -> String {
        "dedup sport=\(sportKey) kept=\(keptSource) dropped=\(droppedSource)"
    }
}
STUB
# swift-corelibs-foundation has no String(localized:); WorkoutSource only passes literals to it.
cat > "$work/LocalizedShim.swift" <<'SHIM'
extension String { init(localized key: String) { self = key } }
SHIM
swiftc -o "$work/run" "$work/main.swift" \
  "$src/FusionTypes.swift" "$src/FusionResolver.swift" "$src/MetricArbitrationPolicy.swift" "$src/StepsSourceResolver.swift" \
  "$root/Strand/Data/AppleSyncLedger.swift" \
  "$work/WorkoutRowStub.swift" "$work/WorkoutSource.swift" "$root/Strand/Data/WorkoutCatalog.swift" \
  "$work/WorkoutsTraceStub.swift" "$work/LocalizedShim.swift" \
  "${files[@]}"
"$work/run"
