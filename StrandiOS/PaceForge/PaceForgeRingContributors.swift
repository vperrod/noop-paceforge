#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - What explains a PaceForge ring today
//
// The contributor rows on a PaceForge ring's page (PFRingDetailSheet): the rows come from PFRingRows (PaceForgeRingRows.swift).
// A ring with nothing to list says so in one line instead of inventing rows.

enum PFRingContributors {
    /// The rows for one ring. Empty when the readings are missing or not today's, and always for Strain (its rows are `PFRingRows.strain`).
    static func rows(_ kind: PFRingKind, readings: DayReadings?) -> [PFContributorRow] {
        guard let readings else { return [] }
        let facts = PFRingFacts(
            garminReadiness: readings.garminReadiness, garminLevel: readings.garminLevel,
            garminFactors: readings.garminFactors.map { PFRingFacts.Factor(name: $0.name, value: $0.value, status: $0.status) },
            garminRecoveryTimeH: readings.garminRecoveryTimeH, paceforgeDrivers: readings.paceforgeDrivers,
            garminSleepFactor: readings.garminSleepFactor, garminSleepFactorStatus: readings.garminSleepFactorStatus,
            lastNightNeedText: readings.lastNightNeedText, tonightNeedText: readings.tonightNeedText,
            tonightBedtime: readings.tonightBedtime)
        switch kind {
        case .recovery: return PFRingRows.recovery(facts)
        case .sleep: return PFRingRows.sleep(facts)
        case .strain: return []
        }
    }

    /// Why a ring has no rows, in one line.
    static func emptyLine(_ kind: PFRingKind) -> String {
        switch kind {
        case .recovery, .sleep:
            return "No contributors on this phone for today yet. They arrive with the next PaceForge refresh."
        case .strain:
            return "Strain has no contributor breakdown on this phone: PaceForge sends the score and its target, not the parts."
        }
    }
}

/// The contributor rows as one card; one line saying so when there are none.
struct PFRingContributorsCard: View {
    let kind: PFRingKind
    let rows: [PFContributorRow]
    /// The server's one sentence under the rows (the Strain parts' note).
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What explains it").strandOverline()
            if rows.isEmpty {
                PFParagraph(PFRingContributors.emptyLine(kind))
                    .accessibilityIdentifier("pf-ring-contributors-empty")
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label)
                                    .font(LookFont.text(14, weight: .medium))
                                    .foregroundStyle(NoopLook.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let note = row.note {
                                    Text(note).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                                }
                            }
                            Spacer(minLength: 8)
                            if let value = row.value {
                                Text(value).font(LookFont.text(15, weight: .semibold)).foregroundStyle(NoopLook.textPrimary)
                            }
                            PFSourceTag(source: row.source)
                        }
                        if let share = row.share {
                            ProgressView(value: share)
                                .tint(NoopLook.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                if let caption {
                    Text(caption).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-ring-contributors-note")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityIdentifier("pf-ring-contributors")
    }
}

/// The contributors and the recent trend, between the score and the server's readout on a PaceForge ring's page.
/// The trend lines are Garmin's own daily series the phone already holds (PaceForge's three scores are today-only values here);
/// each says so in its title.
struct PFRingExplainSection: View {
    let kind: PFRingKind
    let values: PFScoresValues
    @EnvironmentObject private var repo: Repository
    @State private var series: [String: [LookPoint]] = [:]

    private static let garminSource = "paceforge-garmin"

    private var specs: [(key: String, title: String, unit: String)] {
        switch kind {
        case .recovery: return [("hrv", "HRV \u{00B7} Garmin", "ms"), ("rhr", "Resting heart rate \u{00B7} Garmin", "bpm")]
        case .sleep: return [("sleep_score", "Sleep score \u{00B7} Garmin", "")]
        case .strain: return [("training_load_7day", "7-day training load \u{00B7} Garmin", "")]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if kind == .strain {
                PFRingContributorsCard(kind: kind, rows: PFRingRows.strain(values.strainParts), caption: values.strainPartsNote)
            } else {
                PFRingContributorsCard(kind: kind, rows: PFRingContributors.rows(kind, readings: values.readings))
            }
            ForEach(specs, id: \.key) { spec in
                LookTrendLineCard(title: spec.title, unit: spec.unit, points: lastDays(series[spec.key] ?? [], 30),
                                  identifier: "pf-ring-trend-\(spec.key)")
            }
        }
        .task(id: "\(repo.refreshSeq)|\(kind.rawValue)") { await load() }
    }

    private func lastDays(_ points: [LookPoint], _ days: Int) -> [LookPoint] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return LookSeries.within(points, from: start, to: end)
    }

    @MainActor private func load() async {
        var out: [String: [LookPoint]] = [:]
        for spec in specs {
            let rows = await repo.exploreSeries(key: spec.key, source: Self.garminSource, days: 400)
            out[spec.key] = LookSeries.points(rows, calendar: Calendar.current)
        }
        guard !Task.isCancelled else { return }
        series = out
    }
}

/// "Why is my Recovery 72%?": hands the Coach a question naming this ring, its source and today's value. The sheet closes first (a
/// sheet cannot open over a sheet); the Coach opens once the dismissal has finished, like the other pages that hand it a question.
struct PFRingAskCoachRow: View {
    let kind: PFRingKind
    let values: PFScoresValues
    @EnvironmentObject private var router: NavRouter
    @Environment(\.dismiss) private var dismiss

    private var valueText: String? {
        switch kind {
        case .recovery: return values.recovery.map { String(Safe.int($0)) + "%" }
        case .sleep: return values.sleep.map { String(Safe.int($0)) + "%" }
        case .strain: return values.strain.map { PFFormat.oneDecimal($0) + " of 21" }
        }
    }

    @ViewBuilder var body: some View {
        if PFAPI.isConfigured, let valueText {
            LookInsightCard("Why is my PaceForge \(kind.title) \(valueText)?", linkTitle: "Ask the coach about this", action: {
                PFChatPrefill.shared.text = "My PaceForge \(kind.title) (calculated from Garmin data) is \(valueText) today. Why is it there, and what should I do about it?"
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.openCoach() }
            })
            .accessibilityIdentifier("pf-ring-ask-coach")
        }
    }
}
#endif
