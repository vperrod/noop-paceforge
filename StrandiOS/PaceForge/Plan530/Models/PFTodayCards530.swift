import Foundation

/// data/today-cards.json: the overview card on Today, morning or evening.
///
/// The document is static between site builds, so the phone chooses the card itself (`choice`): the evening card from `eveningFrom` on, or
/// while the morning card does not exist yet (then `evening` is YESTERDAY's card and says so in its title and `date`).
/// Every field is optional and every block decodes on its own: a malformed trend never costs the verdict, a malformed morning card never
/// costs the evening card. A key this build does not know is ignored.
struct PFTodayCards530: Decodable, Equatable {
    /// The day the document was written for.
    var date: String?
    /// The server's view when it wrote the document: morning | evening. Followed only when `eveningFrom` is missing.
    var phase: String?
    /// "HH:MM", athlete-local: the evening card takes over from here.
    var eveningFrom: String?
    /// True when today's morning card exists (the night is processed).
    var morningReady: Bool?
    var morning: Morning?
    var evening: Evening?

    /// Screen 3a: the verdict, one block per device, each device's last eight mornings and the Today / Tonight / Tomorrow rows.
    struct Morning: Decodable, Equatable {
        var date: String?
        var title: String?
        var verdict: String?
        var devices: [PFDailyShort.Device]?
        var trend: [Trend]?
        var reading: String?
        var rows: [Row]?
        var link: PFInboxDoc.Link?
    }

    /// One device's morning scores, oldest first; a night without a score is null. `bands` are green | amber | red (null where no score).
    struct Trend: Decodable, Equatable {
        var source: String?
        /// recovery (WHOOP) | readiness (Garmin)
        var label: String?
        var values: [Double?]?
        var bands: [String?]?
    }

    struct Row: Decodable, Equatable {
        /// Today | Tonight | Tomorrow
        var title: String?
        var text: String?
    }

    /// Screen 5d (top): the day against the plan, what moved, what the devices found today, tonight. `verdict`, `againstPlan` and `moved`
    /// can be null (the line is left out); `found` entries are evidence strings ("Bed at 23:57") or labels.
    struct Evening: Decodable, Equatable {
        /// The day this card is about (yesterday's until today's morning card exists).
        var date: String?
        var title: String?
        var verdict: String?
        var againstPlan: String?
        var moved: String?
        var found: [String]?
        var tonight: String?
    }
}

// MARK: Lenient decoding

/// A list that keeps the elements that decode and skips the others.
struct PFTodayLossyList530<Element: Decodable>: Decodable {
    let items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var kept: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                kept.append(element)
            } else {
                _ = try? container.decode(PFTodayDiscard530.self)
            }
        }
        items = kept
    }
}

/// Moves an unkeyed container past an element that did not decode.
struct PFTodayDiscard530: Decodable {
    init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// The value under `key`, or nil when it is missing, null or malformed.
    func pfLossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// The list under `key` without its malformed elements, or nil when the key is missing, null or not a list.
    func pfLossyList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T]? {
        (try? decodeIfPresent(PFTodayLossyList530<T>.self, forKey: key))?.items
    }
}

extension PFTodayCards530 {
    private enum CodingKeys: String, CodingKey {
        case date, phase, eveningFrom, morningReady, morning, evening
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.pfLossy(String.self, .date)
        phase = c.pfLossy(String.self, .phase)
        eveningFrom = c.pfLossy(String.self, .eveningFrom)
        morningReady = c.pfLossy(Bool.self, .morningReady)
        morning = c.pfLossy(Morning.self, .morning)
        evening = c.pfLossy(Evening.self, .evening)
    }
}

extension PFTodayCards530.Morning {
    private enum CodingKeys: String, CodingKey {
        case date, title, verdict, devices, trend, reading, rows, link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.pfLossy(String.self, .date)
        title = c.pfLossy(String.self, .title)
        verdict = c.pfLossy(String.self, .verdict)
        devices = c.pfLossyList(PFDailyShort.Device.self, .devices)
        trend = c.pfLossyList(PFTodayCards530.Trend.self, .trend)
        reading = c.pfLossy(String.self, .reading)
        rows = c.pfLossyList(PFTodayCards530.Row.self, .rows)
        link = c.pfLossy(PFInboxDoc.Link.self, .link)
    }
}

extension PFTodayCards530.Trend {
    private enum CodingKeys: String, CodingKey {
        case source, label, values, bands
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.pfLossy(String.self, .source)
        label = c.pfLossy(String.self, .label)
        values = c.pfLossy([Double?].self, .values)
        bands = c.pfLossy([String?].self, .bands)
    }
}

extension PFTodayCards530.Evening {
    private enum CodingKeys: String, CodingKey {
        case date, title, verdict, againstPlan, moved, found, tonight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = c.pfLossy(String.self, .date)
        title = c.pfLossy(String.self, .title)
        verdict = c.pfLossy(String.self, .verdict)
        againstPlan = c.pfLossy(String.self, .againstPlan)
        moved = c.pfLossy(String.self, .moved)
        found = c.pfLossyList(String.self, .found)
        tonight = c.pfLossy(String.self, .tonight)
    }
}

// MARK: Which card

/// What the overview card shows.
enum PFTodayCardChoice530: Equatable {
    case morning
    case evening
    /// Nothing is drawn: both cards are missing or empty.
    case nothing
}

extension PFTodayCards530 {
    /// The card to show at `minutesOfDay` (minutes after local midnight).
    /// Evening when the clock is at or after `eveningFrom`, or when there is no morning card (after midnight, before the night is processed: the
    /// document then carries yesterday's evening card); otherwise morning. Without `eveningFrom` the server's `phase` decides the time half.
    /// A card is never drawn empty: when the wanted card is missing the other one is shown, and with neither nothing is.
    /// `forcedEvening` replaces the clock (UI tests only).
    func choice(minutesOfDay: Int, forcedEvening: Bool? = nil) -> PFTodayCardChoice530 {
        let hasMorning = morning?.isDrawable == true
        let hasEvening = evening?.isDrawable == true
        if !hasMorning && !hasEvening { return .nothing }
        let clockSaysEvening: Bool
        if let forcedEvening {
            clockSaysEvening = forcedEvening
        } else if let from = Self.minutes(ofClock: eveningFrom) {
            clockSaysEvening = minutesOfDay >= from
        } else {
            clockSaysEvening = phase == "evening"
        }
        if clockSaysEvening || !hasMorning { return hasEvening ? .evening : .morning }
        return .morning
    }

    /// "21:15" -> 1275; nil for anything else.
    static func minutes(ofClock clock: String?) -> Int? {
        guard let clock else { return nil }
        let parts = clock.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

extension PFTodayCards530.Morning {
    /// Something to draw: a card with none of its lines is not a card.
    var isDrawable: Bool {
        verdict != nil || reading != nil || !(devices ?? []).isEmpty || !(rows ?? []).isEmpty || !(trend ?? []).isEmpty
    }
}

extension PFTodayCards530.Evening {
    var isDrawable: Bool {
        verdict != nil || againstPlan != nil || moved != nil || !(found ?? []).isEmpty || !(tonight ?? "").isEmpty
    }
}
