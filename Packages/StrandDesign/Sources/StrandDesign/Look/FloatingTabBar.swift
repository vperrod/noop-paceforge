#if !os(watchOS)
import SwiftUI

// MARK: - FloatingTabBar
//
// The rounded bar that floats over the screen with the coach button beside it. It is a plain control over a
// list of tabs and a binding to the selected id; wiring it into the app shell is a separate step.

public struct LookTabItem: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var symbol: String

    public init(id: String, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

public struct FloatingTabBar: View {
    public var items: [LookTabItem]
    @Binding public var selection: String
    public var onCoach: () -> Void

    public init(items: [LookTabItem], selection: Binding<String>, onCoach: @escaping () -> Void) {
        self.items = items
        self._selection = selection
        self.onCoach = onCoach
    }

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(items) { item in tab(item) }
            }
            .padding(.horizontal, 6)
            .frame(height: NoopLook.Metric.tabBarHeight)
            .background(Capsule(style: .continuous).fill(Color(light: "#FFFFFF", dark: "#2C3035").opacity(0.94)))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
            coachButton
        }
        .padding(.horizontal, NoopLook.Metric.screenInset)
    }

    private func tab(_ item: LookTabItem) -> some View {
        let isOn = item.id == selection
        return Button { selection = item.id } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .regular))
                Text(item.title)
                    .font(LookFont.text(11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isOn ? NoopLook.textPrimary : NoopLook.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: NoopLook.Metric.tabBarHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("look-tab-\(item.id)")
    }

    private var coachButton: some View {
        Button(action: onCoach) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(RadialGradient(colors: NoopLook.coachButtonFill, center: .center, startRadius: 0, endRadius: 44))
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NoopLook.coachButtonRing.opacity(0.25), lineWidth: 1)
                Circle()
                    .strokeBorder(NoopLook.coachButtonRing, lineWidth: 2)
                    .frame(width: 34, height: 34)
                Text("N")
                    .font(LookFont.text(14, weight: .bold))
                    .foregroundStyle(Color(hex: "#DFE4FF"))
            }
            .frame(width: 64, height: NoopLook.Metric.tabBarHeight)
        }
        .buttonStyle(.plain)
        // NOOP's own Coach, so it is told apart from PaceForge's Coach segment in the PaceForge tab.
        .accessibilityLabel("NOOP Coach")
        .accessibilityIdentifier("look-coach")
    }
}

#if DEBUG
private struct FloatingTabBarPreviewHost: View {
    @State private var selection = "home"

    var body: some View {
        FloatingTabBar(items: [
            LookTabItem(id: "home", title: "Home", symbol: "house"),
            LookTabItem(id: "health", title: "Health", symbol: "heart"),
            LookTabItem(id: "paceforge", title: "PaceForge", symbol: "figure.run"),
            LookTabItem(id: "more", title: "More", symbol: "line.3.horizontal"),
        ], selection: $selection, onCoach: {})
    }
}

#Preview("FloatingTabBar") {
    FloatingTabBarPreviewHost()
        .frame(width: 402, height: 120)
        .lookScreenBackground()
        .preferredColorScheme(.dark)
}
#endif
#endif
