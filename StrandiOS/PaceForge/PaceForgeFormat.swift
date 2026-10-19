import Foundation

// Date, pace and number formatting shared by the PaceForge tab. Foundation only, so the Linux logic tests compile it.

enum PFFormat {
    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let dayName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f
    }()
    private static let shortDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f
    }()

    static func date(_ iso: String) -> Date {
        isoDay.date(from: String(iso.prefix(10))) ?? Date(timeIntervalSince1970: 0)
    }
    static func dayTitle(_ iso: String) -> String { dayName.string(from: date(iso)) }
    static func shortDate(_ iso: String) -> String { shortDay.string(from: date(iso)) }

    private static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        return cal
    }()

    static func isoString(_ date: Date) -> String { isoDay.string(from: date) }

    static func addDays(_ iso: String, _ days: Int) -> String {
        let shifted = gregorian.date(byAdding: .day, value: days, to: date(iso)) ?? date(iso)
        return isoString(shifted)
    }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        gregorian.dateComponents([.day], from: date(from), to: date(to)).day ?? 0
    }

    /// The Monday of the week containing `iso`.
    static func monday(of iso: String) -> String {
        let weekday = gregorian.component(.weekday, from: date(iso))   // 1 = Sunday
        return addDays(iso, -((weekday + 5) % 7))
    }

    /// ISO week key as PaceForge writes it, e.g. "2026-W41".
    static func isoWeekKey(_ iso: String) -> String {
        let cal = Calendar(identifier: .iso8601)
        let parts = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date(iso))
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    /// "08:12" for an ISO-8601 timestamp, in the phone's time zone; a timestamp with no zone is read as
    /// local. nil when it cannot be parsed.
    static func timeOfDay(_ timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        guard let when = isoWithFraction.date(from: timestamp) ?? isoPlain.date(from: timestamp)
                ?? isoLocalSeconds.date(from: timestamp) else { return nil }
        return clockMinutes.string(from: when)
    }

    /// Made once and shared: a formatter is costly to build and these run for every row of a list.
    static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain = ISO8601DateFormatter()

    private static let clockMinutes: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let isoLocalSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// "5–11 Oct" for a Monday-to-Sunday span inside one month, otherwise "28 Sep – 4 Oct".
    static func span(_ start: String, _ end: String) -> String {
        let cal = Calendar(identifier: .gregorian)
        let s = date(start), e = date(end)
        if cal.component(.month, from: s) == cal.component(.month, from: e) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "MMM"
            return "\(cal.component(.day, from: s))\u{2013}\(cal.component(.day, from: e)) \(f.string(from: e))"
        }
        return "\(shortDate(start)) \u{2013} \(shortDate(end))"
    }

    /// sec/km as m:ss.
    static func pace(_ secPerKm: Double) -> String {
        let total = Safe.int(secPerKm)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 6382 -> 1:46:22
    static func clock(_ seconds: Double) -> String {
        let total = Safe.int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }

    static func trimmed(_ v: Double) -> String {
        v.rounded() == v ? String(Safe.int(v)) : oneDecimal(v)
    }

    static func capitalized(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }

    static func words(_ snake: String) -> String { snake.replacingOccurrences(of: "_", with: " ") }
}
