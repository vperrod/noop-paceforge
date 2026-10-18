import SwiftUI
import StrandDesign

// Customising the order of the PaceForge Today cards on the phone: the store for the phone's own arrangement and
// the Up / Down / Pin bar shown over each card while Customise is on. The ordering rules are in
// PaceForgeTodayLayout.swift (unit-tested). The app cannot write PaceForge's own layout (its token may only log
// measurements), so the arrangement lives in UserDefaults and replaces the server's while it exists.

/// The phone's own Today arrangement. A UI-test fixture starts empty on every launch and never touches the real one.
/// Deliberately not `@MainActor`: it is only called from view code, and the closures that call it (the Up / Down /
/// Pin handlers) are plain function values that do not all carry the main actor.
final class PFTodayLayoutStore: ObservableObject {
    static let shared = PFTodayLayoutStore()

    /// nil: nothing arranged on this iPhone, so PaceForge's layout (or the default order) applies.
    @Published private(set) var local: PFTodayLayout?
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if !PFAPI.usesPhoneState, let suite = UserDefaults(suiteName: "noop.paceforge.todayLayout.fixture") {
            suite.removePersistentDomain(forName: "noop.paceforge.todayLayout.fixture")
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
        local = PFTodayLayoutStorage.load(defaults: self.defaults)
    }

    /// The layout in force: this iPhone's own arrangement, else the server's.
    func layout(server: PFTodayLayout) -> PFTodayLayout {
        PFTodayOrder.effective(local: local, server: server)
    }

    func set(_ layout: PFTodayLayout) {
        local = layout
        PFTodayLayoutStorage.save(layout, defaults: defaults)
    }

    /// Back to PaceForge's own order.
    func reset() {
        local = nil
        PFTodayLayoutStorage.save(nil, defaults: defaults)
    }
}

/// The Customise row at the top of Today: the toggle, and while it is on, what it does and how to undo it.
struct PFTodayCustomiseHeader: View {
    @Binding var isArranging: Bool
    let hasLocalOrder: Bool
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Button(isArranging ? "Done" : "Customise") { isArranging.toggle() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(StrandPalette.accent)
                    .accessibilityIdentifier("pf-today-customise")
            }
            if isArranging {
                PFParagraph("Move cards up or down and pin the ones you want first. The order is saved on this iPhone only: the app cannot change PaceForge's own order, which you set on its web page. Until you change something here, the web page's order is used.")
                    .accessibilityIdentifier("pf-today-customise-help")
                if hasLocalOrder {
                    Button("Use PaceForge's order again", action: onReset)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(StrandPalette.accent)
                        .accessibilityIdentifier("pf-today-customise-reset")
                }
            }
        }
    }
}

/// Up, Down and Pin for one card.
struct PFArrangeBar: View {
    let card: PFTodayCard
    let isPinned: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onPin: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(card.title).strandOverline()
            Spacer(minLength: 8)
            Button(action: onUp) { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp)
                .accessibilityLabel("Move \(card.title) up")
                .accessibilityIdentifier("pf-arrange-up-\(card.rawValue)")
            Button(action: onDown) { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown)
                .accessibilityLabel("Move \(card.title) down")
                .accessibilityIdentifier("pf-arrange-down-\(card.rawValue)")
            Button(action: onPin) { Image(systemName: isPinned ? "pin.fill" : "pin") }
                .accessibilityLabel(isPinned ? "Unpin \(card.title)" : "Pin \(card.title) to the top")
                .accessibilityIdentifier("pf-arrange-pin-\(card.rawValue)")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(StrandPalette.accent)
    }
}
