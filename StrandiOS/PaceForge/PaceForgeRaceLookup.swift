import Foundation

extension PFSnapshot {
    /// The week strip's race entry for a race day. The title match wins; when the strip titles the race differently from `events.json`,
    /// the one race item of that day that carries a recording is used, so a finished race never falls back to its plan.
    func raceItem(on date: String, name: String) -> PFTodayCall.WeekItem? {
        let items = todayCall?.week.first { $0.date == date }?.items.filter { $0.kind == "race" } ?? []
        return items.first { $0.title == name && ($0.result != nil || $0.status == "done" || $0.activityID != nil) }
            ?? items.first { $0.activityID != nil }
    }

    /// The Garmin activity id of the recording of a race: the strip's `activity_id`, else a recording that day named like the race
    /// (or, for HYROX, named HYROX).
    func raceRecordingID(on date: String, name: String) -> String? {
        if let id = raceItem(on: date, name: name)?.activityID, !id.isEmpty { return id }
        let isHyrox = name.localizedCaseInsensitiveContains("hyrox")
        return activities.values
            .filter { activity in
                guard let start = activity.startTime, start.hasPrefix(date) else { return false }
                let label = activity.name ?? ""
                return (!name.isEmpty && label.localizedCaseInsensitiveContains(name)) || (isHyrox && label.localizedCaseInsensitiveContains("hyrox"))
            }
            .map { $0.id }
            .min()
    }
}
