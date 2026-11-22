import SwiftUI
import StrandDesign

// The reading rules of the Plan screens (build 543). Every text size follows the phone's text setting (a size maps to a Dynamic Type style,
// never under 15 points), a badge always says its state in words, a button is at least 44 points tall and wraps instead of shrinking.
// Test it at the largest setting: the previews at the bottom of PFSessionScreen543.swift and PFWeekRows543.swift run at accessibility5.

enum PFPlanFont543 {
    /// The size a design asked for, as a Dynamic Type style. `LookFont.text` is fixed size; this is the Plan section's replacement for it.
    static func text(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(textStyle(forSize: size)).weight(weight)
    }

    static func textStyle(forSize size: CGFloat) -> Font.TextStyle {
        switch PFPlanTextStyle543.style(forSize: Double(size)) {
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .body: return .body
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title
        }
    }
}

extension View {
    /// A caps label in the Plan's scaling font.
    func pfCaps(_ size: CGFloat = 13, weight: Font.Weight = .bold) -> some View {
        self.font(PFPlanFont543.text(size, weight: weight))
            .tracking(max(size, 15) * 0.06)
            .textCase(.uppercase)
    }
}

// MARK: Badges

enum PFPlanBadgeStyle543 {
    static func color(_ tone: PFPlanBadge543.Tone) -> Color {
        switch tone {
        case .coach, .required: return PFColor.violet
        case .mine, .todo: return NoopLook.textSecondary
        case .classTone, .moved, .reassessing: return PFWeekColor529.blue
        case .draft, .needsYou, .overlap, .skipped: return PFWeekColor529.amber
        case .done: return PFWeekColor529.teal
        }
    }

    /// A symbol beside the words, so the state is never colour alone (and never a symbol alone either).
    static func symbol(_ tone: PFPlanBadge543.Tone) -> String {
        switch tone {
        case .coach: return "person.crop.circle"
        case .mine: return "person"
        case .classTone: return "person.3"
        case .draft: return "pencil"
        case .required: return "exclamationmark.circle"
        case .todo: return "circle"
        case .done: return "checkmark.circle.fill"
        case .moved: return "arrow.right.circle"
        case .skipped: return "xmark.circle"
        case .reassessing: return "arrow.triangle.2.circlepath"
        case .needsYou: return "questionmark.circle"
        case .overlap: return "square.on.square"
        }
    }
}

/// One badge: a coloured symbol and the words in the primary text colour, wrapping onto a second line when the text is large.
struct PFPlanBadgeView543: View {
    let badge: PFPlanBadge543

    var body: some View {
        let color = PFPlanBadgeStyle543.color(badge.tone)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: PFPlanBadgeStyle543.symbol(badge.tone))
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(badge.text)
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(color.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(color.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.text)
    }
}

/// A wrapping row of badges.
struct PFPlanBadgeRow543: View {
    let badges: [PFPlanBadge543]

    var body: some View {
        LookFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in PFPlanBadgeView543(badge: badge) }
        }
    }
}

// MARK: Buttons and fields

/// A full-width button of the Plan screens: at least 44 points tall, the label wraps, nothing shrinks.
struct PFPlanButton543: View {
    let title: String
    var isProminent = false
    var isDisabled = false
    var systemImage: String? = nil
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(title)
                    .font(PFPlanFont543.text(16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isProminent ? Color(hex: "#06231A") : NoopLook.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isProminent ? PFWeekColor529.teal : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isProminent ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityIdentifier(identifier)
    }
}

/// A chip you tap to choose: the chosen one is filled and says "selected" to VoiceOver.
struct PFPlanChoiceChip543: View {
    let title: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(title)
                    .font(PFPlanFont543.text(16, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? Color(hex: "#06231A") : NoopLook.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? PFWeekColor529.teal : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier(identifier)
    }
}

/// The tint a coach session's card edge and row accent take: purple, as the design says.
enum PFPlanCoachEdge543 {
    static let color = PFColor.violet
}
