import Foundation

// What the "Where you stand", Garmin recovery and ride widgets read. The app cuts these from the PaceForge files
// it fetched (standing.json, the activities, ride-metrics.json and the plan) and leaves them in the PaceForge
// summary in the App Group; the widget extension has no network. Foundation only, so the redaction below is
// unit-tested on any machine.
//
// Every number here is either a measurement (heart rate, power) or sits behind a Settings > Hide numbers switch:
// `redacted(...)` takes those out, and the faces draw only the redacted copy.

/// The strongest and the focus metrics of "Where you stand", with the band each sits in.
public struct PFStandingGlance: Codable, Equatable {
    public struct Item: Codable, Equatable, Identifiable {
        public var id: String
        public var label: String
        /// 1 (poor) to 5 (elite); nil when the metric is not rated.
        public var band: Int?
        public var bandName: String?
        /// The value as the scorecard prints it ("58 bpm"). Replaced by the placeholder while its switch is on.
        public var value: String?
        /// "body" or "scores": the Hide-numbers switch that covers `value`. Nil when none does.
        public var hideKind: String?

        public init(id: String, label: String, band: Int? = nil, bandName: String? = nil, value: String? = nil,
                    hideKind: String? = nil) {
            self.id = id; self.label = label; self.band = band; self.bandName = bandName
            self.value = value; self.hideKind = hideKind
        }
    }

    public var strongest: [Item]
    public var focus: [Item]
    /// `yyyy-MM-dd` of the scorecard.
    public var date: String?

    public init(strongest: [Item], focus: [Item], date: String? = nil) {
        self.strongest = strongest; self.focus = focus; self.date = date
    }

    public var isEmpty: Bool { strongest.isEmpty && focus.isEmpty }

    /// The same glance with the value of every item whose switch is on replaced by the placeholder.
    public func redacted(scores: Bool, body: Bool) -> PFStandingGlance {
        func hide(_ item: Item) -> Item {
            guard item.value != nil else { return item }
            let hidden = (item.hideKind == "scores" && scores) || (item.hideKind == "body" && body)
            guard hidden else { return item }
            var out = item
            out.value = PFRedact.placeholder
            return out
        }
        return PFStandingGlance(strongest: strongest.map(hide), focus: focus.map(hide), date: date)
    }
}

/// Garmin's own recovery heart rate (`hrr_garmin`) after the newest session that has it, in the app's words.
public struct PFGarminRecoveryGlance: Codable, Equatable {
    /// Beats the heart rate fell in the 2 minutes after the stop.
    public var dropBpm: Int
    /// "Garmin recovery heart rate: -46 bpm in 2 minutes".
    public var headline: String
    /// "149 at the stop, 103 two minutes later"; nil when the file did not carry both readings.
    public var detail: String?
    public var sessionName: String?
    /// `yyyy-MM-dd` of the session.
    public var date: String?

    public init(dropBpm: Int, headline: String, detail: String? = nil, sessionName: String? = nil, date: String? = nil) {
        self.dropBpm = dropBpm; self.headline = headline; self.detail = detail
        self.sessionName = sessionName; self.date = date
    }
}

/// The latest ride and the next planned one.
public struct PFRideGlance: Codable, Equatable {
    public struct Last: Codable, Equatable {
        public var title: String
        public var date: String
        public var durationS: Double?
        public var avgPower: Double?
        public var np: Double?
        /// Training stress score: behind the Charge / Effort / Sleep switch. Nil while hidden.
        public var tss: Double?
        public var avgHr: Double?

        public init(title: String, date: String, durationS: Double? = nil, avgPower: Double? = nil, np: Double? = nil,
                    tss: Double? = nil, avgHr: Double? = nil) {
            self.title = title; self.date = date; self.durationS = durationS; self.avgPower = avgPower
            self.np = np; self.tss = tss; self.avgHr = avgHr
        }
    }

    public struct Next: Codable, Equatable {
        public var name: String
        /// `yyyy-MM-dd`.
        public var date: String
        /// "45 km · 90 min"
        public var detail: String?
        /// "180–200 W" or the plan's own target text.
        public var target: String?

        public init(name: String, date: String, detail: String? = nil, target: String? = nil) {
            self.name = name; self.date = date; self.detail = detail; self.target = target
        }
    }

    public var last: Last?
    public var next: Next?

    public init(last: Last? = nil, next: Next? = nil) {
        self.last = last; self.next = next
    }

    public var isEmpty: Bool { last == nil && next == nil }

    /// The same glance without the training stress score while the scores are hidden, and without a next ride
    /// whose day has gone by (a widget can outlive the day the app wrote it).
    public func redacted(scores: Bool, today: String) -> PFRideGlance {
        var out = self
        if scores { out.last?.tss = nil }
        if let next, next.date < today { out.next = nil }
        return out
    }
}
