import Foundation

extension Notification.Name {
    static let myDayOpen = Notification.Name("noop.myday.open")
}

/// Opens the Today tab on My Day: `noop://myday`, and PaceForge's "Open My Day" button. Held as `pending`
/// until the tab shell exists, so a cold launch from a link still lands there.
@MainActor
enum MyDayDeepLink {
    static var pending = false

    static func open() {
        pending = true
        NotificationCenter.default.post(name: .myDayOpen, object: nil)
    }
}
