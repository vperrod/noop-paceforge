import Foundation

/// data/today-cards.json: the overview card on Today, morning or evening.
struct PFTodayCards530: Codable, Equatable {
    /// morning | evening
    var phase: String?
    var morning: Morning?
    var evening: Evening?

    /// Screen 3a: the verdict, one block per device, the seven-night trend and the Today / Tonight / Tomorrow rows.
    struct Morning: Codable, Equatable {
        var title: String?
        var verdict: String?
        var devices: [PFDailyShort.Device]?
        var trend: [Trend]?
        var reading: String?
        var rows: [Row]?
        var link: PFInboxDoc.Link?
    }

    struct Trend: Codable, Equatable {
        var source: String?
        var values: [Double?]?
        var bands: [String]?
    }

    struct Row: Codable, Equatable {
        /// Today | Tonight | Tomorrow
        var title: String?
        var text: String?
    }

    /// Screen 5d (top): the day against the plan, what moved, what the devices found today, tonight.
    struct Evening: Codable, Equatable {
        var title: String?
        var verdict: String?
        var againstPlan: String?
        var moved: String?
        var found: [String]?
        var tonight: String?
    }
}
