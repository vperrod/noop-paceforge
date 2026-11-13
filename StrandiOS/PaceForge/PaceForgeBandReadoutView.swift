#if os(iOS)
import SwiftUI
import StrandDesign

// Recovery read two ways (body signals and sleep) and a plain verdict line per score (see PaceForgeBandReport.swift for the numbers).
// Today shows the two signed bars with their numbers and keeps the sentences behind an (i); the Coach shows the whole card, verdict lines
// included. Every sentence is the server's own, shown as served; the Hide numbers switch applies. The card says whose numbers it holds,
// leaves out when the server sends none, and a watch worn by day only keeps just the Strain line.

// MARK: - Today: the two signals, compact

/// On Today, under the monitor tiles and the heart-rate chart. Nothing for a past day, under Hide numbers, or when the server sends no
/// signal (a watch worn by day only has just the Strain line, which the Coach shows).
struct TodayPFReadout: View {
    let isToday: Bool
    @ObservedObject private var store = PFScoresStore.shared
    @ObservedObject private var reports = PFReportsStore.shared
    private let hiding = PFHiding()

    private var readout: PFRecoveryReadout? {
        guard isToday, !hiding.hides(.scores) else { return nil }
        return store.values?.readout?.visible(overnight: reports.showsOvernight)
    }

    var body: some View {
        if let readout, readout.bodySignals != nil || readout.sleepSignal != nil {
            PFReadoutCard(readout: readout, isCompact: true)
        }
    }
}

/// The Coach's copy: the whole card, the three verdict lines included.
struct CoachPFReadout: View {
    @ObservedObject private var store = PFScoresStore.shared
    @ObservedObject private var reports = PFReportsStore.shared
    private let hiding = PFHiding()

    private var readout: PFRecoveryReadout? {
        guard !hiding.hides(.scores) else { return nil }
        return store.values?.readout?.visible(overnight: reports.showsOvernight)
    }

    var body: some View {
        if let readout {
            PFReadoutCard(readout: readout, isCompact: false)
        }
    }
}

struct PFReadoutCard: View {
    let readout: PFRecoveryReadout
    /// Today's version: the bars and numbers only, the sentences behind an (i), no verdict lines.
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFReadoutHeader(source: readout.source)
            if readout.bodySignals != nil || readout.sleepSignal != nil {
                PFSignalPair(bodySignals: readout.bodySignals, sleepSignal: readout.sleepSignal, isCompact: isCompact)
            }
            if !isCompact, readout.recovery != nil || readout.sleep != nil || readout.strain != nil {
                PFVerdictRows(readout: readout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("today-pf-readout")
    }
}

private struct PFReadoutHeader: View {
    let source: String?
    private let hiding = PFHiding()

    private var label: String { hiding.text(source ?? PFRecoveryReadout.defaultSource) }

    var body: some View {
        HStack(spacing: 6) {
            PFChip(text: "PaceForge", color: PFColor.sky)
            Text(label)
                .font(LookFont.text(11, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }
}

/// Body signals and Sleep, each on a signed -10 to +10 line where 0 is the usual, with the server's one line and its short gloss.
private struct PFSignalPair: View {
    let bodySignals: PFSignalReading?
    let sleepSignal: PFSignalReading?
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bodySignals {
                PFSignalRow(title: "Body signals", reading: bodySignals, identifier: "today-pf-body-signals", isCompact: isCompact)
            }
            if let sleepSignal {
                PFSignalRow(title: "Sleep", reading: sleepSignal, identifier: "today-pf-sleep-signal", isCompact: isCompact)
            }
        }
    }
}

private struct PFSignalRow: View {
    let title: String
    let reading: PFSignalReading
    let identifier: String
    let isCompact: Bool
    private let hiding = PFHiding()

    private var valueText: String { String(format: "%+.1f", locale: Locale.current, reading.value) }

    var body: some View {
        if isCompact { compactBody } else { fullBody }
    }

    /// Title, number and the bar; the server's line and gloss open from the (i) beside it.
    private var compactBody: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(title)).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                    Spacer(minLength: 8)
                    Text(hiding.shown(valueText, .scores)).font(LookFont.numeral(22)).foregroundStyle(NoopLook.textPrimary)
                }
                SignedScaleBar(value: hiding.hides(.scores) ? 0 : reading.value)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(verbatim: hiding.text(reading.line)))
            .accessibilityIdentifier(identifier)
            PFReadingInfoButton(title: title, reading: reading)
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title)).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Text(hiding.shown(valueText, .scores)).font(LookFont.numeral(22)).foregroundStyle(NoopLook.textPrimary)
            }
            SignedScaleBar(value: hiding.hides(.scores) ? 0 : reading.value)
            Text(hiding.text(reading.line))
                .font(LookFont.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let gloss = reading.gloss {
                Text(hiding.text(gloss))
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// The (i) beside a compact signal row: opens the server's one line and its gloss in the same sheet the other explainers use. Same look
/// as `PFInfoButton` (15 pt, tertiary, 32 pt target).
private struct PFReadingInfoButton: View {
    let title: String
    let reading: PFSignalReading
    @State private var isShowing = false
    private let hiding = PFHiding()

    private var explainer: PFExplainer {
        let text = [reading.line, reading.gloss].compactMap { $0 }.map { hiding.text($0) }.joined(separator: "\n\n")
        return PFExplainer(id: "reading-\(title)", title: title, plain: text)
    }

    var body: some View {
        Button { isShowing = true } label: {
            Image(systemName: "info.circle")
                .font(StrandFont.scaled(15, weight: .regular))
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("What \(title) says"))
        .accessibilityIdentifier("today-pf-info-\(title)")
        .sheet(isPresented: $isShowing) { PFExplainerSheet(explainer: explainer) }
    }
}

/// The three plain lines: Recovery, Sleep and Strain, each a verdict, the biggest driver in a sentence and, while it is still
/// calibrating, the server's counter.
private struct PFVerdictRows: View {
    let readout: PFRecoveryReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let line = readout.recovery { PFVerdictRow(title: "Recovery", line: line, identifier: "today-pf-line-recovery") }
            if let line = readout.sleep { PFVerdictRow(title: "Sleep", line: line, identifier: "today-pf-line-sleep") }
            if let line = readout.strain { PFVerdictRow(title: "Strain", line: line, identifier: "today-pf-line-strain") }
        }
    }
}

private struct PFVerdictRow: View {
    let title: LocalizedStringKey
    let line: PFVerdictLine
    let identifier: String
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
            if let verdict = line.verdict {
                Text(hiding.text(verdict))
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let driver = line.driver {
                Text(hiding.text(driver))
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let counter = line.calibrating {
                Text(hiding.text(counter))
                    .font(LookFont.text(12.5, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
#endif
