import Foundation

/// data/season.json: the season bar, the race cards with their priority options and timeline, past races, hours by week, programmes.
struct PFSeasonDoc: Codable, Equatable {
    var version: Int?
    var generatedAt: String?
    var today: String?
    var end: String?
    var title: String?
    var now: Now?
    var bar: [BarSegment]?
    var races: [Race]?
    var pastRaces: [PastRace]?
    var hours: Hours?
    var programmes: Programmes?

    struct Now: Codable, Equatable {
        var phase: String?
        var line: String?
        var detail: String?
    }

    struct BarSegment: Codable, Equatable {
        var phase: String?
        var days: Int?
    }

    struct Race: Codable, Equatable {
        var date: String?
        var name: String?
        var short: String?
        var daysOut: Int?
        var dayLabel: String?
        var format: String?
        var goal: String?
        var goalSub: String?
        var sub: String?
        /// A | B | C
        var priority: String?
        var prioritySet: Bool?
        var priorityNote: String?
        var priorityOptions: [PriorityOption]?
        var bar: [BarSegment]?
        var phaseLines: [String]?
        var aim: String?
        var timeline: [TimelineRow]?
        var result: RaceResult?
        var activityId: String?
        var packReady: Bool?
        var debriefReady: Bool?
        var isHyrox: Bool?
    }

    struct PriorityOption: Codable, Equatable {
        var key: String?
        var title: String?
        var sub: String?
    }

    struct TimelineRow: Codable, Equatable {
        var when: String?
        var title: String?
        var sub: String?
        var race: Bool?
    }

    struct RaceResult: Codable, Equatable {
        var time: String?
        var delta: String?
    }

    struct PastRace: Codable, Equatable {
        var date: String?
        var name: String?
        var result: RaceResult?
        var activityId: String?
        var priority: String?
        var prioritySet: Bool?
        var isHyrox: Bool?
    }

    struct Hours: Codable, Equatable {
        var max: Double?
        var weeks: [Week]?
        var note: String?
    }

    struct Week: Codable, Equatable {
        var week: String?
        var label: String?
        var planned: Double?
        var done: Double?
        var race: Bool?
    }

    struct Programmes: Codable, Equatable {
        var line: String?
        var webRoute: String?
    }
}
