import SwiftUI
import StrandDesign

/// W1 (build 543, drawing 3.1): the coming (or current) week. The week's name with the plus button, the strip of what needs you, the progress
/// line with the Week notes bar, then every day with one row per session. Everything that used to sit above Monday is under Week notes.
struct PFWeekComing529: View {
    let week: String
    let doc: PFPlanWeekDoc
    let header: PFWeekHeader529
    let hooks: PFWeekHooks529
    @ObservedObject var decisions: PFWeekDecisions529
    let reload: () async -> PFPlanWeekDoc?

    private var days: [PFPlanWeekDoc.Day] { doc.days ?? [] }

    /// The day the week document marks as today (the server's own clock), when this week holds it.
    private var todayDate: String? { doc.strip?.first(where: { $0.today == true })?.date }

    /// Changes are offered on sessions that are still ahead: all of a coming week, today and later in the current week, nothing in a finished one.
    private func allowsEdits(_ day: PFPlanWeekDoc.Day) -> Bool {
        switch doc.state ?? "" {
        case "finished": return false
        case "current": return (day.date ?? "") >= (todayDate ?? PFAPI.todayISO)
        default: return true
        }
    }

    /// Where the plus button puts a new workout: the first day of a coming week, today in the current one.
    private var addDate: String {
        switch doc.state ?? "" {
        case "finished": return ""
        case "current": return todayDate ?? (PFAPI.todayISO >= (doc.from ?? "") && PFAPI.todayISO <= (doc.to ?? "") ? PFAPI.todayISO : "")
        default: return doc.from ?? ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                header
                PFWeekAddButton543(addDate: addDate)
            }
            .pfWeekCard()
            PFNeedsStripView543(week: week, doc: doc, hooks: hooks, decisions: decisions)
            PFWeekNotesBar543(week: week, doc: doc, decisions: decisions, reload: reload)
            // Keyed by the day's date, not its position: a row keeps its own state when the list around it changes.
            ForEach(days, id: \.date) { day in
                PFWeekDay529(week: week, day: day, isToday: isToday(day), hooks: hooks, allowsEdits: allowsEdits(day))
                    .id(day.date ?? "")
            }
            PFPlanButton543(title: "How are you today?", systemImage: "heart.text.square", identifier: "plan529-how-today") {
                PFDeepLink529.open(.sheet(.changeToday))
            }
        }
    }

    private func isToday(_ day: PFPlanWeekDoc.Day) -> Bool {
        doc.strip?.first(where: { $0.date == day.date })?.today == true
    }
}
