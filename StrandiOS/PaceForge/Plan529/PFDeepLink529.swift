import Foundation

/// Opens the Plan section from anywhere: a chip of the Plan tab (with a week for the Week chip), or one of its sheets.
/// It switches to the Plan tab the same way the old "This week" link did (`PFDeepLink`) and hands the rest to `PFPlan529Router`, which
/// the Plan tab applies; a sheet is presented over the Plan tab.
@MainActor
enum PFDeepLink529 {
    enum Target: Equatable {
        case chip(CalendarChip)
        /// The Week chip, on this ISO week ("2026-W47").
        case week(String)
        case sheet(Plan529Route)
    }

    static func open(_ target: Target) {
        let router = PFPlan529Router.shared
        switch target {
        case .chip(let chip):
            router.chipRequest = chip
        case .week(let isoWeek):
            router.week = isoWeek
            router.chipRequest = .week
        case .sheet(let route):
            // Landing on the Plan tab resets its chip; a sheet leaves the chip as it was.
            router.chipRequest = CalendarChip(stored: UserDefaults.standard.string(forKey: CalendarChip.storageKey)) ?? .week
            router.sheet = route
        }
        PFDeepLink.open(.week)
    }

    #if DEBUG
    private static var didOpenFromLaunch = false

    /// UI tests: `-Plan529Open <target>` opens a destination once the Plan tab is up. Targets: `chip:season`, `week:2026-W47`,
    /// `session:2026-W47:c10def6f`, `change:0dfc53f2`, `change-today`, `race:2026-12-16`, `daily:2026-11-15`, `month:2026-10`,
    /// `settings`, `inbox`.
    static func openFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !didOpenFromLaunch, let at = arguments.firstIndex(of: "-Plan529Open"), arguments.indices.contains(at + 1) else { return }
        didOpenFromLaunch = true
        let parts = arguments[at + 1].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let arg = Array(parts.dropFirst())
        switch parts[0] {
        case "chip": if let raw = arg.first, let chip = CalendarChip(rawValue: raw) { open(.chip(chip)) }
        case "week": if let week = arg.first { open(.week(week)) }
        case "session": if arg.count == 2 { open(.sheet(.session(week: arg[0], id: arg[1]))) }
        case "change": if let id = arg.first { open(.sheet(.change(id: id))) }
        case "change-today": open(.sheet(.changeToday))
        case "race": if let date = arg.first { open(.sheet(.race(date: date))) }
        case "daily": if let date = arg.first { open(.sheet(.dailyReport(date: date))) }
        case "month": if let key = arg.first { open(.sheet(.monthReport(key: key))) }
        case "settings": open(.sheet(.planSettings))
        case "inbox": open(.sheet(.inbox))
        default: break
        }
    }
    #endif
}
