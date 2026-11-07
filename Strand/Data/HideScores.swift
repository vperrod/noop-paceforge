import Foundation

// Hide scores: two switches in Settings that blank the numbers the person would rather not have on screen when
// someone else can see it. One covers the three daily scores (Charge, Effort, Rest, Sleep on the PaceForge tab);
// the other covers body weight and body fat. A hidden value reads "Hidden" in its place. Nothing stored changes:
// only what Today and the PaceForge tab draw. Foundation only, so the key lists are unit-tested.

enum HideScoresKind: Equatable {
    /// Charge, Effort and Rest (Sleep on the PaceForge tab).
    case scores
    /// Body weight and body fat.
    case body
}

enum HideScoresPrefs {
    static let scoresKey = "noop.hide.scores"
    static let bodyKey = "noop.hide.body"
    static let placeholder = "Hidden"

    /// The metric-catalog keys that are the three daily scores: Charge, Effort and Rest.
    static let scoreMetricKeys: Set<String> = ["recovery", "strain", "sleep_performance"]
    /// The metric-catalog keys that are body composition.
    static let bodyMetricKeys: Set<String> = ["weight", "body_fat"]

    static func kind(forMetricKey key: String?) -> HideScoresKind? {
        guard let key else { return nil }
        if scoreMetricKeys.contains(key) { return .scores }
        if bodyMetricKeys.contains(key) { return .body }
        return nil
    }

    /// Whether the tile with this metric key is hidden under the two switches.
    static func hides(key: String?, scores: Bool, body: Bool) -> Bool {
        switch kind(forMetricKey: key) {
        case .scores?: return scores
        case .body?: return body
        case nil: return false
        }
    }

    /// `text`, or the placeholder while hidden.
    static func shown(_ text: String, hidden: Bool) -> String { hidden ? placeholder : text }

    /// Posted when either switch changes, so the iOS app can restate the choice to the widgets at once.
    static let changedNotification = Notification.Name("noop.hide.changed")

    static func announceChange() {
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }

    static func isOn(_ kind: HideScoresKind, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: kind == .scores ? scoresKey : bodyKey)
    }
}
