import SwiftUI
import StrandDesign

// The Plan section's destinations (build 529). One route enum (`Plan529Route`, in TabRoute.swift), two ways to show it: pushed through
// `TabRoute.plan529`, or as a sheet over the Plan tab through `PFPlan529Router`. Each destination lives in its own file; this one only
// maps a route to it, so the screens can be built side by side without touching the same file.

/// Draws the screen a route names.
struct PFPlan529Destination: View {
    let route: Plan529Route

    var body: some View {
        switch route {
        case .session(let week, let id): PFSessionSheet529(week: week, sessionId: id)
        case .change(let id): PFChangeSheet529(changeId: id)
        case .changeToday: PFChangeTodaySheet529()
        case .race(let date): PFRacePage529(date: date)
        case .dailyReport(let date): PFDailyReport529(date: date)
        case .monthReport(let key): PFMonthReport529(key: key)
        case .planSettings: PFPlanSettings529()
        case .inbox: PFInbox529()
        case .review(let isoWeek): PFWeekReview530(week: isoWeek)
        case .journalMorning: PFJournalMorning530()
        case .journalAfternoon: PFJournalDaySheet530(window: PFJournalLogic530.afternoon)
        case .journalEvening: PFJournalEvening530()
        case .journalInsights: PFJournalInsights530()
        case .journalCustomise: PFJournalCustomise530()
        case .week(let isoWeek):
            ScrollView {
                PFPlanWeekChip(week: isoWeek)
                    .padding(.horizontal, NoopLook.Metric.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle("Week")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// What a destination shows until its builder replaces it: its title, in the look's screen frame.
struct PFPlan529Placeholder: View {
    let title: String
    let identifier: String

    var body: some View {
        ScrollView {
            Text(title)
                .font(LookFont.text(17, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 16)
        }
        .lookScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier(identifier)
    }
}

extension Plan529Route: Identifiable {
    var id: Self { self }
}

/// The sheet a deep link asks for and the chip and week it asks the Plan tab to show. The Plan tab applies and clears them.
@MainActor
final class PFPlan529Router: ObservableObject {
    static let shared = PFPlan529Router()

    @Published var sheet: Plan529Route?
    @Published var chipRequest: CalendarChip?
    /// The ISO week the Week chip should open on, until the athlete pages elsewhere. Read by the Week screen.
    @Published var week: String?
}

/// Presents `PFPlan529Router.sheet` over the Plan tab, in its own navigation stack so a sheet can push further destinations.
struct PFPlan529Sheets: ViewModifier {
    @ObservedObject private var router = PFPlan529Router.shared

    func body(content: Content) -> some View {
        content.sheet(item: $router.sheet) { route in
            NavigationStack {
                PFPlan529Destination(route: route)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { router.sheet = nil }
                                .accessibilityIdentifier("plan529-sheet-done")
                        }
                    }
                    .tabRouteDestinations()
            }
        }
    }
}
