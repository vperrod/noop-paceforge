import SwiftUI
import StrandDesign

// Shared formatting and small building blocks for the PaceForge tab.

enum PFFormat {
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dayName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f
    }()

    static func date(_ iso: String) -> Date {
        isoDay.date(from: String(iso.prefix(10))) ?? Date(timeIntervalSince1970: 0)
    }
    static func dayTitle(_ iso: String) -> String { dayName.string(from: date(iso)) }
    static func shortDate(_ iso: String) -> String { shortDay.string(from: date(iso)) }

    /// "5–11 Oct" for a Monday-to-Sunday span inside one month, otherwise "28 Sep – 4 Oct".
    static func span(_ start: String, _ end: String) -> String {
        let cal = Calendar(identifier: .gregorian)
        let s = date(start), e = date(end)
        if cal.component(.month, from: s) == cal.component(.month, from: e) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "MMM"
            return "\(cal.component(.day, from: s))\u{2013}\(cal.component(.day, from: e)) \(f.string(from: e))"
        }
        return "\(shortDate(start)) \u{2013} \(shortDate(end))"
    }

    /// sec/km as m:ss.
    static func pace(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 6382 -> 1:46:22
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    static func trimmed(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : oneDecimal(v)
    }

    static func capitalized(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }

    static func words(_ snake: String) -> String { snake.replacingOccurrences(of: "_", with: " ") }
}

enum PFColor {
    // Computed: the palette's status colours follow the user's chart-style preference.
    static var positive: Color { StrandPalette.statusPositive }
    static var warning: Color { StrandPalette.statusWarning }
    static var critical: Color { StrandPalette.statusCritical }
    static let violet = Color(hex: "#9B7BFF")
    static var sky: Color { StrandPalette.restColor }

    static func workout(_ kind: String?) -> Color {
        switch kind ?? "" {
        case "easy_run", "recovery_run", "easy_with_strides", "bike_recovery":
            return positive
        case "tempo", "threshold", "race_pace":
            return warning
        case "intervals", "speed", "vo2max", "fartlek", "hills", "strides":
            return critical
        case "cross_training", "hyrox_mixed", "hyrox_station_day", "hyrox_simulation",
             "class_session", "strength", "brick":
            return violet
        case "rest":
            return StrandPalette.textTertiary
        default:
            return sky
        }
    }

    static func status(_ status: String) -> Color {
        switch status {
        case "done": return positive
        case "partial": return warning
        case "missed": return critical
        default: return StrandPalette.textTertiary
        }
    }
}

/// A titled card, the one container every PaceForge screen is built from.
struct PFCard<Content: View, Trailing: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        StrandCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                    }
                    Text(title)
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer(minLength: 8)
                    trailing()
                }
                content()
            }
        }
    }
}

extension PFCard where Trailing == EmptyView {
    init(_ title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, trailing: { EmptyView() }, content: content)
    }
}

/// A small coloured pill, e.g. "done", "31 days", "Readiness 81 . green".
struct PFChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(StrandFont.overline)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
            .overlay(Capsule(style: .continuous).stroke(color.opacity(0.3), lineWidth: 1))
    }
}

/// A body-text paragraph in the secondary colour.
struct PFParagraph: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An overline label above a block of text.
struct PFLabeled: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).strandOverline()
            PFParagraph(text)
        }
    }
}

/// The "Preview . data from 11 Oct" caption every screen carries.
struct PFPreviewLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(StrandFont.footnote)
        }
        .foregroundStyle(StrandPalette.textTertiary)
        .accessibilityIdentifier("pf-preview-label")
    }
}

/// A key figure with a caption underneath.
struct PFFigure: View {
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(StrandFont.rounded(24))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Text(label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
