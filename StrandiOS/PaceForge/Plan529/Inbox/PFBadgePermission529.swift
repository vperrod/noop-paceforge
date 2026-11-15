import UIKit
import UserNotifications

/// The app icon shows the unread count only when iOS has badges on for NOOP. The first notification ask now includes badges; a phone that
/// answered before it asks once more (iOS does not show the prompt again for an authorised app and may switch badges on silently). If
/// they are still off, the inbox's switches screen says so and opens the app's notification settings.
@MainActor
enum PFBadgePermission529 {
    private static let migratedKey = "noop.paceforge.badgeAsked"

    static func migrateOnce() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey), PFAPI.isConfigured, !PFAPI.isFixture else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        // Not answered yet: the first ask (which includes badges) is still to come.
        guard status == .authorized || status == .provisional else { return }
        defaults.set(true, forKey: migratedKey)
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        PFInboxStore529.shared.updateBadge()
    }

    /// True when notifications are allowed but badges are not.
    static func badgesAreOff() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return false }
        return settings.badgeSetting != .enabled
    }

    static func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
