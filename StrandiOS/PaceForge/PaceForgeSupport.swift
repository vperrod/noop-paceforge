import SwiftUI
import MarkdownUI
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

    private static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()

    static func isoString(_ date: Date) -> String { isoDay.string(from: date) }

    static func addDays(_ iso: String, _ days: Int) -> String {
        let shifted = gregorian.date(byAdding: .day, value: days, to: date(iso)) ?? date(iso)
        return isoString(shifted)
    }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        gregorian.dateComponents([.day], from: date(from), to: date(to)).day ?? 0
    }

    /// The Monday of the week containing `iso`.
    static func monday(of iso: String) -> String {
        let weekday = gregorian.component(.weekday, from: date(iso))   // 1 = Sunday
        return addDays(iso, -((weekday + 5) % 7))
    }

    /// ISO week key as PaceForge writes it, e.g. "2026-W41".
    static func isoWeekKey(_ iso: String) -> String {
        let cal = Calendar(identifier: .iso8601)
        let parts = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date(iso))
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// "5 min ago" for an ISO-8601 timestamp; the raw text when it cannot be parsed.
    static func relative(_ timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let when = formatter.date(from: timestamp) ?? plain.date(from: timestamp)
                ?? isoLocalSeconds.date(from: timestamp) else { return timestamp }
        return RelativeDateTimeFormatter().localizedString(for: when, relativeTo: Date())
    }

    /// "08:12" for an ISO-8601 timestamp, in the phone's time zone; a timestamp with no zone is read as
    /// local. nil when it cannot be parsed.
    static func timeOfDay(_ timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let when = withFraction.date(from: timestamp) ?? plain.date(from: timestamp)
                ?? isoLocalSeconds.date(from: timestamp) else { return nil }
        return clockMinutes.string(from: when)
    }

    private static let clockMinutes: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let isoLocalSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

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
    /// A metric-explainer id: the card then shows an (i) that opens "how it works" when the server has one.
    var info: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    /// The look's card: a 12 pt tile on the dark gradient, a small caps title, content below. Every PaceForge
    /// screen builds on it, so this is the one place its card style lives.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                }
                Text(title)
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                trailing()
                if let info { PFInfoButton(id: info) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }
}

extension PFCard where Trailing == EmptyView {
    init(_ title: String, icon: String? = nil, info: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, info: info, trailing: { EmptyView() }, content: content)
    }
}

/// A small coloured pill, e.g. "done", "31 days", "Readiness 81 . green".
struct PFChip: View {
    let text: String
    let color: Color
    private let hiding = PFHiding()

    var body: some View {
        Text(hiding.text(text))
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
    private let hiding = PFHiding()
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(hiding.text(text))
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

// MARK: Load states

struct PFLoadingView: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading PaceForge")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .accessibilityIdentifier("pf-loading")
    }
}

struct PFNotSetUpView: View {
    var body: some View {
        PFCard("PaceForge sync not set up", icon: "link.badge.plus") {
            VStack(alignment: .leading, spacing: 10) {
                PFParagraph("Add your PaceForge endpoint and bearer token in More \u{203A} PaceForge sync, then come back here. NOOP reads your plan, briefing, body scale and session results straight from your PaceForge server.")
            }
        }
        .accessibilityIdentifier("pf-not-set-up")
    }
}

struct PFFailedView: View {
    let message: String
    let detail: String?
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        PFCard(message, icon: "wifi.exclamationmark") {
            VStack(alignment: .leading, spacing: 12) {
                PFParagraph("Check that you are online and that your PaceForge server is running, then try again.")
                if let detail {
                    Text(detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("pf-failed-detail")
                }
                Button(action: retry) {
                    Text(isRetrying ? "Trying" : "Retry")
                        .font(StrandFont.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(isRetrying)
                .accessibilityIdentifier("pf-retry")
            }
        }
        .accessibilityIdentifier("pf-failed")
    }
}

/// Shown above a screen that is displaying saved data because the last refresh failed.
struct PFOfflineBanner: View {
    let text: String
    let detail: String?
    let isRetrying: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(PFColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Button(isRetrying ? "Trying" : "Retry", action: retry)
                .font(StrandFont.caption.weight(.semibold))
                .disabled(isRetrying)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PFColor.warning.opacity(0.12)))
        .accessibilityIdentifier("pf-offline-banner")
    }
}

/// A small dimmed label above content that is not from today.
struct PFStaleLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
    }
}

/// Renders markdown text (the coach's analysis, the briefing sections) in the app's look.
struct PFMarkdown: View {
    let text: String
    private let hiding = PFHiding()

    var body: some View {
        Markdown(hiding.text(text))
            .markdownTheme(.strand)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

