import SwiftUI
import MarkdownUI
import StrandDesign

// Shared formatting and small building blocks for the PaceForge tab.

// RelativeDateTimeFormatter is not in the Linux Foundation, so this one stays out of PaceForgeFormat.swift.
extension PFFormat {
    /// "5 min ago" for an ISO-8601 timestamp; the raw text when it cannot be parsed.
    static func relative(_ timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        guard let when = isoWithFraction.date(from: timestamp) ?? isoPlain.date(from: timestamp)
                ?? isoLocalSeconds.date(from: timestamp) else { return timestamp }
        return RelativeDateTimeFormatter().localizedString(for: when, relativeTo: Date())
    }
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
                let _ = NoopDiag.body("PFCard")
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
            .lookCaps(11)
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
            .font(LookFont.text(15, weight: .medium))
            .foregroundStyle(NoopLook.textSecondary)
            .lineSpacing(2)
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
                    .font(LookFont.numeral(24))
                    .foregroundStyle(NoopLook.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(LookFont.text(12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
            }
            Text(label)
                .font(LookFont.text(12, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
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
            PFOfflineBannerText(text: text, detail: detail)
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

/// The banner's message and, under it, the failure detail.
private struct PFOfflineBannerText: View {
    let text: String
    let detail: String?

    var body: some View {
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

