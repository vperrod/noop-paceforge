#if !os(watchOS)
import SwiftUI

// MARK: - InsightCard
//
// Our explanation of a score, in a card with the coach-blue gradient border and a caps link underneath that
// opens the full breakdown. The text is NOOP's own sentence; the card only frames it.

/// The gradient-bordered frame itself, for insight-style cards whose content is more than a sentence and a link.
public struct InsightCardFrame<Content: View>: View {
    @ViewBuilder public var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.insightRadius - 1.5, style: .continuous)
                .fill(NoopLook.insightFill))
            .padding(1.5)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.insightRadius, style: .continuous)
                .fill(LinearGradient(colors: NoopLook.coachBorder, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

/// The caps link at the foot of an insight card ("BREAK DOWN MY CHARGE →"), in the coach gradient.
public struct InsightLink: View {
    public var title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title + " \u{2192}")
            .lookCaps(12.5)
            .foregroundStyle(LinearGradient(colors: NoopLook.coachLink, startPoint: .leading, endPoint: .trailing))
            .accessibilityAddTraits(.isLink)
    }
}

public struct InsightCard: View {
    public var text: String
    public var linkTitle: String?
    public var action: (() -> Void)?

    public init(_ text: String, linkTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.linkTitle = linkTitle
        self.action = action
    }

    public var body: some View {
        InsightCardFrame {
            Text(text)
                .font(LookFont.text(15.5, weight: .medium))
                .foregroundStyle(NoopLook.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let linkTitle {
                if let action {
                    Button(action: action) { InsightLink(linkTitle) }
                        .buttonStyle(.plain)
                } else {
                    InsightLink(linkTitle)
                }
            }
        }
    }
}

#if DEBUG
#Preview("InsightCard") {
    VStack(spacing: 14) {
        InsightCard("Your resting heart rate (59 bpm) is within its typical range of 58 to 62 bpm, and HRV is a little low, which gives a yellow Charge. A good day to stay active without a hard session.",
                    linkTitle: "Break down my Charge", action: {})
        InsightCard("Effort between 14.0 and 17.9 is strenuous.")
    }
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
