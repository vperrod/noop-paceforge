import SwiftUI
import StrandDesign

/// Where the Coach was opened from ("Asked from Train > HYROX"), set when the Coach sheet opens over a tab. The Ask composer shows it as a
/// small removable chip and, while it stays, puts it in front of the question it sends (part of the message text; the server is unchanged).
@MainActor
final class PFCoachContext: ObservableObject {
    static let shared = PFCoachContext()

    @Published var line: String?

    /// "Train > HYROX" for the tab on show and the chip it keeps, "Today" for a tab with no chips.
    static func screen(tab: Int) -> String {
        let defaults = UserDefaults.standard
        switch tab {
        case 1:
            let chip = CalendarChip(stored: defaults.string(forKey: CalendarChip.storageKey)) ?? .week
            return "Plan > \(chip.title)"
        case 2:
            let chip = TrainChip(rawValue: defaults.string(forKey: TrainChip.storageKey) ?? "") ?? .hyrox
            return "Train > \(chip.title)"
        case 3:
            let chip = HealthChip(rawValue: defaults.string(forKey: HealthChip.storageKey) ?? "") ?? .day
            return "Health > \(chip.title)"
        default:
            return "Today"
        }
    }

    func set(fromTab tab: Int) { line = "Asked from \(Self.screen(tab: tab))" }

    /// The question with the context in front of it; the question alone once the chip is removed.
    func wrap(_ message: String) -> String {
        guard let line else { return message }
        return "[\(line)] \(message)"
    }
}

/// The chip above the composer: the context, and a button that removes it.
struct PFCoachContextChip: View {
    @ObservedObject private var context = PFCoachContext.shared

    var body: some View {
        if let line = context.line {
            HStack(spacing: 6) {
                Text(line).font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary).lineLimit(1)
                Button { context.line = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(StrandPalette.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove the context")
                .accessibilityIdentifier("pf-coach-context-remove")
            }
            .padding(.leading, 12)
            .background(Capsule().fill(StrandPalette.surfaceInset))
            .accessibilityIdentifier("pf-coach-context")
        }
    }
}
