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

extension PFSnapshot {
    /// The recording of an official HYROX result, or nil when none fits. A result is dated by the event's first day, so a recording
    /// counts when it lies within 3 days of that date and (when the result names a city) carries the city in its name. Candidates are the
    /// week strip's race items with an `activity_id` plus recordings named HYROX or like the city. Of several, the one whose title holds
    /// every word of the division wins, then the nearest day.
    func recordingID(forResult race: PFHyroxResultRace) -> String? {
        guard let resultDate = race.date, resultDate.count >= 10 else { return nil }
        let city = (race.city ?? "").trimmingCharacters(in: .whitespaces)
        var candidates: [(id: String, date: String, title: String)] = []
        for day in todayCall?.week ?? [] {
            for item in day.items where item.kind == "race" {
                if let id = item.activityID, !id.isEmpty { candidates.append((id, day.date, item.title)) }
            }
        }
        for activity in activities.values {
            guard let start = activity.startTime, start.count >= 10 else { continue }
            let name = activity.name ?? ""
            guard name.localizedCaseInsensitiveContains("hyrox") || (!city.isEmpty && name.localizedCaseInsensitiveContains(city)) else { continue }
            candidates.append((activity.id, String(start.prefix(10)), name))
        }
        let anchor = PFFormat.date(resultDate)
        func gap(_ date: String) -> Double { abs(PFFormat.date(date).timeIntervalSince(anchor) / 86_400).rounded() }
        let words = (race.division ?? "").lowercased().split { !$0.isLetter }.map(String.init)
        let near = candidates.filter { c in
            gap(c.date) <= 3 && (city.isEmpty || c.title.localizedCaseInsensitiveContains(city))
        }
        func hasDivision(_ title: String) -> Bool { !words.isEmpty && words.allSatisfy { title.lowercased().contains($0) } }
        let pool = near.contains { hasDivision($0.title) } ? near.filter { hasDivision($0.title) } : near
        return pool.min { (gap($0.date), $0.id) < (gap($1.date), $1.id) }?.id
    }
}
