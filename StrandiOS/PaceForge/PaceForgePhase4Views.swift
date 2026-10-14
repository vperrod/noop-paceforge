import SwiftUI
import StrandDesign

// The shared frame of the Phase 4 screens (Highlights, Healthspan, Journal impact, Monthly report): one scrolling dark screen
// that refreshes the shared store, and one view that turns a document's state into either the screen's content, the server's own
// reason when the document is unavailable, or a quiet note when it was not served. Nothing here scores or stores anything.

/// A dark scrolling screen for one of the Phase 4 documents.
struct PFDocScreen<Content: View>: View {
    let title: String
    let identifier: String
    @ViewBuilder let content: () -> Content
    @ObservedObject private var store = PFPhase4Store.shared

    init(title: String, identifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .lookScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(identifier)
        .task { await store.refreshIfStale() }
    }
}

/// A document as content, the server's reason, or a note that it was not served.
struct PFDocStateView<T: Equatable, Content: View>: View {
    let state: PFDocState<T>
    let didLoad: Bool
    let title: String
    let icon: String
    let identifier: String
    let content: (T, PFIntelItem) -> Content

    init(state: PFDocState<T>, didLoad: Bool, title: String, icon: String, identifier: String,
         @ViewBuilder content: @escaping (T, PFIntelItem) -> Content) {
        self.state = state
        self.didLoad = didLoad
        self.title = title
        self.icon = icon
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        switch state {
        case .ready(let value, let item):
            content(value, item)
        case .unavailable(let reason, _):
            PFIntelNote(title: title, icon: icon, text: reason ?? "Not available yet.", identifier: "\(identifier)-unavailable")
        case .missing:
            if didLoad {
                PFIntelNote(title: title, icon: icon,
                            text: "\(title) needs PaceForge. It is not reachable or has not published this yet.",
                            identifier: "\(identifier)-empty")
            } else {
                Text("Reading \(title.lowercased())")
                    .font(LookFont.text(15, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
    }
}

/// A caps label with a hairline running to the right edge ("STREAKS", "NOTABLE STATS").
struct PFRuleLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lookCaps(12)
                .tracking(1.4)
                .foregroundStyle(NoopLook.textSecondary)
            Rectangle().fill(NoopLook.divider).frame(height: 1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A round badge with a dashed ring and an SF Symbol inside, the streak and notable-stat badge.
struct PFBadgeIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 46
    var isDimmed = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(isDimmed ? 0.35 : 1), style: StrokeStyle(lineWidth: 1.6, dash: [3.5, 3]))
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color.opacity(isDimmed ? 0.45 : 1))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A source label next to a figure: "NOOP", "GARMIN", "PACEFORGE". Never blended into one number.
struct PFSourceTag: View {
    let source: String?

    var body: some View {
        if let source, !source.isEmpty {
            Text(source == "NOOP" ? "NOOP STRAP" : source.uppercased())
                .lookCaps(9.5)
                .foregroundStyle(NoopLook.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NoopLook.row))
                .accessibilityLabel("Source \(source)")
        }
    }
}
