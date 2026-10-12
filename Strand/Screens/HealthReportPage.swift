import SwiftUI
import StrandDesign
import WhoopStore

// MARK: - Health report (Trends report sheet)
//
// A one-page PDF of the last 30 nights of the Health Monitor vitals: HRV, resting heart rate, respiratory rate,
// blood oxygen and skin temperature against your own baseline. The figures come from the pure
// `HealthReportData` (unit-tested); this file lays them out, renders the page to a PDF with the same renderer
// the trends report uses, and offers it through a ShareLink. Everything is computed on the device and the file
// is only shared when the person taps Share. The page and the card both say what this is not: it is not a
// diagnosis and not medical advice.

extension HealthReportVitalKind {
    var tint: Color {
        switch self {
        case .hrv: return StrandPalette.metricPurple
        case .restingHr: return StrandPalette.metricRose
        case .respRate: return StrandPalette.metricCyan
        case .spo2: return StrandPalette.restColor
        case .skinTemp: return StrandPalette.metricAmber
        }
    }
}

/// The laid-out page: the exact view handed to the PDF renderer.
struct HealthReportPage: View {
    let report: HealthReport
    let generatedOn: String

    static let pageWidth: CGFloat = TrendsReportPage.pageWidth

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            header
            notAdvice
            if report.isEmpty {
                emptyState
            } else {
                ForEach(report.vitals.filter(\.hasData)) { vital in vitalCard(vital) }
                missingNote
            }
            footer
        }
        .padding(NoopMetrics.space8)
        .frame(width: Self.pageWidth, alignment: .leading)
        .background(StrandPalette.surfaceBase)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: NoopMetrics.cardRadius, elevated: true)
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                HStack(alignment: .firstTextBaseline) {
                    BrandMark(size: 22)
                    Text(verbatim: "NOOP").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.accent)
                    Spacer()
                    Text(verbatim: "Last \(report.windowNights) nights").strandOverline()
                }
                Text(verbatim: "Health report")
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(verbatim: "\(report.start) to \(report.end)")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            .padding(NoopMetrics.cardPadding)
        }
    }

    private var notAdvice: some View {
        NoopCard {
            HStack(alignment: .top, spacing: NoopMetrics.space2) {
                Image(systemName: "info.circle")
                    .foregroundStyle(StrandPalette.accent)
                Text(verbatim: "Not medical advice. These are the readings your strap recorded while you slept, shown as they are. They are not a diagnosis, and a number outside your usual range is not a reason to worry on its own. Talk to a doctor about any health concern.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func vitalCard(_ vital: HealthReportVital) -> some View {
        NoopCard(tint: vital.kind.tint) {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: vital.kind.title).strandOverline()
                    Spacer()
                    if let latest = vital.latest {
                        Text(verbatim: "\(vital.text(latest)) \(vital.unit)")
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                if let delta = vital.deltaText(nightsInReport: report.windowNights) {
                    Text(verbatim: delta)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if vital.series.count >= 2 {
                    Sparkline(values: vital.series,
                              gradient: Gradient(colors: [vital.kind.tint.opacity(0.55), vital.kind.tint]))
                        .frame(height: 34)
                        .accessibilityHidden(true)
                }
                Divider().overlay(StrandPalette.hairline)
                HStack(spacing: 0) {
                    figure("Average", vital.mean.map { vital.text($0) })
                    figure("Lowest", vital.minimum.map { vital.text($0) })
                    figure("Highest", vital.maximum.map { vital.text($0) })
                    figure("Nights", "\(vital.nights) of \(report.windowNights)")
                }
                Text(verbatim: vital.kind.caption)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    private func figure(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label.uppercased()).font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
            Text(verbatim: value ?? "\u{2013}").font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var missingNote: some View {
        let missing = report.vitals.filter { !$0.hasData }.map { $0.kind.title }
        if !missing.isEmpty {
            Text(verbatim: "No readings in this period: \(missing.joined(separator: ", ")).")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }

    private var emptyState: some View {
        NoopCard {
            Text(verbatim: "No vitals were recorded in the last \(report.windowNights) nights. Wear your strap to sleep for a few nights, then make the report again.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            Divider().overlay(StrandPalette.hairline)
            Text(verbatim: "Generated by NOOP on \(generatedOn). Worked out on this device; nothing was sent anywhere to make it. Informational only, not medical advice.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The card in the trends report sheet

/// "Health report": makes the PDF as the sheet opens (or when the data changes) and offers it with ShareLink.
struct HealthReportCard: View {
    let days: [DailyMetric]

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    @State private var pdfURL: URL?
    @State private var isPreparing = false
    private static let previewTitle: String = "NOOP health report"

    private var today: String { Repository.localDayKey(Date()) }

    private var fahrenheit: Bool {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        return UnitPrefs.resolveTemperature(system: system, override: temperatureRaw) == .fahrenheit
    }

    private var report: HealthReport {
        let nights = days.map { day in
            HealthReportNight(day: day.day, hrv: day.avgHrv, restingHr: day.restingHr.map(Double.init),
                              respRate: day.respRateBpm, spo2: day.spo2Pct, skinTempDev: day.skinTempDevC)
        }
        return HealthReportData.build(nights: nights, today: today, fahrenheit: fahrenheit)
    }

    private var generatedOn: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: Date())
    }

    private var taskKey: String { "\(days.count)|\(days.last?.day ?? "")|\(today)|\(fahrenheit)" }

    var body: some View {
        let current = report
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(verbatim: "Health report").strandOverline()
            Text(verbatim: "The last \(current.windowNights) nights of HRV, resting heart rate, respiratory rate, blood oxygen and skin temperature against your baseline, as a one-page PDF you can share with a doctor or keep.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "Not medical advice. It shows what your strap recorded, not a diagnosis.")
                .font(StrandFont.footnote.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
                .accessibilityIdentifier("health-report-disclaimer")
            if current.isEmpty {
                Text(verbatim: "No vitals in the last \(current.windowNights) nights yet.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityIdentifier("health-report-empty")
            } else if let pdfURL {
                ShareLink(item: pdfURL, preview: SharePreview(Self.previewTitle)) {
                    Label {
                        Text(verbatim: "Share health report")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(StrandPalette.accent)
                .accessibilityIdentifier("health-report-share")
            } else {
                Text(verbatim: isPreparing ? "Preparing\u{2026}" : "The report could not be made.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("health-report-card")
        .task(id: taskKey) { await prepare(current) }
    }

    @MainActor
    private func prepare(_ report: HealthReport) async {
        guard !report.isEmpty else { pdfURL = nil; return }
        isPreparing = true
        defer { isPreparing = false }
        let page = HealthReportPage(report: report, generatedOn: generatedOn)
        pdfURL = TrendsReportRenderer.makePDF(page: page, fileName: "NOOP-health-report-\(report.end).pdf")
    }
}
