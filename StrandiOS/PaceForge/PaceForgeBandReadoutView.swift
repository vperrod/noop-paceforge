#if os(iOS)
import SwiftUI
import StrandDesign

// Recovery read two ways (body signals and sleep) and a plain verdict line per score, under NOOP Today's rings (see
// PaceForgeBandReport.swift for the numbers). Every sentence is the server's own, shown as served; the Hide numbers switch applies.
// The card says whose numbers it holds, leaves out when the server sends none, and a watch worn by day only keeps just the Strain line.

// MARK: - Today: Recovery two ways and the verdict lines

/// Under the six rings. Nothing for a past day, under Hide numbers, or when the server sends none; a watch worn by day only keeps the Strain line.
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
        if let readout {
            PFReadoutCard(readout: readout)
        }
    }
}

struct PFReadoutCard: View {
    let readout: PFRecoveryReadout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFReadoutHeader(source: readout.source)
            if readout.bodySignals != nil || readout.sleepSignal != nil {
                PFSignalPair(bodySignals: readout.bodySignals, sleepSignal: readout.sleepSignal)
            }
            if readout.recovery != nil || readout.sleep != nil || readout.strain != nil {
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

    private var label: String { source ?? PFRecoveryReadout.defaultSource }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let bodySignals { PFSignalRow(title: "Body signals", reading: bodySignals, identifier: "today-pf-body-signals") }
            if let sleepSignal { PFSignalRow(title: "Sleep", reading: sleepSignal, identifier: "today-pf-sleep-signal") }
        }
    }
}

private struct PFSignalRow: View {
    let title: LocalizedStringKey
    let reading: PFSignalReading
    let identifier: String
    private let hiding = PFHiding()

    private var valueText: String { String(format: "%+.1f", locale: Locale.current, reading.value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Text(valueText).font(LookFont.numeral(22)).foregroundStyle(NoopLook.textPrimary)
            }
            SignedScaleBar(value: reading.value)
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
