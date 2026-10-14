import SwiftUI
import WidgetKit
import StrandDesign

// The "Effort target" widget faces. They live in the shared folder so the extension draws them and the app's
// debug widget gallery renders the very same views. They read a WidgetSnapshot only: today's Effort, the
// OPTIMAL band and the "to go" sentence, all pre-formatted by the app on the user's Effort scale.
//
// Colours stay neutral on purpose: the band is a quiet block and "above range" is not an error. On the lock
// screen the system desaturates colour anyway, so the circular face uses only .primary / .secondary.

/// The fractions on the stored 0-100 axis, shared by both faces.
private struct EffortTargetFractions {
    let effort: Double?
    let low: Double?
    let high: Double?

    init(_ s: WidgetSnapshot) {
        func f(_ v: Int?) -> Double? { v.map { max(0, min(1, Double($0) / 100)) } }
        effort = f(s.effortTargetEffort)
        low = f(s.effortBandLow)
        high = f(s.effortBandHigh)
    }
}

/// A thin bar: band as a quiet block, Effort filling from the left.
private struct EffortTargetWidgetBar: View {
    let fractions: EffortTargetFractions

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(StrandPalette.hairline)
                if let lo = fractions.low, let hi = fractions.high {
                    Capsule().fill(StrandPalette.textTertiary.opacity(0.4))
                        .frame(width: max(5, w * CGFloat(hi - lo)))
                        .offset(x: w * CGFloat(lo))
                }
                if let e = fractions.effort {
                    Capsule().fill(StrandPalette.effortColor.opacity(0.9))
                        .frame(width: max(5, w * CGFloat(e)))
                }
            }
        }
        .frame(height: 8)
    }
}

/// A 270-degree gauge: track, band, then Effort. Single weight, no colour, so it survives the lock screen.
private struct EffortTargetArc: View {
    let fractions: EffortTargetFractions
    private let sweep = 0.75

    var body: some View {
        ZStack {
            arc(from: 0, to: 1).stroke(Color.secondary.opacity(0.28), style: style(5))
            if let lo = fractions.low, let hi = fractions.high {
                arc(from: lo, to: hi).stroke(Color.secondary.opacity(0.75), style: style(5))
            }
            if let e = fractions.effort {
                arc(from: 0, to: e).stroke(Color.primary, style: style(3))
            }
        }
        .rotationEffect(.degrees(135))
        .padding(4)
    }

    private func arc(from: Double, to: Double) -> some Shape {
        Circle().trim(from: CGFloat(from * sweep), to: CGFloat(max(to, from + 0.004) * sweep))
    }

    private func style(_ width: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: width, lineCap: .round) }
}

struct EffortTargetWidgetFace: View {
    let snapshot: WidgetSnapshot?
    /// True when there is no snapshot, it is for another day, or it was written too long ago.
    let stale: Bool
    let family: WidgetFamily

    var body: some View {
        if let s = snapshot, !stale, s.scoresHidden == true {
            hidden
        } else if let s = snapshot, !stale {
            switch family {
            case .accessoryCircular: circular(s)
            default: small(s)
            }
        } else if family == .accessoryCircular {
            PFWidgetStale(compact: true)
        } else {
            PFWidgetStale()
        }
    }

    // MARK: Hidden (Settings > Hide numbers)

    private var hidden: some View {
        VStack(alignment: family == .accessoryCircular ? .center : .leading, spacing: 4) {
            if family != .accessoryCircular {
                Text("EFFORT TARGET")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Image(systemName: "eye.slash")
                .font(.system(size: family == .accessoryCircular ? 14 : 22))
            Text(PFRedact.placeholder)
                .font(.system(size: family == .accessoryCircular ? 10 : 13, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .foregroundStyle(family == .accessoryCircular ? Color.primary : StrandPalette.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: family == .accessoryCircular ? .center : .topLeading)
    }

    // MARK: Small

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EFFORT TARGET")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            if s.effortBandText == nil {
                Text("Waiting for today's Charge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(StrandPalette.textSecondary)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(s.effortTargetEffortText ?? "\u{2013}")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let band = s.effortBandText {
                        Text("of \(band)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                EffortTargetWidgetBar(fractions: EffortTargetFractions(s))
                if let toGo = s.effortToGo {
                    Text(toGo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Lock Screen circular

    private func circular(_ s: WidgetSnapshot) -> some View {
        ZStack {
            EffortTargetArc(fractions: EffortTargetFractions(s))
            VStack(spacing: 0) {
                Text(s.effortTargetEffortText ?? "\u{2013}")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("Effort")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
        }
    }
}

extension WidgetSnapshot {
    /// Obviously synthetic data for the widget picker and the debug gallery: 42 against a 55-70 band.
    static var effortTargetSample: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            recovery: 72, bpm: nil, batteryPct: nil, bonded: false, updated: now,
            effortTargetEffort: 42, effortTargetEffortText: "42",
            effortBandLow: 55, effortBandHigh: 70, effortBandText: "55\u{2013}70",
            effortToGo: "13\u{2013}28 to go",
            effortTargetDay: logicalDayKey(now), effortTargetAt: now)
    }
}
