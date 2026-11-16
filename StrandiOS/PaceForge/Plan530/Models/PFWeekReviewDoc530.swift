import Foundation

// Build 530 documents (Sunday review, journal, Today cards): Foundation only, every field optional, decoded with `PFPlan529Decoder.make()`.

/// The `review` block of a finished week's `report` in data/plan-week/<ISO week>.json (the Sunday review). Shapes follow the server's
/// `week_review.py` (SRV-1). Garmin and WHOOP are never merged: every series and reading names its device.
///
/// It rides inside the week document the Plan tab already reads, so nothing in it may fail the week: every block decodes on its own,
/// and inside a block every field and every list entry does too (a field the server sends in a shape this build does not know reads as
/// nil, an entry that cannot be read is left out).
struct PFWeekReviewDoc530: Codable, Equatable {
    var trainingDays: [TrainingDay]?
    var hours: Hours?
    var raceLosses: [RaceLoss]?
    var sleep: Sleep?
    var hrvRhr: [HrvRhr]?
    var readings: Readings?
    var ahead: Ahead?

    /// One day of the training bars: a single-letter weekday, minutes and effort (easy | moderate | hard | race), nil effort on a rest day.
    struct TrainingDay: Codable, Equatable {
        var dow: String?
        var minutes: Int?
        var effort: String?
    }

    /// The week's training time against the mean of the last finished weeks; the `usual*` fields are absent with too few weeks behind.
    struct Hours: Codable, Equatable {
        var thisLabel: String?
        var thisH: Double?
        var usualWeeks: Int?
        var usualLabel: String?
        var usualH: Double?
        var pctVsUsual: Double?
        var plannedDone: PlannedDone?
    }

    struct PlannedDone: Codable, Equatable {
        var done: Int?
        var planned: Int?
    }

    /// One race and the stations that cost the most against `against`, biggest first, at most three.
    struct RaceLoss: Codable, Equatable {
        var date: String?
        var name: String?
        var against: String?
        var losses: [Loss]?
    }

    struct Loss: Codable, Equatable {
        var station: String?
        var seconds: Double?
    }

    /// Garmin's nights: hours per night (nil = no reading), the label under each bar ("8:07"), the need and the short nights.
    struct Sleep: Codable, Equatable {
        var source: String?
        var hours: [Double?]?
        var labels: [String?]?
        var needH: Double?
        var shortNights: Int?
        var avgLabel: String?
    }

    /// One device's HRV and resting heart rate over the week, each with the device's own usual (absent with too few mornings).
    struct HrvRhr: Codable, Equatable {
        var source: String?
        var hrv: [Double?]?
        var rhr: [Double?]?
        var hrvUsual: Double?
        var rhrUsual: Double?
    }

    /// The one line under each chart, composed and checked on the server. A line the server could not support is absent.
    struct Readings: Codable, Equatable {
        var training: String?
        var races: String?
        var stations: String?
        var whoop: String?
        var garmin: String?
        var sleep: String?
        var hrvRhr: String?
    }

    /// The week ahead half of the page.
    struct Ahead: Codable, Equatable {
        var week: String?
        var headline: String?
        var calendar: [Phase]?
        var nextRace: NextRace?
        var mix: [Mix]?
        var calendarReading: String?
    }

    struct Phase: Codable, Equatable {
        var phase: String?
        var days: Int?
        var from: String?
        var to: String?
    }

    struct NextRace: Codable, Equatable {
        var name: String?
        var date: String?
        var goal: String?
    }

    /// classes | strength | running | cycling | other, in minutes.
    struct Mix: Codable, Equatable {
        var type: String?
        var minutes: Int?
    }
}

// MARK: Tolerant decoding

extension KeyedDecodingContainer {
    /// A value of a shape this build does not know reads as nil instead of failing the container.
    func review530Value<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// A list whose unreadable entries are left out instead of failing the list.
    func review530List<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        guard let raw = review530Value([Review530Entry<T>].self, key) else { return nil }
        return raw.compactMap { $0.value }
    }
}

/// An entry that decodes to nil when it cannot be read; used by `review530List`.
private struct Review530Entry<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension PFWeekReviewDoc530 {
    /// True when the server sent no block this build could read.
    var isEmpty: Bool { self == PFWeekReviewDoc530() }

    private enum CodingKeys: String, CodingKey {
        case trainingDays, hours, raceLosses, sleep, hrvRhr, readings, ahead
    }

    init(from decoder: Decoder) throws {
        // A block that is not an object at all reads as an empty review, never as a failed week document.
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        trainingDays = c.review530List(TrainingDay.self, .trainingDays)
        hours = c.review530Value(Hours.self, .hours)
        raceLosses = c.review530List(RaceLoss.self, .raceLosses)
        sleep = c.review530Value(Sleep.self, .sleep)
        hrvRhr = c.review530List(HrvRhr.self, .hrvRhr)
        readings = c.review530Value(Readings.self, .readings)
        ahead = c.review530Value(Ahead.self, .ahead)
    }
}

extension PFWeekReviewDoc530.TrainingDay {
    private enum CodingKeys: String, CodingKey { case dow, minutes, effort }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dow = c.review530Value(String.self, .dow)
        minutes = c.review530Value(Int.self, .minutes)
        effort = c.review530Value(String.self, .effort)
    }
}

extension PFWeekReviewDoc530.Hours {
    private enum CodingKeys: String, CodingKey { case thisLabel, thisH, usualWeeks, usualLabel, usualH, pctVsUsual, plannedDone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thisLabel = c.review530Value(String.self, .thisLabel)
        thisH = c.review530Value(Double.self, .thisH)
        usualWeeks = c.review530Value(Int.self, .usualWeeks)
        usualLabel = c.review530Value(String.self, .usualLabel)
        usualH = c.review530Value(Double.self, .usualH)
        pctVsUsual = c.review530Value(Double.self, .pctVsUsual)
        plannedDone = c.review530Value(PFWeekReviewDoc530.PlannedDone.self, .plannedDone)
    }
}

extension PFWeekReviewDoc530.PlannedDone {
    private enum CodingKeys: String, CodingKey { case done, planned }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = c.review530Value(Int.self, .done)
        planned = c.review530Value(Int.self, .planned)
    }
}

extension PFWeekReviewDoc530.RaceLoss {
    private enum CodingKeys: String, CodingKey { case date, name, against, losses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.review530Value(String.self, .date)
        name = c.review530Value(String.self, .name)
        against = c.review530Value(String.self, .against)
        losses = c.review530List(PFWeekReviewDoc530.Loss.self, .losses)
    }
}

extension PFWeekReviewDoc530.Loss {
    private enum CodingKeys: String, CodingKey { case station, seconds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        station = c.review530Value(String.self, .station)
        seconds = c.review530Value(Double.self, .seconds)
    }
}

extension PFWeekReviewDoc530.Sleep {
    private enum CodingKeys: String, CodingKey { case source, hours, labels, needH, shortNights, avgLabel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.review530Value(String.self, .source)
        hours = c.review530Value([Double?].self, .hours)
        labels = c.review530Value([String?].self, .labels)
        needH = c.review530Value(Double.self, .needH)
        shortNights = c.review530Value(Int.self, .shortNights)
        avgLabel = c.review530Value(String.self, .avgLabel)
    }
}

extension PFWeekReviewDoc530.HrvRhr {
    private enum CodingKeys: String, CodingKey { case source, hrv, rhr, hrvUsual, rhrUsual }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.review530Value(String.self, .source)
        hrv = c.review530Value([Double?].self, .hrv)
        rhr = c.review530Value([Double?].self, .rhr)
        hrvUsual = c.review530Value(Double.self, .hrvUsual)
        rhrUsual = c.review530Value(Double.self, .rhrUsual)
    }
}

extension PFWeekReviewDoc530.Readings {
    private enum CodingKeys: String, CodingKey { case training, races, stations, whoop, garmin, sleep, hrvRhr }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        training = c.review530Value(String.self, .training)
        races = c.review530Value(String.self, .races)
        stations = c.review530Value(String.self, .stations)
        whoop = c.review530Value(String.self, .whoop)
        garmin = c.review530Value(String.self, .garmin)
        sleep = c.review530Value(String.self, .sleep)
        hrvRhr = c.review530Value(String.self, .hrvRhr)
    }
}

extension PFWeekReviewDoc530.Ahead {
    private enum CodingKeys: String, CodingKey { case week, headline, calendar, nextRace, mix, calendarReading }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = c.review530Value(String.self, .week)
        headline = c.review530Value(String.self, .headline)
        calendar = c.review530List(PFWeekReviewDoc530.Phase.self, .calendar)
        nextRace = c.review530Value(PFWeekReviewDoc530.NextRace.self, .nextRace)
        mix = c.review530List(PFWeekReviewDoc530.Mix.self, .mix)
        calendarReading = c.review530Value(String.self, .calendarReading)
    }
}

extension PFWeekReviewDoc530.Phase {
    private enum CodingKeys: String, CodingKey { case phase, days, from, to }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = c.review530Value(String.self, .phase)
        days = c.review530Value(Int.self, .days)
        from = c.review530Value(String.self, .from)
        to = c.review530Value(String.self, .to)
    }
}

extension PFWeekReviewDoc530.NextRace {
    private enum CodingKeys: String, CodingKey { case name, date, goal }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.review530Value(String.self, .name)
        date = c.review530Value(String.self, .date)
        goal = c.review530Value(String.self, .goal)
    }
}

extension PFWeekReviewDoc530.Mix {
    private enum CodingKeys: String, CodingKey { case type, minutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.review530Value(String.self, .type)
        minutes = c.review530Value(Int.self, .minutes)
    }
}
