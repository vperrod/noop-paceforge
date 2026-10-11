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

    /// Days to the race counted from today rather than from when the file was written.
    public var raceDaysNow: Int? {
        guard let race else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let target = f.date(from: race.date) else { return race.days }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: target).day
        return days ?? race.days
    }
}

public enum PFWidgetKind {
    public static let today = "PaceForgeTodayWidget"
    public static let session = "PaceForgeSessionWidget"
    public static let race = "PaceForgeRaceWidget"
    public static let recoveryGauge = "PaceForgeRecoveryGaugeWidget"
    public static let strainGauge = "PaceForgeStrainGaugeWidget"
    public static let all = [today, session, race, recoveryGauge, strainGauge]
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
