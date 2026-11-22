import Foundation

/// Reads the reports list for the notification paths: a report is announced only when the list's `today` row says it is ready
/// (`PFReportReadiness529`). A list that cannot be read answers "not ready", so the notification waits for a later contact.
@MainActor
enum PFReportGate529 {
    static func todayRow() async -> PFReportsListDoc.Row? {
        guard let data = await PFAPI.fetchOptional(PFDocPath529.reportsList),
              let doc = try? PFPlan529Decoder.make().decode(PFReportsListDoc.self, from: data) else { return nil }
        return doc.today
    }

    /// The inbox items that may be announced now. The list is only fetched when an item opens a daily report.
    static func announceable(_ items: [PFInboxDoc.Item]) async -> [PFInboxDoc.Item] {
        guard items.contains(where: PFReportReadiness529.isDailyReport) else { return items }
        return PFReportReadiness529.announceable(items, today: await todayRow())
    }

    /// Whether the report for this day is finished, for the brief notices.
    static func isReady(_ date: String) async -> Bool {
        let row = await todayRow()
        return row?.key == date && PFReportReadiness529.isReady(row)
    }
}
