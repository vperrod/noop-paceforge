import Foundation

/// A small Codable summary of the day so far, written by the app into the App Group container and read by
/// the My Day widget. The extension never touches the database or the network; this file is its only source.
///
/// The heart-rate line is the last six hours as five-minute means, positioned by TIME, so a file that stops
/// short leaves the right edge of the line empty rather than stretching old readings across the window.
public struct MyDaySummary: Codable, Equatable {
    /// The next session still to do: today's if there is one, else the next PaceForge day's.
    public struct Next: Codable, Equatable {
        public var name: String
        /// "8.0 km · 55 min".
        public var detail: String?
        /// A clock time ("18:00") when the plan has a slot today, else a day label ("Thu"), else nil.
        public var when: String?

        public init(name: String, detail: String? = nil, when: String? = nil) {
            self.name = name; self.detail = detail; self.when = when
        }
    }

    /// When the app wrote this file; the right edge of the heart-rate window.
    public var updated: Date
    /// The local day (`yyyy-MM-dd`) the file describes.
    public var date: String
    public var hr: [HrPoint] = []
    public var latestBpm: Int?
    public var next: Next?
    public var plannedCount = 0
    public var doneCount = 0

    public init(updated: Date, date: String) {
        self.updated = updated
        self.date = date
    }

    public static let fileName = "my-day-summary.json"
    public static let widgetKind = "MyDayWidget"
    /// How much heart rate the widget shows.
    public static let windowSec: Int64 = 6 * 60 * 60
    /// Past this the heart-rate window is mostly empty, and the widget asks the user to open NOOP.
    public static let staleAfter: TimeInterval = 6 * 60 * 60

    /// Resolved once: `containerURL(forSecurityApplicationGroupIdentifier:)` is a synchronous round trip to the container
    /// daemon, and the summary writers called it on every read and write from the main actor.
    private static let fileURL: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.suiteName)?
        .appendingPathComponent(fileName)

    public static func load() -> MyDaySummary? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MyDaySummary.self, from: data)
    }

    @discardableResult
    public func save() -> Bool {
        guard let url = Self.fileURL else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// Local `yyyy-MM-dd` for a date.
    public static func dayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Written for another day, or more than `staleAfter` ago: the widget then says to open NOOP instead of
    /// drawing yesterday's heart as today's.
    public func isStale(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updated) > Self.staleAfter || date != Self.dayString(now)
    }

    /// The window the line is drawn over, ending at `updated`.
    public var windowEnd: Int64 { Int64(updated.timeIntervalSince1970) }
    public var windowStart: Int64 { windowEnd - Self.windowSec }
}

extension MyDaySummary {
    /// Obviously synthetic data for the widget picker and the debug gallery: a calm morning, a short effort,
    /// a gap, and a session still to do.
    public static var sample: MyDaySummary {
        let now = Date()
        var s = MyDaySummary(updated: now, date: dayString(now))
        let end = Int64(now.timeIntervalSince1970)
        var points: [HrPoint] = []
        for i in 0..<72 {
            let ts = end - Self.windowSec + Int64(i) * 300
            if i >= 30 && i < 38 { continue }
            let effort = i >= 50 && i < 56 ? 55.0 : 0
            let bpm = 68 + 6 * sin(Double(i) / 5) + effort
            points.append(HrPoint(ts: ts, bpm: Int(bpm.rounded())))
        }
        s.hr = points
        s.latestBpm = points.last?.bpm
        s.next = Next(name: "Intervals", detail: "8.0 km \u{00B7} 55 min", when: "18:00")
        s.plannedCount = 2
        s.doneCount = 1
        return s
    }
}
