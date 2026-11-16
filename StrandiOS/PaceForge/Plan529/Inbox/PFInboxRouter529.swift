import SwiftUI
import StrandDesign

/// Opens what an inbox row or an inbox notification is about. A Plan route goes through `PFDeepLink529`, a workout or a Needs you item
/// through the earlier alert link (`PFAlertLink`), and the three screens that are not on a tab (stress, heart rate, effort) as a sheet
/// over Today (`PFInboxLanding529`).
@MainActor
enum PFInboxRouter529 {
    static func open(_ row: PFInboxRow529) {
        if let legacy = row.legacy {
            PFAlertLink.open(userInfo: legacy.userInfo)
        } else {
            open(link: row.link)
        }
    }

    static func open(link: PFInboxDoc.Link?) {
        switch PFInboxRoute529(link: link) {
        case .week(let week):
            if let week { PFDeepLink529.open(.week(week)) } else { PFDeepLink529.open(.chip(.week)) }
        case .dailyReport(let date):
            PFDeepLink529.open(.sheet(.dailyReport(date: date ?? PFAPI.todayISO)))
        case .monthReport(let key):
            if let key { PFDeepLink529.open(.sheet(.monthReport(key: key))) } else { PFDeepLink529.open(.chip(.reports)) }
        case .race(let date):
            if let date { PFDeepLink529.open(.sheet(.race(date: date))) } else { PFDeepLink529.open(.chip(.season)) }
        case .workout(let activityID, _):
            // The workout's results, with the coach's review: the sheet a tap on an alert about that activity opens.
            if let activityID {
                PFAlertLink.open(userInfo: PFAlertRoute.userInfo(kind: PFAlertRoute.alertKind, id: activityID, activityID: activityID))
            } else {
                PFDeepLink529.open(.sheet(.inbox))
            }
        case .inbox:
            PFDeepLink529.open(.sheet(.inbox))
        case .review(let week):
            PFDeepLink529.open(.sheet(.review(week: week ?? PFISOWeek529.previous(PFAPI.todayISO))))
        case .journalMorning:
            PFDeepLink529.open(.sheet(.journalMorning))
        case .journalEvening:
            PFDeepLink529.open(.sheet(.journalEvening))
        case .coachNoticed, .today:
            // The Coach noticed card sits near the top of Today.
            PFDeepLink.openToday()
        case .stress:
            land(.stress)
        case .heartRate:
            land(.heartRate)
        case .effort:
            land(.effort)
        case .needsYou:
            PFAlertLink.open(userInfo: PFAlertRoute.userInfo(kind: PFAlertRoute.needsYouKind, id: ""))
        }
    }

    private static func land(_ destination: PFInboxLanding529.Destination) {
        PFDeepLink.openToday()
        PFInboxLanding529.shared.destination = destination
    }
}

/// The screens an inbox link opens as a sheet over Today. `LiquidTodayView`'s bell presents it, so it shows wherever the link came from.
@MainActor
final class PFInboxLanding529: ObservableObject {
    static let shared = PFInboxLanding529()

    enum Destination: String, Identifiable {
        case stress, heartRate, effort
        var id: String { rawValue }
    }

    @Published var destination: Destination?
}

struct PFInboxLandingSheet529: View {
    let destination: PFInboxLanding529.Destination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("plan529-landing-done")
                    }
                }
                .tabRouteDestinations()
        }
        .containerIdentifier("plan529-landing-\(destination.rawValue)")
    }

    @ViewBuilder private var content: some View {
        switch destination {
        case .stress: StressView()
        case .heartRate: FullDayChartView()
        case .effort:
            if let metric = MetricCatalog.all.first(where: { $0.key == HeroRingMetric.effort }) {
                MetricDetailView(metric: metric)
            } else {
                HealthView()
            }
        }
    }
}
