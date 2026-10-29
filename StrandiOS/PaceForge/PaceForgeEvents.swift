import Foundation

// Events (races) and HYROX simulations logged from the app. Foundation only, so it is compiled into the macOS unit-test bundle.
//
// `save-events` REPLACES the whole list (data/events.json), so the app reads the file, changes the list and sends all of it back, every
// row's other keys untouched (type, goal_time, priority, partner ...). The date is an event's only identifier. `hyrox-sim-add` takes
// times as text (m:ss, h:mm:ss, 4m05s or seconds, 20 s to 30 min), which the server checks and explains when it refuses one.

/// An event as the list shows it.
struct PFEventRow: Equatable, Identifiable {
    let date: String
    let name: String
    let type: String?
    /// Unique in a list even when two events share a date (and a name): the date, the name and which of those it is.
    let id: String
}

/// One change to the list, applied to the list as it is on the server at the moment of sending.
enum PFEventChange {
    case add(name: String, date: String, type: String, location: String)
    case cancel(date: String, name: String)
}

/// Why an event could not be added, in words for the form.
enum PFEventProblem: Error, Equatable {
    case nameMissing
    case nameTooLong
    case badDate
    case dateTaken
    case tooMany
    case textTooLong
    case unreadable

    var message: String {
        switch self {
        case .nameMissing: return "Give the event a name."
        case .nameTooLong: return "The name is longer than 200 characters."
        case .badDate: return "Pick the event's date."
        case .dateTaken: return "There is already an event on that day."
        case .tooMany: return "PaceForge keeps at most 100 events."
        case .textTooLong: return "The type or place is longer than 500 characters."
        case .unreadable: return "PaceForge's events could not be read, so nothing was changed."
        }
    }
}

enum PFEvents {
    static let maxEvents = 100

    /// `data/events.json` as a list of rows; nil when it is not a list at all, so nothing is ever sent back from an unreadable file.
    static func parse(_ data: Data?) -> [[String: Any]]? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [[String: Any]]
    }

    /// The rows to show, soonest first. A row without a date or a name is not shown (and is still sent back untouched).
    static func rows(_ list: [[String: Any]]) -> [PFEventRow] {
        var seen: [String: Int] = [:]
        let rows = list.compactMap { row -> PFEventRow? in
            guard let date = row["date"] as? String, let name = row["name"] as? String, !date.isEmpty, !name.isEmpty else { return nil }
            let type = (row["type"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let key = date + "|" + name
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            return PFEventRow(date: date, name: name, type: type, id: key + "|" + String(occurrence))
        }
        return rows.sorted { $0.date < $1.date }
    }

    /// The list with one event added (the original shape: date, name, type, goal_time), or the reason it cannot be.
    static func adding(name rawName: String, date: String, type rawType: String, location rawLocation: String,
                       to list: [[String: Any]]) -> Result<[[String: Any]], PFEventProblem> {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .failure(.nameMissing) }
        if name.unicodeScalars.count > 200 { return .failure(.nameTooLong) }
        if !PFJobInputs.isDay(date) { return .failure(.badDate) }
        if type.unicodeScalars.count > 500 || location.unicodeScalars.count > 500 { return .failure(.textTooLong) }
        if list.contains(where: { ($0["date"] as? String) == date }) { return .failure(.dateTaken) }
        if list.count >= maxEvents { return .failure(.tooMany) }
        var row: [String: Any] = ["date": date, "name": name, "type": type, "goal_time": ""]
        if !location.isEmpty { row["location"] = location }
        return .success(list + [row])
    }

    /// The list without the first event that has this date AND this name; any other event on that date stays.
    static func removing(date: String, name: String, from list: [[String: Any]]) -> [[String: Any]] {
        guard let index = list.firstIndex(where: { ($0["date"] as? String) == date && ($0["name"] as? String) == name }) else { return list }
        var kept = list
        kept.remove(at: index)
        return kept
    }

    /// The list with one change applied, or why it cannot be.
    static func applying(_ change: PFEventChange, to list: [[String: Any]]) -> Result<[[String: Any]], PFEventProblem> {
        switch change {
        case .add(let name, let date, let type, let location):
            return adding(name: name, date: date, type: type, location: location, to: list)
        case .cancel(let date, let name):
            return .success(removing(date: date, name: name, from: list))
        }
    }

    /// `save-events`: `{"data": [every event]}`, soonest first as the web sends it.
    static func inputs(_ list: [[String: Any]]) -> [String: Any]? {
        guard list.count <= maxEvents else { return nil }
        return ["data": list.sorted { (($0["date"] as? String) ?? "") < (($1["date"] as? String) ?? "") }]
    }
}

/// A HYROX simulation typed as two lists of times.
enum PFHyroxSimInput {
    static let splits = 8

    /// The times in a field: split at commas when there are any (an empty place skips a split), else at spaces and line breaks.
    static func times(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        if trimmed.contains(",") {
            return trimmed.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

extension PFJobInputs {
    /// `hyrox-sim-add`: the day, the run times and the station times (up to 8 each, in race order), the optional Roxzone total.
    /// nil without a single time, or with more than 8 of one kind: the server would refuse it.
    static func hyroxSim(date: String, runs: String, stations: String, roxzone: String) -> [String: Any]? {
        let runTimes = PFHyroxSimInput.times(runs)
        let stationTimes = PFHyroxSimInput.times(stations)
        guard runTimes.count <= PFHyroxSimInput.splits, stationTimes.count <= PFHyroxSimInput.splits,
              (runTimes + stationTimes).contains(where: { !$0.isEmpty }), isDay(date) else { return nil }
        var inputs: [String: Any] = ["date": date]
        if !runTimes.isEmpty { inputs["runs"] = runTimes }
        if !stationTimes.isEmpty { inputs["stations"] = stationTimes }
        let total = roxzone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !total.isEmpty { inputs["roxzone"] = total }
        return inputs
    }
}
