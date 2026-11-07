#!/usr/bin/env bash
# Runs the "look" logic tests (Packages/StrandDesign LookLogicTests and LookScoreLogicTests: score bands, delta chips,
# today-vs-30-days marks, dial geometry, trend ranges and date steppers, monthly segments, axis ticks, the 7-day
# average, week strip, Rest bands, planner wording, overnight heart-rate line) on Linux with a bare Swift toolchain.
# LookLogic.swift and LookScoreLogic.swift are Foundation only, so they are compiled straight into the test binary;
# the rest of the package needs SwiftUI and is not touched.
# Usage: scripts/look-logic-tests-linux.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkg="$root/Packages/StrandDesign"
suites=(LookLogicTests LookScoreLogicTests LookStageTypicalTests)
files=()
{ echo "import XCTest"; echo -n "XCTMain(["; } > "$work/main.swift"
for t in "${suites[@]}"; do
  sed '/^@testable import StrandDesign$/d' "$pkg/Tests/StrandDesignTests/$t.swift" > "$work/$t.swift"
  names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
  { echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
    for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
  files+=("$work/$t.swift" "$work/$t.all.swift")
  echo -n "testCase($t.allTests)," >> "$work/main.swift"
done
echo "])" >> "$work/main.swift"
swiftc -o "$work/run" "$work/main.swift" "$pkg/Sources/StrandDesign/Look/LookLogic.swift" \
  "$pkg/Sources/StrandDesign/Look/LookScoreLogic.swift" "${files[@]}"
"$work/run"
