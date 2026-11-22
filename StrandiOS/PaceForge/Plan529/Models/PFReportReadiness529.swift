import Foundation

/// Whether today's daily report may be announced or listed as finished. The server's reports list says (`today.ready`); the phone never
/// decides it. Only `ready == true` counts: a row without the field, or a list that could not be read, is not ready.
enum PFReportReadiness529 {
    static let pendingTitle = "Today's report is not ready yet"

    static func isReady(_ row: PFReportsListDoc.Row?) -> Bool { row?.ready == true }

    /// The server's reason on a row that is not ready, as a sentence; nil when it gave none.
    static func pendingSub(_ row: PFReportsListDoc.Row) -> String? { PFWatchStatus529.sentence(row.reason) }

    /// Whether this inbox item opens a daily report. Only those are held back: the other kinds say nothing about a report being ready.
    static func isDailyReport(_ item: PFInboxDoc.Item) -> Bool { item.link?.route == "report_daily" }

    /// Items that may raise a notification now. A daily-report item for the day in the list's `today` row waits until that row is ready;
    /// one for any other day, or with no `today` row to check, waits too, because nothing says it is ready.
    static func announceable(_ items: [PFInboxDoc.Item], today: PFReportsListDoc.Row?) -> [PFInboxDoc.Item] {
        items.filter { item in
            guard isDailyReport(item) else { return true }
            guard let today, let key = today.key else { return false }
            if let date = item.link?.date, date != key { return false }
            return isReady(today)
        }
    }
}
