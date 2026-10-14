#if !os(watchOS)
import SwiftUI

// MARK: - RingDial
//
// A thin score dial: grey track, coloured arc from 12 o'clock, the number in the middle in the numeral face and,
// for Effort, a grey target arc with a white tick at its start. `.compact` is the Home row (92 pt in the
// reference, 5.5 pt stroke); `.hero` is the detail screen (272 pt, 11 pt stroke, wordmark on top and the dial
// name under the number). Geometry is a ratio of the diameter, so the dial scales to any width.

public struct RingDial: View {

    public enum Style: Equatable {
        case compact, hero

        /// Stroke width as a share of the diameter (5.5 / 92 and 11 / 272 in the reference).
        var strokeRatio: CGFloat { self == .compact ? 5.5 / 92 : 11 / 272 }
        /// Number size as a share of the diameter (30 / 92 and 74 / 272).
        var numberRatio: CGFloat { self == .compact ? 30 / 92 : 74 / 272 }
        /// Unit ("%") size as a share of the number.
        var unitRatio: CGFloat { self == .compact ? 19 / 30 : 42 / 74 }
    }

    public var fraction: Double
    public var color: Color
    public var valueText: String
    public var unitText: String?
    /// Target range as circle fractions; the tick sits at its start.
    public var target: (start: Double, end: Double)?
    public var diameter: CGFloat
    public var style: Style
    /// Hero only: the wordmark above the number (our own, "NOOP").
    public var wordmark: String?
    /// Hero only: the dial's name under the number ("CHARGE"); a second line is allowed ("REST" / "PERFORMANCE").
    public var titleLines: [String]
    /// Spoken name, e.g. "Charge".
    public var accessibilityName: String

    public init(fraction: Double, color: Color, valueText: String, unitText: String? = nil,
                target: (start: Double, end: Double)? = nil, diameter: CGFloat, style: Style = .compact,
                wordmark: String? = nil, titleLines: [String] = [], accessibilityName: String) {
        self.fraction = fraction
        self.color = color
        self.valueText = valueText
        self.unitText = unitText
        self.target = target
        self.diameter = diameter
        self.style = style
        self.wordmark = wordmark
        self.titleLines = titleLines
        self.accessibilityName = accessibilityName
    }

    private var stroke: CGFloat { diameter * style.strokeRatio }
    /// Centre-line inset: the ring sits 4/46 (compact) of the radius inside the box, as in the reference.
    private var inset: CGFloat { diameter * 0.0435 }
    private var radius: CGFloat { diameter / 2 - inset }
    private var clamped: Double { min(max(fraction, 0), 1) }

    public var body: some View {
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(NoopLook.track, lineWidth: stroke)
            targetArc
            if clamped > 0 {
                Circle()
                    .inset(by: inset)
                    .trim(from: 0, to: CGFloat(clamped))
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            targetTick
            center
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName) \(valueText)\(unitText ?? "")")
    }

    @ViewBuilder private var targetArc: some View {
        if let target {
            Circle()
                .inset(by: inset)
                .trim(from: CGFloat(target.start), to: CGFloat(target.end))
                .stroke(Color(hex: "#5A6067"), style: StrokeStyle(lineWidth: stroke, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }

    @ViewBuilder private var targetTick: some View {
        if let target {
            Capsule()
                .fill(Color.white)
                .frame(width: max(stroke * 0.4, 2), height: stroke * 1.6)
                .offset(y: -radius)
                .rotationEffect(.degrees(LookDial.degrees(forFraction: target.start)))
        }
    }

    private var numberSize: CGFloat { diameter * style.numberRatio }

    private var center: some View {
        VStack(spacing: 0) {
            if style == .hero, let wordmark {
                Text(wordmark)
                    .font(LookFont.text(diameter * 20 / 272, weight: .light))
                    .tracking(diameter * 1.5 / 272 * 2)
                    .foregroundStyle(NoopLook.textPrimary.opacity(0.9))
                    .padding(.bottom, diameter * 22 / 272)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(valueText)
                    .font(LookFont.numeral(numberSize))
                    .foregroundStyle(NoopLook.textPrimary)
                if let unitText {
                    Text(unitText)
                        .font(LookFont.numeral(numberSize * style.unitRatio))
                        .foregroundStyle(NoopLook.textPrimary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            ForEach(Array(titleLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .lookCaps(diameter * 14 / 272)
                    .foregroundStyle(NoopLook.textPrimary)
            }
        }
        .padding(.horizontal, stroke + 2)
        .offset(y: style == .hero ? -diameter * 0.02 : 0)
    }
}

#if DEBUG
#Preview("RingDial") {
    VStack(spacing: 24) {
        HStack(alignment: .top, spacing: 16) {
            RingDial(fraction: 0.73, color: NoopLook.rest, valueText: "73", unitText: "%", diameter: 92,
                     accessibilityName: "Rest")
            RingDial(fraction: 0.23, color: NoopLook.chargeColor(23), valueText: "23", unitText: "%", diameter: 92,
                     accessibilityName: "Charge")
            RingDial(fraction: 0.13, color: NoopLook.effort, valueText: "2.7",
                     target: LookDial.targetArc(low: 13.2, high: 16.5, max: 21), diameter: 92,
                     accessibilityName: "Effort")
        }
        RingDial(fraction: 0.55, color: NoopLook.chargeColor(55), valueText: "55", unitText: "%", diameter: 272,
                 style: .hero, wordmark: "NOOP", titleLines: ["CHARGE"], accessibilityName: "Charge")
        RingDial(fraction: 0.67, color: NoopLook.effort, valueText: "14.2", diameter: 272, style: .hero,
                 wordmark: "NOOP", titleLines: ["EFFORT"], accessibilityName: "Effort")
    }
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
