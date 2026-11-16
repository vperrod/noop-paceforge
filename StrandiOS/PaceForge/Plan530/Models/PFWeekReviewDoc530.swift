import Foundation

// Build 530 documents (Sunday review, journal, Today cards): Foundation only, every field optional, decoded with `PFPlan529Decoder.make()`.

/// The `review` block of a finished week's `report` in data/plan-week/<ISO week>.json (the Sunday review). Garmin and WHOOP are never
/// merged: every series and reading names its device.
///
/// It rides inside the week document the Plan tab already reads, so a block the server sends in a shape this build does not know reads as
/// nil here and never fails the week document: each block is decoded on its own.
struct PFWeekReviewDoc530: Codable, Equatable {
    var trainingDays: [TrainingDay]?
    var hours: Hours?
    var raceLosses: [RaceLoss]?
    var sleep: Sleep?
    var hrvRhr: [HrvRhr]?
    var readings: Readings?
    var ahead: Ahead?

    /// One day of the training bars: minutes and effort (easy | moderate | hard | race), nil effort on a rest day.
    struct TrainingDay: Codable, Equatable {
        var dow: String?
        var minutes: Int?
        var effort: String?
    }

    struct Hours: Codable, Equatable {
        var thisLabel: String?
        var thisH: Double?
        var usualLabel: String?
        var usualH: Double?
        var pctVsUsual: Double?
        var plannedDone: String?
    }

    /// One race and the stations (or segments) that cost the most against the plan, biggest first, at most three.
    struct RaceLoss: Codable, Equatable {
        var race: String?
        var date: String?
        var stations: [Station]?
    }

    struct Station: Codable, Equatable {
        var station: String?
        var seconds: Double?
    }

    /// Garmin's nights: hours per night, the label under each bar ("8:07"), the need and the short nights.
    struct Sleep: Codable, Equatable {
        var source: String?
        var hours: [Double?]?
        var labels: [String?]?
        var needH: Double?
        var shortNights: Int?
        var avgLabel: String?
    }

    /// One device's HRV and resting heart rate over the week, each with the device's own usual.
    struct HrvRhr: Codable, Equatable {
        var source: String?
        var hrv: [Double?]?
        var rhr: [Double?]?
        var hrvUsual: Double?
        var rhrUsual: Double?
    }

    /// The one line under each chart, composed and checked on the server.
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

    /// classes | strength | running | cycling, in minutes.
    struct Mix: Codable, Equatable {
        var type: String?
        var minutes: Int?
    }
}

extension PFWeekReviewDoc530 {
    private enum CodingKeys: String, CodingKey {
        case trainingDays, hours, raceLosses, sleep, hrvRhr, readings, ahead
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trainingDays = try? c.decodeIfPresent([TrainingDay].self, forKey: .trainingDays)
        hours = try? c.decodeIfPresent(Hours.self, forKey: .hours)
        raceLosses = try? c.decodeIfPresent([RaceLoss].self, forKey: .raceLosses)
        sleep = try? c.decodeIfPresent(Sleep.self, forKey: .sleep)
        hrvRhr = try? c.decodeIfPresent([HrvRhr].self, forKey: .hrvRhr)
        readings = try? c.decodeIfPresent(Readings.self, forKey: .readings)
        ahead = try? c.decodeIfPresent(Ahead.self, forKey: .ahead)
    }
}
