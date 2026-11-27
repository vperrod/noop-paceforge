#if DEBUG
import SwiftUI
import StrandAnalytics
import WhoopStore

/// `--demo-screen coachingcharge` (CoachingChargeUITests): a throwaway store of made-up strap and Garmin days, merged by
/// the real Repository, and what coaching and the reports read from it. Every strap Charge is 40; Garmin's own differs.
/// COACHING_SCENARIO=missing gives today no strap row.
struct CoachingChargeHarness: View {
    private struct Line: Identifiable {
        let id: String
        let text: String
    }

    @State private var lines: [Line] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(lines) { line in
                    Text(verbatim: line.text).accessibilityIdentifier("cc-\(line.id)")
                }
            }
            .padding()
        }
        .task { lines = await Self.run() }
    }

    @MainActor private static func run() async -> [Line] {
        let isMissing = ProcessInfo.processInfo.environment["COACHING_SCENARIO"] == "missing"
        let now = Date()
        func key(_ back: Int) -> String { Repository.logicalDayKey(now.addingTimeInterval(-Double(back) * 86_400)) }
        func row(_ back: Int, hrv: Double, restingHr: Int, recovery: Double?) -> DailyMetric {
            DailyMetric(day: key(back), totalSleepMin: 450, efficiency: 0.9, deepMin: 90, remMin: 100, lightMin: 260,
                        disturbances: 3, restingHr: restingHr, avgHrv: hrv, recovery: recovery, strain: nil,
                        exerciseCount: nil)
        }
        let strap = ((isMissing ? 1 : 0)...13).map { row($0, hrv: 50, restingHr: 55, recovery: 40) }
        // Garmin sends no score: the app works its Charge out from these, high on the last two nights.
        let garmin = (0...13).map { row($0, hrv: $0 <= 1 ? 120 : 78 + Double($0 % 3) * 2, restingHr: 45, recovery: nil) }

        let repo = Repository(deviceId: "my-whoop")
        do {
            let store = try await WhoopStore.inMemory()
            _ = try await store.upsertDailyMetrics(strap, deviceId: "my-whoop-noop")
            _ = try await store.upsertDailyMetrics(garmin, deviceId: "paceforge-garmin")
            repo.setStoreForTesting(store)
        } catch {
            return [Line(id: "status", text: "Store failed: \(error)")]
        }
        await repo.refresh()

        func whole(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "missing" }
        let context = AICoachEngine(repo: repo).buildContext().components(separatedBy: "\n")
        func contextLine(_ prefix: String) -> String {
            context.first { $0.hasPrefix(prefix) }?.trimmingCharacters(in: .whitespaces) ?? "none"
        }
        let digest = WeeklyDigestSource.digest(from: repo.strapDays, anchorDay: key(1))
        let report = TrendsReportData.report(for: .days30, days: repo.strapDays, today: Repository.localDayKey(now))
        let digestText = "Charge \(whole(digest.summary(.charge)?.thisWeek.mean)) | "
            + (WeeklyDigestSource.garminChargeLine(digest, repo.garminCharge) ?? "none")
        let reportText = "Charge \(whole(report.metrics.first { $0.metric == .recovery }?.mean)) | "
            + (GarminChargeReference.line(repo.garminCharge, from: report.start, to: report.end) ?? "none")

        return [
            Line(id: "garmin-today", text: whole(repo.garminCharge[key(0)])),
            Line(id: "garmin-yesterday", text: whole(repo.garminCharge[key(1)])),
            Line(id: "merged-today", text: whole(repo.days.last { $0.day == key(0) }?.recovery)),
            Line(id: "coaching-today", text: whole(repo.strapToday?.recovery)),
            Line(id: "coach-today", text: contextLine("  \(key(0)):")),
            Line(id: "coach-yesterday", text: contextLine("  \(key(1)):")),
            Line(id: "coach-average", text: contextLine("  charge: ")),
            Line(id: "coach-garmin-average", text: contextLine("  Garmin Charge")),
            Line(id: "digest", text: digestText),
            Line(id: "report", text: reportText),
            Line(id: "status", text: "Done"),
        ]
    }
}
#endif
