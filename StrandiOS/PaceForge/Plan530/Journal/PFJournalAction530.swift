import Foundation
import UserNotifications

/// The afternoon journal question answered from the lock screen (screen 5c): a notification category with Yes and No, and the handler
/// that saves the tapped answer through the journal's own store without opening the app. The answer is saved under the day the question was
/// raised for (the item id `journal:<date>:afternoon`), so one given late is still the day it is about. APP-4's notifier decides when the
/// notification is raised and gives it `categoryId(forItemID:)`; `NotificationPresenter` passes a tapped action here.
enum PFJournalAction530 {
    /// Also written in `NotificationPresenter` (shared with macOS, which cannot see this file): keep the two the same.
    static let categoryId = "pf530.journal.afternoon"
    static let yesId = "pf530.journal.yes"
    static let noId = "pf530.journal.no"

    /// Adds the category to the ones already registered. Called once at launch, before the first scene.
    static func register() {
        let yes = UNNotificationAction(identifier: yesId, title: "Yes", options: [])
        let no = UNNotificationAction(identifier: noId, title: "No", options: [])
        let category = UNNotificationCategory(identifier: categoryId, actions: [yes, no], intentIdentifiers: [], options: [])
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var all = existing.filter { $0.identifier != categoryId }
            all.insert(category)
            center.setNotificationCategories(all)
        }
    }

    /// The category for an inbox item's notification: the afternoon question's, else nil (the item keeps its own).
    static func categoryId(forItemID id: String?) -> String? {
        PFJournalLogic530.journalItem(id)?.window == PFJournalLogic530.afternoon ? categoryId : nil
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
