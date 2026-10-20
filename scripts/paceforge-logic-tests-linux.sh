#!/usr/bin/env bash
# Runs the Foundation-only PaceForge logic tests on Linux with a bare Swift toolchain (swiftc + XCTest), no Xcode.
# The tests are the same files the macOS StrandTests bundle runs; only `@testable import Strand` is dropped, because
# the logic sources are compiled straight into the test binary here (as project.yml does for the macOS bundle).
# Usage: scripts/paceforge-logic-tests-linux.sh [Test file names without .swift ...]   (default: the new ones)
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
export PATH="$HOME/.local/swift/usr/bin:$PATH"
command -v swiftc >/dev/null || { echo "swiftc not found (looked in PATH and ~/.local/swift/usr/bin)"; exit 2; }
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# The Insights v2 tests read the synthetic UI-test fixture; the copied test files no longer sit next to it.
export PF_FIXTURE_FILE="$root/NOOPiOSUITests/PaceForgeFixture.json"
# The crash-guard tests also read the live documents' shapes with every value replaced.
export PF_REAL_SHAPES_FILE="$root/StrandTests/LiveShapes/PaceForgeRealShapes.json"
pf="$root/StrandiOS/PaceForge"
tests=("$@"); [ ${#tests[@]} -gt 0 ] || tests=(PaceForgeLogTests PaceForgeTodayLayoutTests PaceForgeDismissTests PaceForgeHRRGarminTests PaceForgeRedactTests WidgetSnapshotHideTests PaceForgeGlanceTests LiftFiltersTests PaceForgeInsightsV2Tests PaceForgeHyroxPrognosisTests PaceForgeDailyIntelTests PaceForgeIntelDocsTests PaceForgeMovementTests MyDashboardPrefsTests JournalFlowLogicTests StressMonitorLogicTests PaceForgeCrashGuardTests PaceForgeSavedStateTests)
sources=("$root/StrandiOSShared/SafeNumber.swift" "$pf/PaceForgeFormat.swift" "$pf/PaceForgeModels.swift" "$pf/PaceForgeBuilder.swift" "$pf/PaceForgeDocs.swift" "$pf/PaceForgeWave2.swift" "$pf/PaceForgeLocalExplainers.swift" "$pf/PaceForgeDayMerge.swift" "$pf/PaceForgeJSON.swift" "$pf/PaceForgeWave3.swift" "$pf/PaceForgeDismiss.swift" "$pf/PaceForgeLog.swift" "$pf/PaceForgeTodayLayout.swift" "$pf/PaceForgeHRRGarmin.swift" "$root/StrandiOSShared/PaceForgeRedact.swift" "$root/Strand/Data/HideScores.swift"
         "$pf/PaceForgeStanding.swift" "$pf/PaceForgeInsightsV2.swift" "$pf/PaceForgeHyroxPrognosis.swift" "$pf/PaceForgeDailyIntel.swift" "$pf/PaceForgeIntelDocs.swift" "$pf/PaceForgeMovement.swift" "$pf/PaceForgeRide.swift" "$root/Strand/Data/MyDashboardPrefs.swift" "$root/Strand/Data/JournalFlowLogic.swift" "$root/Strand/Data/StressMonitorLogic.swift" "$pf/PaceForgeGlanceBuilder.swift" "$root/StrandiOSShared/PaceForgeGlance.swift"
         "$root/StrandiOSShared/WidgetSnapshot.swift" "$root/StrandiOSShared/HrTrace.swift" "$root/StrandiOSShared/StressTrace.swift"
         "$root/Strand/Data/LiftFilters.swift" "$root/Packages/WhoopStore/Sources/WhoopStore/LiftMuscle.swift")
# TodayLayoutPrefs imports SwiftUI for nothing it uses here and localises its titles; the Linux Foundation has no
# `String(localized:)`, so the staged copy drops the import and reads the key as the title.
sed -e '/^import SwiftUI$/d' -e 's/String(localized: /String(/g' "$root/Strand/Data/TodayLayoutPrefs.swift" > "$work/TodayLayoutPrefs.swift"
sources+=("$work/TodayLayoutPrefs.swift")
entries=""
for t in "${tests[@]}"; do
  sed '/^@testable import Strand$/d' "$root/StrandTests/$t.swift" > "$work/$t.swift"
  names=$(sed -n 's/^ *func \(test[A-Za-z0-9_]*\)().*/\1/p' "$work/$t.swift")
  { echo "import XCTest"; echo "extension $t { static var allTests: [(String, ($t) -> () throws -> Void)] { ["
    for n in $names; do echo "(\"$n\", $n),"; done; echo "] } }"; } > "$work/$t.all.swift"
  entries+="testCase($t.allTests), "
done
{ echo "import XCTest"; echo "XCTMain([${entries%, }])"; } > "$work/main.swift"
swiftc -o "$work/run" "$work/main.swift" "${sources[@]}" "$work"/*Tests.swift "$work"/*.all.swift
"$work/run"
