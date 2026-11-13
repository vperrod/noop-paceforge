import Foundation

// The Race kind of the Reports index: the events that have a race pack or a debrief (an analysis of the activity recorded on the race
// day), newest first. Foundation only, so it is compiled into the macOS unit-test bundle.

struct PFRaceReport: Equatable, Identifiable {
    /// The race day (`yyyy-MM-dd`) with the name, so two races on one day stay two rows.
    let id: String
    let name: String
    let date: String
    let goalTime: String?
    /// The server writes a pack for this race (an upcoming HYROX race it knows).
    let hasPack: Bool
    /// The activity recorded on the race day that has an analysis: the debrief.
    let analysisActivityID: String?
}

enum PFRaceReports {
    /// Races with a pack or a race-matched analysis, newest first. `packDates` are the days of the races the server has a pack for.
    static func rows(races: [PFNextRace], activities: [String: PFActivity], analyses: [String: PFAnalysisRow],
                     packDates: Set<String>) -> [PFRaceReport] {
        var seen = Set<String>()
        var out: [PFRaceReport] = []
        for race in races {
            let id = race.date + " " + race.name
            guard seen.insert(id).inserted else { continue }
            let analysis = matchedAnalysis(on: race.date, activities: activities, analyses: analyses)
            let hasPack = packDates.contains(race.date)
            guard hasPack || analysis != nil else { continue }
            out.append(PFRaceReport(id: id, name: race.name, date: race.date, goalTime: race.goalTime, hasPack: hasPack,
                                    analysisActivityID: analysis))
        }
        return out.sorted { $0.date == $1.date ? $0.name < $1.name : $0.date > $1.date }
    }

    /// The longest activity that started on `date` and has an analysis, or nil.
    static func matchedAnalysis(on date: String, activities: [String: PFActivity], analyses: [String: PFAnalysisRow]) -> String? {
        activities.values
            .filter { ($0.startTime ?? "").hasPrefix(date) && analyses[$0.id] != nil }
            .max { ($0.durationS ?? 0) < ($1.durationS ?? 0) }?
            .id
    }

    /// "Pack and debrief", "Race pack", "Debrief": what the row has.
    static func summary(_ report: PFRaceReport) -> String {
        switch (report.hasPack, report.analysisActivityID != nil) {
        case (true, true): return "Pack and debrief"
        case (true, false): return "Race pack"
        default: return "Debrief"
        }
    }
}
