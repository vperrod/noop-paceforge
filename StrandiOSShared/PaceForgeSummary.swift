import Foundation
import AppIntents

/// A small, Codable summary of the PaceForge day, written by the app after every successful PaceForge
/// fetch into the App Group container and read by the PaceForge widgets, Siri and Shortcuts. The widget
/// extension never touches the network or the Keychain; this file is its only source.
public struct PFSummary: Codable, Equatable {
    public struct Session: Codable, Equatable, Identifiable {
        public var name: String
        public var sport: String?
        /// "9.0 km · 55 min"
        public var detail: String?
        /// Target pace / heart rate, e.g. "4:10–4:20/km".
        public var target: String?
        /// Main set in one line, e.g. "4 × 800 m @ 4:10/km".
        public var mainSet: String?
        public var done: Bool
        public var id: String { name + (detail ?? "") }

        public init(name: String, sport: String? = nil, detail: String? = nil, target: String? = nil,
                    mainSet: String? = nil, done: Bool = false) {
            self.name = name; self.sport = sport; self.detail = detail; self.target = target
            self.mainSet = mainSet; self.done = done
        }
    }

    public struct Race: Codable, Equatable {
        public var name: String
        public var date: String
        public var days: Int

        public init(name: String, date: String, days: Int) {
            self.name = name; self.date = date; self.days = days
        }
    }

    /// One day of the current week for the week-strip widget.
    public struct WeekDay: Codable, Equatable, Identifiable {
        public var date: String
        /// Single-letter weekday, "M".
        public var label: String
        public var planned: Int
        public var done: Int
        public var isToday: Bool
        public var id: String { date }

        public init(date: String, label: String, planned: Int, done: Int, isToday: Bool) {
            self.date = date; self.label = label; self.planned = planned; self.done = done; self.isToday = isToday
        }
    }

    /// One night for the sleep and HRV trend. Either value can be missing.
    public struct Night: Codable, Equatable, Identifiable {
        public var date: String
        public var sleepMinutes: Double?
        public var hrv: Double?
        public var id: String { date }

        public init(date: String, sleepMinutes: Double? = nil, hrv: Double? = nil) {
            self.date = date; self.sleepMinutes = sleepMinutes; self.hrv = hrv
        }
    }

    /// The latest Hume reading and its change since the reading before it.
    public struct BodyReading: Codable, Equatable {
        public var date: String?
        public var score: Double?
        public var band: String?
        public var weightKg: Double?
        public var weightDelta: Double?
        public var fatPct: Double?
        public var fatPctDelta: Double?

        public init(date: String? = nil, score: Double? = nil, band: String? = nil, weightKg: Double? = nil,
                    weightDelta: Double? = nil, fatPct: Double? = nil, fatPctDelta: Double? = nil) {
            self.date = date; self.score = score; self.band = band; self.weightKg = weightKg
            self.weightDelta = weightDelta; self.fatPct = fatPct; self.fatPctDelta = fatPctDelta
        }
    }

    /// Heart-rate recovery of the latest workout that had a measurement, for Siri.
    public struct HeartRecovery: Codable, Equatable {
        public var sport: String
        public var date: String
        public var after1Minute: Int?
        public var after2Minutes: Int?

        public init(sport: String, date: String, after1Minute: Int?, after2Minutes: Int?) {
            self.sport = sport; self.date = date; self.after1Minute = after1Minute; self.after2Minutes = after2Minutes
        }
    }

    /// First-minute heart-rate recovery of the latest PaceForge session that has one.
    public struct HRR1: Codable, Equatable {
        public var bpm: Int
        /// Only "post" (after stopping) is written; files from older builds may still say "mid".
        public var kind: String
        /// The athlete's own band (good, normal, watch or flag), present only with a personal baseline.
        public var band: String?
        public var sessionName: String?
        public var date: String?

        public init(bpm: Int, kind: String, band: String? = nil, sessionName: String? = nil, date: String? = nil) {
            self.bpm = bpm; self.kind = kind; self.band = band; self.sessionName = sessionName; self.date = date
        }
    }

    /// When the app wrote this file.
    public var updated: Date
    /// The local day (`yyyy-MM-dd`) the sessions and scores describe.
    public var date: String
    public var sessions: [Session] = []
    public var recovery: Double?
    public var recoveryBand: String?
    public var strain: Double?
    public var strainLow: Double?
    public var strainHigh: Double?
    public var sleep: Double?
    public var sleepHours: String?
    public var sleepNeed: String?
    public var hrv: Double?
    public var restingHr: Double?
    /// Acute : chronic load ratio.
    public var acwr: Double?
    public var fitness: Double?
    public var fatigue: Double?
    public var briefHeadline: String?
    public var briefDate: String?
    public var race: Race?

    // Added after the first widgets shipped. Optional on purpose: a file written by an older build has
    // none of these keys, and the synthesized decoder only tolerates a missing key for an Optional.
    public var weekDays: [WeekDay]?
    public var weekDoneMinutes: Double?
    public var weekTargetMinutes: Double?
    public var nights: [Night]?
    public var sleepNeedMinutes: Double?
    public var hrvBaseline: Double?
    public var hrvLow: Double?
    public var hrvHigh: Double?
    public var ctl: Double?
    public var atl: Double?
    public var body: BodyReading?
    public var heartRecovery: HeartRecovery?
    /// The next session still to do after today's, and its day.
    public var nextSession: Session?
    public var nextSessionDate: String?
    public var hrr1: HRR1?
    /// How many PaceForge alerts are open.
    public var openAlerts: Int?

    public init(updated: Date, date: String) {
        self.updated = updated
        self.date = date
    }

    public static let fileName = "paceforge-summary.json"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.suiteName)?
            .appendingPathComponent(fileName)
    }

    public static func load() -> PFSummary? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PFSummary.self, from: data)
    }

    public func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Local `yyyy-MM-dd` for a date.
    public static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Older than 24 hours, or written for a different day than today: the widgets then ask the user to
    /// open NOOP instead of showing yesterday's session as today's.
    public func isStale(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updated) > 24 * 3600 || date != Self.dayString(now)
    }

    /// Days to the race counted from today: the days stored at write time, less the days since then.
    public var raceDaysNow: Int? {
        guard let race else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let written = f.date(from: date) else { return race.days }
        let elapsed = Calendar.current.dateComponents([.day], from: written, to: Date()).day ?? 0
        return race.days - max(0, elapsed)
    }
}

public enum PFWidgetKind {
    public static let today = "PaceForgeTodayWidget"
    public static let session = "PaceForgeSessionWidget"
    public static let race = "PaceForgeRaceWidget"
    public static let recoveryGauge = "PaceForgeRecoveryGaugeWidget"
    public static let strainGauge = "PaceForgeStrainGaugeWidget"
    public static let week = "PaceForgeWeekWidget"
    public static let sleepHrv = "PaceForgeSleepHrvWidget"
    public static let load = "PaceForgeLoadWidget"
    public static let body = "PaceForgeBodyWidget"
    public static let hrr = "PaceForgeHeartRecoveryWidget"
    public static let all = [today, session, race, recoveryGauge, strainGauge, week, sleepHrv, load, body, hrr]
}

/// The acute:chronic workload ratio band that is treated as safe, used by the load widgets.
public enum PFLoadZone {
    public static let safeLow = 0.8
    public static let safeHigh = 1.3
    /// Top of the ratio scale the widgets draw.
    public static let scaleMax = 2.0

    public enum State { case low, safe, high }

    public static func state(_ ratio: Double) -> State {
        ratio < safeLow ? .low : (ratio > safeHigh ? .high : .safe)
    }
}

/// Set by the Control Center / lock-screen control; the app opens PaceForge > Today when it next
/// becomes active.
public enum PFOpenRequest {
    public static let key = "noop.paceforge.openTodayRequest"

    public static func raise() {
        UserDefaults(suiteName: WidgetSnapshot.suiteName)?.set(true, forKey: key)
    }

    public static func consume() -> Bool {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName), defaults.bool(forKey: key) else { return false }
        defaults.set(false, forKey: key)
        return true
    }
}

/// Opens NOOP on PaceForge > Today. Compiled into the app and the widget extension.
public struct OpenPaceForgeTodayIntent: AppIntent {
    public static var title: LocalizedStringResource = "PaceForge Today"
    public static var description = IntentDescription("Open NOOP on the PaceForge Today screen.")
    public static var openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        PFOpenRequest.raise()
        return .result()
    }
}

extension PFSummary {
    /// Fills every field that is still nil with obviously synthetic numbers, so a widget preview (the
    /// picker's face and the debug gallery) shows each face drawn rather than its "open NOOP" state.
    /// Fields that already have a value are left alone.
    public func fillingSampleGaps() -> PFSummary {
        var out = self
        let cal = Calendar(identifier: .iso8601)
        let monday = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        if out.weekDays == nil {
            let letters = ["M", "T", "W", "T", "F", "S", "S"]
            let planned = [1, 1, 1, 0, 1, 1, 0]
            let todayIndex = cal.dateComponents([.day], from: monday, to: Date()).day ?? 0
            out.weekDays = (0..<7).map { i in
                let day = cal.date(byAdding: .day, value: i, to: monday) ?? monday
                return WeekDay(date: Self.dayString(day), label: letters[i], planned: planned[i],
                               done: i < todayIndex ? planned[i] : 0, isToday: i == todayIndex)
            }
            out.weekDoneMinutes = 205
            out.weekTargetMinutes = 420
        }
        if out.nights == nil || out.nights?.isEmpty == true {
            let sleep: [Double] = [402, 431, 388, 455, 417, 360, 440]
            let hrv: [Double] = [38, 41, 36, 43, 40, 37, 42]
            out.nights = (0..<7).map { i in
                let day = Date().addingTimeInterval(Double(i - 6) * 86_400)
                return Night(date: Self.dayString(day), sleepMinutes: sleep[i], hrv: hrv[i])
            }
        }
        out.sleepNeedMinutes = out.sleepNeedMinutes ?? 480
        out.hrvBaseline = out.hrvBaseline ?? 39.5
        out.hrvLow = out.hrvLow ?? 36
        out.hrvHigh = out.hrvHigh ?? 43
        out.acwr = out.acwr ?? 1.1
        out.ctl = out.ctl ?? 56.8
        out.atl = out.atl ?? 51
        if out.body == nil {
            out.body = BodyReading(date: date, score: 56, band: "Fair", weightKg: 90.8, weightDelta: -0.4,
                                   fatPct: 24.0, fatPctDelta: -0.2)
        }
        if out.hrr1 == nil {
            out.hrr1 = HRR1(bpm: 24, kind: "post", band: "good", sessionName: "Example intervals", date: date)
        }
        out.openAlerts = out.openAlerts ?? 2
        return out
    }
}
