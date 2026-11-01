#if os(iOS)
import SwiftUI
import StrandDesign

// The band-report cards on the health side (see PaceForgeBandReport.swift for the numbers): the WHOOP strap's overnight HRV status
// beside the Health monitor, the Healthspan input panel on the Healthspan screen, and the graded watch level on the Health monitor.
// Server sentences are shown as served and follow the Hide numbers switch; each card names whose numbers it holds, and none of them
// merges two sources.

// MARK: - The WHOOP strap's overnight HRV, read by NOOP

@MainActor
final class PFStrapHRVStore: ObservableObject {
    static let shared = PFStrapHRVStore()

    enum State: Equatable {
        case loading
        /// No file, or a file that lists no night: the strap has not been read yet.
        case none
        case ready(PFStrapHRV)
    }

    @Published private(set) var state: State = .loading
    private var lastFetch: Date?

    private init() {}

    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 300 { return }
        guard PFAPI.isConfigured else { return }
        let data = await Self.read(PFBandParse.strapHRVPath)
        if let parsed = PFBandParse.strapHRV(PFJ(data: data)) {
            state = .ready(parsed)
        } else {
            state = .none
        }
        lastFetch = Date()
    }

    /// The server's copy, else (offline) the one the last good fetch left on the phone. A fixture never reads the cache.
    nonisolated private static func read(_ path: String) async -> Data? {
        let data = await PFAPI.fetchOptional(path)
        if data == nil, PFAPI.usesPhoneState { return PFStore.read(path: path) }
        return data
    }
}

/// Under the Health monitor. Nothing while it loads, for a watch worn by day only, or when PaceForge is not set up.
struct PFStrapHRVSection: View {
    @ObservedObject private var store = PFStrapHRVStore.shared
    @ObservedObject private var reports = PFReportsStore.shared

    var body: some View {
        // A stack with its own .task, so the load starts whether or not there is anything to draw yet.
        VStack(spacing: 0) { content }
            .task { await store.refreshIfStale() }
    }

    @ViewBuilder private var content: some View {
        if reports.showsOvernight {
            switch store.state {
            case .loading:
                EmptyView()
            case .none:
                PFIntelNote(title: "HRV status, WHOOP strap (via NOOP)", icon: "waveform.path.ecg",
                            text: "No strap data yet. Once the strap's overnight beats have been read, its HRV status shows here.",
                            identifier: "pf-strap-hrv-none")
            case .ready(let hrv):
                PFStrapHRVCard(hrv: hrv)
            }
        }
    }
}

private func pfStrapColor(_ state: String) -> Color {
    switch state {
    case "in_band": return PFColor.positive
    case "calibrating": return PFColor.sky
    default: return PFColor.warning
    }
}

struct PFStrapHRVCard: View {
    let hrv: PFStrapHRV

    var body: some View {
        PFCard(title: "HRV status, WHOOP strap (via NOOP)", icon: "waveform.path.ecg",
               trailing: { PFChip(text: PFBandLogic.strapStateWord(hrv.state), color: pfStrapColor(hrv.state)) }) {
            VStack(alignment: .leading, spacing: 12) {
                PFStrapFigures(hrv: hrv)
                if let bar = PFBandLogic.strapBar(hrv) { PFRangeTrack(bar: bar, color: pfStrapColor(hrv.state)) }
                PFParagraph("Read from the WHOOP strap's overnight beats by NOOP. Garmin's HRV status, from a different sensor, is a different measure: the two are shown side by side and never combined.")
            }
        }
        .containerIdentifier("pf-strap-hrv")
    }
}

private struct PFStrapFigures: View {
    let hrv: PFStrapHRV

    private var average: String? { hrv.mean7.map { String(Safe.int($0)) } }

    private var usual: String? {
        guard let low = hrv.bandLow, let high = hrv.bandHigh else { return nil }
        return "Usual range \(Safe.int(low))\u{2013}\(Safe.int(high)) ms" + (hrv.baseline60.map { ", 60-night baseline \(Safe.int($0)) ms" } ?? "")
    }

    private var lastNight: String? {
        guard let night = PFBandLogic.lastFullNight(hrv), let ms = night.rmssdMs else { return nil }
        return "Last full night \(PFFormat.shortDate(night.date)): \(Safe.int(ms)) ms"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let average {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(average)
                        .font(LookFont.numeral(44))
                        .foregroundStyle(NoopLook.textPrimary)
                        .accessibilityIdentifier("pf-strap-hrv-average")
                    Text("ms, 7-night average")
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
            } else {
                Text("Calibrating: \(hrv.nightsUsed) full nights so far")
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            if let usual {
                Text(usual).font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
            }
            if let lastNight {
                Text(lastNight).font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
            }
        }
    }
}

// MARK: - Healthspan: what goes into it

struct PFHealthInputPanelView: View {
    let panel: PFHealthInputPanel

    var body: some View {
        PFCard("What goes into it", icon: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                if let status = panel.statusText { PFParagraph(status) }
                if !panel.movers.isEmpty { PFHealthMovers(movers: panel.movers) }
                if !panel.missing.isEmpty { PFHealthMissing(missing: panel.missing) }
                if let reason = panel.holdingBack { PFParagraph(reason) }
            }
        }
        .containerIdentifier("pf-healthspan-inputs")
    }
}

private struct PFHealthMovers: View {
    let movers: [PFHealthInput]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biggest movers").lookCaps(11).foregroundStyle(NoopLook.textSecondary)
            ForEach(movers) { input in PFHealthMoverRow(input: input) }
        }
    }
}

private struct PFHealthMoverRow: View {
    let input: PFHealthInput
    private let hiding = PFHiding()

    private var yearsText: String {
        guard let years = input.years else { return "" }
        return String(format: "%+.1f", locale: Locale.current, years) + " years"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(input.label)
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                Text(yearsText)
                    .font(LookFont.text(14, weight: .semibold))
                    .foregroundStyle((input.years ?? 0) > 0 ? NoopLook.trendDown : NoopLook.trendUp)
            }
            if let value = input.valueText {
                Text(hiding.text(value + (input.targetText.map { ", target \($0)" } ?? "")))
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            if let gloss = input.gloss {
                Text(hiding.text(gloss))
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-healthspan-mover-\(input.key)")
    }
}

private struct PFHealthMissing: View {
    let missing: [PFHealthInput]
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Missing").lookCaps(11).foregroundStyle(NoopLook.textSecondary)
            ForEach(missing) { input in
                VStack(alignment: .leading, spacing: 2) {
                    Text(input.label)
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    if let fix = input.fix {
                        Text(hiding.text(fix))
                            .font(LookFont.text(13, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-healthspan-missing-\(input.key)")
            }
        }
    }
}

// MARK: - Health monitor: the graded watch

/// The none / watch / act level beside the yes/no alert, with each vital that moved said in words. Wording stays non-diagnostic.
struct PFGradedWatchView: View {
    let graded: PFGradedWatch

    private var color: Color {
        switch graded.level {
        case "act": return PFColor.critical
        case "watch": return PFColor.warning
        default: return PFColor.positive
        }
    }

    var body: some View {
        PFCard(title: "Health watch", icon: "stethoscope", trailing: { PFChip(text: PFBandLogic.gradedWord(graded.level), color: color) }) {
            VStack(alignment: .leading, spacing: 10) {
                if let text = graded.text { PFParagraph(text) }
                if !graded.metrics.isEmpty { PFGradedMetrics(metrics: graded.metrics) }
                if let reason = graded.capReason {
                    Text("Held at watch: \(reason).")
                        .font(LookFont.text(12.5, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let basis = graded.basis {
                    Text(basis)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .containerIdentifier("pf-graded-watch")
    }
}

private struct PFGradedMetrics: View {
    let metrics: [PFGradedMetric]
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.label).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                    Text(hiding.text(metric.text))
                        .font(LookFont.text(14, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-graded-\(metric.key)")
            }
        }
    }
}
#endif
