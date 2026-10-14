#if !os(watchOS)
import SwiftUI

// MARK: - ActivityPillRow
//
// One row of the day: a coloured pill with an icon and a figure (sleep hours, Effort), the activity name in
// caps, start and end times and a thin bar in the activity's colour. `ActivitiesCard` stacks the rows under
// a "Today's activities" header with the Add and Start buttons.

public struct ActivityPillItem: Identifiable, Equatable {
    public let id: String
    public var pillColor: Color
    public var icon: String
    public var pillText: String
    public var title: String
    public var startText: String?
    public var endText: String?
    public var barColor: Color?

    public init(id: String, pillColor: Color, icon: String, pillText: String, title: String,
                startText: String? = nil, endText: String? = nil, barColor: Color? = nil) {
        self.id = id
        self.pillColor = pillColor
        self.icon = icon
        self.pillText = pillText
        self.title = title
        self.startText = startText
        self.endText = endText
        self.barColor = barColor
    }
}

public struct ActivityPillRow: View {
    public var item: ActivityPillItem
    public var action: (() -> Void)?

    public init(_ item: ActivityPillItem, action: (() -> Void)? = nil) {
        self.item = item
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(item.pillText)
                    .font(LookFont.numeral(21))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.white)
            .frame(width: 88, height: 42)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(item.pillColor))
            Text(item.title)
                .lookCaps(13.5)
                .foregroundStyle(NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.startText != nil || item.endText != nil {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(item.startText ?? " ")
                    Text(item.endText ?? " ")
                }
                .font(LookFont.numeralRegular(11))
                .foregroundStyle(NoopLook.textSecondary)
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.barColor ?? NoopLook.textSecondary)
                .frame(width: 2, height: 26)
                .padding(.leading, 6)
                .accessibilityHidden(true)
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(item.title) \(item.pillText)"
        if let start = item.startText, let end = item.endText { text += ", \(start) to \(end)" }
        return text
    }
}

public struct ActivitiesCard: View {
    public var title: String
    public var items: [ActivityPillItem]
    public var onAdd: () -> Void
    public var onStart: () -> Void
    public var onOpen: ((ActivityPillItem) -> Void)?

    public init(title: String = "Today's activities", items: [ActivityPillItem], onAdd: @escaping () -> Void,
                onStart: @escaping () -> Void, onOpen: ((ActivityPillItem) -> Void)? = nil) {
        self.title = title
        self.items = items
        self.onAdd = onAdd
        self.onStart = onStart
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(title)
                    .lookCaps(12)
                    .foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 3)
            ForEach(items) { item in
                ActivityPillRow(item, action: onOpen == nil ? nil : { onOpen?(item) })
            }
            HStack(spacing: 10) {
                button("Add activity", symbol: "plus", action: onAdd)
                button("Start activity", symbol: "timer", action: onStart)
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                Text(title).lookCaps(12)
            }
            .foregroundStyle(NoopLook.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.row))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("ActivitiesCard") {
    ActivitiesCard(items: [
        ActivityPillItem(id: "sleep", pillColor: Color(hex: "#8FB0C9"), icon: "moon.fill", pillText: "6:20",
                         title: "Sleep", startText: "23:17", endText: "05:48", barColor: Color(hex: "#CFD6DC")),
        ActivityPillItem(id: "walk", pillColor: NoopLook.effort, icon: "figure.walk", pillText: "2.7",
                         title: "Walking", startText: "07:05", endText: "07:42", barColor: NoopLook.effort),
    ], onAdd: {}, onStart: {})
    .padding(16)
    .frame(width: 402)
    .lookScreenBackground()
    .preferredColorScheme(.dark)
}
#endif
#endif
