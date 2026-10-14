#!/usr/bin/env bash
# Runs the "look" logic tests (Packages/StrandDesign LookLogicTests: score bands, delta chips, today-vs-30-days
# marks, dial geometry, trend ranges and date steppers, monthly segments, axis ticks) on Linux with a bare Swift
# toolchain. LookLogic.swift is Foundation only, so it is compiled straight into the test binary; the rest of the
# package needs SwiftUI and is not touched.
# Usage: scripts/look-logic-tests-linux.sh
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pkg="$root/Packages/StrandDesign"
t=LookLogicTests
sed '/^@testable import StrandDesign$/d' "$pkg/Tests/StrandDesignTests/$t.swift" > "$work/$t.swift"
names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
{ echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
  for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
{ echo "import XCTest"; echo "XCTMain([testCase($t.allTests)])"; } > "$work/main.swift"
swiftc -o "$work/run" "$work/main.swift" "$pkg/Sources/StrandDesign/Look/LookLogic.swift" "$work/$t.swift" "$work/$t.all.swift"
"$work/run"
