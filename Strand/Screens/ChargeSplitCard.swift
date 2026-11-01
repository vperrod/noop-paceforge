#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Charge in two parts (Charge detail)
//
// What the body signals say and how last night's sleep went, each on a signed -10 to +10 line where 0 is the usual
// (`ChargeSplit`, a pure function in StrandAnalytics). It re-reads the terms Charge already used: the Charge number, its
// drivers and its colour are not changed. Both parts name their source.

struct ChargeSplitCard: View {
    let split: ChargeSplit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Charge in two parts").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
            if let bodySignal = split.body {
                SplitSignalRow(title: "Body signals", signal: bodySignal, gloss: ChargeSplit.bodyGloss, identifier: "charge-split-body")
            }
            if let sleep = split.sleep {
                SplitSignalRow(title: "Sleep", signal: sleep, gloss: ChargeSplit.sleepGloss, identifier: "charge-split-sleep")
            }
            Text("NOOP, from your WHOOP strap")
                .font(LookFont.text(12, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityIdentifier("charge-split")
    }
}

private struct SplitSignalRow: View {
    let title: LocalizedStringKey
    let signal: ChargeSignal
    let gloss: String
    let identifier: String

    private var valueText: String { String(format: "%+.1f", locale: Locale.current, signal.value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(LookFont.numeral(24))
                    .foregroundStyle(NoopLook.textPrimary)
            }
            SplitBar(value: signal.value)
            Text(LocalizedStringKey(signal.line))
                .font(LookFont.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(LocalizedStringKey(gloss))
                .font(LookFont.text(12.5, weight: .medium))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// A line from -10 to +10 with a tick at 0 and the reading drawn from the tick to its place.
private struct SplitBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let centre = width / 2
            let place = width * CGFloat((min(max(value, -10), 10) + 10) / 20)
            ZStack(alignment: .leading) {
                Capsule().fill(NoopLook.track)
                Capsule()
                    .fill(NoopLook.rest.opacity(0.55))
                    .frame(width: max(abs(place - centre), 3))
                    .offset(x: min(place, centre))
                Rectangle()
                    .fill(NoopLook.textTertiary)
                    .frame(width: 1, height: 12)
                    .offset(x: centre)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}
#endif
