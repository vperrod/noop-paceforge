import SwiftUI

// MARK: - NoopLook: the dark "look" tokens
//
// One place for the colours, type and surfaces of the new look. Dark is the default on iPhone and light is
// chosen in Settings, so every surface and text token is a dynamic `Color(light:dark:)` that re-resolves
// when the scheme flips; the DATA colours (bands, effort blue, rest blue-grey, stage and zone colours) are
// the same in both schemes because they carry meaning.
//
// Names are NOOP's own: Charge / Effort / Rest. Nothing here is a brand asset; the values are plain colours.

public enum NoopLook {

    /// The raw hex values, so a token that must stay a `String` (NoopVisualStyle's dynamic colours) can share them.
    public enum Hex {
        // Screen backgrounds: standard and alternate (cards) dark.
        public static let bgStd = "#101518"
        public static let bgAlt = "#1A2227"
        /// Legacy card fill on iPhone dark: a step lighter than the gradient's top so cards read at the top edge.
        public static let surface = "#222B31"
        public static let surfaceTop = "#283239"
        public static let inset = "#151B1F"
        public static let border = "#2A3339"
        public static let borderHighlight = "#35404A"

        // Charge bands.
        public static let chargeHigh = "#19EC06"
        public static let chargeMedium = "#FFDE00"
        public static let chargeLow = "#FF0026"

        public static let effort = "#0093E7"
        public static let rest = "#7BA1BB"

        public static let trendUp = "#00F19F"
        public static let trendDown = "#FFA722"
        public static let sufficient = "#6BBCC1"
        public static let alert = "#FF0026"

        public static let awake = "#C8C8C8"
        public static let light = "#A4A3F1"
        public static let deep = "#FA95FA"
        public static let rem = "#AC5AED"

        public static let zone1 = "#ADC2CD"
        public static let zone2 = "#479AC2"
        public static let zone3 = "#59B996"
        public static let zone4 = "#FCAC5D"
        public static let zone5 = "#FF6422"

        public static let coachBlue = "#6E9CFF"
    }

    // MARK: Screen and surfaces

    /// Top and bottom of the screen gradient (dark #1A2227 down to #101518; light stays a quiet grey).
    public static let screenTop = Color(light: "#F6F8FB", dark: Hex.bgAlt)
    public static let screenBottom = Color(light: "#E9EDF2", dark: Hex.bgStd)

    /// Monitor tile / small card on the gradient.
    public static let tile = Color(light: "#FFFFFF", dark: "#313438")
    /// A row sitting on a tile or card (activity row, button).
    public static let row = Color(light: "#EEF1F5", dark: "#3A3F45")
    /// The card behind the "today vs. last 30 days" rows and the sleep detail.
    public static let card = Color(light: "#FFFFFF", dark: "#2B2F34")
    /// Inside the gradient border of an insight card.
    public static let insightFill = Color(light: "#FFFFFF", dark: "#1B1F26")
    /// The deepest card (the "What is it?" card, the legend strip).
    public static let cardDeep = Color(light: "#E4E8EE", dark: "#14181B")
    /// Empty part of a ring, track and bar.
    public static let track = Color(light: "#DDE2E8", dark: "#373C40")
    public static let divider = Color(light: "#D8DEE5", dark: "#3A3F45")
    /// The thin daily line on a trend chart (dim blue-grey so the monthly averages stand out).
    public static let trendLine = Color(light: "#8FA3B5", dark: "#3D5468")
    /// Diagonal hatching on an empty stage track.
    public static let hatch = Color(light: "#C9D0D8", dark: "#3F454B")
    /// The pill that holds the selected segment in a W / M / 6M control.
    public static let segmentOn = Color(light: "#FFFFFF", dark: "#393D46")
    public static let segmentOff = Color(light: "#DDE2E8", dark: "#1C2023")

    // MARK: Text

    public static let textPrimary = Color(light: "#10181F", dark: "#FFFFFF")
    public static let textSecondary = Color(light: "#4A5560", dark: "#B0B5BA")
    public static let textTertiary = Color(light: "#6F7A86", dark: "#8A9097")
    public static let textMuted = Color(light: "#8C96A1", dark: "#5D6369")

    // MARK: Data colours (same in both schemes)

    public static let chargeHigh = Color(hex: Hex.chargeHigh)
    public static let chargeMedium = Color(hex: Hex.chargeMedium)
    public static let chargeLow = Color(hex: Hex.chargeLow)
    public static let effort = Color(hex: Hex.effort)
    public static let rest = Color(hex: Hex.rest)
    public static let trendUp = Color(hex: Hex.trendUp)
    public static let trendDown = Color(hex: Hex.trendDown)
    public static let sufficient = Color(hex: Hex.sufficient)
    public static let alert = Color(hex: Hex.alert)
    /// Background of an alert badge (dark red wash).
    public static let alertWash = Color(light: "#FBE3E6", dark: "#4A1F26")
    /// "Stress medium" mint (the reference's medium reading).
    public static let stressMedium = Color(hex: "#76F0A7")

    public static let stageAwake = Color(hex: Hex.awake)
    public static let stageLight = Color(hex: Hex.light)
    public static let stageDeep = Color(hex: Hex.deep)
    public static let stageRem = Color(hex: Hex.rem)

    public static let zones: [Color] = [
        Color(hex: Hex.zone1), Color(hex: Hex.zone2), Color(hex: Hex.zone3), Color(hex: Hex.zone4), Color(hex: Hex.zone5),
    ]

    /// Colour for a Charge band (hard bands at 67 and 34, see `LookBand`).
    public static func color(for band: LookBand) -> Color {
        switch band {
        case .high: return chargeHigh
        case .medium: return chargeMedium
        case .low: return chargeLow
        }
    }

    /// Colour of a Charge score, banded on its rounded value.
    public static func chargeColor(_ score: Double) -> Color { color(for: LookBand.forScore(score)) }

    /// Trend triangle / chip colour.
    public static func color(forTone tone: LookChip.Tone) -> Color {
        switch tone {
        case .positive: return trendUp
        case .negative: return trendDown
        case .neutral: return textTertiary
        }
    }

    public static func color(forTone tone: LookTodayMark.Tone) -> Color {
        switch tone {
        case .favourable: return trendUp
        case .unfavourable: return trendDown
        case .neutral: return textTertiary
        }
    }

    /// Poor / Sufficient / Optimal step colours.
    public static func color(for step: LookStep) -> Color {
        switch step {
        case .poor: return trendDown
        case .sufficient: return textTertiary
        case .optimal: return trendUp
        }
    }

    public static func color(for level: LookStressLevel) -> Color {
        switch level {
        case .low: return sufficient
        case .medium: return stressMedium
        case .high: return trendDown
        }
    }

    // MARK: Coach gradient (insight card border, link text, coach button)

    public static let coachBorder: [Color] = [Color(hex: "#7B5CFF"), Color(hex: "#4F7DFF"), Color(hex: "#6E9CFF")]
    public static let coachLink: [Color] = [Color(hex: "#9B7BFF"), Color(hex: "#6AA2FF")]
    public static let coachButtonFill: [Color] = [Color(hex: "#2F3557"), Color(hex: "#20243A"), Color(hex: "#1B1E2C")]
    public static let coachButtonRing = Color(hex: "#8F9CFF")

    /// The "Daily Outlook" bar gradient (warm left to cool right).
    public static let outlookBar: [Color] = [Color(hex: "#77705F"), Color(hex: "#5B5A52"), Color(hex: "#3A4656")]

    // MARK: Geometry (points, from the 402-wide reference)

    public enum Metric {
        public static let screenInset: CGFloat = 16
        public static let tileRadius: CGFloat = 12
        public static let rowRadius: CGFloat = 10
        public static let insightRadius: CGFloat = 14
        public static let dialStroke: CGFloat = 5.5 / 92      // share of the dial diameter
        public static let heroStroke: CGFloat = 11 / 272
        public static let tabBarHeight: CGFloat = 64
    }
}

// MARK: - Screen background

public extension View {
    /// The look's screen gradient behind the whole view, extending under the status bar.
    func lookScreenBackground() -> some View {
        background(
            LinearGradient(colors: [NoopLook.screenTop, NoopLook.screenBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

/// The look's screen gradient as a standalone view (ScreenScaffold draws it as its canvas on iPhone).
public struct LookScreenGradient: View {
    public init() {}

    public var body: some View {
        LinearGradient(colors: [NoopLook.screenTop, NoopLook.screenBottom], startPoint: .top, endPoint: .bottom)
    }
}
