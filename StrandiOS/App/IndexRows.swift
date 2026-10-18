#if os(iOS)
import SwiftUI
import StrandDesign

// The list idiom of the More tab (an UPPERCASE overline over one grouped card of rows, each row a navigation link that pushes a VALUE,
// so a re-tap of the tab can pop it off the bound path, #135/#198) and the section chips the Insights and Data screens switch with.

/// One titled group: the overline, then the rows in a single grouped card with hairline dividers.
struct IndexSection<Rows: View>: View {
    let title: LocalizedStringKey
    let rows: () -> Rows

    init(_ title: LocalizedStringKey, @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).strandOverline()
            // Zero internal padding so each row owns its own comfortable insets + height; the rows draw their own hairline
            // separators, and the clip trims the last one inside the card's rounded corners.
            NoopCard(padding: 0) {
                VStack(spacing: 0) { rows() }
                    .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            }
        }
    }
}

/// One tappable destination row: the SF Symbol in the accent, the title, a trailing chevron. ~44 pt minimum height.
struct IndexRow<Route: Hashable>: View {
    let title: LocalizedStringKey
    let icon: String
    let route: Route
    let identifier: String

    init(_ title: LocalizedStringKey, _ icon: String, _ route: Route, id: String) {
        self.title = title; self.icon = icon; self.route = route; self.identifier = id
    }

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                // Pin the icon to the accent explicitly. A plain inherited tint gets re-resolved by iOS to its default blue a
                // beat after first render, so the icons flashed green to blue (#184).
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(StrandPalette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// The sections of a screen as a wrapping grid of chips, one selected. Every chip is on screen at once (no sideways scroll to hunt
/// for one) and carries `<prefix>-<id>` as its identifier.
struct SectionChips<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let idPrefix: String
    let id: (Option) -> String
    let title: (Option) -> String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .lookCaps(12)
                        .foregroundStyle(isOn ? NoopLook.textPrimary : NoopLook.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isOn ? NoopLook.segmentOn : NoopLook.segmentOff))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(idPrefix)-\(id(option))")
            }
        }
    }
}
#endif
