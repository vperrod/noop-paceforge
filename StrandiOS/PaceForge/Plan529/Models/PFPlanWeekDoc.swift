import Foundation

/// data/plan-week/<ISO week>.json: one week, every workout written out, the coach's changes, and (finished weeks) the report.
struct PFPlanWeekDoc: Codable, Equatable {
    var version: Int?
    var week: String?
    var from: String?
    var to: String?
    var label: String?
    var generatedAt: String?
    /// finished | current | coming
    var state: String?
    var phase: Phase?
    var nextRace: NextRace?
    var why: String?
    var hours: Hours?
    var strip: [StripDay]?
    var changes: [Change]?
    var decided: [String]?
    var deleted: [DeletedSession]?
    var days: [Day]?
    var report: Report?

    struct DeletedSession: Codable, Equatable {
        var sessionId: String?
        var title: String?
        var dow: String?
        var date: String?
    }

    struct Phase: Codable, Equatable {
        var key: String?
        var label: String?
        var pill: String?
    }

    struct NextRace: Codable, Equatable {
        var name: String?
        var short: String?
        var date: String?
        var daysOut: Int?
        var pill: String?
    }

    struct Hours: Codable, Equatable {
        var firm: Double?
        var optional: Double?
        var planned: Double?
        var aim: Double?
        var target: Double?
        var typical: Double?
        var done: Double?
        var firmLabel: String?
        var optionalLabel: String?
        var aimLabel: String?
        var targetLabel: String?
        var doneLabel: String?
        var note: String?
    }

    struct StripDay: Codable, Equatable {
        var date: String?
        var dow: String?
        var today: Bool?
        var label: String?
        var bars: [Bar]?
    }

    struct Bar: Codable, Equatable {
        var minutes: Int?
        /// easy | moderate | hard | race
        var effort: String?
        /// planned | optional | done | missed
        var state: String?
    }

    struct Change: Codable, Equatable {
        var id: String?
        var day: String?
        var sessionIds: [String]?
        var title: String?
        var sheetTitle: String?
        var oneLine: String?
        var before: Side?
        var after: Side?
        var dataSays: String?
        var why: String?
        var ifKeep: String?
        var acceptLabel: String?
        var keepLabel: String?
        var footnote: String?
        /// Change workout (build 529 addition): the athlete asked for it by type; the built workout, warnings and the "Try another" label.
        var requested: Bool?
        var afterDetail: AfterDetail?
        var warnings: [String]?
        var againLabel: String?
    }

    /// The workout a requested change would put in place: title, effort pill and the written-out lines.
    struct AfterDetail: Codable, Equatable {
        var title: String?
        var effortLabel: String?
        var why: String?
        var howHard: String?
        var `do`: String?
    }

    /// The previous matching activity of a session, when the server names it (the session sheet falls back to a match on the phone).
    struct LastTime: Codable, Equatable {
        var activityId: String?
        var date: String?
        var title: String?
    }

    /// One side of a change: a big label with a line under it.
    struct Side: Codable, Equatable {
        var label: String?
        var sub: String?
    }

    struct Day: Codable, Equatable {
        var date: String?
        var dow: String?
        var title: String?
        var tag: String?
        var items: [Item]?
    }

    /// A session, a race or a rest day. Race items carry `raceDate` and `result`; finished sessions carry `done` and `review`.
    struct Item: Codable, Equatable {
        /// session | race | rest
        var kind: String?
        var sessionId: String?
        var title: String?
        var minutes: Int?
        var km: Double?
        var effort: String?
        var effortLabel: String?
        var rpe: Int?
        var fixed: Bool?
        var optional: Bool?
        /// planned | optional | done | partial | missed
        var status: String?
        var pills: [String]?
        var changeIds: [String]?
        var changePill: String?
        var why: String?
        var howHard: String?
        var `do`: String?
        var ifRed: String?
        var after: String?
        var `where`: String?
        /// more | move | skip | easier (as the server sends them today)
        var actions: [String]?
        var done: Done?
        var review: Review?
        var activityId: String?
        var raceDate: String?
        var result: RaceResult?
        var lastTime: LastTime?
        /// Build 530: true when the coach filled the slot and it is not booked.
        var proposed: Bool?
        /// Build 542, a session from the athlete's TrueCoach plan: true, mandatory in its week (`weekStart` is that week's Monday), with the
        /// coach's text verbatim. `skippedMandatory` and `coachRemoved` are read when the server sends them.
        var coachAssigned: Bool?
        var mandatory: Bool?
        var coachDetails: String?
        var weekStart: String?
        var skippedMandatory: Bool?
        var coachRemoved: Bool?
        /// The session's own written description (the athlete's, or the coach's text when he has not changed it), and whether he rewrote it.
        var description: String?
        var athleteEdited: Bool?
    }

    struct Done: Codable, Equatable {
        var line: String?
        var minutes: Int?
        var km: Double?
        var avgHr: Int?
    }

    struct Review: Codable, Equatable {
        /// ready | pending | silent
        var state: String?
        var verdict: String?
        /// One sentence on what the review means for the athlete (optional, build 529 addition).
        var meaning: String?
    }

    struct RaceResult: Codable, Equatable {
        var time: String?
        var goal: String?
        var delta: String?
        var deltaS: Int?
        var source: String?
    }

    /// The finished week's report: verdict, races, planned against done, nights, what went well and what held back, next week.
    struct Report: Codable, Equatable {
        var readyAt: String?
        var verdict: String?
        /// The week told in 4 to 8 sentences, under the verdict (optional, build 529 addition).
        var story: String?
        /// Up to three titled findings under the story (optional, build 529 addition).
        var insights: [Insight]?
        var races: [Race]?
        var plannedDone: PlannedDone?
        var nights: Nights?
        var wentWell: [String]?
        var heldBack: [String]?
        var notToDo: String?
        var nextWeek: NextWeek?
        var detail: Detail?
        /// The Sunday review block (build 530): the week told in charts and one reading line each.
        var review: PFWeekReviewDoc530?
    }

    struct Insight: Codable, Equatable {
        var title: String?
        var text: String?
    }

    struct Race: Codable, Equatable {
        var date: String?
        var day: String?
        var name: String?
        var time: String?
        var sub: String?
        var activityId: String?
    }

    struct PlannedDone: Codable, Equatable {
        var line: String?
        var facts: [String]?
        var vsPrev: String?
    }

    struct Nights: Codable, Equatable {
        var labels: [String]?
        var series: [Series]?
        var note: String?
    }

    /// One device's nights. Garmin and WHOOP are separate series, never merged.
    struct Series: Codable, Equatable {
        var source: String?
        var title: String?
        var max: Double?
        var values: [Double?]?
        var bands: [String]?
        /// Build 530: the device's own usual for these nights (the dashed line).
        var usual: Double?
    }

    struct NextWeek: Codable, Equatable {
        var week: String?
        var summary: String?
        var changes: Int?
    }

    struct Detail: Codable, Equatable {
        var numbersTitle: String?
        var expertsTitle: String?
        var expertReport: String?
    }
}
