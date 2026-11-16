import Foundation
import UserNotifications

/// The afternoon journal question answered from the lock screen (screen 5c): a notification category with Yes and No, and the handler
/// that saves the tapped answer through the journal's own store without opening the app. The answer is saved under the day the question was
/// raised for (the item id `journal:<date>:afternoon`), so one given late is still the day it is about. APP-4's notifier decides when the
/// notification is raised and gives a journal item of window `day` the category below (`PFAlertCategory530.journalDay`).
/// `NotificationPresenter` hands a tapped Yes or No here before any routing.
enum PFJournalAction530 {
    static let categoryId = PFAlertCategory530.journalDay
    /// `NotificationPresenter` (shared with macOS, which cannot see this file) intercepts action ids with this prefix.
    static let yesId = "pf530.journal.yes"
    static let noId = "pf530.journal.no"

    /// The lock-screen category with Yes and No. `PFAlertCategoryRegistration530.register()` adds it together with the inbox category.
    static var category: UNNotificationCategory {
        let yes = UNNotificationAction(identifier: yesId, title: "Yes", options: [])
        let no = UNNotificationAction(identifier: noId, title: "No", options: [])
        return UNNotificationCategory(identifier: categoryId, actions: [yes, no], intentIdentifiers: [], options: [])
    }

    /// Saves a Yes or No tapped on the notification. Any other action, or a notification that is not the afternoon question's, does nothing.
    @MainActor
    static func handle(_ response: UNNotificationResponse, repo: Repository) async {
        let action = response.actionIdentifier
        guard action == yesId || action == noId else { return }
        let info = response.notification.request.content.userInfo
        guard let item = PFJournalLogic530.journalItem(info["pf.id"] as? String), item.window == PFJournalLogic530.afternoon else { return }
        await repo.saveJournalAnswer(day: item.date, question: question(), answeredYes: action == yesId)
    }

    /// The afternoon question's key from the last copy of the journal document saved on the phone, else the starter question.
    private static func question() -> String {
        var doc: PFJournalDoc530?
        if let data = PFStore.read(path: PFDocPath529.journal) {
            doc = try? PFPlan529Decoder.make().decode(PFJournalDoc530.self, from: data)
        }
        return PFJournalLogic530.afternoonKey(doc)
    }
}
