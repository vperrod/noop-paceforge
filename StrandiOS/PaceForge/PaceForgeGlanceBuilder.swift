import Foundation

/// Cuts the three widget glances (Where you stand, Garmin recovery, rides) out of what the app fetched. Foundation
/// only, and it takes plain inputs rather than the whole snapshot, so it is unit-tested without the app.
enum PFGlanceBuilder {
    /// A planned session, reduced to what the next-ride pick needs.
    struct Session: Equatable {
        var name: String
        var sport: String?
        var kind: String?
        var date: String
        /// Not done, not skipped, not optional.
        var isOpen: Bool
        var detail: String?
        var target: String?
    }

    /// A finished activity, reduced to what the recovery glance needs.
    struct Activity: Equatable {
        var name: String?
        var startTime: String?
        var hrrGarmin: PFHRRGarmin?
    }

    // MARK: Where you stand

    /// The three strongest and the three focus metrics, or nil when the scorecard has neither.
    static func standing(_ standing: PFStanding?) -> PFStandingGlance? {
        guard let standing, standing.isApplicable else { return nil }
        func item(_ metric: PFStandingMetric) -> PFStandingGlance.Item {
            PFStandingGlance.Item(id: metric.id, label: metric.label, band: metric.isRated ? metric.band : nil,
                                  bandName: metric.bandName, value: metric.value == nil && metric.display == nil ? nil : metric.valueText,
                                  hideKind: metric.hideKind.map { $0 == .body ? "body" : "scores" })
        }
        let glance = PFStandingGlance(strongest: standing.strongestTop.map(item), focus: standing.focusTop.map(item),
                                      date: standing.generatedAt.map { String($0.prefix(10)) })
        return glance.isEmpty ? nil : glance
    }

    // MARK: Garmin recovery

    /// The newest activity that has Garmin's own recovery heart rate, in the card's words.
    static func garminRecovery(_ activities: [Activity]) -> PFGarminRecoveryGlance? {
        let newest = activities
            .filter { $0.hrrGarmin != nil }
            .max { ($0.startTime ?? "") < ($1.startTime ?? "") }
        guard let newest, let hrr = newest.hrrGarmin else { return nil }
        return PFGarminRecoveryGlance(dropBpm: hrr.dropBpm, headline: hrr.headline, detail: hrr.detail,
                                      sessionName: newest.name, date: newest.startTime.map { String($0.prefix(10)) })
    }

    // MARK: Rides

    /// A bike session by its sport or kind ("cycling", "indoor_cycling", "bike", "ride").
    static func isRide(sport: String?, kind: String?) -> Bool {
        [sport, kind].contains { value in
            let text = (value ?? "").lowercased()
            return text.contains("cycl") || text.contains("bik") || text.contains("ride")
        }
    }

    /// The newest ride (the list is newest first) and the next open bike session from `today` on.
    static func rides(_ rides: [PFRide], sessions: [Session], today: String) -> PFRideGlance? {
        let last = rides.first.map {
            PFRideGlance.Last(title: $0.title, date: $0.date, durationS: $0.durationS, avgPower: $0.avgPower, np: $0.np,
                              tss: $0.tss, avgHr: $0.avgHr)
        }
        let next = sessions
            .filter { $0.isOpen && $0.date >= today && isRide(sport: $0.sport, kind: $0.kind) }
            .min { $0.date < $1.date }
            .map { PFRideGlance.Next(name: $0.name, date: $0.date, detail: $0.detail, target: $0.target) }
        let glance = PFRideGlance(last: last, next: next)
        return glance.isEmpty ? nil : glance
    }
}
