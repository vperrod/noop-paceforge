import Foundation

/// One of his own HYROX races (finish time as the server printed it). No rank, field or predicted time.
struct PFHyroxRaceRow: Identifiable, Equatable {
    var label: String
    var date: String
    var display: String
    var seconds: Double
    var isPersonalBest: Bool
    var id: String { date + label }
}

enum PFHyroxPrognosisParse {
    static let maxRaces = 7

    /// The running prognosis against the goal, only when the server judged a road-race goal. For a HYROX (or any
    /// non-running) goal it answers `available: false` with no times, so there is nothing to compare.
    static func runningAgainstGoal(_ prognosis: PFJ) -> (prognosisSec: Double, goalSec: Double, verdict: String)? {
        guard prognosis["available"].bool != false,
              prognosis["reason"].string != "not a running goal",
              let sec = prognosis["prognosis_time_sec"].double,
              let goal = prognosis["goal_time_sec"].double else { return nil }
        return (sec, goal, prognosis["goal_verdict"].string ?? "")
    }

    /// The last `maxRaces` HYROX results, oldest first, with the fastest of them marked.
    static func races(_ hyrox: PFJ) -> [PFHyroxRaceRow] {
        let rows: [PFHyroxRaceRow] = hyrox["progression"]["races"].array.compactMap { r in
            guard let seconds = r["total_seconds"].double, seconds > 0 else { return nil }
            let date = r["event_date"].string ?? ""
            return PFHyroxRaceRow(label: r["event_label"].string ?? r["city"].string ?? "HYROX", date: date,
                                  display: r["total_display"].string ?? clock(seconds), seconds: seconds,
                                  isPersonalBest: false)
        }
        let last = Array(rows.suffix(maxRaces))
        guard let best = last.map(\.seconds).min() else { return [] }
        return last.map { var row = $0; row.isPersonalBest = row.seconds == best; return row }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
